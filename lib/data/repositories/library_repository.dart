import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../models/media_ref.dart';

class WatchEntry {
  WatchEntry({required this.ref, required this.position, required this.duration});
  final MediaRef ref;
  final Duration position;
  final Duration duration;

  double get progress => duration.inSeconds == 0
      ? 0
      : (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'k': ref.key,
        't': ref.title,
        'tv': ref.isTv,
        'id': ref.tmdbId,
        's': ref.season,
        'e': ref.episode,
        'p': position.inSeconds,
        'd': duration.inSeconds,
      };

  static WatchEntry fromJson(Map<String, dynamic> j) => WatchEntry(
        ref: MediaRef(
          tmdbId: (j['id'] ?? 0) as int,
          isTv: (j['tv'] ?? false) as bool,
          title: (j['t'] ?? '').toString(),
          season: (j['s'] ?? 1) as int,
          episode: (j['e'] ?? 1) as int,
        ),
        position: Duration(seconds: (j['p'] ?? 0) as int),
        duration: Duration(seconds: (j['d'] ?? 0) as int),
      );
}

class LibraryRepository {
  LibraryRepository._();
  static final LibraryRepository instance = LibraryRepository._();

  static const String _kFavs = 'tmc_favs';
  static const String _kWatch = 'tmc_watch';

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<MediaItem> _favs = <MediaItem>[];
  List<WatchEntry> _watch = <WatchEntry>[];

  List<MediaItem> get favorites => List<MediaItem>.unmodifiable(_favs);
  List<WatchEntry> get continueWatching =>
      _watch.where((WatchEntry w) => w.progress < 0.95).toList();

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    try {
      final String raw = prefs.getString(_kFavs) ?? '[]';
      _favs = (jsonDecode(raw) as List<dynamic>).map((dynamic e) {
        final Map<String, dynamic> m = (e as Map<String, dynamic>);
        return MediaItem.fromJson(m, (m['isTv'] ?? false) as bool);
      }).toList();
    } catch (_) {
      _favs = <MediaItem>[];
    }

    try {
      final String raw = prefs.getString(_kWatch) ?? '[]';
      _watch = (jsonDecode(raw) as List<dynamic>)
          .map((dynamic e) => WatchEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _watch = <WatchEntry>[];
    }

    revision.value++;
  }

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _kFavs,
      jsonEncode(_favs
          .map((MediaItem m) => <String, dynamic>{
                'id': m.id,
                'title': m.title,
                'isTv': m.isTv,
                'poster_path': m.poster,
                'backdrop_path': m.backdrop,
                'overview': m.overview,
                'release_date': m.date,
                'vote_average': m.rating,
              })
          .toList()),
    );
    await prefs.setString(_kWatch, jsonEncode(_watch.map((WatchEntry w) => w.toJson()).toList()));
    revision.value++;
  }

  bool isFavorite(String key) => _favs.any((MediaItem m) => m.key == key);

  Future<void> toggleFavorite(MediaItem item) async {
    if (isFavorite(item.key)) {
      _favs = _favs.where((MediaItem m) => m.key != item.key).toList();
    } else {
      _favs = <MediaItem>[item, ..._favs.where((MediaItem m) => m.key != item.key)];
    }
    await _persist();
  }

  Duration positionOf(String key) {
    for (final WatchEntry w in _watch) {
      if (w.ref.key == key) return w.position;
    }
    return Duration.zero;
  }

  Future<void> saveProgress(MediaRef ref, Duration position, Duration duration) async {
    if (position.inSeconds < 5 || duration.inSeconds <= 0) return;
    _watch = <WatchEntry>[
      WatchEntry(ref: ref, position: position, duration: duration),
      ..._watch.where((WatchEntry w) => w.ref.key != ref.key),
    ];
    if (_watch.length > 60) _watch = _watch.sublist(0, 60);
    await _persist();
  }

  Future<void> complete(MediaRef ref) async {
    final Duration p = positionOf(ref.key);
    await saveProgress(ref, p, p == Duration.zero ? const Duration(seconds: 1) : p);
  }
}