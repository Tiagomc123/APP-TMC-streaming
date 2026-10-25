# =====================================================================
#  TMC  -  ATUALIZADOR AUTOMATICO DO APP  (build 2.1 - fixes)
#  Corrige: setMediaPlaybackRequiresUserGesture (compatibilidade),
#           campo nao usado e ~60 avisos de concatenacao de string.
#  Uso: powershell -ExecutionPolicy Bypass -File .\atualizar.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if ([string]::IsNullOrEmpty($root)) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '   TMC  -  Atualizando aplicativo (build 2.1)' -ForegroundColor Cyan
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host ''

$libDir   = Join-Path $root 'lib'
$mainPath = Join-Path $libDir 'main.dart'

if (-not (Test-Path -LiteralPath $libDir)) {
    New-Item -ItemType Directory -Force -Path $libDir | Out-Null
}

$pubPath = Join-Path $root 'pubspec.yaml'
if (Test-Path -LiteralPath $pubPath) {
    $pubRaw = Get-Content -LiteralPath $pubPath -Raw
    if ($pubRaw -notmatch 'shared_preferences') {
        Write-Host '-> Adicionando dependencia shared_preferences...' -ForegroundColor Yellow
        try { & flutter pub add shared_preferences } catch { Write-Host '   (aviso: flutter pub add falhou)' -ForegroundColor Yellow }
    } else {
        Write-Host '-> shared_preferences ja presente no pubspec.' -ForegroundColor DarkGray
    }
}

if (Test-Path -LiteralPath $mainPath) {
    Copy-Item -LiteralPath $mainPath -Destination "$mainPath.bak" -Force
    Write-Host '-> Backup salvo em lib/main.dart.bak' -ForegroundColor DarkGray
}

$dart = @'
// =====================================================================
//  TMC  -  Agregador de Streaming   (build 2.1 - "YouCine Edition")
//  Catalogo TMDB + Resolvedores BR + Player HLS + Resume + Favoritos
//  >>>>> COLE A SUA CHAVE DO TMDB NA LINHA MARCADA ABAIXO <<<<<
// =====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ======================= CONFIGURACAO ================================
String tmdbApiKey = "SUA_CHAVE_AQUI";

const String kTmdbBase = "https://api.themoviedb.org/3";
const String kTmdbImg = "https://image.tmdb.org/t/p";
const String kUserAgent =
    "Mozilla/5.0 (Linux; Android 11; Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

const Color kBg = Color(0xFF070A12);
const Color kSurface = Color(0xFF121826);
const Color kCard = Color(0xFF1A2233);
const Color kAccent = Color(0xFF3D7BFF);
const Color kGold = Color(0xFFF5C451);
const Color kRed = Color(0xFFE5484D);

const int kGenreSoap = 10766;
const int kGenreDrama = 18;
const int kGenreAction = 28;
const int kGenreAnimation = 16;

late SharedPreferences prefs;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  prefs = await SharedPreferences.getInstance();
  runApp(const TmcApp());
}

class TmcApp extends StatelessWidget {
  const TmcApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData base = ThemeData.dark(useMaterial3: true);
    // Correcao de tipos do GoogleFonts: usamos apenas o fontFamily e
    // aplicamos no TextTheme do proprio tema (evita conflito de tipos).
    final String? font = GoogleFonts.poppins().fontFamily;

    return MaterialApp(
      title: 'TMC',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: kBg,
        colorScheme: base.colorScheme.copyWith(
          primary: kAccent,
          secondary: kGold,
          surface: kSurface,
        ),
        textTheme: base.textTheme.apply(
          fontFamily: font,
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: kCard,
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const RootShell(),
    );
  }
}

// ============================ MODELOS ================================
class MediaItem {
  final int id;
  final String title;
  final String? poster;
  final String? backdrop;
  final String overview;
  final String? date;
  final double rating;
  final bool isTv;
  final List<int> genres;

  MediaItem({
    required this.id,
    required this.title,
    this.poster,
    this.backdrop,
    this.overview = '',
    this.date,
    this.rating = 0,
    required this.isTv,
    this.genres = const <int>[],
  });

  String get key => isTv ? 'tv_$id' : 'movie_$id';
  String get typeLabel => isTv ? 'SERIE' : 'FILME';
  String get posterUrl =>
      (poster == null || poster!.isEmpty) ? '' : '$kTmdbImg/w342$poster';
  String get backdropUrl =>
      (backdrop == null || backdrop!.isEmpty) ? '' : '$kTmdbImg/w780$backdrop';

  String get year {
    final String? d = date;
    if (d != null && d.length >= 4) return d.substring(0, 4);
    return '';
  }

  factory MediaItem.fromJson(Map<String, dynamic> j, bool isTv) {
    final dynamic rawTitle = isTv ? j['name'] : j['title'];
    return MediaItem(
      id: (j['id'] ?? 0) as int,
      title: (rawTitle ?? j['name'] ?? j['title'] ?? 'Sem titulo').toString(),
      poster: j['poster_path']?.toString(),
      backdrop: j['backdrop_path']?.toString(),
      overview: (j['overview'] ?? '').toString(),
      date: (isTv ? j['first_air_date'] : j['release_date'])?.toString(),
      rating: ((j['vote_average'] ?? 0) as num).toDouble(),
      isTv: isTv,
      genres: ((j['genre_ids'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => (e as num).toInt())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'poster_path': poster,
        'backdrop_path': backdrop,
        'overview': overview,
        'release_date': date,
        'first_air_date': date,
        'vote_average': rating,
        'isTv': isTv,
      };

  static MediaItem fromStored(Map<String, dynamic> j) => MediaItem(
        id: (j['id'] ?? 0) as int,
        title: (j['title'] ?? 'Sem titulo').toString(),
        poster: j['poster_path']?.toString(),
        backdrop: j['backdrop_path']?.toString(),
        overview: (j['overview'] ?? '').toString(),
        date: (j['release_date'] ?? j['first_air_date'])?.toString(),
        rating: ((j['vote_average'] ?? 0) as num).toDouble(),
        isTv: (j['isTv'] ?? false) as bool,
      );
}

class Episode {
  final int number;
  final String name;
  final String overview;
  final String? still;
  final String? air;
  final int runtime;

  Episode({
    required this.number,
    required this.name,
    this.overview = '',
    this.still,
    this.air,
    this.runtime = 0,
  });

  String get stillUrl =>
      (still == null || still!.isEmpty) ? '' : '$kTmdbImg/w300$still';

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        number: (j['episode_number'] ?? 0) as int,
        name: (j['name'] ?? 'Capitulo').toString(),
        overview: (j['overview'] ?? '').toString(),
        still: j['still_path']?.toString(),
        air: j['air_date']?.toString(),
        runtime: (j['runtime'] ?? 0) as int,
      );
}

class WatchItem {
  final MediaItem media;
  final int season;
  final int episode;
  final int position;
  final int duration;

  WatchItem({
    required this.media,
    this.season = 0,
    this.episode = 0,
    this.position = 0,
    this.duration = 0,
  });

  String get key =>
      media.isTv ? '${media.key}_${season}_$episode' : media.key;

  double get progress =>
      duration <= 0 ? 0.0 : (position / duration).clamp(0.0, 1.0);

  String get label => media.isTv ? 'T$season E$episode' : 'FILME';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'media': media.toJson(),
        's': season,
        'e': episode,
        'p': position,
        'd': duration,
      };

  static WatchItem fromJson(Map<String, dynamic> j) => WatchItem(
        media: MediaItem.fromStored(
            (j['media'] as Map<dynamic, dynamic>).cast<String, dynamic>()),
        season: (j['s'] ?? 0) as int,
        episode: (j['e'] ?? 0) as int,
        position: (j['p'] ?? 0) as int,
        duration: (j['d'] ?? 0) as int,
      );
}

// ========================= ARMAZENAMENTO =============================
class Store {
  static const String kFavs = 'tmc_favs';
  static const String kProg = 'tmc_progress';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<String> _favKeys() => prefs.getStringList(kFavs) ?? <String>[];
  static List<String> _progKeys() => prefs.getStringList(kProg) ?? <String>[];

