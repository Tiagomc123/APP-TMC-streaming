import '../../../data/models/media_ref.dart';
import '../../../data/models/resolved_stream.dart';
import 'stream_provider.dart';

class PontoFinalProvider extends StreamProvider {

  @override
  String get id => 'pontofinal';

  @override
  String get label => 'PontoFinal';

  @override
  int get priority => 40;

  @override
  Future<ResolvedStream?> resolve(MediaRef ref, ResolverContext ctx) async {
    for (final String base in ctx.sourceBases(id)) {
      final Uri page = Uri.parse(ref.isTv
          ? '$base/serie/${ref.tmdbId}/${ref.season}/${ref.episode}'
          : '$base/filme/${ref.tmdbId}');
      final ResolvedStream? stream = await ctx.follow(
        page,
        providerId: id,
        providerLabel: label,
      );
      if (stream != null) return stream;
    }
    return null;
  }
}
