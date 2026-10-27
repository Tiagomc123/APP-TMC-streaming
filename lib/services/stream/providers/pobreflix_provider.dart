import '../../../core/app_config.dart';
import '../../../core/net/tmc_http.dart';
import '../../../core/slug.dart';
import '../../../data/models/media_ref.dart';
import '../../../data/models/resolved_stream.dart';
import '../stream_scanner.dart';
import 'stream_provider.dart';

/// =============================================================================
///  POBREFLIX HD - extracao 100% HTTP, sem WebView
///
///  O site coloca uma tela intermediaria de "verificacao" antes do player.
///  O fluxo aqui e resolvido em 4 passos, tudo por HTTP:
///
///   1. monta as URLs candidatas (`/filmes/online/<slug>-<id>` e variacoes,
///      com `-dublado` na frente por preferencia de audio PT-BR);
///   2. baixa a pagina com User-Agent rotativo, Referer/Origin e cookies
///      de sessao (o TmcHttp ja mantem o cookie jar por host);
///   3. se cair na tela de verificacao, extrai o alvo do meta-refresh /
///      location.href e repete (ate [AppConfig.maxRedirectHops] saltos);
///   4. coleta os tokens do player (token/hash/expires) e delega ao
///      [ResolverContext.follow], que varre iframes, JS empacotado (Dean
///      Edwards) e blobs base64 ate o .m3u8/.mp4 limpo, sem anuncios.
///
///  Se o scraping falhar (site fora do ar / layout novo), cai automaticamente
///  na API publica do SuperFlix, que devolve stream direta e rapida.
/// =============================================================================
class PobreFlixProvider extends StreamProvider {
  @override
  String get id => 'pobreflix';

  @override
  String get label => 'PobreFlix';

  @override
  int get priority => 15;

  static final RegExp _playerLinkRe = RegExp(
    r'''(?:src|href|file)\s*[:=]\s*["']([^"']*(?:/player|/embed|player\.php|\?id=|/e/)[^"']*)["']''',
    caseSensitive: false,
  );

  static final RegExp _metaRefreshRe = RegExp(
    r'''http-equiv\s*=\s*["']?refresh["']?[^>]*content\s*=\s*["'][^"']*url\s*=\s*([^"';]+)''',
    caseSensitive: false,
  );

