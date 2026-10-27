/// Referencia minima e serializavel de um titulo reproduzivel.
class MediaRef {
  const MediaRef({
    required this.tmdbId,
    required this.isTv,
    required this.title,
    this.season = 1,
    this.episode = 1,
    this.year = '',
    this.imdbId = '',
    this.poster = '',
  });

  final int tmdbId;
  final bool isTv;
  final String title;
  final int season;
  final int episode;
  final String year;
  final String imdbId;

  /// Caminho TMDB do poster (ex.: "/abc.jpg"). Usado no historico.
  final String poster;

  String get key => isTv ? 'tv_${tmdbId}_${season}_$episode' : 'movie_$tmdbId';
  String get display => isTv ? '$title - T$season E$episode' : title;

  MediaRef nextEpisode() => MediaRef(
        tmdbId: tmdbId,
        isTv: isTv,
        title: title,
        season: season,
        episode: episode + 1,
        year: year,
        imdbId: imdbId,
        poster: poster,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': tmdbId,
        'tv': isTv,
        't': title,
        's': season,
        'e': episode,
        'yr': year,
        'imdb': imdbId,
        'po': poster,
      };

  static MediaRef fromJson(Map<String, dynamic> j) => MediaRef(
        tmdbId: (j['id'] ?? 0) as int,
        isTv: (j['tv'] ?? false) as bool,
        title: (j['t'] ?? '').toString(),
        season: (j['s'] ?? 1) as int,
        episode: (j['e'] ?? 1) as int,
        year: (j['yr'] ?? '').toString(),
        imdbId: (j['imdb'] ?? '').toString(),
        poster: (j['po'] ?? '').toString(),
      );

  @override
  bool operator ==(Object other) => other is MediaRef && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'MediaRef($key)';
}