import '../../core/app_config.dart';
import '../../core/net/tmc_http.dart';
import '../../data/models/hls_models.dart';
import '../../data/models/resolved_stream.dart';
import 'hls_service.dart';
import 'stream_scanner.dart';

/// Segue paginas, iframes, JSON e telas de verificacao ate o arquivo limpo.
class StreamExtractor {
  StreamExtractor(this._http);
  final TmcHttp _http;

  String lastError = '';

  static final RegExp _metaRefreshRe = RegExp(
    r'''http-equiv\s*=\s*["']?refresh["']?[^>]*content\s*=\s*["'][^"']*url\s*=\s*([^"';]+)''',
    caseSensitive: false,
  );

  static final RegExp _jsRedirectRe = RegExp(
    r'''(?:location\.href|location\.replace\s*\(|location\.assign\s*\(|window\.location\s*=|location\s*=)\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  Future<ResolvedStream?> resolveFrom(
    Uri page, {
    required String providerId,
    required String providerLabel,
    int depth = 0,
    String? referer,
    Set<String>? visited,
  }) async {
    if (depth > AppConfig.maxIframeDepth) return null;

    visited ??= <String>{};
    if (!visited.add(page.toString())) return null;

    final String origin = '${page.scheme}://${page.host}';
    final HttpResult? res = await _http.getText(
      page.toString(),
      referer: referer ?? '$origin/',
      origin: origin,
    );

    if (res == null) {
      lastError = 'Sem resposta de $providerLabel';
      return null;
    }
    if (res.challenged) {
      lastError = '$providerLabel bloqueou (verificacao/Cloudflare)';
      return null;
    }

    final List<StreamCandidate> candidates =
        StreamScanner.scan(res.body, base: res.finalUrl);

    // 1) candidatos jogaveis, do maior score para o menor
    for (final StreamCandidate c in candidates.where((StreamCandidate c) => c.playable)) {
      final ProbeResult probe = await _http.probe(c.url, referer: res.finalUrl.toString());
      if (!probe.ok) continue;

      final StreamKind kind = probe.isHls ? StreamKind.hls : StreamKind.mp4;

      List<HlsVariant> variants = const <HlsVariant>[];
      List<HlsAudioTrack> audios = const <HlsAudioTrack>[];
      List<HlsSubtitleTrack> subs = const <HlsSubtitleTrack>[];

      if (kind == StreamKind.hls) {
        final HlsManifest? master =
            await HlsService(_http).parseMaster(c.url, referer: res.finalUrl.toString());
        if (master != null) {
          variants = master.variants;
          audios = master.audios;
          subs = master.subtitles;
        }
      }

      return ResolvedStream(
        url: Uri.parse(c.url),
        kind: kind,
        providerId: providerId,
        providerLabel: providerLabel,
        // headers reenviados em TODA requisicao do HLS (playlist, segmentos, chave)
        headers: <String, String>{
          'User-Agent': AppConfig.userAgent,
          'Referer': res.finalUrl.toString(),
          'Origin': '${Uri.parse(c.url).scheme}://${Uri.parse(c.url).host}',
        },
        embedPage: res.finalUrl,
        variants: variants,
        audioTracks: audios,
        subtitleTracks: subs,
      );
    }

    // 2) nenhum direto: segue os iframes
    for (final StreamCandidate c in candidates.where((StreamCandidate c) => c.kind == CandidateKind.iframe)) {
      final Uri? child = Uri.tryParse(c.url);
      if (child == null) continue;

      if (_nonHlsHost(child.host)) {
        return ResolvedStream(
          url: child,
          kind: StreamKind.embed,
          providerId: providerId,
          providerLabel: providerLabel,
          headers: const <String, String>{},
          embedPage: child,
        );
      }

      final ResolvedStream? nested = await resolveFrom(
        child,
        providerId: providerId,
        providerLabel: providerLabel,
        depth: depth + 1,
        referer: res.finalUrl.toString(),
        visited: visited,
      );
      if (nested != null) return nested;
    }

    // 3) nada encontrado: a pagina pode ser apenas a tela de verificacao.
    //    Extrai o alvo do meta-refresh / location.href e repete o fluxo.
    final Uri? redirect = _verificationTarget(res.body, res.finalUrl);
    if (redirect != null && redirect.toString() != page.toString()) {
      final ResolvedStream? hop = await resolveFrom(
        redirect,
        providerId: providerId,
        providerLabel: providerLabel,
        depth: depth + 1,
        referer: res.finalUrl.toString(),
        visited: visited,
      );
      if (hop != null) return hop;
    }

    lastError = 'Nenhum stream limpo em $providerLabel';
    return null;
  }

  /// Detecta tela de "verificando / aguarde" e devolve o alvo do salto.
  Uri? _verificationTarget(String body, Uri base) {
    final bool looksInterstitial = body.contains('verific') ||
        body.contains('Verific') ||
        body.contains('aguarde') ||
        body.contains('Aguarde') ||
        body.contains('checking') ||
        body.contains('Just a moment') ||
        body.contains('refresh');

    for (final RegExp re in <RegExp>[_metaRefreshRe, _jsRedirectRe]) {
      for (final RegExpMatch m in re.allMatches(body)) {
        final String raw = m.group(1)!.trim();
        if (raw.isEmpty || raw.startsWith('javascript:')) continue;
        final Uri? abs = _abs(raw, base);
        if (abs == null) continue;
        if (abs.toString() == base.toString()) continue;
        if (!looksInterstitial && StreamScanner.isAdUrl(abs.toString())) continue;
        return abs;
      }
    }
    return null;
  }

  Uri? _abs(String raw, Uri base) {
    try {
      final Uri u = base.resolve(raw.trim());
      return u.hasScheme ? u : null;
    } catch (_) {
      return null;
    }
  }

  bool _nonHlsHost(String host) {
    final String h = host.toLowerCase();
    return h.contains('ok.ru') ||
        h.contains('dailymotion') ||
        h.contains('vimeo') ||
        h.contains('youtube') ||
        h.contains('youtu.be') ||
        h.contains('blogger') ||
        h.contains('drive.google');
  }
}