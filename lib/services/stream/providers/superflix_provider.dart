import '../../../data/models/media_ref.dart';
import '../../../data/models/resolved_stream.dart';
import 'stream_provider.dart';

/// SuperFlix API (JSON): rota direta, sem HTML. Fonte mais rapida.
class SuperFlixApiProvider extends StreamProvider {
  @override
  String get id => 'superflix_api';

  @override
  String get label => 'SuperFlix';

  @override
  int get priority => 10;

  @override
  Future<ResolvedStream?> resolve(MediaRef ref, ResolverContext ctx) async {
    for (final String base in ctx.sourceBases(id)) {
      final String path = ref.isTv
          ? 'serie/${ref.tmdbId}/${ref.season}/${ref.episode}'
          : 'filme/${ref.tmdbId}';

      final Map<String, dynamic>? json =
          await ctx.http.getJson('$base/$path?format=json', referer: '$base/');
      if (json == null) continue;

      final ResolvedStream? direct = await ctx.fromDirectCandidates(
        _deepCollect(json),
        providerId: id,
        providerLabel: label,
        referer: '$base/',
      );
      if (direct != null) return direct;

      // a API pode devolver uma pagina de embed em vez do arquivo
      final dynamic embedRaw = json['url'] ?? json['player'];
      if (embedRaw is String && embedRaw.startsWith('http')) {
        final ResolvedStream? nested =
            await ctx.follow(Uri.parse(embedRaw), providerId: id, providerLabel: label);
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
        if (s.startsWith('http') && (s.contains('.m3u8') || s.contains('.mp4'))) out.add(s);
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
