import '../../../core/app_config.dart';
import '../../../core/net/tmc_http.dart';
import '../../../data/models/media_ref.dart';
import '../../../data/models/resolved_stream.dart';
import 'stream_provider.dart';

/// =============================================================================
///  VIDLINK - API JSON publica (sem chave, sem cadastro)
///
///  Devolve a playlist HLS direta em `stream.playlist`, o que permite tocar no
///  player nativo sem passar por HTML. Exige Referer/Origin do proprio site.
///
///  movie : /api/b/movie/{tmdbId}?multiLang=0
///  tv    : /api/b/tv/{tmdbId}/{temporada}/{episodio}?multiLang=0
///
///  `multiLang=1` costuma trazer faixas de audio extras (PT-BR incluso).
/// =============================================================================
class VidLinkProvider extends StreamProvider {
  @override
  String get id => 'vidlink';

  @override
  String get label => 'VidLink';

  @override
  int get priority => 12;

  /// Player oficial do VidLink, usado como fallback quando a API direta
  /// não devolve uma playlist válida.
  static Uri pageFor(MediaRef ref, {String base = 'https://vidlink.pro'}) {
    final String path = ref.isTv
        ? 'tv/${ref.tmdbId}/${ref.season}/${ref.episode}'
        : 'movie/${ref.tmdbId}';
    return Uri.parse('$base/$path').replace(
      queryParameters: const <String, String>{'autoplay': 'true'},
    );
  }

  @override
  Future<ResolvedStream?> resolve(MediaRef ref, ResolverContext ctx) async {
    for (final String base in ctx.basesFor(id)) {
      final String path = ref.isTv
          ? 'tv/${ref.tmdbId}/${ref.season}/${ref.episode}'
          : 'movie/${ref.tmdbId}';

      for (final String multi in <String>['0', '1']) {
        final Uri api = Uri.parse('$base/api/b/$path?multiLang=$multi');
        final Map<String, dynamic>? json = await ctx.http.getJson(
          api.toString(),
          referer: '$base/',
          origin: base,
        );
        if (json == null) continue;

        final String? playlist = _playlist(json);
        if (playlist == null) continue;

        final ProbeResult probe =
            await ctx.http.probe(playlist, referer: '$base/');
        if (!probe.ok) continue;

        return ResolvedStream(
          url: Uri.parse(playlist),
          kind: probe.isHls ? StreamKind.hls : StreamKind.mp4,
          providerId: id,
          providerLabel: label,
          headers: <String, String>{
            'User-Agent': AppConfig.userAgent,
            'Referer': '$base/',
            'Origin': base,
          },
          embedPage: Uri.parse('$base/$path'),
        );
      }
    }
    return null;
  }

  String? _playlist(Map<String, dynamic> json) {
    final dynamic stream = json['stream'];
    if (stream is Map) {
      final dynamic p = stream['playlist'] ?? stream['url'];
      if (p is String && p.startsWith('http')) return p;
    }
    final dynamic direct = json['playlist'] ?? json['url'];
    if (direct is String && direct.startsWith('http')) return direct;
    return null;
  }
}
