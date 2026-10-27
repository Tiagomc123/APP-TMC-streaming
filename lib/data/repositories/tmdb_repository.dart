import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/app_config.dart';
import '../models/media_item.dart';

class TmdbException implements Exception {
  TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TmdbPage {
  const TmdbPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  final List<MediaItem> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

class TmdbRepository {
  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? q,
  ]) async {
    final Map<String, String> params = <String, String>{
      'path': path,
      'language': 'pt-BR',
      'region': 'BR',
      ...?q,
    };
    final Uri uri = Uri.parse(AppConfig.tmdbProxyBase)
        .replace(queryParameters: params);

    final http.Response res = await http
        .get(
          uri,
          headers: <String, String>{'apikey': AppConfig.supabasePublishableKey},
        )
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw TmdbException('Proxy TMDB HTTP ${res.statusCode}');
    }
    return json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<TmdbPage> _list(
    String path,
    bool isTv, {
    int page = 1,
    Map<String, String>? query,
    bool mixedMedia = false,
  }) async {
    final Map<String, String> params = <String, String>{
      'page': '$page',
      ...?query,
    };
    final Map<String, dynamic> data = await _get(path, params);
    final List<dynamic> results =
        (data['results'] as List<dynamic>?) ?? const <dynamic>[];
    final Iterable<dynamic> supportedResults = mixedMedia
        ? results.where(
            (dynamic item) =>
                item is Map &&
                (item['media_type'] == 'movie' || item['media_type'] == 'tv'),
          )
        : results;
    final List<MediaItem> items = supportedResults
        .map((dynamic e) => MediaItem.fromJson(e as Map<String, dynamic>, isTv))
        .where((MediaItem m) => m.id != 0)
        .toList();
    final int currentPage = (data['page'] as num?)?.toInt() ?? page;
    final int totalPages =
        ((data['total_pages'] as num?)?.toInt() ?? currentPage)
            .clamp(1, 500)
            .toInt();
    return TmdbPage(items: items, page: currentPage, totalPages: totalPages);
  }

  Future<TmdbPage> trending({int page = 1}) =>
      _list('/trending/all/week', false, page: page, mixedMedia: true);

  Future<TmdbPage> popularMovies({int page = 1}) =>
      _list('/movie/popular', false, page: page);

  Future<TmdbPage> popularTv({int page = 1}) =>
      _list('/tv/popular', true, page: page);

  Future<TmdbPage> topRatedMovies({int page = 1}) =>
      _list('/movie/top_rated', false, page: page);

  Future<TmdbPage> topRatedTv({int page = 1}) =>
      _list('/tv/top_rated', true, page: page);

  Future<TmdbPage> search(String query, bool isTv, {int page = 1}) => _list(
    isTv ? '/search/tv' : '/search/movie',
    isTv,
    page: page,
    query: <String, String>{'query': query, 'include_adult': 'false'},
  );

  /// Catalogo com filtros rapidos de genero / nota / ordenacao.
  Future<TmdbPage> discover({
    required bool isTv,
    int page = 1,
    int? genreId,
    double minRating = 0,
    String sort = 'popularity.desc',
    int? year,
  }) {
    final Map<String, String> query = <String, String>{
      'sort_by': sort,
      'include_adult': 'false',
      if (genreId != null && genreId > 0) 'with_genres': '$genreId',
      if (minRating > 0) 'vote_average.gte': minRating.toStringAsFixed(1),
      if (minRating > 0) 'vote_count.gte': '60',
      if (year != null && year > 1900)
        (isTv ? 'first_air_date_year' : 'primary_release_year'): '$year',
    };
    return _list(isTv ? '/discover/tv' : '/discover/movie', isTv, page: page, query: query);
  }

  Future<List<Map<String, dynamic>>> genres(bool isTv) async {
    try {
      final Map<String, dynamic> data =
          await _get(isTv ? '/genre/tv/list' : '/genre/movie/list');
      return ((data['genres'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> m) => m.cast<String, dynamic>())
          .where((Map<String, dynamic> m) => (m['name'] ?? '').toString().isNotEmpty)
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> movieDetails(int id) async {
    try {
      final Map<String, dynamic> details = await _get('/movie/$id', <String, String>{
        'append_to_response': 'videos,credits,release_dates,similar',
      });
      details['videos'] = await _videosWithLanguageFallback('/movie/$id/videos', details['videos']);
      return details;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> tvDetails(int id) async {
    try {
      final Map<String, dynamic> details = await _get('/tv/$id', <String, String>{
        'append_to_response': 'videos,credits,content_ratings,similar',
      });
      details['videos'] = await _videosWithLanguageFallback('/tv/$id/videos', details['videos']);
      return details;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _videosWithLanguageFallback(
    String path,
    dynamic initial,
  ) async {
    bool hasYoutubeTrailer(dynamic value) =>
        value is Map &&
        value['results'] is List &&
        (value['results'] as List).any(
          (dynamic video) =>
              video is Map &&
              video['site'] == 'YouTube' &&
              video['type'] == 'Trailer' &&
              (video['key']?.toString().isNotEmpty ?? false),
        );

    if (hasYoutubeTrailer(initial)) return Map<String, dynamic>.from(initial as Map);

    for (final String language in <String>['pt-BR', 'en-US']) {
      try {
        final Map<String, dynamic> response = await _get(path, <String, String>{
          'language': language,
          'include_video_language': 'pt,null,en',
        });
        if (hasYoutubeTrailer(response)) return response;
      } catch (_) {}
    }
    return initial is Map
        ? Map<String, dynamic>.from(initial)
        : <String, dynamic>{'results': <dynamic>[]};
  }

  Future<List<Map<String, dynamic>>> similar(int id, bool isTv) async {
    try {
      final Map<String, dynamic> d = await _get(
        isTv ? '/tv/$id/similar' : '/movie/$id/similar',
      );
      return ((d['results'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e as Map<String, dynamic>)
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}