  static bool isFav(String key) => prefs.getBool('fav_$key') ?? false;

  static Future<void> toggleFav(MediaItem m) async {
    final List<String> list = _favKeys().toList();
    if (isFav(m.key)) {
      await prefs.setBool('fav_${m.key}', false);
      list.remove(m.key);
    } else {
      await prefs.setBool('fav_${m.key}', true);
      await prefs.setString('favd_${m.key}', jsonEncode(m.toJson()));
      list.remove(m.key);
      list.insert(0, m.key);
    }
    await prefs.setStringList(kFavs, list);
    revision.value++;
  }

  static List<MediaItem> favorites() {
    final List<MediaItem> out = <MediaItem>[];
    for (final String k in _favKeys()) {
      final String? raw = prefs.getString('favd_$k');
      if (raw == null) continue;
      try {
        out.add(MediaItem.fromStored(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  static WatchItem? progress(String key) {
    final String? raw = prefs.getString('prog_$key');
    if (raw == null) return null;
    try {
      return WatchItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static int seconds(String key) => prefs.getInt('pos_$key') ?? 0;

  static Future<void> saveProgress(WatchItem w) async {
    if (w.position < 5) return;
    final List<String> list = _progKeys().toList();
    list.remove(w.key);
    list.insert(0, w.key);
    await prefs.setStringList(kProg, list);
    await prefs.setString('prog_${w.key}', jsonEncode(w.toJson()));
    await prefs.setInt('pos_${w.key}', w.position);
    revision.value++;
  }

  static Future<void> removeProgress(String key) async {
    final List<String> list = _progKeys().toList();
    list.remove(key);
    await prefs.setStringList(kProg, list);
    await prefs.remove('prog_$key');
    await prefs.remove('pos_$key');
    revision.value++;
  }

  static List<WatchItem> continueWatching() {
    final List<WatchItem> out = <WatchItem>[];
    for (final String k in _progKeys()) {
      final WatchItem? w = progress(k);
      if (w == null) continue;
      if (w.duration > 0 && w.progress >= 0.95) continue;
      out.add(w);
    }
    return out;
  }
}

// ============================ SERVICO TMDB ===========================
class TmdbException implements Exception {
  final String message;
  TmdbException(this.message);
  @override
  String toString() => message;
}

class TmdbService {
  static bool get ok =>
      tmdbApiKey.trim().isNotEmpty && tmdbApiKey != 'SUA_CHAVE_AQUI';

  static void _check() {
    if (!ok) {
      throw TmdbException(
          'Cole a sua chave do TMDB na variavel tmdbApiKey (topo do lib/main.dart).');
    }
  }

  static Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? q]) async {
    _check();
    final Map<String, String> params = <String, String>{
      'api_key': tmdbApiKey,
      'language': 'pt-BR',
    };
    if (q != null) params.addAll(q);
    final Uri uri = Uri.parse('$kTmdbBase$path').replace(queryParameters: params);
    final http.Response res =
        await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode == 401) {
      throw TmdbException('Chave do TMDB invalida (401). Confira a tmdbApiKey.');
    }
    if (res.statusCode != 200) {
      throw TmdbException('Erro do TMDB: HTTP ${res.statusCode}');
    }
    return json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<List<MediaItem>> _list(String path, bool isTv,
      [Map<String, String>? q, bool auto = false]) async {
    final Map<String, dynamic> data = await _get(path, q);
    final List<dynamic> results =
        (data['results'] as List<dynamic>?) ?? const <dynamic>[];
    final List<MediaItem> out = <MediaItem>[];
    for (final dynamic e in results) {
      final Map<String, dynamic> j = e as Map<String, dynamic>;
      final bool tv = auto ? (j['media_type'] == 'tv') : isTv;
      final MediaItem m = MediaItem.fromJson(j, tv);
      if (m.id != 0) out.add(m);
    }
    return out;
  }

  static Future<List<MediaItem>> _safePage(String path, bool isTv, int page,
      Map<String, String>? q, bool auto) async {
    try {
      return await _list(
          path, isTv, <String, String>{...?q, 'page': '$page'}, auto);
    } catch (_) {
      return <MediaItem>[];
    }
  }

  static Future<List<MediaItem>> _pages(String path, bool isTv,
      {int pages = 2, Map<String, String>? q, bool auto = false}) async {
    final List<Future<List<MediaItem>>> futures = <Future<List<MediaItem>>>[];
    for (int p = 1; p <= pages; p++) {
      futures.add(_safePage(path, isTv, p, q, auto));
    }
    final List<List<MediaItem>> res = await Future.wait(futures);
    final List<MediaItem> out = <MediaItem>[];
    final Set<String> seen = <String>{};
    for (final List<MediaItem> l in res) {
      for (final MediaItem m in l) {
        if (seen.add(m.key)) out.add(m);
      }
    }
    return out;
  }

  static Future<List<MediaItem>> trending({int pages = 3}) =>
      _pages('/trending/all/week', false, pages: pages, auto: true);

  static Future<List<MediaItem>> popularMovies({int pages = 3}) =>
      _pages('/movie/popular', false, pages: pages);

  static Future<List<MediaItem>> topMovies({int pages = 1}) =>
      _pages('/movie/top_rated', false, pages: pages);

  static Future<List<MediaItem>> nowPlaying({int pages = 1}) =>
      _pages('/movie/now_playing', false, pages: pages);

  static Future<List<MediaItem>> popularTv({int pages = 3}) =>
      _pages('/tv/popular', true, pages: pages);

  static Future<List<MediaItem>> topTv({int pages = 1}) =>
      _pages('/tv/top_rated', true, pages: pages);

  static Future<List<MediaItem>> onAirTv({int pages = 2}) =>
      _pages('/tv/on_the_air', true, pages: pages);

  static Future<List<MediaItem>> novelas({int pages = 2}) => _pages(
        '/discover/tv',
        true,
        pages: pages,
        q: <String, String>{
          'with_genres': '$kGenreSoap',
          'sort_by': 'popularity.desc',
        },
      );

  static Future<List<MediaItem>> shortDramas({int pages = 2}) => _pages(
        '/discover/tv',
        true,
        pages: pages,
        q: <String, String>{
          'with_genres': '$kGenreDrama',
          'with_runtime.lte': '45',
          'sort_by': 'popularity.desc',
        },
      );

  static Future<List<MediaItem>> actionMovies({int pages = 1}) => _pages(
        '/discover/movie',
        false,
        pages: pages,
        q: <String, String>{
          'with_genres': '$kGenreAction',
          'sort_by': 'popularity.desc',
        },
      );

  static Future<List<MediaItem>> animations({int pages = 1}) => _pages(
        '/discover/movie',
        false,
        pages: pages,
        q: <String, String>{
          'with_genres': '$kGenreAnimation',
          'sort_by': 'popularity.desc',
        },
      );

  static Future<List<MediaItem>> search(String query, bool isTv,
          {int pages = 1}) =>
      _pages(isTv ? '/search/tv' : '/search/movie', isTv,
          pages: pages,
          q: <String, String>{'query': query, 'include_adult': 'false'});

  static Future<List<MediaItem>> similar(int id, bool isTv, {int pages = 1}) =>
      _pages(isTv ? '/tv/$id/similar' : '/movie/$id/similar', isTv,
          pages: pages);

  static Future<Map<String, dynamic>> details(int id, bool isTv) => _get(
        isTv ? '/tv/$id' : '/movie/$id',
        <String, String>{
          'append_to_response': 'videos,release_dates,content_ratings,credits',
        },
      );

  static Future<Map<String, dynamic>> season(int id, int s) =>
      _get('/tv/$id/season/$s');

  static Future<List<Episode>> episodes(int id, int s) async {
    final Map<String, dynamic> d = await season(id, s);
    final List<dynamic> raw =
        (d['episodes'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((dynamic e) => Episode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<String?> trailerKey(int id, bool isTv) async {
    try {
      final Map<String, dynamic> d =
          await _get(isTv ? '/tv/$id/videos' : '/movie/$id/videos');
      return findTrailer(d);
    } catch (_) {
      return null;
    }
  }

  static String? findTrailer(Map<String, dynamic>? d) {
    if (d == null) return null;
    final Map<String, dynamic>? v = d['videos'] as Map<String, dynamic>?;
    final List<dynamic> raw =
        (v?['results'] as List<dynamic>?) ?? const <dynamic>[];
    Map<String, dynamic>? best;
    for (final dynamic e in raw) {
      final Map<String, dynamic> m = e as Map<String, dynamic>;
      if ((m['site'] ?? '') != 'YouTube') continue;
      final String t = (m['type'] ?? '').toString();
      if (t == 'Trailer') {
        best = m;
        if ((m['official'] ?? false) == true) break;
      } else if (best == null && t == 'Teaser') {
        best = m;
      }
    }
    return best?['key']?.toString();
  }
}

// ===================== RESOLVEDORES (FALLBACK) =======================
class PlayTarget {
  final String provider;
  final String url;
  final bool direct;
  final String referer;

  PlayTarget({
    required this.provider,
    required this.url,
    required this.direct,
    this.referer = '',
  });
}

typedef UrlBuilder = String Function(bool isTv, int id, int season, int episode);

class Provider {
  final String name;
  final UrlBuilder build;
  const Provider(this.name, this.build);
}

final List<Provider> kProviders = <Provider>[
  Provider(
    'SuperFlixAPI',
    (bool isTv, int id, int s, int e) => isTv
        ? 'https://superflixapi.top/serie/$id/$s/$e'
        : 'https://superflixapi.top/filme/$id',
  ),
  Provider(
    'EmbedCine',
    (bool isTv, int id, int s, int e) => isTv
        ? 'https://embedcine.com/serie/$id/$s/$e'
        : 'https://embedcine.com/filme/$id',
  ),
  Provider(
    'WarezCDN',
    (bool isTv, int id, int s, int e) => isTv
        ? 'https://warezcdn.com/embed/serie.php?id=$id&season=$s&episode=$e'
        : 'https://warezcdn.com/embed/filme.php?id=$id',
  ),
];

class Resolver {
  static final RegExp _m3u8 =
      RegExp(r'''https?://[^"'\s\\<>]+\.m3u8[^"'\s\\<>]*''');
  static final RegExp _iframe =
      RegExp(r'''<iframe[^>]*src=["']([^"']+)["']''', caseSensitive: false);

  static Map<String, String> _headers([String referer = '']) {
    final Map<String, String> h = <String, String>{'User-Agent': kUserAgent};
    if (referer.isNotEmpty) h['Referer'] = referer;
    return h;
  }

  /// Varredura silenciosa: confirma se o servidor esta no ar (HTTP 2xx/3xx).
  static Future<bool> alive(String url) async {
    try {
      final http.Response r = await http
          .head(Uri.parse(url), headers: _headers())
          .timeout(const Duration(seconds: 8));
      if (r.statusCode >= 200 && r.statusCode < 400) return true;
    } catch (_) {}
    try {
      final http.Response r = await http
          .get(Uri.parse(url), headers: _headers())
          .timeout(const Duration(seconds: 12));
      return r.statusCode >= 200 && r.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  static Future<PlayTarget?> resolve(
      Provider p, bool isTv, int id, int season, int episode) async {
    final String pageUrl = p.build(isTv, id, season, episode);
    final bool up = await alive(pageUrl);

    String body = '';
    try {
      final http.Response r = await http
          .get(Uri.parse(pageUrl), headers: _headers(pageUrl))
          .timeout(const Duration(seconds: 15));
      body = r.body;
    } catch (_) {}

    final Match? m = _m3u8.firstMatch(body);
    if (m != null) {
      return PlayTarget(
          provider: p.name, url: m.group(0)!, direct: true, referer: pageUrl);
    }

    final Match? f = _iframe.firstMatch(body);
    if (f != null) {
      String src = f.group(1)!.trim();
      if (src.startsWith('//')) src = 'https:$src';
      src = Uri.parse(pageUrl).resolve(src).toString();
      try {
        final http.Response r2 = await http
            .get(Uri.parse(src), headers: _headers(pageUrl))
            .timeout(const Duration(seconds: 12));
        final Match? m2 = _m3u8.firstMatch(r2.body);
        if (m2 != null) {
          return PlayTarget(
              provider: p.name, url: m2.group(0)!, direct: true, referer: src);
        }
      } catch (_) {}
      return PlayTarget(
          provider: p.name, url: src, direct: false, referer: pageUrl);
    }

    if (!up && body.isEmpty) return null;
    return PlayTarget(
        provider: p.name, url: pageUrl, direct: false, referer: pageUrl);
  }

  /// Escolhe a melhor fonte viva: prioriza link direto (.m3u8).
  static Future<PlayTarget?> best(bool isTv, int id, int season, int episode,
      {int forced = -1}) async {
    final List<Provider> list =
        forced >= 0 ? <Provider>[kProviders[forced]] : kProviders;
    PlayTarget? page;
    for (final Provider p in list) {
      final PlayTarget? t = await resolve(p, isTv, id, season, episode);
      if (t == null) continue;
      if (t.direct) return t;
      page ??= t;
    }
    return page;
  }
}

// ======================= HELPERS DE NAVEGACAO ========================
class LoadingDialog extends StatelessWidget {
  const LoadingDialog({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 72,
        height: 72,
        child: Card(
          color: kSurface,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}

Future<void> openPlayer(
  BuildContext context,
  MediaItem item, {
  int season = 1,
  int episode = 1,
  int forced = -1,
}) async {
  final NavigatorState nav = Navigator.of(context, rootNavigator: true);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (BuildContext _) => const LoadingDialog(),
  );

  PlayTarget? t;
  try {
    t = await Resolver.best(item.isTv, item.id, season, episode, forced: forced);
  } catch (_) {
    t = null;
  }

  if (nav.canPop()) nav.pop();

  if (t == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Nenhum servidor respondeu agora. Tente novamente.')));
    return;
  }

  if (t.direct) {
    nav.push(MaterialPageRoute<void>(
      builder: (BuildContext _) => PlayerScreen(
        url: t!.url,
        title: item.title,
        provider: t.provider,
        referer: t.referer,
        media: item,
        season: season,
        episode: episode,
      ),
    ));
  } else {
    nav.push(MaterialPageRoute<void>(
      builder: (BuildContext _) => WebScreen(url: t!.url, title: item.title),
    ));
  }
}

Future<void> showTrailer(
    BuildContext context, String videoKey, String title) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Trailer',
    barrierColor: Colors.black.withValues(alpha: 0.86),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.movie_creation_outlined, color: kGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: TrailerView(videoKey: videoKey),
                ),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (BuildContext ctx, Animation<double> a,
        Animation<double> b, Widget child) {
      return FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(a),
          child: child,
        ),
      );
    },
  );
}

// ============================== SHELL ================================
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _i,
        children: const <Widget>[HomeScreen(), SearchScreen(), FavoritesScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        backgroundColor: kSurface,
        indicatorColor: kAccent,
        onDestinationSelected: (int v) => setState(() => _i = v),
        destinations: const <NavigationDestination>[
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
          NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'Favoritos'),
        ],
      ),
    );
  }
}

// =========================== LOGO / CHIP =============================
class TmcLogo extends StatelessWidget {
  final double size;
  const TmcLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: <Color>[Color(0xFF1E4AAA), kAccent]),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Center(
        child: Text(
          'MC',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: size * 0.44,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

// ============================ HOME ===================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _err;
  MediaItem? _hero;
  List<MediaItem> _trending = <MediaItem>[];
  List<MediaItem> _movies = <MediaItem>[];
  List<MediaItem> _topMovies = <MediaItem>[];
  List<MediaItem> _series = <MediaItem>[];
  List<MediaItem> _novelas = <MediaItem>[];
  List<MediaItem> _dramas = <MediaItem>[];
  List<MediaItem> _action = <MediaItem>[];
  List<MediaItem> _anim = <MediaItem>[];
  List<WatchItem> _cont = <WatchItem>[];
  List<MediaItem> _favs = <MediaItem>[];

  @override
  void initState() {
    super.initState();
    Store.revision.addListener(_localRefresh);
    _localRefresh();
    _load();
  }

  @override
  void dispose() {
    Store.revision.removeListener(_localRefresh);
    super.dispose();
  }

  void _localRefresh() {
    if (!mounted) return;
    setState(() {
      _cont = Store.continueWatching();
      _favs = Store.favorites();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = null;
    });

    if (!TmdbService.ok) {
      setState(() {
        _loading = false;
        _err =
            'Cole a sua chave do TMDB na variavel tmdbApiKey (topo do lib/main.dart)';
      });
      return;
    }

    try {
      final List<List<MediaItem>> r =
          await Future.wait(<Future<List<MediaItem>>>[
        TmdbService.trending(pages: 3),
        TmdbService.popularMovies(pages: 3),
        TmdbService.topMovies(pages: 1),
        TmdbService.popularTv(pages: 3),
        TmdbService.novelas(pages: 2),
        TmdbService.shortDramas(pages: 2),
        TmdbService.actionMovies(pages: 1),
        TmdbService.animations(pages: 1),
      ]);
      if (!mounted) return;
      setState(() {
        _trending = r[0];
        _movies = r[1];
        _topMovies = r[2];
        _series = r[3];
        _novelas = r[4];
        _dramas = r[5];
        _action = r[6];
        _anim = r[7];
        _hero = _pickHero(_trending);
        _loading = false;
      });
      _localRefresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e.toString();
          _loading = false;
        });
      }
    }
  }

  MediaItem? _pickHero(List<MediaItem> list) {
    for (final MediaItem m in list) {
      if (m.backdropUrl.isNotEmpty) return m;
    }
    return list.isEmpty ? null : list.first;
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: kGold,
          backgroundColor: kSurface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverAppBar(
                floating: true,
                backgroundColor: kBg,
                elevation: 0,
                titleSpacing: 16,
                title: Row(
                  children: <Widget>[
                    const TmcLogo(size: 30),
                    const SizedBox(width: 10),
                    const Text('TMC',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, letterSpacing: 2)),
                  ],
                ),
                actions: <Widget>[
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Buscar',
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_err != null)
                SliverToBoxAdapter(child: _errorBox())
              else ...<Widget>[
                if (_hero != null)
                  SliverToBoxAdapter(child: HeroBanner(item: _hero!)),
                SliverToBoxAdapter(
                  child: ContinueRow(items: _cont, onChanged: _localRefresh),
                ),
                SliverToBoxAdapter(
                  child: MediaRow(title: 'Meus Favoritos', items: _favs),
                ),
                SliverToBoxAdapter(
                  child: MediaRow(title: 'Filmes em Destaque', items: _movies),
                ),
                SliverToBoxAdapter(
                  child: MediaRow(title: 'Séries em Alta', items: _series),
                ),
                SliverToBoxAdapter(
                  child: MediaRow(title: 'Novelas', items: _novelas),
                ),
                SliverToBoxAdapter(
                  child: MediaRow(title: 'Dramas Curtos', items: _dramas),
                ),
                SliverToBoxAdapter(
                  child:
                      MediaRow(title: 'Tendencias da Semana', items: _trending),
                ),
                SliverToBoxAdapter(
                  child: MediaRow(title: 'Aclamados', items: _topMovies),
                ),
                SliverToBoxAdapter(
                  child: MediaRow(title: 'Acao e Aventura', items: _action),
                ),
                SliverToBoxAdapter(
                  child: MediaRow(title: 'Animacao', items: _anim),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      child: Column(
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 54, color: kGold),
          const SizedBox(height: 14),
          Text(_err!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// =========================== HERO BANNER =============================
class HeroBanner extends StatefulWidget {
  final MediaItem item;
  const HeroBanner({super.key, required this.item});

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    _fav = Store.isFav(widget.item.key);
  }

  @override
  Widget build(BuildContext context) {
    final MediaItem item = widget.item;
    final double h =
        (MediaQuery.of(context).size.height * 0.62).clamp(340.0, 640.0);

    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (item.backdropUrl.isEmpty)
            Container(color: kSurface)
          else
            Image.network(
              item.backdropUrl,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                  Container(color: kSurface),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xCC070A12), Color(0x55070A12), kBg],
                stops: <double>[0, 0.42, 1],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: kRed,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('EM ALTA',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1)),
                    ),
                    const SizedBox(width: 8),
                    Text(item.typeLabel,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                            letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Icon(Icons.star, color: kGold, size: 16),
                    const SizedBox(width: 4),
                    Text(item.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 12),
                    if (item.year.isNotEmpty)
                      Text(item.year,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                  ],
                ),
                if (item.overview.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    item.overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5, height: 1.4),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => openPlayer(context, item),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('ASSISTIR',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Store.toggleFav(item);
                        if (mounted) {
                          setState(() => _fav = Store.isFav(item.key));
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                      ),
                      icon: Icon(
                          _fav ? Icons.favorite : Icons.favorite_border,
                          size: 18),
                      label: Text(_fav ? 'FAVORITO' : 'FAVORITAR',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Detalhes',
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => DetailsScreen(item: item)));
                      },
                      icon: const Icon(Icons.info_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ FILEIRAS ===============================
class MediaRow extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final double height;

  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    this.height = 214,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: kGold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              Text('${items.length}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (BuildContext context, int i) =>
                PosterCard(item: items[i], width: 134),
          ),
        ),
      ],
    );
  }
}

class ContinueRow extends StatelessWidget {
  final List<WatchItem> items;
  final VoidCallback onChanged;

