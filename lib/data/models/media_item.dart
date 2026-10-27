import '../../core/app_config.dart';

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.isTv,
    this.poster = '',
    this.backdrop = '',
    this.overview = '',
    this.date = '',
    this.rating = 0,
  });

  final int id;
  final String title;
  final bool isTv;
  final String poster;
  final String backdrop;
  final String overview;
  final String date;
  final double rating;

  String get key => isTv ? 'tv_$id' : 'movie_$id';
  String get typeLabel => isTv ? 'SERIE' : 'FILME';
  String get year => date.length >= 4 ? date.substring(0, 4) : '';
  String get posterUrl =>
      poster.isEmpty ? '' : '${AppConfig.tmdbImageBase}/w342$poster';
  String get backdropUrl =>
      backdrop.isEmpty ? '' : '${AppConfig.tmdbImageBase}/w780$backdrop';

  factory MediaItem.fromJson(Map<String, dynamic> j, bool isTv) {
    // /trending/all mixes movies and TV shows; trust its media_type per item.
    final bool itemIsTv = isTv || j['media_type'] == 'tv';
    return MediaItem(
      id: (j['id'] ?? 0) as int,
      title: (itemIsTv ? j['name'] : j['title'] ?? j['name'] ?? 'Sem titulo')
          .toString(),
      isTv: itemIsTv,
      poster: (j['poster_path'] ?? '').toString(),
      backdrop: (j['backdrop_path'] ?? '').toString(),
      overview: (j['overview'] ?? '').toString(),
      date: (itemIsTv ? j['first_air_date'] : j['release_date'] ?? '')
          .toString(),
      rating: ((j['vote_average'] ?? 0) as num).toDouble(),
    );
  }
}
