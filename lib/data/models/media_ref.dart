class MediaRef {
  const MediaRef({
    required this.tmdbId,
    required this.isTv,
    required this.title,
    this.season = 1,
    this.episode = 1,
    this.year = '',
    this.imdbId = '',
  });

  final int tmdbId;
  final bool isTv;
  final String title;
  final int season;
  final int episode;
  final String year;
  final String imdbId;

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
      );

  @override
  bool operator ==(Object other) => other is MediaRef && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'MediaRef($key)';
}