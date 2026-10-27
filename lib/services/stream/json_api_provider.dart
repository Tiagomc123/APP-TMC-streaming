import 'dart:convert';

import '../../core/net/tmc_http.dart';
import '../../data/models/media_ref.dart';
import '../../data/models/resolved_stream.dart';
import 'json_api_spec.dart';
import 'url_sanitizer.dart';
import 'providers/stream_provider.dart';

/// =============================================================================
///  MOTOR DE API JSON
///
///  Um unico provider serve todas as fontes: le o [JsonApiSpec], monta a URL
///  com o ID do TMDB/IMDB, consome o JSON, sanitiza as strings e devolve
///  apenas a URL direta do manifesto.
///
///  Nao abre WebView. Nao renderiza HTML para o usuario.
/// =============================================================================
class JsonApiProvider extends StreamProvider {
  JsonApiProvider(this.spec);

  final JsonApiSpec spec;

  static const int _maxRequests = 6;

  @override
  String get id => spec.id;

  @override
  String get label => spec.label;

  @override
  int get priority => spec.priority;

  @override
  Future<ResolvedStream?> resolve(MediaRef ref, ResolverContext ctx) async {
    final List<String> bases = ctx.basesFor(id, spec.bases);
    if (bases.isEmpty) return null;

    int budget = _maxRequests;

    for (final String path in spec.pathsFor(ref)) {
      final String? built = spec.build(ref, path);
      if (built == null) continue;

      for (final String base in bases) {
        if (budget <= 0) break;
        budget--;

        final String endpoint = '$base/$built';
        final HttpResult? res = await ctx.http.getText(
          endpoint,
          referer: '$base/',
          origin: base,
          json: true,
        );
        if (res == null || !res.ok) continue;

        final List<String> media = _mediaFrom(res.body);
        if (media.isNotEmpty) {
          final ResolvedStream? direct = await ctx.fromDirectCandidates(
            media,
            providerId: id,
            providerLabel: label,
            referer: '$base/',
          );
          if (direct != null) return direct;
        }

        if (spec.followPages) {
          final ResolvedStream? hop = await _followFirstPage(res.body, base, ctx);
          if (hop != null) return hop;
        }
      }
    }
    return null;
  }

  /// Extrai midia do corpo: JSON puro ou HTML/JS cru.
  List<String> _mediaFrom(String body) {
    final String trimmed = body.trimLeft();

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final dynamic decoded = jsonDecode(body);

        if (spec.mode == JsonApiMode.playlistField) {
          final String? field = _playlistField(decoded);
          if (field != null) {
            final String? clean = UrlSanitizer.extractMedia(field);
            if (clean != null) return <String>[clean];
          }
        }

        final List<String> all = UrlSanitizer.extractAll(decoded);
        if (all.isNotEmpty) return all;
      } catch (_) {}
    }

    final List<String> raw = <String>[];
    for (final RegExpMatch m in UrlSanitizer.urlRe.allMatches(body)) {
      raw.add(m.group(0)!);
    }
    return UrlSanitizer.extractAll(raw);
  }

  /// Campo de manifesto declarado pela API (ex.: stream.playlist).
  String? _playlistField(dynamic node) {
    if (node is Map) {
      for (final String key in <String>['playlist', 'url', 'file', 'link']) {
        final dynamic value = node[key];
        if (value is String && value.startsWith('http') && UrlSanitizer.isMedia(value)) {
          return value;
        }
        if (value is Map) {
          final dynamic nested = value['playlist'] ?? value['url'] ?? value['file'];
          if (nested is String && nested.startsWith('http')) return nested;
        }
      }
      for (final dynamic value in node.values) {
        final String? found = _playlistField(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final dynamic item in node) {
        final String? found = _playlistField(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Ultimo recurso: 1 salto HTTP na primeira pagina de player encontrada.
  Future<ResolvedStream?> _followFirstPage(
    String body,
    String base,
    ResolverContext ctx,
  ) async {
    final List<String> pages = UrlSanitizer.extractPages(body);
    for (final String page in pages.take(2)) {
      final ResolvedStream? stream = await ctx.follow(
        Uri.parse(page),
        providerId: id,
        providerLabel: label,
        referer: '$base/',
      );
      if (stream != null && stream.kind != StreamKind.embed) return stream;
    }
    return null;
  }
}