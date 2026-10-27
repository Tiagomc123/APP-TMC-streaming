import '../../../core/app_config.dart';
import '../../../core/net/tmc_http.dart';
import '../../../data/models/media_ref.dart';
import '../../../data/models/resolved_stream.dart';
import '../stream_extractor.dart';

/// Contrato de uma fonte. Cada provider monta as URLs dela e delega a
/// varredura ao [ResolverContext].
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

  /// Bases editaveis (Supabase) primeiro; depois os fallbacks embutidos.
  /// Assim o app continua reproduzindo mesmo se o dominio trocar.
  List<String> basesFor(String id, List<String> fallback) {
    final List<String> all = <String>[
      ...sourceBases(id),
      ...fallback,
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

  /// Segue uma pagina de embed ate o stream limpo.
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

  /// Testa candidatos diretos vindos de API JSON, PT-BR primeiro.
  Future<ResolvedStream?> fromDirectCandidates(
    List<String> urls, {
    required String providerId,
    required String providerLabel,
    String? referer,
  }) async {
    final List<String> ordered = List<String>.of(urls)
      ..sort((String a, String b) => ptBrRank(a).compareTo(ptBrRank(b)));

    for (final String url in ordered) {
      final ProbeResult probe = await http.probe(url, referer: referer);
      if (!probe.ok) continue;

      return ResolvedStream(
        url: Uri.parse(url),
        kind: probe.isHls ? StreamKind.hls : StreamKind.mp4,
        providerId: providerId,
        providerLabel: providerLabel,
        headers: <String, String>{
          'User-Agent': AppConfig.userAgent,
          'Referer': ?referer,
        },
      );
    }
    return null;
  }

  /// Menor valor = melhor. Prioriza dublado/PT-BR e penaliza legendado.
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
        rank += 3;
        break;
      }
    }
    if (u.contains('.m3u8')) rank -= 2;
    if (u.contains('1080')) rank -= 1;
    return rank;
  }
}