import '../../../data/models/media_ref.dart';
import '../../../data/models/resolved_stream.dart';
import 'stream_provider.dart';

/// WarezCDN: a pagina de embed esconde os parametros em JS e so o
/// `getPlayer.php` devolve o host real. Duas requisicoes invisiveis,
/// sem abrir WebView.
class WarezCdnProvider extends StreamProvider {

  @override
  String get id => 'warezcdn';

  @override
  String get label => 'WarezCDN';

  @override
  int get priority => 20;

  @override
  Future<ResolvedStream?> resolve(MediaRef ref, ResolverContext ctx) async {
    for (final String base in ctx.sourceBases(id)) {
      final ResolvedStream? stream = await _resolveFromBase(ref, ctx, base);
      if (stream != null) return stream;
    }
    return null;
  }

  Future<ResolvedStream?> _resolveFromBase(
    MediaRef ref,
    ResolverContext ctx,
    String base,
  ) async {
    final String embedUrl = ref.isTv
        ? '$base/embed/serie.php?id=${ref.tmdbId}&season=${ref.season}&episode=${ref.episode}'
        : '$base/embed/filme.php?id=${ref.tmdbId}';

    final res = await ctx.http.getText(embedUrl, referer: '$base/');
    if (res == null || !res.ok) return null;

    final RegExpMatch? apiMatch =
        RegExp(r'''getPlayer\.php\?([^"'\\]+)''').firstMatch(res.body);

    if (apiMatch != null) {
      final Map<String, dynamic>? json = await ctx.http.getJson(
        '$base/getPlayer.php?${apiMatch.group(1)}',
        referer: embedUrl,
      );

      if (json != null) {
        final String? host = json['host'] as String?;
        final String? url = json['url'] as String?;

        if (url != null && url.startsWith('http')) {
          final ResolvedStream? direct = await ctx.fromDirectCandidates(
            <String>[url],
            providerId: id,
            providerLabel: label,
            referer: '$base/',
          );
          if (direct != null) return direct;

          if (host != null) {
            final ResolvedStream? nested = await ctx.follow(
              Uri.parse(_hostToEmbed(host, url)),
              providerId: id,
              providerLabel: label,
            );
            if (nested != null) return nested;
          }
        }
      }
    }

    // fallback: varredura normal do HTML do embed
    return ctx.follow(Uri.parse(embedUrl), providerId: id, providerLabel: label);
  }

  String _hostToEmbed(String host, String id) {
    switch (host.toLowerCase()) {
      case 'embed':
      case 'warezcdn':
        return 'https://embed.warezcdn.com/embed.php?id=$id';
      case 'superflix':
        return 'https://superflixapi.fun/filme/$id';
      default:
        return id.startsWith('http') ? id : 'https://embed.warezcdn.com/embed.php?id=$id';
    }
  }
}
