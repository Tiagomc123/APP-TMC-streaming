import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../models/media_ref.dart';

/// Registro de reproducao com precisao de MILISSEGUNDOS.
class WatchEntry {
  WatchEntry({
    required this.ref,
    required this.position,
    required this.duration,
    DateTime? watchedAt,
  }) : watchedAt = watchedAt ?? DateTime.now();

  final MediaRef ref;
  final Duration position;
  final Duration duration;
  final DateTime watchedAt;

  double get progress => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  bool get finished => progress >= 0.95;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'k': ref.key,
        't': ref.title,
        'tv': ref.isTv,
        'id': ref.tmdbId,
        's': ref.season,
        'e': ref.episode,
        'yr': ref.year,
        'po': ref.poster,
        'pm': position.inMilliseconds,
        'dm': duration.inMilliseconds,
        'w': watchedAt.millisecondsSinceEpoch,
      };

  /// Compatibilidade: registros antigos gravavam segundos em 'p'/'d'.
  static WatchEntry fromJson(Map<String, dynamic> j) {
    final int positionMs = j['pm'] != null
        ? (j['pm'] as num).toInt()
        : ((j['p'] ?? 0) as num).toInt() * 1000;
    final int durationMs = j['dm'] != null
        ? (j['dm'] as num).toInt()
        : ((j['d'] ?? 0) as num).toInt() * 1000;

    return WatchEntry(
      ref: MediaRef(
        tmdbId: (j['id'] ?? 0) as int,
        isTv: (j['tv'] ?? false) as bool,
        title: (j['t'] ?? '').toString(),
        season: (j['s'] ?? 1) as int,
        episode: (j['e'] ?? 1) as int,
        year: (j['yr'] ?? '').toString(),
        poster: (j['po'] ?? '').toString(),
      ),
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      watchedAt: DateTime.fromMillisecondsSinceEpoch((j['w'] ?? 0) as int),
    );
  }
}

/// Persistencia local: favoritos, "continuar assistindo" e historico geral.
class LibraryRepository {
  LibraryRepository._();
  static final LibraryRepository instance = LibraryRepository._();

  static const String _kFavs = 'tmc_favs';
  static const String _kWatch = 'tmc_watch';
  static const String _kHistory = 'tmc_history_v1';
  static const int _maxWatch = 60;
  static const int _maxHistory = 200;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<MediaItem> _favs = <MediaItem>[];
  List<WatchEntry> _watch = <WatchEntry>[];
  List<WatchEntry> _history = <WatchEntry>[];

  List<MediaItem> get favorites => List<MediaItem>.unmodifiable(_favs);

  /// Fila de "continuar assistindo": nao concluidos, mais recentes primeiro.
  List<WatchEntry> get continueWatching {
    final List<WatchEntry> out =
        _watch.where((WatchEntry w) => !w.finished).toList()
          ..sort((WatchEntry a, WatchEntry b) => b.watchedAt.compareTo(a.watchedAt));
    return List<WatchEntry>.unmodifiable(out.take(20).toList());
  }

  /// Historico geral, mais recente primeiro.
  List<WatchEntry> get history {
    final List<WatchEntry> out = List<WatchEntry>.of(_history)
      ..sort((WatchEntry a, WatchEntry b) => b.watchedAt.compareTo(a.watchedAt));
    return List<WatchEntry>.unmodifiable(out);
  }

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

    _watch = _decodeList(prefs.getString(_kWatch));
    _history = _decodeList(prefs.getString(_kHistory));

    revision.value++;
  }

  List<WatchEntry> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <WatchEntry>[];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((dynamic e) => WatchEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <WatchEntry>[];
    }
  }

  Map<String, dynamic> _favJson(MediaItem m) => <String, dynamic>{
        'id': m.id,
        'title': m.title,
        'isTv': m.isTv,
        'poster_path': m.poster,
        'backdrop_path': m.backdrop,
        'overview': m.overview,
        'release_date': m.date,
        'vote_average': m.rating,
      };

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _kFavs,
      jsonEncode(_favs.map(_favJson).toList()),
    );
    await prefs.setString(
      _kWatch,
      jsonEncode(_watch.map((WatchEntry w) => w.toJson()).toList()),
    );
    await prefs.setString(
      _kHistory,
      jsonEncode(_history.map((WatchEntry w) => w.toJson()).toList()),
    );
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

  WatchEntry? entryOf(String key) {
    for (final WatchEntry w in _watch) {
      if (w.ref.key == key) return w;
    }
    return null;
  }

  /// Grava progresso (ms) e alimenta simultaneamente "continuar assistindo"
  /// e o historico geral.
  Future<void> saveProgress(
    MediaRef ref,
    Duration position,
    Duration duration,
  ) async {
    if (duration <= Duration.zero && position < const Duration(seconds: 3)) {
      return;
    }

    final WatchEntry entry =
        WatchEntry(ref: ref, position: position, duration: duration);

    _watch = <WatchEntry>[
      entry,
      ..._watch.where((WatchEntry w) => w.ref.key != ref.key),
    ];
    if (_watch.length > _maxWatch) _watch = _watch.sublist(0, _maxWatch);

    _history = <WatchEntry>[
      entry,
      ..._history.where((WatchEntry w) => w.ref.key != ref.key),
    ];
    if (_history.length > _maxHistory) _history = _history.sublist(0, _maxHistory);

    await _persist();
  }

  Future<void> addHistory(MediaRef ref, Duration position, Duration duration) =>
      saveProgress(ref, position, duration);

  Future<void> complete(MediaRef ref) async {
    Duration position = Duration.zero;
    Duration duration = Duration.zero;
    for (final WatchEntry w in _watch) {
      if (w.ref.key == ref.key) {
        position = w.position;
        duration = w.duration;
        break;
      }
    }
    if (duration <= Duration.zero) duration = position;
    if (duration <= Duration.zero) duration = const Duration(seconds: 1);
    await saveProgress(ref, duration, duration);
  }

  Future<void> removeFromHistory(String key) async {
    _history = _history.where((WatchEntry w) => w.ref.key != key).toList();
    await _persist();
  }

  Future<void> clearHistory() async {
    _history = <WatchEntry>[];
    await _persist();
  }

  Future<void> clearContinueWatching() async {
    _watch = <WatchEntry>[];
    await _persist();
  }

  /// Apaga historico + progresso (mantem favoritos).
  Future<void> clearAllHistory() async {
    _watch = <WatchEntry>[];
    _history = <WatchEntry>[];
    await _persist();
  }
}