  const ContinueRow({super.key, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              const Text('Continuar Assistindo',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (BuildContext context, int i) =>
                _ContinueCard(item: items[i], onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatefulWidget {
  final WatchItem item;
  final VoidCallback onChanged;

  const _ContinueCard({required this.item, required this.onChanged});

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final WatchItem w = widget.item;
    return AnimatedScale(
      scale: _focused ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: 250,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onFocusChange: (bool v) => setState(() => _focused = v),
            onTap: () async {
              await openPlayer(context, w.media,
                  season: w.season, episode: w.episode);
              widget.onChanged();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (w.media.backdropUrl.isEmpty)
                        Container(color: kSurface)
                      else
                        Image.network(
                          w.media.backdropUrl,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (BuildContext c, Object e, StackTrace? s) =>
                                  Container(color: kSurface),
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: <Color>[
                              Color(0xCC000000),
                              Colors.transparent
                            ],
                          ),
                        ),
                      ),
                      const Center(
                        child: Icon(Icons.play_circle_fill,
                            size: 42, color: Colors.white),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: InkWell(
                          onTap: () async {
                            await Store.removeProgress(w.key);
                            widget.onChanged();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 14),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: w.progress,
                          minHeight: 4,
                          color: kGold,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(w.media.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${w.label}  •  ${_fmtSeg(w.position)}',
                        style: const TextStyle(
                            fontSize: 10.5, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _fmtSeg(int seconds) {
  final int h = seconds ~/ 3600;
  final int m = (seconds % 3600) ~/ 60;
  final int s = seconds % 60;
  final String mm = m.toString().padLeft(2, '0');
  final String ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

// ============================= CARD ==================================
class PosterCard extends StatefulWidget {
  final MediaItem item;
  final bool autofocus;
  final double? width;

  const PosterCard({
    super.key,
    required this.item,
    this.autofocus = false,
    this.width,
  });

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DetailsScreen(item: widget.item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget card = AnimatedScale(
      scale: _focused ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          autofocus: widget.autofocus,
          onFocusChange: (bool v) => setState(() => _focused = v),
          onTap: _open,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _focused ? kGold : Colors.white12, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _image(),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.star, color: kGold, size: 10),
                                const SizedBox(width: 3),
                                Text(widget.item.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                        fontSize: 10, color: kGold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              Text(
                widget.item.year.isEmpty
                    ? widget.item.typeLabel
                    : '${widget.item.year}  •  ${widget.item.typeLabel}',
                maxLines: 1,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.width == null) return card;
    return SizedBox(width: widget.width, child: card);
  }

  Widget _image() {
    final String url = widget.item.posterUrl;
    if (url.isEmpty) {
      return Container(
        color: kSurface,
        child: const Icon(Icons.movie, color: Colors.white24, size: 36),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (BuildContext c, Widget w, ImageChunkEvent? p) {
        if (p == null) return w;
        return Container(
          color: kSurface,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => Container(
        color: kSurface,
        child: const Icon(Icons.broken_image, color: Colors.white24),
      ),
    );
  }
}

class ItemGrid extends StatelessWidget {
  final List<MediaItem> items;
  final String empty;

  const ItemGrid({
    super.key,
    required this.items,
    this.empty = 'Nada por aqui ainda.',
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(empty,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final int cols = (c.maxWidth / 140).floor().clamp(2, 8).toInt();
        return GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.56,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int i) =>
              PosterCard(item: items[i], autofocus: i == 0),
        );
      },
    );
  }
}

// =========================== FAVORITOS ===============================
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<MediaItem> _items = <MediaItem>[];

  @override
  void initState() {
    super.initState();
    Store.revision.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    Store.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _items = Store.favorites());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Meus Favoritos',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ItemGrid(
        items: _items,
        empty: 'Toque no coracao de um titulo para salvar aqui.',
      ),
    );
  }
}

// =========================== TELA BUSCA ==============================
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _ctl = TextEditingController();
  Timer? _deb;
  bool _isTv = false;
  String _q = '';
  List<MediaItem> _items = <MediaItem>[];
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    _deb?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 450), () => _run(v.trim()));
  }

  Future<void> _run(String q) async {
    if (!mounted) return;
    setState(() {
      _q = q;
      _busy = q.isNotEmpty;
    });
    if (q.isEmpty) {
      setState(() => _items = <MediaItem>[]);
      return;
    }
    try {
      final List<MediaItem> r = await TmdbService.search(q, _isTv, pages: 2);
      if (mounted) setState(() => _items = r);
    } catch (_) {
      if (mounted) setState(() => _items = <MediaItem>[]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Buscar filme ou serie...',
            border: InputBorder.none,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              setState(() => _isTv = !_isTv);
              if (_q.isNotEmpty) _run(_q);
            },
            child: Text(
              _isTv ? 'SERIES' : 'FILMES',
              style: const TextStyle(color: kGold, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _q.isEmpty
              ? const Center(
                  child: Text('Digite algo para buscar.',
                      style: TextStyle(color: Colors.white54)),
                )
              : ItemGrid(items: _items, empty: 'Nada encontrado para "$_q".'),
    );
  }
}

// =========================== TELA DETALHES ===========================
class DetailsScreen extends StatefulWidget {
  final MediaItem item;
  const DetailsScreen({super.key, required this.item});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _err;
  bool _fav = false;
  bool _descFull = false;
  int _server = -1;
  int _season = 1;
  List<Map<String, dynamic>> _seasons = <Map<String, dynamic>>[];
  List<Episode> _episodes = <Episode>[];
  List<MediaItem> _similar = <MediaItem>[];
  bool _epLoading = false;

  bool get _isTv => widget.item.isTv;

  @override
  void initState() {
    super.initState();
    _fav = Store.isFav(widget.item.key);
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> d =
          await TmdbService.details(widget.item.id, _isTv);

      final List<Map<String, dynamic>> seasons = <Map<String, dynamic>>[];
      if (_isTv) {
        final List<dynamic> raw =
            (d['seasons'] as List<dynamic>?) ?? const <dynamic>[];
        for (final dynamic s in raw) {
          final Map<String, dynamic> m = s as Map<String, dynamic>;
          seasons.add(<String, dynamic>{
            'n': (m['season_number'] ?? 1) as int,
            'name': (m['name'] ?? 'Temporada').toString(),
            'c': (m['episode_count'] ?? 0) as int,
          });
        }
        seasons.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
            (a['n'] as int).compareTo(b['n'] as int));
      }

      if (!mounted) return;
      setState(() {
        _d = d;
        _seasons = seasons;
        _loading = false;
      });

      if (_isTv && seasons.isNotEmpty) {
        _season = seasons.first['n'] as int;
        await _loadEpisodes();
      }

      try {
        final List<MediaItem> sim =
            await TmdbService.similar(widget.item.id, _isTv);
        if (mounted) setState(() => _similar = sim);
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadEpisodes() async {
    setState(() {
      _epLoading = true;
      _episodes = <Episode>[];
    });
    try {
      final List<Episode> eps =
          await TmdbService.episodes(widget.item.id, _season);
      if (mounted) setState(() => _episodes = eps);
    } catch (_) {
      if (mounted) setState(() => _episodes = <Episode>[]);
    } finally {
      if (mounted) setState(() => _epLoading = false);
    }
  }

  int _runtime() {
    final Map<String, dynamic>? d = _d;
    if (d == null) return 0;
    if (!_isTv) return (d['runtime'] ?? 0) as int;
    final List<dynamic> r =
        (d['episode_run_time'] as List<dynamic>?) ?? const <dynamic>[];
    if (r.isNotEmpty) return (r.first as num).toInt();
    return 0;
  }

  String _cert() {
    final Map<String, dynamic>? d = _d;
    if (d == null) return '';
    try {
      if (!_isTv) {
        final Map<String, dynamic>? rd =
            d['release_dates'] as Map<String, dynamic>?;
        final List<dynamic> results =
            (rd?['results'] as List<dynamic>?) ?? const <dynamic>[];
        for (final dynamic r in results) {
          final Map<String, dynamic> m = r as Map<String, dynamic>;
          if (m['iso_3166_1'] == 'BR') {
            final List<dynamic> list =
                (m['release_dates'] as List<dynamic>?) ?? const <dynamic>[];
            for (final dynamic x in list) {
              final String c =
                  ((x as Map<String, dynamic>)['certification'] ?? '')
                      .toString();
              if (c.isNotEmpty) return c;
            }
          }
        }
      } else {
        final Map<String, dynamic>? cr =
            d['content_ratings'] as Map<String, dynamic>?;
        final List<dynamic> results =
            (cr?['results'] as List<dynamic>?) ?? const <dynamic>[];
        for (final dynamic r in results) {
          final Map<String, dynamic> m = r as Map<String, dynamic>;
          if (m['iso_3166_1'] == 'BR') return (m['rating'] ?? '').toString();
        }
      }
    } catch (_) {}
    return '';
  }

  List<String> _genreNames() {
    final Map<String, dynamic>? d = _d;
    if (d == null) return <String>[];
    final List<dynamic> raw =
        (d['genres'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .map((dynamic e) =>
            ((e as Map<String, dynamic>)['name'] ?? '').toString())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  String _runtimeLabel() {
    final int r = _runtime();
    if (r <= 0) return '';
    if (r < 60) return '$r min';
    final int h = r ~/ 60;
    final int m = r % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  Future<void> _verTrailer() async {
    String? key = TmdbService.findTrailer(_d);
    key ??= await TmdbService.trailerKey(widget.item.id, _isTv);
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Trailer nao disponivel para este titulo.')));
      return;
    }
    await showTrailer(context, key, widget.item.title);
  }

  @override
  Widget build(BuildContext context) {
    final MediaItem item = widget.item;
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 330,
            backgroundColor: kBg,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(item.title,
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (item.backdropUrl.isEmpty)
                    Container(color: kSurface)
                  else
                    Image.network(
                      item.backdropUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                          Container(color: kSurface),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0x88070A12), kBg],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_err != null) {
      return Column(
        children: <Widget>[
          Text(_err!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kGold)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _loading = true;
                _err = null;
              });
              _load();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      );
    }
    return _info();
  }

  Widget _info() {
    final MediaItem item = widget.item;
    final Map<String, dynamic>? d = _d;
    final List<String> genres = _genreNames();
    final String cert = _cert();
    final String runtime = _runtimeLabel();
    final String overview = (d?['overview'] ?? item.overview).toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _chip('★ ${item.rating.toStringAsFixed(1)}', kGold),
            if (item.year.isNotEmpty) _chip(item.year, Colors.white70),
            _chip(item.typeLabel, Colors.white70),
            if (runtime.isNotEmpty) _chip(runtime, Colors.white70),
            if (cert.isNotEmpty) _chip(cert, kGold),
            if (_isTv && d?['number_of_seasons'] != null)
              _chip('${d!['number_of_seasons']} temporadas', Colors.white70),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                autofocus: true,
                onPressed: () => openPlayer(context, item,
                    season: _season, episode: 1, forced: _server),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('ASSISTIR',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 0.6)),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _verTrailer,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              ),
              icon: const Icon(Icons.smart_display_outlined, size: 18),
              label: const Text('VER TRAILER',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Favoritar',
              onPressed: () async {
                await Store.toggleFav(item);
                if (mounted) setState(() => _fav = Store.isFav(item.key));
              },
              icon: Icon(_fav ? Icons.favorite : Icons.favorite_border,
                  color: _fav ? kRed : Colors.white),
            ),
          ],
        ),
        if (genres.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                genres.map((String g) => _chip(g, Colors.white70)).toList(),
          ),
        ],
        const SizedBox(height: 10),
        const Text('Servidor:',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: <Widget>[
            _serverChip(-1, 'AUTOMATICO'),
            for (int i = 0; i < kProviders.length; i++)
              _serverChip(i, kProviders[i].name),
          ],
        ),
        if (_isTv) _tvSection(),
        const SizedBox(height: 22),
        const Text('Sinopse',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          overview.isEmpty ? 'Sem sinopse disponivel.' : overview,
          maxLines: _descFull ? 40 : 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        if (overview.length > 220)
          TextButton(
            onPressed: () => setState(() => _descFull = !_descFull),
            child: Text(_descFull ? 'Ver menos' : 'Ver mais',
                style: const TextStyle(color: kGold)),
          ),
        if (_cast().isNotEmpty) _castSection(),
        if (_similar.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          MediaRow(title: 'Parecidos com este', items: _similar),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  List<Map<String, dynamic>> _cast() {
    final Map<String, dynamic>? d = _d;
    if (d == null) return <Map<String, dynamic>>[];
    final Map<String, dynamic>? cr = d['credits'] as Map<String, dynamic>?;
    final List<dynamic> raw =
        (cr?['cast'] as List<dynamic>?) ?? const <dynamic>[];
    return raw
        .take(16)
        .map((dynamic e) => e as Map<String, dynamic>)
        .toList();
  }

  Widget _castSection() {
    final List<Map<String, dynamic>> cast = _cast();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 20),
        const Text('Elenco principal',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 118,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            itemBuilder: (BuildContext context, int i) {
              final Map<String, dynamic> p = cast[i];
              final String? ph = p['profile_path']?.toString();
              return Container(
                width: 84,
                margin: const EdgeInsets.only(right: 10),
                child: Column(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: kCard,
                      backgroundImage: (ph == null || ph.isEmpty)
                          ? null
                          : NetworkImage('$kTmdbImg/w185$ph'),
                      child: (ph == null || ph.isEmpty)
                          ? const Icon(Icons.person, color: Colors.white38)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (p['name'] ?? '').toString(),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tvSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 18),
        const Text('Temporadas e Capitulos',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: _season,
          dropdownColor: kSurface,
          isExpanded: true,
          items: _seasons.map((Map<String, dynamic> s) {
            final int n = s['n'] as int;
            final String name = s['name'] as String;
            final int c = s['c'] as int;
            return DropdownMenuItem<int>(
              value: n,
              child: Text('$name  ($c cap.)',
                  style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: (int? v) async {
            if (v == null) return;
            setState(() {
              _season = v;
              _episodes = <Episode>[];
            });
            await _loadEpisodes();
          },
        ),
        const SizedBox(height: 10),
        if (_epLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_episodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Nenhum capitulo encontrado para esta temporada.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _episodes.length,
            itemBuilder: (BuildContext context, int i) =>
                _episodeTile(_episodes[i]),
          ),
      ],
    );
  }

  Widget _episodeTile(Episode e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPlayer(context, widget.item,
              season: _season, episode: e.number, forced: _server),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 128,
                    height: 72,
                    child: e.stillUrl.isEmpty
                        ? Container(
                            color: kSurface,
                            child: const Icon(Icons.movie_outlined,
                                color: Colors.white24))
                        : Image.network(
                            e.stillUrl,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (BuildContext c, Object o, StackTrace? s) =>
                                    Container(color: kSurface),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${e.number}. ${e.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.overview.isEmpty
                            ? 'Sem sinopse para este capitulo.'
                            : e.overview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.white60,
                            height: 1.35),
                      ),
                      if (e.runtime > 0) ...<Widget>[
                        const SizedBox(height: 4),
                        Text('${e.runtime} min',
                            style: const TextStyle(
                                fontSize: 10.5, color: kGold)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String t, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(t,
          style: TextStyle(
              fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _serverChip(int i, String label) {
    return ChoiceChip(
      selected: _server == i,
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selectedColor: kGold,
      onSelected: (bool _) => setState(() => _server = i),
    );
  }
}

// =========================== PLAYER VIDEO ============================
class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String provider;
  final String referer;
  final MediaItem? media;
  final int season;
  final int episode;

  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.provider = '',
    this.referer = '',
    this.media,
    this.season = 1,
    this.episode = 1,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _c;
  bool _ready = false;
  String? _err;
  bool _ui = true;
  Timer? _hide;
  Timer? _saver;

  String get _key {
    final MediaItem? m = widget.media;
    if (m == null) return 'generic_${widget.title}';
    return m.isTv
        ? '${m.key}_${widget.season}_${widget.episode}'
        : m.key;
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _start();
  }

  Future<void> _start() async {
    try {
      final Map<String, String> headers = <String, String>{
        'User-Agent': kUserAgent,
      };
      if (widget.referer.isNotEmpty) headers['Referer'] = widget.referer;

      final VideoPlayerController c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize();
      await c.setLooping(false);

      // HLS adaptativo: o player negocia a faixa sozinho (Qualidade Automatica).
      final int saved = Store.seconds(_key);
      final int total = c.value.duration.inSeconds;
      if (saved > 15 && total > 0 && (total - saved) > 8) {
        final bool go = await _askResume(saved);
        if (!mounted) {
          await c.dispose();
          return;
        }
        if (go) {
          await c.seekTo(Duration(seconds: saved));
        } else {
          await Store.removeProgress(_key);
        }
      }

      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_tick);
      setState(() {
        _c = c;
        _ready = true;
      });
      _saver = Timer.periodic(const Duration(seconds: 5), (Timer _) => _save());
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  Future<bool> _askResume(int seconds) async {
    final bool? r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: kSurface,
          title: const Text('Continuar de onde parou?'),
          content: Text(
            'Voce parou em ${_fmtSeg(seconds)}. Deseja retomar deste ponto?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Comecar do inicio'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    return r ?? false;
  }

  void _save() {
    final VideoPlayerController? c = _c;
    final MediaItem? m = widget.media;
    if (c == null || m == null || !c.value.isInitialized) return;
    final int pos = c.value.position.inSeconds;
    final int dur = c.value.duration.inSeconds;
    if (pos < 5 || dur <= 0) return;
    Store.saveProgress(WatchItem(
      media: m,
      season: widget.season,
      episode: widget.episode,
      position: pos,
      duration: dur,
    ));
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _ui = false);
    });
  }

  void _toggleUi() {
    setState(() => _ui = !_ui);
    if (_ui) _scheduleHide();
  }

  @override
  void dispose() {
    _save();
    _hide?.cancel();
    _saver?.cancel();
    _c?.removeListener(_tick);
    _c?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _openWeb() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebScreen(url: widget.url, title: widget.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent ev) {
          if (ev is KeyDownEvent) _toggleUi();
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: _toggleUi,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: <Widget>[
              Center(child: _surface(c)),
              AnimatedOpacity(
                opacity: _ui ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_ui,
                  child: _overlay(c),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _surface(VideoPlayerController? c) {
    if (_err != null) return _errorBox();
    if (!_ready || c == null) return const CircularProgressIndicator();
    return AspectRatio(
      aspectRatio: c.value.aspectRatio,
      child: VideoPlayer(c),
    );
  }

  Widget _errorBox() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.error_outline, color: kGold, size: 48),
          const SizedBox(height: 12),
          const Text('Falha ao abrir o stream direto.',
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(_err ?? '',
              maxLines: 3,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => WebScreen(url: widget.url, title: widget.title),
                ),
              );
            },
            icon: const Icon(Icons.language),
            label: const Text('Abrir na WebView'),
          ),
        ],
      ),
    );
  }

  Widget _overlay(VideoPlayerController? c) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black87,
            Colors.transparent,
            Colors.transparent,
            Colors.black87,
          ],
          stops: <double>[0, 0.25, 0.7, 1],
        ),
      ),
      child: Column(
        children: <Widget>[
          _topBar(),
          const Spacer(),
          if (c != null && c.value.isInitialized) _playRow(c),
          const Spacer(),
          if (c != null && c.value.isInitialized) _seekBar(c),
        ],
      ),
    );
  }

  Widget _topBar() {
    return SafeArea(
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGold.withValues(alpha: 0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.hd_outlined, size: 12, color: kGold),
                SizedBox(width: 4),
                Text('AUTO',
                    style: TextStyle(
                        fontSize: 10,
                        color: kGold,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          if (widget.provider.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(widget.provider,
                  style: const TextStyle(fontSize: 11, color: Colors.white54)),
            ),
          IconButton(
            tooltip: 'WebView',
            icon: const Icon(Icons.language),
            onPressed: _openWeb,
          ),
        ],
      ),
    );
  }

  Widget _playRow(VideoPlayerController c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          iconSize: 34,
          icon: const Icon(Icons.replay_10),
          onPressed: () {
            final Duration p = c.value.position - const Duration(seconds: 10);
            c.seekTo(p < Duration.zero ? Duration.zero : p);
            _scheduleHide();
          },
        ),
        const SizedBox(width: 10),
        IconButton(
          iconSize: 58,
          icon: Icon(c.value.isPlaying
              ? Icons.pause_circle_filled
              : Icons.play_circle_filled),
          onPressed: () {
            if (c.value.isPlaying) {
              c.pause();
              _save();
            } else {
              c.play();
            }
            _scheduleHide();
          },
        ),
        const SizedBox(width: 10),
        IconButton(
          iconSize: 34,
          icon: const Icon(Icons.forward_10),
          onPressed: () {
            c.seekTo(c.value.position + const Duration(seconds: 10));
            _scheduleHide();
          },
        ),
      ],
    );
  }

  Widget _seekBar(VideoPlayerController c) {
    final double total = c.value.duration.inMilliseconds.toDouble();
    final double max = total <= 0 ? 1.0 : total;
    final double pos = c.value.position.inMilliseconds.toDouble().clamp(0, max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: <Widget>[
          Text(_fmtSeg(c.value.position.inSeconds),
              style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: pos,
              max: max,
              activeColor: kGold,
              onChanged: (double v) {
                c.seekTo(Duration(milliseconds: v.toInt()));
                _scheduleHide();
              },
              onChangeEnd: (double _) => _save(),
            ),
          ),
          Text(_fmtSeg(c.value.duration.inSeconds),
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================= WEBVIEW ===============================
const List<String> kAdHosts = <String>[
  'doubleclick',
  'googlesyndication',
  'googleads',
  'adservice',
  'popads',
  'propeller',
  'onclickads',
  'adcash',
  'adnxs',
  'taboola',
  'outbrain',
];

const String kPopupKiller = r'''
(function () {
  if (window.__tmcHooked) { return; }
  window.__tmcHooked = true;
  var _open = window.open;
  window.open = function (u, n, f) {
    try {
      if (u && u !== 'about:blank') { window.location.href = u; return null; }
    } catch (e) {}
    try { return _open.apply(window, arguments); } catch (e) { return null; }
  };
  try {
    var b = document.createElement('base');
    b.target = '_self';
    (document.head || document.documentElement).appendChild(b);
  } catch (e) {}
})();
''';

class TrailerView extends StatefulWidget {
  final String videoKey;
  const TrailerView({super.key, required this.videoKey});

  @override
  State<TrailerView> createState() => _TrailerViewState();
}

class _TrailerViewState extends State<TrailerView> {
  late final WebViewController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String _) => _nudge(),
        ),
      )
      ..loadRequest(Uri.parse(
          'https://www.youtube.com/embed/${widget.videoKey}?autoplay=1&playsinline=1&rel=0&modestbranding=1'));
  }

  /// Empurra o play() no <video> do embed (contorna autoplay bloqueado).
  Future<void> _nudge() async {
    const String js =
        "try{var v=document.querySelector('video');if(v){v.play();}}catch(e){}";
    try {
      await _ctl.runJavaScript(js);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 900));
    try {
      await _ctl.runJavaScript(js);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _ctl);
}

class WebScreen extends StatefulWidget {
  final String url;
  final String title;
  const WebScreen({super.key, required this.url, required this.title});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  WebViewController? _ctl;
  int _progress = 0;
  bool _ui = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final WebViewController ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (String _) => _inject(),
          onPageFinished: (String _) => _inject(),
          onNavigationRequest: (NavigationRequest req) {
            final String url = req.url;
            if (url.startsWith('about:') ||
                url.startsWith('data:') ||
                url.startsWith('blob:')) {
              return NavigationDecision.navigate;
            }
            if (!url.startsWith('http')) {
              return NavigationDecision.navigate;
            }
            final String host = Uri.tryParse(url)?.host ?? '';
            for (final String ad in kAdHosts) {
              if (host.contains(ad)) return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
    _ctl = ctl;
  }

  Future<void> _inject() async {
    try {
      await _ctl?.runJavaScript(kPopupKiller);
    } catch (_) {}
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WebViewController? ctl = _ctl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          if (ctl == null)
            const Center(child: CircularProgressIndicator())
          else
            WebViewWidget(controller: ctl),
          if (_progress < 100)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress / 100,
                color: kGold,
                backgroundColor: Colors.black26,
              ),
            ),
          AnimatedOpacity(
            opacity: _ui ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_ui,
              child: SafeArea(child: _bar()),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 70,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _ui = !_ui),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar() {
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Recarregar',
          icon: const Icon(Icons.refresh),
          onPressed: () {
            _ctl?.reload();
            _inject();
          },
        ),
        IconButton(
          tooltip: 'Esconder controles',
          icon: const Icon(Icons.fullscreen_exit),
          onPressed: () => setState(() => _ui = false),
        ),
      ],
    );
  }
}

// ====== Alias para o test/widget_test.dart gerado pelo Flutter =======
typedef MyApp = TmcApp;
'@

$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($mainPath, $dart, $utf8)

$linhas = ([System.IO.File]::ReadAllText($mainPath) -split "`n").Count
Write-Host ''
Write-Host ('-> lib/main.dart reescrito com sucesso (' + $linhas + ' linhas, UTF-8).') -ForegroundColor Green

Write-Host '-> Rodando flutter pub get...' -ForegroundColor Yellow
& flutter pub get

Write-Host '-> Validando com flutter analyze (pode demorar)...' -ForegroundColor Yellow
& flutter analyze --no-fatal-infos

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '   CONCLUIDO! Agora rode:  flutter run --release' -ForegroundColor Cyan
Write-Host '   (backup do arquivo antigo em lib/main.dart.bak)' -ForegroundColor DarkGray
Write-Host '========================================================' -ForegroundColor Cyan