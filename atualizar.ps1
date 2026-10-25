# =====================================================================
#  TMC  -  ATUALIZADOR AUTOMATICO DO APP      (build 4.0 - "TMC PRIME")
#  ------------------------------------------------------------------
#   1) Preserva a sua chave do TMDB ja existente no lib/main.dart
#   2) Reescreve lib/main.dart por completo (UTF-8 sem BOM, ASCII puro)
#   3) Garante dependencias (path_provider / webview_flutter_web)
#   4) Libera INTERNET + armazenamento + launcher de Android TV
#   5) Roda flutter pub get e flutter analyze (aba Problems zerada)
#
#  Uso:  powershell -ExecutionPolicy Bypass -File .\atualizar.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if ([string]::IsNullOrEmpty($root)) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '   TMC  -  Atualizando aplicativo (build 4.0 PRIME)' -ForegroundColor Cyan
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host ''

$libDir   = Join-Path $root 'lib'
$mainPath = Join-Path $libDir 'main.dart'

if (-not (Test-Path -LiteralPath $libDir)) {
    New-Item -ItemType Directory -Force -Path $libDir | Out-Null
}

# ---------------------------------------------------------------------
# 1) PRESERVAR A CHAVE DO TMDB
# ---------------------------------------------------------------------
$keyTmdb = 'SUA_CHAVE_AQUI'
if (Test-Path -LiteralPath $mainPath) {
    try {
        $antigo = [System.IO.File]::ReadAllText($mainPath)
        $m = [regex]::Match($antigo, 'tmdbApiKey\s*=\s*"([^"]*)"')
        if ($m.Success) {
            $v = $m.Groups[1].Value.Trim()
            if ($v -ne '' -and $v -ne 'SUA_CHAVE_AQUI') {
                $keyTmdb = $v
                Write-Host '-> Chave do TMDB localizada e preservada.' -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host '   (aviso: nao foi possivel ler a chave antiga)' -ForegroundColor Yellow
    }
}

if (Test-Path -LiteralPath $mainPath) {
    Copy-Item -LiteralPath $mainPath -Destination "$mainPath.bak" -Force
    Write-Host '-> Backup do arquivo antigo em lib/main.dart.bak' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
# 2) DEPENDENCIAS
# ---------------------------------------------------------------------
$pubPath = Join-Path $root 'pubspec.yaml'

function Ensure-Dep([string]$pkg) {
    if (-not (Test-Path -LiteralPath $pubPath)) { return }
    $raw = [System.IO.File]::ReadAllText($pubPath)
    if ($raw -notmatch [regex]::Escape($pkg)) {
        Write-Host ('-> Adicionando dependencia ' + $pkg + '...') -ForegroundColor Yellow
        try { & flutter pub add $pkg }
        catch { Write-Host ('   (aviso: flutter pub add ' + $pkg + ' falhou)') -ForegroundColor Yellow }
    } else {
        Write-Host ('-> ' + $pkg + ' ja presente no pubspec.') -ForegroundColor DarkGray
    }
}

Ensure-Dep 'shared_preferences'
Ensure-Dep 'path_provider'
Ensure-Dep 'webview_flutter_web'

# ---------------------------------------------------------------------
# 3) REESCREVER lib/main.dart
# ---------------------------------------------------------------------
$dart = @'
// =====================================================================
//  TMC  -  AGREGADOR DE STREAMING                build 4.0  "TMC PRIME"
//  ------------------------------------------------------------------
//  * Player nativo imersivo: +10s / -10s / do comeco / audio / legendas
//  * Resolver resiliente SuperFlixAPI (JSON + deep-scan de .m3u8)
//  * Login local com E-mail + Dica de Senha + recuperacao offline
//  * Abas infinitas PT-BR, scroll por mouse, limpeza rigida de cache
//  Alvos: Flutter Web / Android Mobile / Android TV (TV Box)
//  >>>>> COLE A SUA CHAVE DO TMDB NA LINHA MARCADA ABAIXO <<<<<
// =====================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ======================= CONFIGURACAO ================================
String tmdbApiKey = "__TMDB_KEY__";

const String kTmdbBase = 'https://api.themoviedb.org/3';
const String kTmdbImg = 'https://image.tmdb.org/t/p';
const String kUserAgent =
    'Mozilla/5.0 (Linux; Android 11; Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const Color kBg = Color(0xFF070A12);
const Color kSurface = Color(0xFF121826);
const Color kCard = Color(0xFF1A2233);
const Color kAccent = Color(0xFF3D7BFF);
const Color kGold = Color(0xFFF5C451);
const Color kRed = Color(0xFFE5484D);
const Color kGreen = Color(0xFF35C46A);

const int kGenreSoap = 10766;
const int kGenreDrama = 18;
const int kGenreAction = 28;
const int kGenreAnimation = 16;

late SharedPreferences prefs;

// ============================== MAIN =================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } catch (_) {}
  prefs = await SharedPreferences.getInstance();
  CacheKeeper.install();
  await LocalDb.init();
  runApp(const TmcApp());
}

// ========================= LIMPEZA DE CACHE ==========================
class CacheKeeper {
  static Timer? _timer;

  static void install() {
    final ImageCache c = PaintingBinding.instance.imageCache;
    c.maximumSize = 130;
    c.maximumSizeBytes = 56 << 20;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 70), (Timer _) {
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  /// Descarte total: chamado quando qualquer stream/webview e fechado.
  static void wipe() {
    final ImageCache c = PaintingBinding.instance.imageCache;
    c.clear();
    c.clearLiveImages();
  }

  static Future<void> trim() async {
    PaintingBinding.instance.imageCache.clearLiveImages();
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

// ===================== BANCO LOCAL EM ARQUIVO =======================
class LocalDb {
  static final Map<String, dynamic> root = <String, dynamic>{
    'app': 'TMC',
    'version': 3,
    'updated': '',
    'users': <String, dynamic>{},
  };

  static final List<File> _files = <File>[];
  static String location = 'memoria interna';

  static bool get _android {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> get users =>
      (root['users'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  static List<String> names() {
    final List<String> l = users.keys.toList();
    l.sort();
    return l;
  }

  static bool exists(String u) => users.containsKey(u.trim());

  static bool emailTaken(String mail) {
    final String m = mail.trim().toLowerCase();
    if (m.isEmpty) return false;
    for (final dynamic v in users.values) {
      if (v is Map && (v['email'] ?? '').toString().toLowerCase() == m) {
        return true;
      }
    }
    return false;
  }

  static Map<String, dynamic>? user(String u) {
    final dynamic m = users[u.trim()];
    if (m is Map) return m.cast<String, dynamic>();
    return null;
  }

  static String hashOf(String u) => (user(u)?['hash'] ?? '').toString();
  static String emailOf(String u) => (user(u)?['email'] ?? '').toString();
  static String hintOf(String u) => (user(u)?['hint'] ?? '').toString();

  static Future<void> addUser(
      String u, String hash, String email, String hint) async {
    users[u.trim()] = <String, dynamic>{
      'hash': hash,
      'email': email.trim(),
      'hint': hint.trim(),
      'created': DateTime.now().toIso8601String(),
      'favs': <dynamic>[],
      'prog': <dynamic>[],
    };
    await save();
  }

  static Future<void> setPassword(String u, String hash) async {
    final Map<String, dynamic> m = user(u) ?? <String, dynamic>{};
    m['hash'] = hash;
    users[u.trim()] = m;
    await save();
  }

  static Future<void> setUserData(String u, Map<String, dynamic> data) async {
    final Map<String, dynamic> m = user(u) ?? <String, dynamic>{};
    m['hash'] = (m['hash'] ?? '').toString();
    m['favs'] = data['favs'];
    m['prog'] = data['prog'];
    users[u.trim()] = m;
  }

  static Future<void> init() async {
    _files.clear();
    if (kIsWeb) {
      location = 'navegador (armazenamento local)';
      await _restoreMirror();
      return;
    }
    final List<String> dirs = <String>[];
    try {
      final Directory? ext = await getExternalStorageDirectory();
      if (ext != null) dirs.add('${ext.path}${Platform.pathSeparator}TMC');
    } catch (_) {}
    if (_android) dirs.add('/storage/emulated/0/Download/TMC');
    try {
      final Directory doc = await getApplicationDocumentsDirectory();
      dirs.add('${doc.path}${Platform.pathSeparator}TMC');
    } catch (_) {}
    for (final String d in dirs) {
      try {
        final Directory dir = Directory(d);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        _files.add(File('$d${Platform.pathSeparator}tmc_backup.json'));
      } catch (_) {}
    }
    location = dirs.isEmpty ? 'memoria interna' : dirs.first;
    await _load();
    if (users.isEmpty) await _restoreMirror();
  }

  static Future<void> _restoreMirror() async {
    try {
      final String mir = prefs.getString('tmc_mirror') ?? '';
      if (mir.isEmpty) return;
      final dynamic j = jsonDecode(mir);
      if (j is Map<String, dynamic>) {
        root['users'] =
            (j['users'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      }
    } catch (_) {}
  }

  static Future<void> _load() async {
    Map<String, dynamic>? best;
    String bestDate = '';
    for (final File f in _files) {
      try {
        if (!f.existsSync()) continue;
        final String raw = f.readAsStringSync();
        if (raw.trim().isEmpty) continue;
        final dynamic j = jsonDecode(raw);
        if (j is! Map<String, dynamic>) continue;
        final String d = (j['updated'] ?? '').toString();
        if (best == null || d.compareTo(bestDate) > 0) {
          best = j;
          bestDate = d;
        }
      } catch (_) {}
    }
    if (best != null && best['users'] is Map) {
      root['users'] =
          (best['users'] as Map<dynamic, dynamic>).cast<String, dynamic>();
      root['updated'] = bestDate;
    }
  }

  static Future<void> save() async {
    root['updated'] = DateTime.now().toIso8601String();
    final String raw = jsonEncode(root);
    try {
      await prefs.setString('tmc_mirror', raw);
    } catch (_) {}
    for (final File f in _files) {
      try {
        await f.writeAsString(raw, flush: true);
      } catch (_) {}
    }
  }
}

// ============================ CONTAS =================================
class Auth {
  static final RegExp _user = RegExp(r'^[a-zA-Z0-9._-]{3,18}$');
  static final RegExp _mail =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

  static String hash(String u, String p) {
    final String s = 'tmc|${u.trim().toLowerCase()}|$p|prime';
    int a = 7;
    for (final int c in s.codeUnits) {
      a = ((a * 31) + c) & 0xFFFFFFFF;
    }
    int b = 5381;
    for (int i = s.length - 1; i >= 0; i--) {
      b = ((b * 33) + s.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16).padLeft(8, '0')}${b.toRadixString(16).padLeft(8, '0')}';
  }

  static String validateUser(String u) {
    final String t = u.trim();
    if (t.length < 3) return 'Use pelo menos 3 caracteres no usuario.';
    if (!_user.hasMatch(t)) return 'Usuario: apenas letras, numeros, . _ -';
    return '';
  }

  static String validateMail(String m) {
    if (!_mail.hasMatch(m.trim())) return 'Informe um e-mail valido.';
    return '';
  }

  static String validatePass(String p) {
    if (p.trim().length < 4) return 'A senha precisa de pelo menos 4 caracteres.';
    return '';
  }

  static String? login(String u, String p) {
    final String t = u.trim();
    if (!LocalDb.exists(t)) return 'Usuario nao encontrado neste aparelho.';
    if (LocalDb.hashOf(t) != hash(t, p)) return 'Senha incorreta.';
    return null;
  }

  static Future<String?> register(
      String u, String p, String mail, String hint) async {
    final String eu = validateUser(u);
    if (eu.isNotEmpty) return eu;
    final String em = validateMail(mail);
    if (em.isNotEmpty) return em;
    final String ep = validatePass(p);
    if (ep.isNotEmpty) return ep;
    if (hint.trim().length < 2) return 'Escreva uma dica de senha.';
    if (LocalDb.exists(u)) return 'Este usuario ja existe. Faca login.';
    if (LocalDb.emailTaken(mail)) return 'Este e-mail ja esta cadastrado.';
    await LocalDb.addUser(u, hash(u, p), mail, hint);
    return null;
  }

  static String? findUserByMail(String mail) {
    final String m = mail.trim().toLowerCase();
    for (final String u in LocalDb.names()) {
      if (LocalDb.emailOf(u).toLowerCase() == m) return u;
    }
    return null;
  }

  static bool checkHint(String u, String answer) =>
      LocalDb.hintOf(u).trim().toLowerCase() ==
      answer.trim().toLowerCase();
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

  MediaItem({
    required this.id,
    required this.title,
    this.poster,
    this.backdrop,
    this.overview = '',
    this.date,
    this.rating = 0,
    required this.isTv,
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
  final int runtime;

  Episode({
    required this.number,
    required this.name,
    this.overview = '',
    this.still,
    this.runtime = 0,
  });

  String get stillUrl =>
      (still == null || still!.isEmpty) ? '' : '$kTmdbImg/w300$still';

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        number: (j['episode_number'] ?? 0) as int,
        name: (j['name'] ?? 'Capitulo').toString(),
        overview: (j['overview'] ?? '').toString(),
        still: j['still_path']?.toString(),
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

  String get key => media.isTv ? '${media.key}_${season}_$episode' : media.key;

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

class Channel {
  final String id;
  final String name;
  final String group;
  final String logo;

  const Channel(this.id, this.name, [this.group = 'ABERTOS', this.logo = '']);

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'i': id, 'n': name, 'g': group, 'l': logo};

  static Channel fromJson(Map<String, dynamic> j) => Channel(
        (j['i'] ?? j['u'] ?? '').toString(),
        (j['n'] ?? '').toString(),
        (j['g'] ?? 'MEUS CANAIS').toString(),
        (j['l'] ?? '').toString(),
      );
}

class SportEvent {
  final String title;
  final String sport;
  final String competition;
  final String status;
  final String url;
  final String logo;

  const SportEvent(this.title, this.sport, this.competition, this.status,
      this.url, this.logo);
}

class HlsVariant {
  final String url;
  final int bandwidth;
  final String label;
  final String audioGroup;
  final String subGroup;

  const HlsVariant(this.url, this.bandwidth, this.label, this.audioGroup,
      this.subGroup);
}

class HlsMedia {
  final String name;
  final String lang;
  final String url;
  final bool isAudio;

  const HlsMedia(this.name, this.lang, this.url, this.isAudio);
}

class Cue {
  final int start;
  final int end;
  final String text;
  const Cue(this.start, this.end, this.text);
}

class PlayTarget {
  final String provider;
  final String url;
  final bool direct;
  final String referer;
  final String page;

  PlayTarget({
    required this.provider,
    required this.url,
    required this.direct,
    this.referer = '',
    this.page = '',
  });
}

// ========================= ARMAZENAMENTO =============================
class Store {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static String user = '';
  static List<MediaItem> favs = <MediaItem>[];
  static List<WatchItem> prog = <WatchItem>[];
  static DateTime _lastFile = DateTime.fromMillisecondsSinceEpoch(0);

  static String get _prefKey => 'tmc_data_$user';

  static List<MediaItem> _parseFavs(Map<String, dynamic> j) {
    final List<dynamic> raw = (j['favs'] as List<dynamic>?) ?? const <dynamic>[];
    final List<MediaItem> out = <MediaItem>[];
    for (final dynamic e in raw) {
      try {
        out.add(MediaItem.fromStored(
            (e as Map<dynamic, dynamic>).cast<String, dynamic>()));
      } catch (_) {}
    }
    return out;
  }

  static List<WatchItem> _parseProg(Map<String, dynamic> j) {
    final List<dynamic> raw = (j['prog'] as List<dynamic>?) ?? const <dynamic>[];
    final List<WatchItem> out = <WatchItem>[];
    for (final dynamic e in raw) {
      try {
        out.add(WatchItem.fromJson(
            (e as Map<dynamic, dynamic>).cast<String, dynamic>()));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> load(String u) async {
    user = u.trim();
    favs = <MediaItem>[];
    prog = <WatchItem>[];
    String raw = '';
    try {
      raw = prefs.getString(_prefKey) ?? '';
    } catch (_) {}
    if (raw.isEmpty) {
      final Map<String, dynamic>? m = LocalDb.user(user);
      if (m != null) {
        favs = _parseFavs(m);
        prog = _parseProg(m);
      }
    } else {
      try {
        final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
        favs = _parseFavs(j);
        prog = _parseProg(j);
      } catch (_) {}
    }
    revision.value++;
  }

  static Future<void> persist() async {
    final Map<String, dynamic> j = <String, dynamic>{
      'favs': favs.map((MediaItem m) => m.toJson()).toList(),
      'prog': prog.map((WatchItem w) => w.toJson()).toList(),
    };
    try {
      await prefs.setString(_prefKey, jsonEncode(j));
    } catch (_) {}
    try {
      await LocalDb.setUserData(user, j);
      final DateTime now = DateTime.now();
      if (now.difference(_lastFile).inSeconds >= 8) {
        _lastFile = now;
        await LocalDb.save();
      }
    } catch (_) {}
    revision.value++;
  }

  static bool isFav(String key) => favs.any((MediaItem m) => m.key == key);

  static Future<void> toggleFav(MediaItem m) async {
    if (isFav(m.key)) {
      favs = favs.where((MediaItem x) => x.key != m.key).toList();
    } else {
      favs = <MediaItem>[m, ...favs.where((MediaItem x) => x.key != m.key)];
    }
    await persist();
  }

  static Future<void> removeFav(String key) async {
    favs = favs.where((MediaItem m) => m.key != key).toList();
    await persist();
  }

  static Future<void> clearFavs() async {
    favs = <MediaItem>[];
    await persist();
  }

  static int seconds(String key) {
    for (final WatchItem w in prog) {
      if (w.key == key) return w.position;
    }
    return 0;
  }

  static Future<void> saveProgress(WatchItem w) async {
    if (w.position < 5 || w.duration <= 0) return;
    prog = <WatchItem>[w, ...prog.where((WatchItem x) => x.key != w.key)];
    if (prog.length > 60) prog = prog.sublist(0, 60);
    await persist();
  }

  static Future<void> removeProgress(String key) async {
    prog = prog.where((WatchItem w) => w.key != key).toList();
    await persist();
  }

  static Future<void> clearProgress() async {
    prog = <WatchItem>[];
    await persist();
  }

  static List<WatchItem> continueWatching() => prog
      .where((WatchItem w) => !(w.duration > 0 && w.progress >= 0.95))
      .toList();
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
      'region': 'BR',
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

  /// Pagina unica (scroll infinito das abas) - sempre pt-BR.
  static Future<List<MediaItem>> page(
      String path, bool isTv, int page, Map<String, String> q) async {
    try {
      return await _list(path, isTv, <String, String>{...q, 'page': '$page'});
    } catch (_) {
      return <MediaItem>[];
    }
  }

  static Future<List<MediaItem>> trending({int pages = 3}) =>
      _pages('/trending/all/week', false, pages: pages, auto: true);

  static Future<List<MediaItem>> popularMovies({int pages = 3}) =>
      _pages('/movie/popular', false, pages: pages);

  static Future<List<MediaItem>> topMovies({int pages = 1}) =>
      _pages('/movie/top_rated', false, pages: pages);

  static Future<List<MediaItem>> popularTv({int pages = 3}) =>
      _pages('/tv/popular', true, pages: pages);

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

  static Future<List<MediaItem>> kidsMovies({int pages = 2}) => _pages(
        '/discover/movie',
        false,
        pages: pages,
        q: <String, String>{
          'with_genres': '$kGenreAnimation,10751',
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

  static Future<List<Episode>> episodes(int id, int s) async {
    final Map<String, dynamic> d = await _get('/tv/$id/season/$s');
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

// =============== SUPERFLIXAPI (rotas JSON oficiais + deep-scan) ======
class SuperFlix {
  static const String base = 'https://superflixapi.fun';

  static Map<String, String> get headers => <String, String>{
        'User-Agent': kUserAgent,
        'Accept': 'application/json, text/html, */*',
      };

  static String filmeUrl(String id) => '$base/filme/$id';
  static String serieUrl(String id, int s, int e) => '$base/serie/$id/$s/$e';
  static String canalUrl(String id) => '$base/canal/$id';

  static List<String> rotas(bool isTv, String id, int s, int e) => isTv
      ? <String>[
          '${serieUrl(id, s, e)}?format=json',
          '${serieUrl(id, s, e)}?format=json&type=tmdb',
          serieUrl(id, s, e),
          '$base/e/serie/$id/$s/$e',
        ]
      : <String>[
          '${filmeUrl(id)}?format=json',
          '${filmeUrl(id)}?format=json&type=tmdb',
          filmeUrl(id),
          '$base/e/filme/$id',
        ];

  static Future<http.Response?> get(String url, [String referer = '']) async {
    try {
      final Map<String, String> h = headers;
      if (referer.isNotEmpty) h['Referer'] = referer;
      return await http
          .get(Uri.parse(url), headers: h)
          .timeout(const Duration(seconds: 16));
    } catch (_) {
      return null;
    }
  }

  static String abs(String url, String base) {
    try {
      if (url.startsWith('//')) return 'https:$url';
      return Uri.parse(base).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  /// Varre QUALQUER nivel do JSON procurando um valor que satisfaca o teste.
  static String? deep(dynamic node, bool Function(String) test, [int d = 0]) {
    if (d > 7 || node == null) return null;
    if (node is String) return test(node) ? node : null;
    if (node is List) {
      for (final dynamic e in node) {
        final String? r = deep(e, test, d + 1);
        if (r != null) return r;
      }
      return null;
    }
    if (node is Map) {
      for (final dynamic v in node.values) {
        final String? r = deep(v, test, d + 1);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// Canais publicos estaveis (JSON oficial).
  static Future<List<Channel>> canais() async {
    final List<Channel> out = <Channel>[];
    final http.Response? r =
        await get('$base/lista?category=canais&limit=400&format=json');
    if (r == null) return out;
    try {
      final dynamic j = jsonDecode(utf8.decode(r.bodyBytes));
      final List<dynamic> list =
          (j is Map ? (j['data'] as List<dynamic>?) : null) ?? const <dynamic>[];
      for (final dynamic e in list) {
        if (e is! Map) continue;
        final String id = (e['id'] ?? '').toString();
        final String name = (e['name'] ?? '').toString();
        if (id.isEmpty || name.isEmpty) continue;
        out.add(Channel(id, name, (e['category'] ?? 'ABERTOS').toString(),
            (e['logo_url'] ?? '').toString()));
      }
    } catch (_) {}
    return out;
  }

  /// Eventos esportivos do dia (JSON oficial).
  static Future<List<SportEvent>> eventos() async {
    final List<SportEvent> out = <SportEvent>[];
    final http.Response? r =
        await get('$base/lista?category=eventos&limit=60&format=json');
    if (r == null) return out;
    try {
      final dynamic j = jsonDecode(utf8.decode(r.bodyBytes));
      final List<dynamic> list =
          (j is Map ? (j['data'] as List<dynamic>?) : null) ?? const <dynamic>[];
      for (final dynamic e in list) {
        if (e is! Map) continue;
        String p(List<String> k) {
          for (final String key in k) {
            final dynamic v = e[key];
            if (v is String && v.trim().isNotEmpty) return v.trim();
          }
          return '';
        }

        final String title = p(<String>['name', 'title', 'match', 'event']);
        final String url =
            p(<String>['play_event_url', 'page_url', 'embed_url', 'url']);
        if (title.isEmpty || url.isEmpty) continue;
        out.add(SportEvent(
          title,
          p(<String>['sport', 'modality']),
          p(<String>['competition', 'league', 'championship']),
          p(<String>['status']),
          abs(url, base),
          p(<String>['event_logo', 'image', 'logo_url']),
        ));
      }
    } catch (_) {}
    return out;
  }
}

// ===================== RESOLVEDORES (FALLBACK) =======================
class Source {
  final String name;
  final List<String> Function(bool isTv, int id, int s, int e) rotas;
  final String Function(bool isTv, int id, int s, int e) page;

  const Source(this.name, this.rotas, this.page);
}

final List<Source> kSources = <Source>[
  Source('SuperFlixAPI',
      (bool isTv, int id, int s, int e) => SuperFlix.rotas(isTv, '$id', s, e),
      (bool isTv, int id, int s, int e) =>
          isTv ? SuperFlix.serieUrl('$id', s, e) : SuperFlix.filmeUrl('$id')),
  Source(
    'EmbedCine',
    (bool isTv, int id, int s, int e) => <String>[
      isTv ? 'https://embedcine.com/serie/$id/$s/$e' : 'https://embedcine.com/filme/$id',
    ],
    (bool isTv, int id, int s, int e) =>
        isTv ? 'https://embedcine.com/serie/$id/$s/$e' : 'https://embedcine.com/filme/$id',
  ),
  Source(
    'WarezCDN',
    (bool isTv, int id, int s, int e) => <String>[
      isTv
          ? 'https://warezcdn.com/embed/serie.php?id=$id&season=$s&episode=$e'
          : 'https://warezcdn.com/embed/filme.php?id=$id',
    ],
    (bool isTv, int id, int s, int e) => isTv
        ? 'https://warezcdn.com/embed/serie.php?id=$id&season=$s&episode=$e'
        : 'https://warezcdn.com/embed/filme.php?id=$id',
  ),
];

class Resolver {
  static final RegExp _m3u8 =
      RegExp(r'''https?://[^"'\s\\<>]+\.m3u8[^"'\s\\<>]*''');
  static final RegExp _mp4 =
      RegExp(r'''https?://[^"'\s\\<>]+\.mp4[^"'\s\\<>]*''');
  static final RegExp _iframe =
      RegExp(r'''<iframe[^>]*src=["']([^"']+)["']''', caseSensitive: false);

  /// Varredura silenciosa via HEAD: confirma se o host esta vivo.
  static Future<bool> alive(String url) async {
    try {
      final http.Response r = await http
          .head(Uri.parse(url), headers: SuperFlix.headers)
          .timeout(const Duration(seconds: 7));
      if (r.statusCode >= 200 && r.statusCode < 400) return true;
    } catch (_) {}
    return false;
  }

  static Future<PlayTarget?> _tentar(Source s, String rota, String page) async {
    final http.Response? res = await SuperFlix.get(rota, page);
    if (res == null) return null;
    final String body = res.body;
    final String head = body.trimLeft();

    // --- resposta JSON: deep-scan por qualquer .m3u8 / .mp4 ---
    if (head.startsWith('{') || head.startsWith('[')) {
      dynamic j;
      try {
        j = jsonDecode(body);
      } catch (_) {
        return null;
      }
      final String? m = SuperFlix.deep(j, (String v) => v.contains('.m3u8'));
      if (m != null) {
        return PlayTarget(
            provider: s.name,
            url: SuperFlix.abs(m, rota),
            direct: true,
            referer: rota,
            page: page);
      }
      final String? v = SuperFlix.deep(j, (String v) => v.contains('.mp4'));
      if (v != null) {
        return PlayTarget(
            provider: s.name,
            url: SuperFlix.abs(v, rota),
            direct: true,
            referer: rota,
            page: page);
      }
      final String? pl = SuperFlix.deep(
          j,
          (String v) =>
              v.startsWith('http') &&
              (v.contains('/embed') || v.contains('/player') || v.contains('/e/')));
      if (pl != null) {
        return PlayTarget(
            provider: s.name,
            url: SuperFlix.abs(pl, rota),
            direct: false,
            referer: rota,
            page: page);
      }
      return null;
    }

    // --- resposta HTML: regex direta de .m3u8 ---
    final Match? m = _m3u8.firstMatch(body);
    if (m != null) {
      return PlayTarget(
          provider: s.name,
          url: m.group(0)!,
          direct: true,
          referer: rota,
          page: page);
    }

    // --- HTML com iframe: segue um nivel ---
    final Match? f = _iframe.firstMatch(body);
    if (f != null) {
      final String src = SuperFlix.abs(f.group(1)!.trim(), rota);
      final Match? mDireto = _m3u8.firstMatch(src);
      if (mDireto != null) {
        return PlayTarget(
            provider: s.name,
            url: mDireto.group(0)!,
            direct: true,
            referer: rota,
            page: page);
      }
      final http.Response? r2 = await SuperFlix.get(src, rota);
      if (r2 != null) {
        final Match? m2 = _m3u8.firstMatch(r2.body);
        if (m2 != null) {
          return PlayTarget(
              provider: s.name,
              url: m2.group(0)!,
              direct: true,
              referer: src,
              page: page);
        }
        final Match? f2 = _iframe.firstMatch(r2.body);
        if (f2 != null) {
          return PlayTarget(
              provider: s.name,
              url: SuperFlix.abs(f2.group(1)!.trim(), src),
              direct: false,
              referer: rota,
              page: page);
        }
      }
      return PlayTarget(
          provider: s.name,
          url: src,
          direct: false,
          referer: rota,
          page: page);
    }

    final Match? mp4 = _mp4.firstMatch(body);
    if (mp4 != null) {
      return PlayTarget(
          provider: s.name,
          url: mp4.group(0)!,
          direct: true,
          referer: rota,
          page: page);
    }

    return null;
  }

  /// Tenta todos os resolvedores: devolve o 1o link direto ou o 1o embed.
  static Future<PlayTarget?> best(bool isTv, int id, int season, int episode,
      {int forced = -1}) async {
    final List<Source> lista =
        forced >= 0 && forced < kSources.length
            ? <Source>[kSources[forced]]
            : kSources;
    PlayTarget? embed;
    for (final Source s in lista) {
      final String page = s.page(isTv, id, season, episode);
      for (final String rota in s.rotas(isTv, id, season, episode)) {
        PlayTarget? t;
        try {
          t = await _tentar(s, rota, page);
        } catch (_) {
          t = null;
        }
        if (t == null) continue;
        if (t.direct) return t;
        embed ??= t;
        break;
      }
      # Continua procurando um link direto nos outros servidores; o primeiro embed fica como ultimo recurso.
    }
    return embed;
  }
}

// ======================= HLS (AUDIO/LEGENDAS) ========================
class Hls {
  static Future<String?> _fetch(String url, Map<String, String> h) async {
    try {
      final http.Response r = await http
          .get(Uri.parse(url), headers: h)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) return r.body;
    } catch (_) {}
    return null;
  }

  static String _abs(String url, String base) {
    try {
      return Uri.parse(base).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  static int _attr(String line, String key) {
    final Match? m = RegExp('$key=(\\d+)').firstMatch(line);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }

  static String _name(String line) {
    final Match? m = RegExp('NAME="([^"]+)"').firstMatch(line);
    if (m != null) return m.group(1)!;
    final Match? l = RegExp('LANGUAGE="([^"]+)"').firstMatch(line);
    if (l != null) return l.group(1)!.toUpperCase();
    return 'FAIXA';
  }

  static String _group(String line) {
    final Match? m = RegExp('GROUP-ID="([^"]+)"').firstMatch(line);
    return m == null ? '' : m.group(1)!;
  }

  /// Le o master playlist e separa faixas de video, audio e legendas.
  static Future<Map<String, dynamic>> parse(
      String url, Map<String, String> headers) async {
    final Map<String, dynamic> out = <String, dynamic>{
      'variants': <HlsVariant>[],
      'audios': <HlsMedia>[],
      'subs': <HlsMedia>[],
    };
    if (!url.contains('.m3u8')) return out;
    final String? body = await _fetch(url, headers);
    if (body == null || !body.contains('#EXT-X-STREAM-INF')) return out;

    final List<String> lines = const LineSplitter().convert(body);
    for (int i = 0; i < lines.length; i++) {
      final String l = lines[i].trim();
      if (l.startsWith('#EXT-X-MEDIA')) {
        final bool audio = l.contains('TYPE=AUDIO');
        final bool sub = l.contains('TYPE=SUBTITLES');
        if (!audio && !sub) continue;
        final Match? u = RegExp('URI="([^"]+)"').firstMatch(l);
        final String uri = u == null ? '' : u.group(1)!;
        (out[audio ? 'audios' : 'subs'] as List<HlsMedia>).add(HlsMedia(
          _name(l),
          _group(l),
          uri.isEmpty ? '' : _abs(uri, url),
          audio,
        ));
        continue;
      }
      if (!l.startsWith('#EXT-X-STREAM-INF')) continue;
      final int bw = _attr(l, 'BANDWIDTH');
      final Match? res = RegExp('RESOLUTION=(\\d+x\\d+)').firstMatch(l);
      final Match? au = RegExp('AUDIO="([^"]+)"').firstMatch(l);
      final Match? su = RegExp('SUBTITLES="([^"]+)"').firstMatch(l);
      for (int k = i + 1; k < lines.length; k++) {
        final String n = lines[k].trim();
        if (n.isEmpty || n.startsWith('#')) continue;
        (out['variants'] as List<HlsVariant>).add(HlsVariant(
          _abs(n, url),
          bw,
          res == null ? '${(bw / 1000).round()}k' : res.group(1)!,
          au == null ? '' : au.group(1)!,
          su == null ? '' : su.group(1)!,
        ));
        break;
      }
    }
    (out['variants'] as List<HlsVariant>)
        .sort((HlsVariant a, HlsVariant b) => a.bandwidth.compareTo(b.bandwidth));
    return out;
  }

  /// Baixa e converte uma faixa de legenda em cues prontos para exibir.
  static Future<List<Cue>> cues(String url, Map<String, String> headers) async {
    if (url.isEmpty) return <Cue>[];
    String? raw = await _fetch(url, headers);
    if (raw == null) return <Cue>[];
    if (raw.contains('#EXTM3U')) {
      final List<String> lines = const LineSplitter().convert(raw);
      for (final String l in lines) {
        final String n = l.trim();
        if (n.isEmpty || n.startsWith('#')) continue;
        final String? seg = await _fetch(_abs(n, url), headers);
        if (seg != null && seg.contains('-->')) {
          raw = seg;
          break;
        }
      }
    }
    return parseVtt(raw ?? '');
  }

  static List<Cue> parseVtt(String raw) {
    final List<Cue> out = <Cue>[];
    final String limpo =
        raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final String bloco in limpo.split('\n\n')) {
      final List<String> linhas = bloco
          .split('\n')
          .where((String l) => l.trim().isNotEmpty)
          .toList();
      if (linhas.isEmpty) continue;
      int idx = 0;
      if (!linhas[0].contains('-->')) {
        if (linhas.length < 2) continue;
        idx = 1;
      }
      if (!linhas[idx].contains('-->')) continue;
      final List<String> t = linhas[idx].split('-->');
      if (t.length < 2) continue;
      final int ini = _ms(t[0]);
      final int fim = _ms(t[1]);
      if (ini < 0 || fim < 0) continue;
      final String texto = linhas
          .skip(idx + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();
      if (texto.isEmpty) continue;
      out.add(Cue(ini, fim, texto));
    }
    out.sort((Cue a, Cue b) => a.start.compareTo(b.start));
    return out;
  }

  static int _ms(String t) {
    final String s = t.trim().split(' ').first.replaceAll(',', '.');
    final List<String> p = s.split(':');
    if (p.isEmpty) return -1;
    double total = 0;
    for (final String part in p) {
      final double v = double.tryParse(part) ?? -1;
      if (v < 0) return -1;
      total = total * 60 + v;
    }
    return (total * 1000).round();
  }
}

// ============================ HELPERS ================================
String fmtSeg(int seconds) {
  final int h = seconds ~/ 3600;
  final int m = (seconds % 3600) ~/ 60;
  final int s = seconds % 60;
  final String mm = m.toString().padLeft(2, '0');
  final String ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

Future<bool> askConfirm(
    BuildContext context, String title, String message) async {
  final bool? r = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: kSurface,
      title: Text(title),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );
  return r ?? false;
}

class LoadingDialog extends StatelessWidget {
  const LoadingDialog({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 74,
        height: 74,
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

// =================== NAVEGACAO PARA O PLAYER =========================
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

  // Web (Chrome) nao roda HLS nativo no <video>: prioriza o embed.
  final bool usarNativo = t.direct && !kIsWeb;

  if (usarNativo) {
    nav.push(MaterialPageRoute<void>(
      builder: (BuildContext _) => PlayerScreen(
        url: t!.url,
        title: item.title,
        provider: t.provider,
        referer: t.referer,
        media: item,
        season: season,
        episode: episode,
        embed: t.page,
      ),
    ));
  } else {
    nav.push(MaterialPageRoute<void>(
      builder: (BuildContext _) => WebScreen(
        url: t!.url,
        title: item.title,
        provider: t.provider,
      ),
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

// ======================= SCROLL PARA WEB =============================
class TmcScrollBehavior extends MaterialScrollBehavior {
  const TmcScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}

// ============================== APP ==================================
class TmcApp extends StatefulWidget {
  const TmcApp({super.key});
  @override
  State<TmcApp> createState() => _TmcAppState();
}

class _TmcAppState extends State<TmcApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      CacheKeeper.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData base = ThemeData.dark(useMaterial3: true);
    final String? font = GoogleFonts.poppins().fontFamily;

    return MaterialApp(
      title: 'TMC',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const TmcScrollBehavior(),
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
      home: const EntryGate(),
    );
  }
}

class EntryGate extends StatefulWidget {
  const EntryGate({super.key});
  @override
  State<EntryGate> createState() => _EntryGateState();
}

class _EntryGateState extends State<EntryGate> {
  String _user = '';
  bool _boot = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _auto());
  }

  Future<void> _auto() async {
    try {
      final String last = prefs.getString('tmc_last_user') ?? '';
      if (last.isNotEmpty && LocalDb.exists(last)) {
        await Store.load(last);
        if (!mounted) return;
        setState(() {
          _user = last;
          _boot = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _boot = false);
  }

  Future<void> _logged(String u) async {
    try {
      await prefs.setString('tmc_last_user', u);
    } catch (_) {}
    if (mounted) setState(() => _user = u);
  }

  Future<void> _logout() async {
    try {
      await prefs.remove('tmc_last_user');
    } catch (_) {}
    Store.user = '';
    if (mounted) setState(() => _user = '');
  }

  @override
  Widget build(BuildContext context) {
    if (_boot) return const SplashScreen();
    if (_user.isEmpty) return LoginScreen(onDone: _logged);
    return RootShell(onLogout: _logout);
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TmcLogo(size: 76),
            SizedBox(height: 18),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================== LOGIN ================================
class LoginScreen extends StatefulWidget {
  final Future<void> Function(String user) onDone;
  const LoginScreen({super.key, required this.onDone});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _u = TextEditingController();
  final TextEditingController _m = TextEditingController();
  final TextEditingController _p = TextEditingController();
  final TextEditingController _h = TextEditingController();
  bool _create = false;
  bool _busy = false;
  bool _see = false;
  String _err = '';
  List<String> _contas = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _u.dispose();
    _m.dispose();
    _p.dispose();
    _h.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _contas = LocalDb.names());
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String u = _u.text.trim();
    final String p = _p.text;
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _err = '';
    });

    String? e;
    if (_create) {
      e = await Auth.register(u, p, _m.text, _h.text);
      e ??= Auth.login(u, p);
    } else {
      e = Auth.login(u, p);
    }

    if (e != null) {
      if (!mounted) return;
      setState(() {
        _err = e!;
        _busy = false;
      });
      return;
    }

    await Store.load(u);
    await widget.onDone(u);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _esqueci() async {
    final TextEditingController mail = TextEditingController();
    final TextEditingController resp = TextEditingController();
    final TextEditingController nova = TextEditingController();

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        String etapa = 'email';
        String erro = '';
        String usuario = '';
        return StatefulBuilder(
          builder: (BuildContext c, void Function(void Function()) set) {
            return AlertDialog(
              backgroundColor: kSurface,
              title: const Text('Esqueci minha senha'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (etapa == 'email') ...<Widget>[
                    const Text(
                      'Informe o e-mail cadastrado. Vamos usar a sua Dica de Senha.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mail,
                      decoration: const InputDecoration(
                          labelText: 'E-mail',
                          border: OutlineInputBorder()),
                    ),
                  ],
                  if (etapa == 'hint') ...<Widget>[
                    Text('Usuario: $usuario',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Dica: ${LocalDb.hintOf(usuario)}',
                        style: const TextStyle(color: kGold, fontSize: 13)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: resp,
                      decoration: const InputDecoration(
                          labelText: 'Resposta da dica',
                          border: OutlineInputBorder()),
                    ),
                  ],
                  if (etapa == 'nova') ...<Widget>[
                    const Text('Resposta correta! Defina a nova senha.',
                        style: TextStyle(color: kGreen, fontSize: 12)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nova,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Nova senha',
                          border: OutlineInputBorder()),
                    ),
                  ],
                  if (erro.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(erro,
                        style: const TextStyle(color: kRed, fontSize: 12)),
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (etapa == 'email') {
                      final String? achou =
                          Auth.findUserByMail(mail.text);
                      if (achou == null) {
                        set(() => erro = 'E-mail nao cadastrado neste aparelho.');
                        return;
                      }
                      set(() {
                        usuario = achou;
                        erro = '';
                        etapa = 'hint';
                      });
                      return;
                    }
                    if (etapa == 'hint') {
                      if (!Auth.checkHint(usuario, resp.text)) {
                        set(() => erro = 'Resposta incorreta. Tente novamente.');
                        return;
                      }
                      set(() {
                        erro = '';
                        etapa = 'nova';
                      });
                      return;
                    }
                    final String ep = Auth.validatePass(nova.text);
                    if (ep.isNotEmpty) {
                      set(() => erro = ep);
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text(etapa == 'nova' ? 'REDEFINIR' : 'CONTINUAR'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    final String? alvo = Auth.findUserByMail(mail.text);
    if (alvo == null) return;
    await LocalDb.setPassword(alvo, Auth.hash(alvo, nova.text));
    if (!mounted) return;
    setState(() {
      _u.text = alvo;
      _create = false;
      _err = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha redefinida. Faca login.')));
  }

  Future<void> _reimport() async {
    await LocalDb.init();
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backup recarregado de: ${LocalDb.location}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const TmcLogo(size: 70),
                  const SizedBox(height: 12),
                  const Text('TMC',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6)),
                  const SizedBox(height: 4),
                  const Text('FILMES - SERIES - NOVELAS - KIDS - TV',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                          letterSpacing: 1)),
                  const SizedBox(height: 22),
                  Card(
                    color: kSurface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(child: _mode('ENTRAR', !_create)),
                              const SizedBox(width: 8),
                              Expanded(child: _mode('CRIAR CONTA', _create)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _u,
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Usuario',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_create) ...<Widget>[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _m,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                                prefixIcon: Icon(Icons.alternate_email),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          TextField(
                            controller: _p,
                            obscureText: !_see,
                            textInputAction: _create
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onSubmitted: (String _) {
                              if (!_create) _submit();
                            },
                            decoration: InputDecoration(
                              labelText: 'Senha',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(_see
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () => setState(() => _see = !_see),
                              ),
                            ),
                          ),
                          if (_create) ...<Widget>[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _h,
                              decoration: const InputDecoration(
                                labelText: 'Dica de senha',
                                helperText:
                                    'Ex: cidade onde nasci / nome do meu cao',
                                prefixIcon: Icon(Icons.lightbulb_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (_err.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(_err,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: kRed, fontSize: 12.5)),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15)),
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.login),
                              label: Text(
                                _create ? 'CRIAR E ENTRAR' : 'ENTRAR',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _esqueci,
                            child: const Text('Esqueci minha senha',
                                style: TextStyle(color: kGold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_contas.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    const Text('Contas neste aparelho',
                        style: TextStyle(fontSize: 11.5, color: Colors.white38)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: _contas
                          .map((String c) => ActionChip(
                                label: Text(c),
                                onPressed: () => setState(() {
                                  _u.text = c;
                                  _create = false;
                                }),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text('Backup automatico em: ${LocalDb.location}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.white38)),
                  TextButton.icon(
                    onPressed: _reimport,
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('REIMPORTAR BACKUP DO ARQUIVO'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mode(String label, bool on) {
    final bool alvo = label == 'ENTRAR';
    return SizedBox(
      height: 40,
      child: on
          ? FilledButton(
              onPressed: () => setState(() => _create = !alvo),
              style: FilledButton.styleFrom(backgroundColor: kAccent),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            )
          : OutlinedButton(
              onPressed: () => setState(() => _create = !alvo),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24)),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
    );
  }
}

// ============================== LOGO =================================
class TmcLogo extends StatelessWidget {
  final double size;
  const TmcLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: <Color>[Color(0xFF1E4AAA), kAccent]),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Center(
        child: Text(
          'TMC',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: size * 0.3,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

// ============================ CATALOGO ===============================
class GenreChip {
  final String label;
  final String path;
  final String withGenres;
  final Map<String, String> extra;

  const GenreChip(this.label,
      {required this.path,
      this.withGenres = '',
      this.extra = const <String, String>{}});
}

const List<GenreChip> kChipsFilmes = <GenreChip>[
  GenreChip('TODOS', path: '/discover/movie'),
  GenreChip('ACAO', path: '/discover/movie', withGenres: '28'),
  GenreChip('COMEDIA', path: '/discover/movie', withGenres: '35'),
  GenreChip('AVENTURA', path: '/discover/movie', withGenres: '12'),
  GenreChip('FICCAO', path: '/discover/movie', withGenres: '878'),
  GenreChip('TERROR', path: '/discover/movie', withGenres: '27'),
  GenreChip('SUSPENSE', path: '/discover/movie', withGenres: '53'),
  GenreChip('ROMANCE', path: '/discover/movie', withGenres: '10749'),
  GenreChip('CRIME', path: '/discover/movie', withGenres: '80'),
  GenreChip('ANIMACAO', path: '/discover/movie', withGenres: '16'),
  GenreChip('FAMILIA', path: '/discover/movie', withGenres: '10751'),
  GenreChip('DOCUMENTARIO', path: '/discover/movie', withGenres: '99'),
  GenreChip('ACLAMADOS',
      path: '/discover/movie',
      extra: <String, String>{
        'sort_by': 'vote_average.desc',
        'vote_count.gte': '800',
      }),
];

const List<GenreChip> kChipsSeries = <GenreChip>[
  GenreChip('TODAS', path: '/discover/tv'),
  GenreChip('DRAMA', path: '/discover/tv', withGenres: '18'),
  GenreChip('COMEDIA', path: '/discover/tv', withGenres: '35'),
  GenreChip('CRIME', path: '/discover/tv', withGenres: '80'),
  GenreChip('MISTERIO', path: '/discover/tv', withGenres: '9648'),
  GenreChip('SCI-FI', path: '/discover/tv', withGenres: '10765'),
  GenreChip('ACAO', path: '/discover/tv', withGenres: '10759'),
  GenreChip('ANIMES',
      path: '/discover/tv',
      withGenres: '16',
      extra: <String, String>{'with_origin_country': 'JP'}),
  GenreChip('DORAMAS',
      path: '/discover/tv',
      withGenres: '18',
      extra: <String, String>{'with_origin_country': 'KR'}),
];

const List<GenreChip> kChipsNovelas = <GenreChip>[
  GenreChip('BRASILEIRAS',
      path: '/discover/tv',
      withGenres: '10766',
      extra: <String, String>{'with_origin_country': 'BR'}),
  GenreChip('MEXICANAS',
      path: '/discover/tv',
      withGenres: '10766',
      extra: <String, String>{'with_origin_country': 'MX'}),
  GenreChip('TURCAS',
      path: '/discover/tv',
      withGenres: '10766',
      extra: <String, String>{'with_origin_country': 'TR'}),
  GenreChip('PORTUGUESAS',
      path: '/discover/tv',
      withGenres: '10766',
      extra: <String, String>{'with_origin_country': 'PT'}),
  GenreChip('TODAS', path: '/discover/tv', withGenres: '10766'),
];

const List<GenreChip> kChipsDramas = <GenreChip>[
  GenreChip('TODOS', path: '/discover/tv'),
  GenreChip('DRAMA', path: '/discover/tv', withGenres: '18'),
  GenreChip('ROMANCE', path: '/discover/tv', withGenres: '10749'),
  GenreChip('COMEDIA', path: '/discover/tv', withGenres: '35'),
  GenreChip('DORAMAS',
      path: '/discover/tv',
      withGenres: '18',
      extra: <String, String>{'with_origin_country': 'KR'}),
];

const List<GenreChip> kChipsKids = <GenreChip>[
  GenreChip('ANIMACAO', path: '/discover/movie', withGenres: '16'),
  GenreChip('FAMILIA', path: '/discover/movie', withGenres: '10751'),
  GenreChip('AVENTURA', path: '/discover/movie', withGenres: '12'),
  GenreChip('SERIES INFANTIS', path: '/discover/tv', withGenres: '10762'),
  GenreChip('DESENHOS TV', path: '/discover/tv', withGenres: '16'),
  GenreChip('ANIMES KIDS',
      path: '/discover/tv',
      withGenres: '16',
      extra: <String, String>{'with_origin_country': 'JP'}),
];

// ============================== SHELL ================================
class RootShell extends StatefulWidget {
  final Future<void> Function() onLogout;
  const RootShell({super.key, required this.onLogout});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  static const List<String> _labels = <String>[
    'INICIO',
    'FILMES',
    'SERIES',
    'NOVELAS',
    'DRAMAS CURTOS',
    'KIDS',
    'TV ONLINE',
  ];

  late final TabController _tabs =
      TabController(length: _labels.length, vsync: this);
  late final List<Widget> _pages = _buildPages();
  int _idx = 0;

  List<Widget> _buildPages() => <Widget>[
        const HomeTab(),
        const DiscoverTab(
          chips: kChipsFilmes,
          base: <String, String>{},
          empty: 'Nenhum filme encontrado.',
        ),
        const DiscoverTab(
          chips: kChipsSeries,
          base: <String, String>{},
          empty: 'Nenhuma serie encontrada.',
        ),
        const DiscoverTab(
          chips: kChipsNovelas,
          base: <String, String>{},
          empty: 'Nenhuma novela encontrada.',
        ),
        const DiscoverTab(
          chips: kChipsDramas,
          base: <String, String>{'with_runtime.lte': '45'},
          empty: 'Nenhum drama curto encontrado.',
        ),
        const DiscoverTab(
          chips: kChipsKids,
          base: <String, String>{},
          empty: 'Nada para a criancada por aqui.',
        ),
        const OnlineTvTab(),
      ];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tabs.indexIsChanging) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _idx != _tabs.index) setState(() => _idx = _tabs.index);
    });
  }

  void _search() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
    );
  }

  void _clean() {
    CacheKeeper.wipe();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache de imagens liberado.')));
  }

  Future<void> _backup() async {
    await Store.persist();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Backup do perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Conta: ${Store.user}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Favoritos e historico sao salvos automaticamente. '
              'Reinstale o app e use REIMPORTAR BACKUP na tela de login.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Text('Local: ${LocalDb.location}',
                style: const TextStyle(fontSize: 11, color: kGold)),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearHist() async {
    if (Store.prog.isEmpty) return;
    final bool ok = await askConfirm(context, 'Limpar historico',
        'Apagar TODO o historico de "Continuar Assistindo"?');
    if (!ok) return;
    await Store.clearProgress();
  }

  Future<void> _clearFavs() async {
    if (Store.favs.isEmpty) return;
    final bool ok = await askConfirm(context, 'Apagar favoritos',
        'Remover TODOS os titulos da sua lista de favoritos?');
    if (!ok) return;
    await Store.clearFavs();
  }

  Future<void> _sair() async {
    final bool ok = await askConfirm(
        context, 'Sair da conta', 'Deseja sair de ${Store.user}?');
    if (!ok) return;
    await Store.persist();
    await widget.onLogout();
  }

  void _menu(String v) {
    switch (v) {
      case 'backup':
        _backup();
        break;
      case 'hist':
        _clearHist();
        break;
      case 'favs':
        _clearFavs();
        break;
      case 'sair':
        _sair();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        titleSpacing: 14,
        title: Row(
          children: <Widget>[
            const TmcLogo(size: 28),
            const SizedBox(width: 10),
            const Text('TMC',
                style:
                    TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Buscar',
            onPressed: _search,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Limpar cache',
            onPressed: _clean,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Conta',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: _menu,
            itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                enabled: false,
                value: 'x',
                child: Text('Conta: ${Store.user}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: kGold)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'backup',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.save_alt),
                  title: Text('Backup do perfil'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'hist',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.history),
                  title: Text('Limpar todo o historico'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'favs',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.favorite_border),
                  title: Text('Apagar todos os favoritos'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'sair',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.logout),
                  title: Text('Sair da conta'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: kGold,
          unselectedLabelColor: Colors.white60,
          indicatorColor: kGold,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.6),
          tabs: _labels.map((String t) => Tab(height: 42, text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const BouncingScrollPhysics(),
        children: _pages,
      ),
    );
  }
}

// ============================== INICIO ===============================
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _loading = true;
  String _err = '';
  MediaItem? _hero;
  List<MediaItem> _trending = <MediaItem>[];
  List<MediaItem> _movies = <MediaItem>[];
  List<MediaItem> _series = <MediaItem>[];
  List<MediaItem> _novelas = <MediaItem>[];
  List<MediaItem> _dramas = <MediaItem>[];
  List<MediaItem> _kids = <MediaItem>[];
  List<MediaItem> _action = <MediaItem>[];
  List<WatchItem> _cont = <WatchItem>[];
  List<MediaItem> _favs = <MediaItem>[];

  @override
  void initState() {
    super.initState();
    Store.revision.addListener(_local);
    _local();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    Store.revision.removeListener(_local);
    super.dispose();
  }

  void _local() {
    if (!mounted) return;
    setState(() {
      _cont = Store.continueWatching();
      _favs = Store.favs;
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = '';
    });

    if (!TmdbService.ok) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err =
            'Cole a sua chave do TMDB na variavel tmdbApiKey (topo do lib/main.dart).';
      });
      return;
    }

    try {
      final List<List<MediaItem>> r =
          await Future.wait(<Future<List<MediaItem>>>[
        TmdbService.trending(pages: 3),
        TmdbService.popularMovies(pages: 3),
        TmdbService.popularTv(pages: 3),
        TmdbService.novelas(pages: 2),
        TmdbService.shortDramas(pages: 2),
        TmdbService.kidsMovies(pages: 2),
        TmdbService.actionMovies(pages: 2),
      ]);
      if (!mounted) return;
      setState(() {
        _trending = r[0];
        _movies = r[1];
        _series = r[2];
        _novelas = r[3];
        _dramas = r[4];
        _kids = r[5];
        _action = r[6];
        _hero = _pickHero(_trending);
        _loading = false;
      });
      _local();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  MediaItem? _pickHero(List<MediaItem> list) {
    for (final MediaItem m in list) {
      if (m.backdropUrl.isNotEmpty) return m;
    }
    return list.isEmpty ? null : list.first;
  }

  Future<void> _clearFavs() async {
    if (_favs.isEmpty) return;
    final bool ok = await askConfirm(context, 'Apagar favoritos',
        'Remover TODOS os titulos dos favoritos?');
    if (!ok) return;
    await Store.clearFavs();
  }

  Future<void> _clearHist() async {
    if (_cont.isEmpty) return;
    final bool ok = await askConfirm(context, 'Limpar historico',
        'Apagar TODO o historico de "Continuar Assistindo"?');
    if (!ok) return;
    await Store.clearProgress();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: kGold,
      backgroundColor: kSurface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 70),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_err.isNotEmpty)
            SliverToBoxAdapter(child: _errorBox())
          else ...<Widget>[
            if (_hero != null)
              SliverToBoxAdapter(child: HeroBanner(item: _hero!)),
            SliverToBoxAdapter(
              child: ContinueRow(
                  items: _cont, onChanged: _local, onClear: _clearHist),
            ),
            SliverToBoxAdapter(
              child: MediaRow(
                title: 'Meus Favoritos',
                items: _favs,
                removable: true,
                onRemove: (MediaItem m) => Store.removeFav(m.key),
                onClear: _clearFavs,
              ),
            ),
            SliverToBoxAdapter(
              child: MediaRow(title: 'Filmes em Destaque', items: _movies),
            ),
            SliverToBoxAdapter(
              child: MediaRow(title: 'Series em Alta', items: _series),
            ),
            SliverToBoxAdapter(
              child: MediaRow(title: 'Novelas', items: _novelas),
            ),
            SliverToBoxAdapter(
              child: MediaRow(title: 'Dramas Curtos', items: _dramas),
            ),
            SliverToBoxAdapter(
              child: MediaRow(title: 'Kids e Animacao', items: _kids),
            ),
            SliverToBoxAdapter(
              child: MediaRow(title: 'Tendencias da Semana', items: _trending),
            ),
            SliverToBoxAdapter(
              child: MediaRow(title: 'Acao e Aventura', items: _action),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ],
      ),
    );
  }

  Widget _errorBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 70, 20, 20),
      child: Column(
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 54, color: kGold),
          const SizedBox(height: 14),
          Text(_err,
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
        (MediaQuery.of(context).size.height * 0.6).clamp(320.0, 620.0);

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
            bottom: 18,
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
                      fontSize: 30, height: 1.05, fontWeight: FontWeight.w900),
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
  final bool removable;
  final void Function(MediaItem item)? onRemove;
  final Future<void> Function()? onClear;

  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    this.height = 218,
    this.removable = false,
    this.onRemove,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 10, 8),
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
              if (onClear != null)
                TextButton(
                  onPressed: () {
                    final Future<void> Function()? f = onClear;
                    if (f != null) f();
                  },
                  child: const Text('LIMPAR',
                      style: TextStyle(fontSize: 11, color: kGold)),
                )
              else
                Text('${items.length}',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white38)),
              const SizedBox(width: 6),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (BuildContext context, int i) => PosterCard(
              item: items[i],
              width: 134,
              onRemove: removable && onRemove != null
                  ? () {
                      final void Function(MediaItem)? f = onRemove;
                      if (f != null) f(items[i]);
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class ContinueRow extends StatelessWidget {
  final List<WatchItem> items;
  final VoidCallback onChanged;
  final Future<void> Function()? onClear;

  const ContinueRow({
    super.key,
    required this.items,
    required this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 10, 8),
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
              const Expanded(
                child: Text('Continuar Assistindo',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              if (onClear != null)
                TextButton(
                  onPressed: () {
                    final Future<void> Function()? f = onClear;
                    if (f != null) f();
                  },
                  child: const Text('LIMPAR',
                      style: TextStyle(fontSize: 11, color: kGold)),
                ),
              const SizedBox(width: 6),
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

  Future<void> _remove() async {
    await Store.removeProgress(widget.item.key);
    widget.onChanged();
  }

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
            onLongPress: _remove,
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
                        child: GestureDetector(
                          onTap: _remove,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle),
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
                        '${w.label} - ${fmtSeg(w.position)}',
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

// ============================= CARD ==================================
class PosterCard extends StatefulWidget {
  final MediaItem item;
  final bool autofocus;
  final double? width;
  final VoidCallback? onRemove;

  const PosterCard({
    super.key,
    required this.item,
    this.autofocus = false,
    this.width,
    this.onRemove,
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
          onLongPress: widget.onRemove,
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
                        if (widget.onRemove != null)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: GestureDetector(
                              onTap: widget.onRemove,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                    color: Colors.black87,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close,
                                    size: 13, color: Colors.white),
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
                    : '${widget.item.year} - ${widget.item.typeLabel}',
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

// ========================= ABA INFINITA ==============================
class DiscoverTab extends StatefulWidget {
  final List<GenreChip> chips;
  final Map<String, String> base;
  final String empty;

  const DiscoverTab({
    super.key,
    required this.chips,
    required this.base,
    this.empty = 'Nada por aqui ainda.',
  });

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  int _g = 0;

  Future<List<MediaItem>> _load(int page) {
    final GenreChip g = widget.chips[_g];
    final Map<String, String> q = <String, String>{
      'sort_by': 'popularity.desc',
      'include_adult': 'false',
      'vote_count.gte': '8',
      'language': 'pt-BR',
      ...widget.base,
      ...g.extra,
    };
    if (g.withGenres.isNotEmpty) q['with_genres'] = g.withGenres;
    return TmdbService.page(g.path, g.path.contains('/tv'), page, q);
  }

  @override
  Widget build(BuildContext context) {
    final GenreChip g = widget.chips[_g];
    return Column(
      children: <Widget>[
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: widget.chips.length,
            itemBuilder: (BuildContext c, int i) {
              final bool on = i == _g;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: on,
                  label: Text(widget.chips[i].label,
                      style: const TextStyle(fontSize: 11.5)),
                  selectedColor: kGold,
                  onSelected: (bool _) {
                    if (_g == i) return;
                    setState(() => _g = i);
                  },
                ),
              );
            },
          ),
        ),
        Expanded(
          child: InfiniteGrid(
            key: ValueKey<String>(
                '${g.label}|${g.path}|${g.withGenres}|${g.extra.length}'),
            loader: _load,
            empty: widget.empty,
          ),
        ),
      ],
    );
  }
}

class InfiniteGrid extends StatefulWidget {
  final Future<List<MediaItem>> Function(int page) loader;
  final String empty;

  const InfiniteGrid({
    super.key,
    required this.loader,
    this.empty = 'Nada por aqui ainda.',
  });

  @override
  State<InfiniteGrid> createState() => _InfiniteGridState();
}

class _InfiniteGridState extends State<InfiniteGrid> {
  final ScrollController _ctl = ScrollController();
  final List<MediaItem> _items = <MediaItem>[];
  int _page = 0;
  bool _busy = false;
  bool _done = false;
  bool _fail = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _more());
  }

  @override
  void dispose() {
    _ctl.removeListener(_onScroll);
    _ctl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctl.hasClients) return;
    if (_ctl.position.pixels >= _ctl.position.maxScrollExtent - 700) _more();
  }

  Future<void> _more() async {
    if (_busy || _done || !mounted) return;
    _busy = true;
    final int next = _page + 1;
    List<MediaItem> r = <MediaItem>[];
    try {
      r = await widget.loader(next);
    } catch (_) {
      r = <MediaItem>[];
    }
    if (!mounted) return;
    setState(() {
      _page = next;
      final Set<String> seen = _items.map((MediaItem m) => m.key).toSet();
      for (final MediaItem m in r) {
        if (seen.add(m.key)) _items.add(m);
      }
      if (r.length < 10) _done = true;
      _fail = _items.isEmpty && r.isEmpty;
      _busy = false;
    });
  }

  Future<void> _reset() async {
    if (!mounted) return;
    setState(() {
      _items.clear();
      _page = 0;
      _done = false;
      _busy = false;
      _fail = false;
    });
    await _more();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _done) {
      return RefreshIndicator(
        onRefresh: _reset,
        color: kGold,
        backgroundColor: kSurface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
              child: Column(
                children: <Widget>[
                  Icon(_fail ? Icons.cloud_off : Icons.inbox_outlined,
                      size: 46, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text(
                      _fail
                          ? 'Falha ao carregar. Puxe para tentar de novo.'
                          : widget.empty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reset,
      color: kGold,
      backgroundColor: kSurface,
      child: GridView.builder(
        controller: _ctl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 162,
          childAspectRatio: 0.54,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
        ),
        itemCount: _items.length + 1,
        itemBuilder: (BuildContext c, int i) {
          if (i >= _items.length) return _footer();
          return PosterCard(item: _items[i], autofocus: i == 0);
        },
      ),
    );
  }

  Widget _footer() {
    if (_done) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('FIM',
              style: TextStyle(color: Colors.white24, fontSize: 11)),
        ),
      );
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

// ============================ TV ONLINE ==============================
class OnlineTvTab extends StatefulWidget {
  const OnlineTvTab({super.key});
  @override
  State<OnlineTvTab> createState() => _OnlineTvTabState();
}

class _OnlineTvTabState extends State<OnlineTvTab> {
  bool _eventos = false;
  bool _carregando = true;
  List<Channel> _canais = <Channel>[];
  List<Channel> _meus = <Channel>[];
  List<SportEvent> _jogos = <SportEvent>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _carregando = true);

    final List<Channel> meus = <Channel>[];
    try {
      final String raw = prefs.getString('tmc_ch_${Store.user}') ?? '';
      if (raw.isNotEmpty) {
        final List<dynamic> l = jsonDecode(raw) as List<dynamic>;
        for (final dynamic e in l) {
          meus.add(Channel.fromJson(
              (e as Map<dynamic, dynamic>).cast<String, dynamic>()));
        }
      }
    } catch (_) {}

    final List<Channel> api = await SuperFlix.canais();
    final List<SportEvent> ev = await SuperFlix.eventos();

    if (!mounted) return;
    setState(() {
      _meus = meus;
      _canais = api;
      _jogos = ev;
      _carregando = false;
    });
  }

  Future<void> _save() async {
    try {
      await prefs.setString('tmc_ch_${Store.user}',
          jsonEncode(_meus.map((Channel c) => c.toJson()).toList()));
    } catch (_) {}
  }

  void _abrir(String titulo, String url) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebScreen(url: url, title: titulo, provider: 'TV ONLINE'),
    ));
  }

  void _playCanal(Channel c) => _abrir(c.name, SuperFlix.canalUrl(c.id));

  Future<void> _add() async {
    final TextEditingController n = TextEditingController();
    final TextEditingController u = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Novo canal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: n,
              decoration: const InputDecoration(
                  labelText: 'Nome do canal', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: u,
              decoration: const InputDecoration(
                  labelText: 'Link .m3u8 ou pagina embed',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Adicionar')),
        ],
      ),
    );
    if (ok != true) return;
    if (n.text.trim().isEmpty || u.text.trim().isEmpty) return;
    setState(() => _meus = <Channel>[
          Channel(u.text.trim(), n.text.trim(), 'MEUS CANAIS'),
          ..._meus,
        ]);
    await _save();
  }

  Future<void> _remove(Channel c) async {
    final bool ok = await askConfirm(
        context, 'Remover canal', 'Remover "${c.name}" da sua lista?');
    if (!ok) return;
    setState(() => _meus = _meus.where((Channel x) => x.id != c.id).toList());
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());

    final List<Channel> todos = <Channel>[..._meus, ..._canais];
    final List<String> grupos = <String>[];
    for (final Channel c in todos) {
      if (!grupos.contains(c.group)) grupos.add(c.group);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('CANAIS',
                        style: TextStyle(fontSize: 11.5)),
                    selected: !_eventos,
                    selectedColor: kGold,
                    onSelected: (bool _) => setState(() => _eventos = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('ESPORTES',
                        style: TextStyle(fontSize: 11.5)),
                    selected: _eventos,
                    selectedColor: kGold,
                    onSelected: (bool _) => setState(() => _eventos = true),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('CANAL'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_eventos) ..._listaEventos() else ..._listaCanais(todos, grupos),
      ],
    );
  }

  List<Widget> _listaEventos() {
    if (_jogos.isEmpty) {
      return <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(
            child: Text('Nenhum evento esportivo na agenda agora.',
                style: TextStyle(color: Colors.white54)),
          ),
        ),
      ];
    }
    return _jogos.map((SportEvent e) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _abrir(e.title, e.url),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.sports_soccer, color: kGold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13.5)),
                        Text(
                            <String>[e.competition, e.sport, e.status]
                                .where((String s) => s.isNotEmpty)
                                .join(' - '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10.5, color: Colors.white38)),
                      ],
                    ),
                  ),
                  const Icon(Icons.play_circle_fill, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _listaCanais(List<Channel> todos, List<String> grupos) {
    final List<Widget> out = <Widget>[];
    for (final String g in grupos) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(g.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                color: kGold,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      ));
      for (final Channel c in todos.where((Channel x) => x.group == g)) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: kCard,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _playCanal(c),
              onLongPress:
                  c.group == 'MEUS CANAIS' ? () => _remove(c) : null,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.live_tv, color: kGold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ),
                    const Icon(Icons.play_circle_fill, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ));
      }
    }
    return out;
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
      if (!mounted) return;
      setState(() => _items = r);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = <MediaItem>[]);
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
              : _grid(),
    );
  }

  Widget _grid() {
    if (_items.isEmpty) {
      return Center(
        child: Text('Nada encontrado para "$_q".',
            style: const TextStyle(color: Colors.white54)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 60),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 162,
        childAspectRatio: 0.54,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
      ),
      itemCount: _items.length,
      itemBuilder: (BuildContext c, int i) =>
          PosterCard(item: _items[i], autofocus: i == 0),
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
  String _err = '';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadEpisodes() async {
    if (!mounted) return;
    setState(() {
      _epLoading = true;
      _episodes = <Episode>[];
    });
    try {
      final List<Episode> eps =
          await TmdbService.episodes(widget.item.id, _season);
      if (!mounted) return;
      setState(() => _episodes = eps);
    } catch (_) {
      if (!mounted) return;
      setState(() => _episodes = <Episode>[]);
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
    if (key == null || key.isEmpty) {
      key = await TmdbService.trailerKey(widget.item.id, _isTv);
    }
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
            expandedHeight: 320,
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
                      errorBuilder:
                          (BuildContext c, Object e, StackTrace? s) =>
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
    if (_err.isNotEmpty) {
      return Column(
        children: <Widget>[
          Text(_err,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kGold)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _loading = true;
                _err = '';
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
            _chip('* ${item.rating.toStringAsFixed(1)}', kGold),
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
        const SizedBox(height: 12),
        const Text('Servidor:',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _serverChip(-1, 'AUTOMATICO'),
            for (int i = 0; i < kSources.length; i++)
              _serverChip(i, kSources[i].name),
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
        const SizedBox(height: 60),
      ],
    );
  }

  List<Map<String, dynamic>> _cast() {
    final Map<String, dynamic>? d = _d;
    if (d == null) return <Map<String, dynamic>>[];
    final Map<String, dynamic>? cr = d['credits'] as Map<String, dynamic>?;
    final List<dynamic> raw =
        (cr?['cast'] as List<dynamic>?) ?? const <dynamic>[];
    return raw.take(16).map((dynamic e) => e as Map<String, dynamic>).toList();
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

// ======================= PLAYER NATIVO IMERSIVO ======================
class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String provider;
  final String referer;
  final String embed;
  final MediaItem? media;
  final int season;
  final int episode;
  final bool live;

  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.provider = '',
    this.referer = '',
    this.embed = '',
    this.media,
    this.season = 1,
    this.episode = 1,
    this.live = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _busy = true;
  String _err = '';
  bool _ui = true;
  Timer? _hide;
  Timer? _saver;
  Timer? _watch;

  List<HlsVariant> _variants = <HlsVariant>[];
  List<HlsMedia> _audios = <HlsMedia>[];
  List<HlsMedia> _subs = <HlsMedia>[];
  List<Cue> _cues = <Cue>[];
  Cue? _cue;
  int _audioSel = -1;
  int _subSel = -1;
  bool _auto = true;
  bool _degraded = false;
  int _stall = 0;
  int _lastPos = -1;
  String _qualityLabel = 'AUTO';

  String get _key {
    final MediaItem? m = widget.media;
    if (m == null) return 'live_${widget.title}';
    return m.isTv ? '${m.key}_${widget.season}_${widget.episode}' : m.key;
  }

  Map<String, String> get _headers {
    final Map<String, String> h = <String, String>{'User-Agent': kUserAgent};
    if (widget.referer.isNotEmpty) h['Referer'] = widget.referer;
    return h;
  }

  @override
  void initState() {
    super.initState();
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(widget.url, first: true);
    });
  }

  void _detach() {
    final VideoPlayerController? c = _c;
    _c = null;
    if (c == null) return;
    try {
      c.removeListener(_tick);
    } catch (_) {}
    try {
      c.dispose();
    } catch (_) {}
  }

  Future<void> _open(String url, {bool first = false}) async {
    final VideoPlayerController? old = _c;
    final int keep = (old != null && old.value.isInitialized)
        ? old.value.position.inSeconds
        : 0;
    _detach();
    if (mounted) {
      setState(() {
        _busy = true;
        _err = '';
        _ready = false;
      });
    }

    VideoPlayerController? c;
    try {
      c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: _headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize();
      await c.setLooping(false);
    } catch (e) {
      try {
        await c?.dispose();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _busy = false;
      });
      return;
    }

    if (!mounted) {
      await c.dispose();
      return;
    }

    if (first && !widget.live) {
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
    } else if (keep > 3) {
      try {
        await c.seekTo(Duration(seconds: keep));
      } catch (_) {}
    }

    try {
      await c.play();
    } catch (_) {}

    if (!mounted) {
      await c.dispose();
      return;
    }

    c.addListener(_tick);
    setState(() {
      _c = c;
      _ready = true;
      _busy = false;
    });

    _saver ??= Timer.periodic(const Duration(seconds: 5), (Timer _) => _save());
    _watch ??= Timer.periodic(const Duration(seconds: 2), (Timer _) => _check());
    if (first) {
      _scheduleHide();
      _carregarFaixas();
    }
  }

  Future<void> _carregarFaixas() async {
    if (widget.live || !widget.url.contains('.m3u8')) return;
    final Map<String, dynamic> info = await Hls.parse(widget.url, _headers);
    if (!mounted) return;
    setState(() {
      _variants = (info['variants'] as List<HlsVariant>?) ?? <HlsVariant>[];
      _audios = (info['audios'] as List<HlsMedia>?) ?? <HlsMedia>[];
      _subs = (info['subs'] as List<HlsMedia>?) ?? <HlsMedia>[];
    });
  }

  Future<void> _trocarQualidade(HlsVariant v, {bool auto = false}) async {
    if (mounted) {
      setState(() {
        _auto = auto;
        _qualityLabel = auto ? 'AUTO' : v.label;
      });
    }
    await _open(v.url);
  }

  Future<void> _trocarAudio(HlsMedia m) async {
    setState(() => _audioSel = _audios.indexOf(m));
    if (m.url.isEmpty) {
      await _open(widget.url);
      return;
    }
    await _open(m.url);
  }

  Future<void> _trocarLegenda(HlsMedia m) async {
    if (_subSel >= 0 && _subs[_subSel].url == m.url) {
      setState(() {
        _subSel = -1;
        _cues = <Cue>[];
        _cue = null;
      });
      return;
    }
    setState(() => _subSel = _subs.indexOf(m));
    final List<Cue> cues = await Hls.cues(m.url, _headers);
    if (!mounted) return;
    setState(() => _cues = cues);
  }

  /// Qualidade automatica: cai para a faixa mais leve se a rede engasgar.
  void _check() {
    final VideoPlayerController? c = _c;
    if (c == null || !c.value.isInitialized) return;
    final int p = c.value.position.inSeconds;
    if (c.value.isBuffering || (c.value.isPlaying && p == _lastPos)) {
      _stall++;
    } else {
      _stall = 0;
    }
    _lastPos = p;
    if (_stall >= 3 && _auto && !_degraded && _variants.length > 1) {
      _degraded = true;
      _stall = 0;
      _trocarQualidade(_variants.first, auto: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Rede instavel: qualidade automatica reduzida.')));
      }
    }
  }

  Future<bool> _askResume(int seconds) async {
    final bool? r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Continuar de onde parou?'),
        content: Text(
          'Voce parou em ${fmtSeg(seconds)}. Deseja retomar deste ponto?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Comecar do inicio'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  void _save() {
    if (widget.live) return;
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

  Cue? _cueEm(int ms) {
    for (final Cue c in _cues) {
      if (c.start > ms) break;
      if (ms >= c.start && ms <= c.end) return c;
    }
    return null;
  }

  void _tick() {
    if (!mounted) return;
    final VideoPlayerController? c = _c;
    final int ms = c == null ? 0 : c.value.position.inMilliseconds;
    setState(() {
      _cue = _cues.isEmpty ? null : _cueEm(ms);
    });
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

  Future<void> _doComeco() async {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    await Store.removeProgress(_key);
    await c.seekTo(Duration.zero);
    await c.play();
    _scheduleHide();
  }

  void _pular(int segundos) {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    final Duration alvo = c.value.position + Duration(seconds: segundos);
    c.seekTo(alvo < Duration.zero ? Duration.zero : alvo);
    _scheduleHide();
  }

  @override
  void dispose() {
    _save();
    _hide?.cancel();
    _saver?.cancel();
    _watch?.cancel();
    _detach();
    CacheKeeper.wipe();
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
    super.dispose();
  }

  void _openWeb() {
    final String alvo = widget.embed.isNotEmpty ? widget.embed : widget.url;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WebScreen(url: alvo, title: widget.title),
    ));
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
              if (_cue != null && !_ui)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 34,
                  child: Center(
                    child: Text(
                      _cue!.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        shadows: <Shadow>[
                          Shadow(blurRadius: 6, color: Colors.black),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedOpacity(
                opacity: _ui ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(ignoring: !_ui, child: _overlay(c)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _surface(VideoPlayerController? c) {
    if (_err.isNotEmpty) return _errorBox();
    if (_busy || c == null || !_ready) {
      return const SizedBox(
        width: 46,
        height: 46,
        child: CircularProgressIndicator(),
      );
    }
    return AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c));
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
          Text(_err,
              maxLines: 3,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => _open(widget.url, first: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
              OutlinedButton.icon(
                onPressed: _openWeb,
                icon: const Icon(Icons.language),
                label: const Text('Abrir na WebView'),
              ),
            ],
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
          if (c != null && c.value.isInitialized) _controles(c),
          const Spacer(),
          if (c != null && c.value.isInitialized && !widget.live) _seekBar(c),
          if (widget.live) const SizedBox(height: 14),
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
          _botaoQualidade(),
          _botaoAudio(),
          _botaoLegenda(),
          if (widget.provider.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(widget.provider,
                  style: const TextStyle(fontSize: 11, color: Colors.white54)),
            ),
          IconButton(
            tooltip: 'Abrir no site (fallback)',
            icon: const Icon(Icons.language),
            onPressed: _openWeb,
          ),
        ],
      ),
    );
  }

  Widget _pill(String t, IconData icone) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGold.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icone, size: 12, color: kGold),
          const SizedBox(width: 4),
          Text(t,
              style: const TextStyle(
                  fontSize: 10, color: kGold, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _botaoQualidade() {
    if (widget.live || _variants.isEmpty) {
      return _pill(_qualityLabel, Icons.hd_outlined);
    }
    return PopupMenuButton<int>(
      tooltip: 'Qualidade',
      onSelected: (int v) {
        if (v < 0) {
          setState(() {
            _auto = true;
            _qualityLabel = 'AUTO';
            _degraded = false;
          });
          _open(widget.url);
        } else {
          _trocarQualidade(_variants[v]);
        }
      },
      itemBuilder: (BuildContext c) {
        final List<PopupMenuEntry<int>> items = <PopupMenuEntry<int>>[
          const PopupMenuItem<int>(value: -1, child: Text('AUTO (adaptativo)')),
        ];
        for (int i = _variants.length - 1; i >= 0; i--) {
          items.add(
              PopupMenuItem<int>(value: i, child: Text(_variants[i].label)));
        }
        return items;
      },
      child: _pill(_qualityLabel, Icons.hd_outlined),
    );
  }

  Widget _botaoAudio() {
    final String rotulo = _audioSel >= 0 && _audioSel < _audios.length
        ? _audios[_audioSel].name
        : 'AUDIO';
    if (_audios.isEmpty) return _pill(rotulo, Icons.audiotrack);
    return PopupMenuButton<int>(
      tooltip: 'Idioma / Audio',
      onSelected: (int v) => _trocarAudio(_audios[v]),
      itemBuilder: (BuildContext c) => <PopupMenuEntry<int>>[
        for (int i = 0; i < _audios.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text('${_audios[i].name}  ${_audios[i].lang}'),
          ),
      ],
      child: _pill(rotulo, Icons.audiotrack),
    );
  }

  Widget _botaoLegenda() {
    final bool on = _subSel >= 0 && _subSel < _subs.length;
    final String rotulo =
        on ? 'LEG: ${_subs[_subSel].name}' : 'LEGENDAS';
    if (_subs.isEmpty) return _pill(rotulo, Icons.subtitles_outlined);
    return PopupMenuButton<int>(
      tooltip: 'Legendas',
      onSelected: (int v) {
        if (v < 0) {
          setState(() {
            _subSel = -1;
            _cues = <Cue>[];
            _cue = null;
          });
          return;
        }
        _trocarLegenda(_subs[v]);
      },
      itemBuilder: (BuildContext c) => <PopupMenuEntry<int>>[
        const PopupMenuItem<int>(value: -1, child: Text('DESLIGADAS')),
        for (int i = 0; i < _subs.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text('${_subs[i].name}  ${_subs[i].lang}'),
          ),
      ],
      child: _pill(rotulo, Icons.subtitles_outlined),
    );
  }

  Widget _controles(VideoPlayerController c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: 'Assistir do comeco',
          iconSize: 32,
          icon: const Icon(Icons.restart_alt),
          onPressed: _doComeco,
        ),
        const SizedBox(width: 14),
        IconButton(
          iconSize: 34,
          icon: const Icon(Icons.replay_10),
          onPressed: () => _pular(-10),
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
          onPressed: () => _pular(10),
        ),
        const SizedBox(width: 14),
        IconButton(
          tooltip: 'Legendas',
          iconSize: 30,
          icon: Icon(_subSel >= 0
              ? Icons.closed_caption
              : Icons.closed_caption_outlined),
          onPressed: () {
            if (_subs.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  duration: Duration(seconds: 2),
                  content: Text('Este stream nao informa faixas de legenda.')));
              return;
            }
            _trocarLegenda(_subs[(_subSel + 1) % _subs.length]);
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
          Text(fmtSeg(c.value.position.inSeconds),
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
          Text(fmtSeg(c.value.duration.inSeconds),
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
  WebViewController? _ctl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _montar());
  }

  void _montar() {
    try {
      final WebViewController ctl = WebViewController();
      ctl.setJavaScriptMode(JavaScriptMode.unrestricted);
      ctl.setBackgroundColor(Colors.black);
      ctl.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (String _) => _nudge()),
      );
      ctl.loadRequest(Uri.parse(
          'https://www.youtube.com/embed/${widget.videoKey}?autoplay=1&playsinline=1&rel=0&modestbranding=1'));
      if (mounted) setState(() => _ctl = ctl);
    } catch (_) {
      if (mounted) setState(() => _ctl = null);
    }
  }

  Future<void> _nudge() async {
    final WebViewController? ctl = _ctl;
    if (ctl == null) return;
    const String js =
        "try{var v=document.querySelector('video');if(v){v.play();}}catch(e){}";
    try {
      await ctl.runJavaScript(js);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 900));
    try {
      await ctl.runJavaScript(js);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final WebViewController? ctl = _ctl;
    if (ctl == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return WebViewWidget(controller: ctl);
  }
}

class WebScreen extends StatefulWidget {
  final String url;
  final String title;
  final String provider;
  const WebScreen({
    super.key,
    required this.url,
    required this.title,
    this.provider = '',
  });

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  WebViewController? _ctl;
  int _progress = 0;
  bool _ui = true;
  String _falha = '';

  @override
  void initState() {
    super.initState();
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) => _montar());
  }

  void _montar() {
    try {
      final WebViewController ctl = WebViewController();
      ctl.setJavaScriptMode(JavaScriptMode.unrestricted);
      ctl.setBackgroundColor(Colors.black);
      ctl.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (String _) => _inject(),
          onPageFinished: (String _) => _inject(),
          onWebResourceError: (WebResourceError e) {
            if (mounted && e.isForMainFrame == true) {
              setState(() => _falha = e.description);
            }
          },
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
      );
      final Uri? parsedUrl = Uri.tryParse(widget.url);
      final bool isDirectHls = kIsWeb &&
          parsedUrl != null &&
          parsedUrl.path.toLowerCase().endsWith('.m3u8');
      if (isDirectHls) {
        final String source = jsonEncode(widget.url);
        ctl.loadHtmlString('''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
html,body{margin:0;width:100%;height:100%;background:#000;color:#fff;font-family:Arial,sans-serif}
video{width:100%;height:100%;object-fit:contain;background:#000}
#msg{position:fixed;left:12px;right:12px;bottom:12px;padding:10px;background:#222c;border-radius:8px;font-size:13px}
</style>
</head>
<body>
<video id="player" controls autoplay playsinline></video>
<div id="msg">Conectando ao servidor de vídeo…</div>
<script src="https://cdn.jsdelivr.net/npm/hls.js@1"></script>
<script>
const video=document.getElementById('player');
const msg=document.getElementById('msg');
const source=$source;
function fail(text){msg.textContent=text;msg.style.display='block';}
video.addEventListener('playing',()=>msg.style.display='none');
video.addEventListener('error',()=>fail('O servidor não forneceu um vídeo compatível. Tente outro servidor no TMC.'));
if(window.Hls && Hls.isSupported()){
  const hls=new Hls({enableWorker:true});
  hls.on(Hls.Events.ERROR,(_,data)=>{if(data.fatal)fail('Falha ao carregar o vídeo deste servidor. Volte e selecione outro servidor.');});
  hls.loadSource(source); hls.attachMedia(video);
}else if(video.canPlayType('application/vnd.apple.mpegurl')){
  video.src=source;
}else{
  fail('Este navegador não oferece suporte à reprodução HLS.');
}
</script>
</body>
</html>
''');
      } else {
        ctl.loadRequest(Uri.parse(widget.url));
      }
      if (mounted) setState(() => _ctl = ctl);
    } catch (e) {
      if (mounted) setState(() => _falha = e.toString());
    }
  }

  Future<void> _inject() async {
    try {
      await _ctl?.runJavaScript(kPopupKiller);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _ctl?.clearCache();
    } catch (_) {}
    CacheKeeper.wipe();
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WebViewController? ctl = _ctl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          if (ctl != null)
            WebViewWidget(controller: ctl)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_falha.isEmpty)
                      const CircularProgressIndicator()
                    else ...<Widget>[
                      const Icon(Icons.public_off, color: kGold, size: 44),
                      const SizedBox(height: 12),
                      Text(_falha,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _montar,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SelectableText(widget.url,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 10.5, color: Colors.white38)),
                  ],
                ),
              ),
            ),
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

$dart = $dart.Replace('__TMDB_KEY__', $keyTmdb)

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($mainPath, $dart, $utf8)

$linhas = ([System.IO.File]::ReadAllText($mainPath) -split "`n").Count
Write-Host ''
Write-Host ('-> lib/main.dart reescrito com sucesso (' + $linhas + ' linhas, UTF-8).') -ForegroundColor Green

# ---------------------------------------------------------------------
# 4) ANDROID MANIFEST (internet, armazenamento, Android TV)
# ---------------------------------------------------------------------
$manifest = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
if (Test-Path -LiteralPath $manifest) {
    try {
        $xml = [System.IO.File]::ReadAllText($manifest)
        $changed = $false

        if ($xml -notmatch 'android.permission.INTERNET') {
            $xml = $xml -replace '(<manifest[^>]*>)', '$1' + "`r`n    <uses-permission android:name=`"android.permission.INTERNET`" />"
            $changed = $true
        }
        if ($xml -notmatch 'WRITE_EXTERNAL_STORAGE') {
            $xml = $xml -replace '(<manifest[^>]*>)', '$1' + "`r`n    <uses-permission android:name=`"android.permission.WRITE_EXTERNAL_STORAGE`" android:maxSdkVersion=`"29`" />"
            $changed = $true
        }
        if ($xml -notmatch 'android.software.leanback') {
            $xml = $xml -replace '(<manifest[^>]*>)', '$1' + "`r`n    <uses-feature android:name=`"android.software.leanback`" android:required=`"false`" />`r`n    <uses-feature android:name=`"android.hardware.touchscreen`" android:required=`"false`" />"
            $changed = $true
        }
        if ($xml -notmatch 'LEANBACK_LAUNCHER') {
            $xml = $xml -replace '(<category android:name="android.intent.category.LAUNCHER"\s*/>)', '$1' + "`r`n            <category android:name=`"android.intent.category.LEANBACK_LAUNCHER`" />"
            $changed = $true
        }
        if ($xml -notmatch 'requestLegacyExternalStorage' -and $xml -match '<application') {
            $xml = $xml -replace '(<application\b)', '$1 android:requestLegacyExternalStorage="true"'
            $changed = $true
        }

        if ($changed) {
            [System.IO.File]::WriteAllText($manifest, $xml, $utf8)
            Write-Host '-> AndroidManifest.xml ajustado (internet, backup e Android TV).' -ForegroundColor Green
        } else {
            Write-Host '-> AndroidManifest.xml ja estava correto.' -ForegroundColor DarkGray
        }
    } catch {
        Write-Host '   (aviso: nao foi possivel ajustar o AndroidManifest.xml)' -ForegroundColor Yellow
    }
} else {
    Write-Host '-> AndroidManifest.xml nao encontrado.' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
# 5) VALIDACAO
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '-> Rodando flutter pub get...' -ForegroundColor Yellow
& flutter pub get

Write-Host '-> Validando com flutter analyze (pode demorar)...' -ForegroundColor Yellow
& flutter analyze --no-fatal-infos

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '   CONCLUIDO! Rode:  flutter run --release' -ForegroundColor Cyan
Write-Host '   Backup do arquivo antigo em lib/main.dart.bak' -ForegroundColor DarkGray
Write-Host '   Se aparecer "SUA_CHAVE_AQUI", edite tmdbApiKey no topo.' -ForegroundColor DarkGray
Write-Host '========================================================' -ForegroundColor Cyan
