import '../../../core/app_config.dart';
import '../../../core/net/tmc_http.dart';
import '../../../data/models/media_ref.dart';
import '../../../data/models/resolved_stream.dart';
import '../stream_extractor.dart';
import '../url_sanitizer.dart';

/// Contrato de uma fonte.
abstract class StreamProvider {
  String get id;
  String get label;
  int get priority;
  bool supports(MediaRef ref) => true;
  Future<ResolvedStream?> resolve(MediaRef ref, ResolverContext ctx);
}

class ResolverContext {
  ResolverContext({
    required this.http,
    required this.ref,
    required this._emit,
    required this.sources,
  });

  final TmcHttp http;
  final MediaRef ref;
  final void Function(String, {String? providerId, int attempt, int total}) _emit;
  final Map<String, List<String>> sources;

  List<String> sourceBases(String id) => sources[id] ?? const <String>[];

  /// Bases editaveis (Supabase) primeiro; depois o fallback embutido.
  /// Sem isso, uma falha no endpoint de fontes zerava a lista.
  List<String> basesFor(String id, [List<String> fallback = const <String>[]]) {
    final List<String> hard = fallback.isEmpty ? AppConfig.fallbackFor(id) : fallback;
    final List<String> all = <String>[
      ...sourceBases(id),
      ...hard,
    ].map(_trim).where((String u) => u.startsWith('http')).toList();
    return all.toSet().toList();
  }

  static String _trim(String url) {
    final String t = url.trim();
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  void emit(String msg, {String? providerId, int attempt = 0, int total = 0}) =>
      _emit(msg, providerId: providerId, attempt: attempt, total: total);

  late final StreamExtractor extractor = StreamExtractor(http);

  /// Segue uma pagina de player ate o stream limpo (salto unico de fallback).
  Future<ResolvedStream?> follow(
    Uri page, {
    required String providerId,
    required String providerLabel,
    int depth = 0,
    String? referer,
  }) =>
      extractor.resolveFrom(
        page,
        providerId: providerId,
        providerLabel: providerLabel,
        depth: depth,
        referer: referer,
      );

  /// Testa os candidatos diretos, PT-BR primeiro, e devolve o primeiro vivo.
  Future<ResolvedStream?> fromDirectCandidates(
    List<String> urls, {
    required String providerId,
    required String providerLabel,
    String? referer,
  }) async {
    final Set<String> seen = <String>{};
    final List<String> ordered = <String>[];

    for (final String raw in urls) {
      final String? clean = UrlSanitizer.extractMedia(raw);
      if (clean == null) continue;
      if (seen.add(clean)) ordered.add(clean);
    }

    ordered.sort((String a, String b) =>
        UrlSanitizer.mediaScore(b).compareTo(UrlSanitizer.mediaScore(a)));

    final String? origin =
        referer == null ? null : (Uri.tryParse(referer)?.origin ?? referer);

    for (final String url in ordered) {
      final ProbeResult probe = await http.probe(url, referer: referer);
      if (!probe.ok) continue;

      return ResolvedStream(
        url: Uri.parse(url),
        kind: probe.isHls ? StreamKind.hls : StreamKind.mp4,
        providerId: providerId,
        providerLabel: providerLabel,
        headers: AppConfig.playerHeaders(referer: referer, origin: origin),
      );
    }
    return null;
  }

  /// Menor valor = melhor. Usado como desempate final.
  int ptBrRank(String url) {
    final String u = url.toLowerCase();
    int rank = 0;
    for (final String mark in AppConfig.ptBrMarkers) {
      if (u.contains(mark)) {
        rank -= 6;
        break;
      }
    }
    for (final String mark in AppConfig.legendadoMarkers) {
      if (u.contains(mark)) {
        rank += AppConfig.preferDublado ? 4 : 1;
        break;
      }
    }
    if (u.contains('.m3u8')) rank -= 2;
    return rank;
  }
}