  static final RegExp _jsRedirectRe = RegExp(
    r'''(?:location\.href|location\.replace\s*\(|location\.assign\s*\(|window\.location\s*=|location\s*=)\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  @override
  Future<ResolvedStream?> resolve(MediaRef ref, ResolverContext ctx) async {
    final List<String> bases = ctx.basesFor(id, AppConfig.pobreflixBases);
    if (bases.isEmpty) return _superFlixFallback(ref, ctx);

    final List<Uri> candidates = _candidatePages(bases, ref);
    for (final Uri page in candidates) {
      final ResolvedStream? stream = await _scrape(page, ctx);
      if (stream != null) return stream;
    }
    return _superFlixFallback(ref, ctx);
  }

  /// Padroes de URL, do mais provavel (dublado) ao menos provavel.
  List<Uri> _candidatePages(List<String> bases, MediaRef ref) {
    final String slug = Slug.of(ref.title);
    final int id = ref.tmdbId;
    final List<String> patterns = <String>[];

    if (ref.isTv) {
      patterns.addAll(<String>[
        '/series/online/$slug-dublado-${ref.season}x${ref.episode}-$id',
        '/series/online/$slug-$id',
        '/series/online/$slug-${ref.season}x${ref.episode}-$id',
        '/series/online/$slug-dublado-$id',
        '/series/$id',
        '/serie/$id',
      ]);
    } else {
      patterns.addAll(<String>[
        '/filmes/online/$slug-dublado-$id',
        '/filmes/online/$slug-$id',
        '/filmes/online/$slug-legendado-$id',
        '/filmes/online/$slug-dublado',
        '/filmes/online/$slug',
        '/filmes/$id',
        '/filme/$id',
      ]);
    }
    if (slug.isEmpty) patterns.removeWhere((String p) => p.contains('//'));

    final List<Uri> out = <Uri>[];
    for (final String pattern in patterns) {
      for (final String base in bases) {
        out.add(Uri.parse('$base$pattern'));
      }
    }
    return out.take(AppConfig.maxPagesPerTitle).toList();
  }

  Future<ResolvedStream?> _scrape(Uri page, ResolverContext ctx) async {
    Uri current = page;
    final Set<String> visited = <String>{};

    for (int hop = 0; hop <= AppConfig.maxRedirectHops; hop++) {
      if (!visited.add(current.toString())) return null;

      final String origin = '${current.scheme}://${current.host}';
      HttpResult? res = await ctx.http.getText(
        current.toString(),
        referer: '$origin/',
        origin: origin,
      );

      // Segunda tentativa quando a verificacao dispara (ja com cookies).
      if (res != null && res.challenged) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        AppConfig.rotateUserAgent();
        res = await ctx.http.getText(
          current.toString(),
          referer: '$origin/',
          origin: origin,
        );
      }
      if (res == null || !res.ok) return null;

      final ResolvedStream? viaPlayer = await _followPlayerLink(res.body, res.finalUrl, ctx);
      if (viaPlayer != null) return viaPlayer;

      final ResolvedStream? direct = await ctx.follow(
        res.finalUrl,
        providerId: id,
        providerLabel: label,
      );
      if (direct != null) return direct;

      final Uri? next = _verificationTarget(res.body, res.finalUrl);
      if (next == null || next.toString() == current.toString()) return null;
      current = next;
    }
    return null;
  }

  /// Tenta o link direto do player (com token anexado quando existir).
  Future<ResolvedStream?> _followPlayerLink(
    String body,
    Uri base,
    ResolverContext ctx,
  ) async {
    final Uri? link = _playerLink(body, base);
    if (link == null || link.toString() == base.toString()) return null;
    return ctx.follow(
      link,
      providerId: id,
      providerLabel: label,
      referer: base.toString(),
    );
  }

  Uri? _playerLink(String body, Uri base) {
    for (final RegExpMatch m in _playerLinkRe.allMatches(body)) {
      final String raw = m.group(1)!.trim();
      if (raw.isEmpty || raw.startsWith('javascript:') || raw.startsWith('data:')) {
        continue;
      }
      final Uri? abs = _abs(raw, base);
      if (abs == null) continue;
      if (StreamScanner.isAdUrl(abs.toString())) continue;
      return abs;
    }

    final Map<String, String> tokens = StreamScanner.tokens(body);
    if (tokens.isNotEmpty) {
      final Map<String, String> query = <String, String>{
        ...base.queryParameters,
        ...tokens,
      };
      final Uri signed = base.replace(queryParameters: query);
      if (signed.toString() != base.toString()) return signed;
    }
    return null;
  }

  Uri? _verificationTarget(String body, Uri base) {
    for (final RegExp re in <RegExp>[_metaRefreshRe, _jsRedirectRe]) {
      for (final RegExpMatch m in re.allMatches(body)) {
        final String raw = m.group(1)!.trim();
        if (raw.isEmpty || raw.startsWith('javascript:')) continue;
        final Uri? abs = _abs(raw, base);
        if (abs == null) continue;
        if (abs.toString() == base.toString()) continue;
        return abs;
      }
    }
    return null;
  }

  Uri? _abs(String raw, Uri base) {
    try {
      final Uri u = base.resolve(raw);
      return u.hasScheme ? u : null;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------- fallback API --------------------------------
  /// Ultimo recurso: API publica do SuperFlix (JSON -> stream direta).
  Future<ResolvedStream?> _superFlixFallback(MediaRef ref, ResolverContext ctx) async {
    final List<String> bases = ctx.basesFor('superflix_api', AppConfig.superflixBases);
    for (final String base in bases) {
      final String path = ref.isTv
          ? 'serie/${ref.tmdbId}/${ref.season}/${ref.episode}'
          : 'filme/${ref.tmdbId}';

      final Map<String, dynamic>? json =
          await ctx.http.getJson('$base/$path?format=json', referer: '$base/');
      if (json == null) continue;

      final List<String> urls = _deepCollect(json);
      if (urls.isEmpty) continue;

      final ResolvedStream? stream = await ctx.fromDirectCandidates(
        urls,
        providerId: id,
        providerLabel: label,
        referer: '$base/',
      );
      if (stream != null) return stream;

      final dynamic embed = json['url'] ?? json['player'];
      if (embed is String && embed.startsWith('http')) {
        final ResolvedStream? nested =
            await ctx.follow(Uri.parse(embed), providerId: id, providerLabel: label);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// Percorre o JSON inteiro atras de .m3u8/.mp4 (a estrutura varia por versao).
  List<String> _deepCollect(dynamic node) {
    final List<String> out = <String>[];

    void walk(dynamic n) {
      if (n is String) {
        final String s = n.replaceAll(r'\/', '/');
        if (s.startsWith('http') && (s.contains('.m3u8') || s.contains('.mp4'))) {
          out.add(s);
        }
      } else if (n is List) {
        for (final dynamic i in n) {
          walk(i);
        }
      } else if (n is Map) {
        for (final dynamic v in n.values) {
          walk(v);
        }
      }
    }

    walk(node);
    return out;
  }
}