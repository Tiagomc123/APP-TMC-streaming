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

  /// Testa candidatos diretos vindos de API JSON.
  Future<ResolvedStream?> fromDirectCandidates(
    List<String> urls, {
    required String providerId,
    required String providerLabel,
    String? referer,
  }) async {
    for (final String url in urls) {
      final ProbeResult probe = await http.probe(url, referer: referer);
      if (!probe.ok) continue;

      return ResolvedStream(
        url: Uri.parse(url),
        kind: probe.isHls ? StreamKind.hls : StreamKind.mp4,
        providerId: providerId,
        providerLabel: providerLabel,
        headers: <String, String>{
          'User-Agent': 'Mozilla/5.0',
          'Referer': ?referer,
        },
      );
    }
    return null;
  }
}
