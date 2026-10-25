@echo off
setlocal
chcp 65001 >nul
title TMC - Gerador automatico (Flutter)
color 0B
cd /d "%~dp0"

echo ==========================================================
echo    TMC  -  Gerador automatico do aplicativo (Flutter)
echo    Catalogo TMDB + Resolvedores + Player
echo ==========================================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERRO] Flutter nao foi encontrado no PATH.
    echo        Instale o Flutter SDK e rode este .bat novamente.
    pause
    exit /b 1
)

echo [1/6] Criando o projeto Flutter...
if exist "meu_agregador" rmdir /s /q "meu_agregador"
call flutter create --org com.dmc --project-name mc meu_agregador
if errorlevel 1 goto :erro

cd /d "meu_agregador"

echo.
echo [2/6] Adicionando dependencias...
call flutter pub add http webview_flutter video_player google_fonts flutter_launcher_icons
if errorlevel 1 goto :erro

echo.
echo [3/6] Injetando o codigo-fonte (lib/main.dart)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText('%~f0');$e=New-Object System.Text.UTF8Encoding $false;$m=[regex]::Match($s,'(?s)@@@DART@@@\r?\n(.*?)\r?\n@@@END@@@');[IO.File]::WriteAllText('lib\main.dart',$m.Groups[1].Value,$e);$m2=[regex]::Match($s,'(?s)@@@PS@@@\r?\n(.*?)\r?\n@@@ENDPS@@@');[IO.File]::WriteAllText('_tmc_setup.ps1',$m2.Groups[1].Value,$e);if($m.Success -and $m2.Success){Write-Host '  -^> main.dart + _tmc_setup.ps1 gerados.'}else{Write-Host '  -^> ERRO na extracao';exit 1}"
if errorlevel 1 goto :erro

echo.
echo [4/6] Gerando icone e configurando Android / Android TV...
powershell -NoProfile -ExecutionPolicy Bypass -File "_tmc_setup.ps1"
if errorlevel 1 goto :erro

echo.
echo [5/6] Aplicando icones do launcher...
call flutter pub run flutter_launcher_icons
call flutter pub get

echo.
echo [6/6] Compilando e instalando no dispositivo conectado...
call flutter run --release

echo.
echo ==========================================================
echo    CONCLUIDO. Bom uso!  -  TMC
echo ==========================================================
pause
exit /b 0

:erro
echo.
echo ==========================================================
echo    [ERRO] A execucao foi interrompida.
echo ==========================================================
pause
exit /b 1

@@@DART@@@
// =====================================================================
//  TMC - Agregador de Streaming
//  Catalogo: TMDB  |  Resolvedores: SuperFlixAPI / EmbedCine / WarezCDN
//  Player: video_player (m3u8) ou WebView (embed)
//  >>>>> COLE A SUA CHAVE DO TMDB NA LINHA MARCADA ABAIXO <<<<<
// =====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ======================= CONFIGURACAO ================================
String tmdbApiKey = "SUA_CHAVE_AQUI";

const String kTmdbBase = "https://api.themoviedb.org/3";
const String kTmdbImg = "https://image.tmdb.org/t/p";
const String kUserAgent =
    "Mozilla/5.0 (Linux; Android 11; Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

const Color kBg = Color(0xFF0A0E18);
const Color kSurface = Color(0xFF141B2C);
const Color kAccent = Color(0xFF3D7BFF);
const Color kGold = Color(0xFFF5C451);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const TmcApp());
}

class TmcApp extends StatelessWidget {
  const TmcApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
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
        textTheme: GoogleFonts.poppinsTextTheme(base.textTheme)
            .apply(bodyColor: Colors.white, displayColor: Colors.white),
        appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0),
      ),
      home: const HomeScreen(),
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

  factory MediaItem.fromJson(Map<String, dynamic> j, bool isTv) {
    return MediaItem(
      id: (j['id'] ?? 0) as int,
      title: ((isTv ? j['name'] : j['title']) ?? 'Sem titulo').toString(),
      poster: j['poster_path']?.toString(),
      backdrop: j['backdrop_path']?.toString(),
      overview: (j['overview'] ?? '').toString(),
      date: (isTv ? j['first_air_date'] : j['release_date'])?.toString(),
      rating: ((j['vote_average'] ?? 0) as num).toDouble(),
      isTv: isTv,
    );
  }

  String get posterUrl => (poster == null) ? '' : '$kTmdbImg/w342$poster';
  String get backdropUrl => (backdrop == null) ? '' : '$kTmdbImg/w780$backdrop';

  String get year {
    final d = date;
    if (d != null && d.length >= 4) return d.substring(0, 4);
    return '';
  }
}

class TmdbException implements Exception {
  final String message;
  TmdbException(this.message);
  @override
  String toString() => message;
}

// ======================== SERVICO TMDB ===============================
class TmdbService {
  static bool get _keyOk =>
      tmdbApiKey.trim().isNotEmpty && tmdbApiKey != 'SUA_CHAVE_AQUI';

  static void _checkKey() {
    if (!_keyOk) {
      throw TmdbException(
          'Cole a sua chave do TMDB na variavel tmdbApiKey (topo do lib/main.dart).');
    }
  }

  static Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? q]) async {
    _checkKey();
    final params = <String, String>{
      'api_key': tmdbApiKey,
      'language': 'pt-BR',
      ...?q,
    };
    final uri = Uri.parse('$kTmdbBase$path').replace(queryParameters: params);
    final res = await http.get(uri).timeout(const Duration(seconds: 18));
    if (res.statusCode == 401) {
      throw TmdbException('Chave do TMDB invalida (401). Confira a tmdbApiKey.');
    }
    if (res.statusCode != 200) {
      throw TmdbException('Erro do TMDB: HTTP ${res.statusCode}');
    }
    return json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<List<MediaItem>> _list(String path, bool isTv,
      {Map<String, String>? q}) async {
    final data = await _get(path, q);
    final results = (data['results'] as List?) ?? const [];
    return results
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>, isTv))
        .toList();
  }

  static Future<List<MediaItem>> popularMovies({int page = 1}) =>
      _list('/movie/popular', false, q: {'page': '$page'});

  static Future<List<MediaItem>> popularTv({int page = 1}) =>
      _list('/tv/popular', false == true ? false : true, q: {'page': '$page'});

  static Future<List<MediaItem>> trending() => _list('/trending/all/week', false);

  static Future<List<MediaItem>> search(String query, bool isTv) => _list(
        isTv ? '/search/tv' : '/search/movie',
        isTv,
        q: {'query': query, 'include_adult': 'false'},
      );

  static Future<Map<String, dynamic>> details(int id, bool isTv) =>
      _get(isTv ? '/tv/$id' : '/movie/$id');

  static Future<Map<String, dynamic>> season(int id, int season) =>
      _get('/tv/$id/season/$season');
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

class Provider {
  final String name;
  final String Function(bool isTv, int id, int season, int episode) build;
  const Provider(this.name, this.build);
}

final List<Provider> kProviders = [
  Provider(
    'SuperFlixAPI',
    (isTv, id, s, e) => isTv
        ? 'https://superflixapi.top/serie/$id/$s/$e'
        : 'https://superflixapi.top/filme/$id',
  ),
  Provider(
    'EmbedCine',
    (isTv, id, s, e) => isTv
        ? 'https://embedcine.com/serie/$id/$s/$e'
        : 'https://embedcine.com/filme/$id',
  ),
  Provider(
    'WarezCDN',
    (isTv, id, s, e) => isTv
        ? 'https://warezcdn.com/embed/serie.php?id=$id&season=$s&episode=$e'
        : 'https://warezcdn.com/embed/filme.php?id=$id',
  ),
];

class Resolver {
  static final RegExp _m3u8 =
      RegExp(r'''https?://[^"'\s\\<>]+\.m3u8[^"'\s\\<>]*''');
  static final RegExp _iframe =
      RegExp(r'''<iframe[^>]*src=["']([^"']+)["']''', caseSensitive: false);

  static Future<http.Response?> _fetch(String url, String referer) async {
    try {
      return await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': kUserAgent,
          if (referer.isNotEmpty) 'Referer': referer,
        },
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  static Future<PlayTarget?> resolve(
      Provider p, bool isTv, int id, int season, int episode) async {
    final pageUrl = p.build(isTv, id, season, episode);
    final res = await _fetch(pageUrl, pageUrl);
    final body = res?.body ?? '';

    final m = _m3u8.firstMatch(body);
    if (m != null) {
      return PlayTarget(
          provider: p.name, url: m.group(0)!, direct: true, referer: pageUrl);
    }

    final f = _iframe.firstMatch(body);
    if (f != null) {
      var src = f.group(1)!.trim();
      if (src.startsWith('//')) src = 'https:$src';
      src = Uri.parse(pageUrl).resolve(src).toString();

      final r2 = await _fetch(src, pageUrl);
      final m2 = _m3u8.firstMatch(r2?.body ?? '');
      if (m2 != null) {
        return PlayTarget(
            provider: p.name, url: m2.group(0)!, direct: true, referer: src);
      }
      return PlayTarget(
          provider: p.name, url: src, direct: false, referer: pageUrl);
    }

    if (res == null && body.isEmpty) return null;
    return PlayTarget(
        provider: p.name, url: pageUrl, direct: false, referer: pageUrl);
  }
}

// =========================== TELA HOME ===============================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<MediaItem>> _movies;
  late Future<List<MediaItem>> _series;

  @override
  void initState() {
    super.initState();
    _movies = TmdbService.popularMovies();
    _series = TmdbService.popularTv();
  }

  void _reload() {
    setState(() {
      _movies = TmdbService.popularMovies();
      _series = TmdbService.popularTv();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1E4AAA), kAccent]),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('MC',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: -0.5)),
                ),
              ),
              const SizedBox(width: 10),
              const Text('TMC',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: 2)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Buscar',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen())),
              icon: const Icon(Icons.search),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: kGold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [Tab(text: 'FILMES'), Tab(text: 'SERIES')],
          ),
        ),
        body: Column(
          children: [
            if (tmdbApiKey == 'SUA_CHAVE_AQUI')
              Container(
                width: double.infinity,
                color: kGold.withOpacity(0.15),
                padding: const EdgeInsets.all(10),
                child: const Text(
                  'Cole a sua chave do TMDB na variavel tmdbApiKey no topo do lib/main.dart',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kGold, fontSize: 12),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  PosterGrid(future: _movies),
                  PosterGrid(future: _series),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================== GRADE / CARD ============================
class PosterGrid extends StatelessWidget {
  final Future<List<MediaItem>> future;
  final String emptyMsg;
  const PosterGrid(
      {super.key, required this.future, this.emptyMsg = 'Nada encontrado.'});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaItem>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(snap.error.toString(), textAlign: TextAlign.center),
            ),
          );
        }
        final items = snap.data ?? const <MediaItem>[];
        if (items.isEmpty) {
          return Center(
              child: Text(emptyMsg, style: const TextStyle(color: Colors.white70)));
        }
        return LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 150).floor().clamp(2, 8).toInt();
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 0.55,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) =>
                PosterCard(item: items[i], autofocus: i == 0),
          );
        });
      },
    );
  }
}

class PosterCard extends StatefulWidget {
  final MediaItem item;
  final bool autofocus;
  const PosterCard({super.key, required this.item, this.autofocus = false});

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  void _open() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailsScreen(item: widget.item)));
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.item.posterUrl;
    return AnimatedScale(
      scale: _focused ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          autofocus: widget.autofocus,
          onFocusChange: (v) => setState(() => _focused = v),
          onTap: _open,
          borderRadius: BorderRadius.circular(12),
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
                children: [
                  url.isEmpty
                      ? Container(
                          color: kSurface,
                          child: const Icon(Icons.movie,
                              color: Colors.white24, size: 40))
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          loadingBuilder: (c, w, p) => p == null
                              ? w
                              : Container(
                                  color: kSurface,
                                  child: const Center(
                                      child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))),
                                ),
                          errorBuilder: (_, __, ___) => Container(
                              color: kSurface,
                              child: const Icon(Icons.broken_image,
                                  color: Colors.white24)),
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('★ ${widget.item.rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                              fontSize: 10, color: kGold)),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Text(
                        widget.item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
  Future<List<MediaItem>>? _f;

  @override
  void dispose() {
    _ctl.dispose();
    _deb?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final t = v.trim();
      setState(() {
        _q = t;
        _f = t.isEmpty
            ? Future.value(<MediaItem>[])
            : TmdbService.search(t, _isTv);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Buscar titulo...',
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _isTv = !_isTv;
                _f = _q.isEmpty ? null : TmdbService.search(_q, _isTv);
              });
            },
            child: Text(_isTv ? 'SERIES' : 'FILMES',
                style: const TextStyle(
                    color: kGold, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _f == null
          ? const Center(
              child: Text('Digite algo para buscar.',
                  style: TextStyle(color: Colors.white54)))
          : PosterGrid(future: _f!),
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
  bool _busy = false;
  String _status = '';
  int _server = -1;
  int _season = 1;
  int _episode = 1;
  List<Map<String, dynamic>> _seasons = [];
  List<Map<String, dynamic>> _episodes = [];

  bool get _isTv => widget.item.isTv;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await TmdbService.details(widget.item.id, _isTv);
      final seasons = <Map<String, dynamic>>[];
      if (_isTv) {
        for (final s in (d['seasons'] as List?) ?? const []) {
          final m = s as Map<String, dynamic>;
          seasons.add({
            'n': (m['season_number'] ?? 1) as int,
            'name': (m['name'] ?? 'Temporada').toString(),
          });
        }
        seasons.sort((a, b) => (a['n'] as int).compareTo(b['n'] as int));
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
    try {
      final d = await TmdbService.season(widget.item.id, _season);
      final eps = <Map<String, dynamic>>[];
      for (final e in (d['episodes'] as List?) ?? const []) {
        final m = e as Map<String, dynamic>;
        eps.add({
          'n': (m['episode_number'] ?? 1) as int,
          'name': (m['name'] ?? '').toString(),
        });
      }
      if (mounted) setState(() => _episodes = eps);
    } catch (_) {
      if (mounted) setState(() => _episodes = []);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _play() async {
    setState(() {
      _busy = true;
      _status = 'Procurando servidor...';
    });

    final list = _server == -1 ? kProviders : [kProviders[_server]];
    PlayTarget? direct;
    PlayTarget? page;

    for (final p in list) {
      if (!mounted) break;
      setState(() => _status = 'Testando ${p.name}...');
      final t = await Resolver.resolve(
          p, _isTv, widget.item.id, _season, _episode);
      if (t == null) continue;
      if (t.direct) {
        direct = t;
        break;
      }
      page ??= t;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '';
    });

    final target = direct ?? page;
    if (target == null) {
      _snack('Nenhum resolvedor respondeu. Tente novamente.');
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => target.direct
          ? VideoPlayerScreen(
              url: target.url,
              title: widget.item.title,
              provider: target.provider,
              referer: target.referer,
            )
          : WebScreen(url: target.url, title: widget.item.title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final d = _d;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                backgroundColor: kBg,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(item.title,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 15)),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      item.backdropUrl.isEmpty
                          ? Container(color: kSurface)
                          : Image.network(item.backdropUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: kSurface)),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, kBg],
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
                  child: _loading
                      ? const Center(
                          child: Padding(
                              padding: EdgeInsets.all(30),
                              child: CircularProgressIndicator()))
                      : _err != null
                          ? Column(
                              children: [
                                Text(_err!,
                                    style: const TextStyle(color: kGold),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton(
                                    onPressed: () {
                                      setState(() {
                                        _loading = true;
                                        _err = null;
                                      });
                                      _load();
                                    },
                                    child: const Text('Tentar novamente')),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (item.year.isNotEmpty)
                                      _chip(item.year),
                                    _chip('★ ${item.rating.toStringAsFixed(1)}'),
                                    _chip(_isTv ? 'SERIE' : 'FILME'),
                                    if (d != null && d['runtime'] != null)
                                      _chip('${d['runtime']} min'),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: _busy ? null : _play,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: kAccent,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                        ),
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('ASSISTIR',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Text('Servidor:',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _serverChip(-1, 'AUTO'),
                                    for (int i = 0; i < kProviders.length; i++)
                                      _serverChip(i, kProviders[i].name),
                                  ],
                                ),
                                if (_isTv) ...[
                                  const SizedBox(height: 16),
                                  const Text('Temporada',
                                      style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12)),
                                  const SizedBox(height: 6),
                                  DropdownButton<int>(
                                    value: _season,
                                    dropdownColor: kSurface,
                                    isExpanded: true,
                                    items: _seasons
                                        .map((s) => DropdownMenuItem<int>(
                                              value: s['n'] as int,
                                              child: Text(
                                                  '${s['name']} (T${s['n']})',
                                                  style: const TextStyle(
                                                      fontSize: 13)),
                                            ))
                                        .toList(),
                                    onChanged: (v) async {
                                      if (v == null) return;
                                      setState(() {
                                        _season = v;
                                        _episode = 1;
                                        _episodes = [];
                                      });
                                      await _loadEpisodes();
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  const Text('Episodio',
                                      style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12)),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 44,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _episodes.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (context, i) {
                                        final n =
                                            _episodes[i]['n'] as int;
                                        final sel = n == _episode;
                                        return ChoiceChip(
                                          selected: sel,
                                          label: Text('E$n'),
                                          selectedColor: kGold,
                                          onSelected: (_) =>
                                              setState(() => _episode = n),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                Text(
                                  (d?['overview'] ?? item.overview)
                                          .toString()
                                          .trim()
                                          .isEmpty
                                      ? 'Sem sinopse disponivel.'
                                      : (d?['overview'] ?? item.overview)
                                          .toString(),
                                  style: const TextStyle(
                                      color: Colors.white70, height: 1.5),
                                ),
                                const SizedBox(height: 40),
                              ],
                            ),
                ),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_status),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: kSurface, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(fontSize: 12)),
      );

  Widget _serverChip(int i, String label) {
    final sel = _server == i;
    return ChoiceChip(
      selected: sel,
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selectedColor: kGold,
      onSelected: (_) => setState(() => _server = i),
    );
  }
}

// =========================== PLAYER VIDEO ============================
class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String provider;
  final String referer;
  const VideoPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.provider = '',
    this.referer = '',
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _c;
  bool _ready = false;
  String? _err;
  bool _ui = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _start();
  }

  Future<void> _start() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: {
          'User-Agent': kUserAgent,
          if (widget.referer.isNotEmpty) 'Referer': widget.referer,
        },
      );
      await c.initialize();
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
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
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
    _hide?.cancel();
    _c?.removeListener(_tick);
    _c?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, ev) {
          if (ev is KeyDownEvent) _toggleUi();
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: _toggleUi,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              if (_err != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: kGold, size: 48),
                        const SizedBox(height: 12),
                        const Text('Falha ao abrir o stream direto.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 6),
                        Text(_err!,
                            maxLines: 3,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white54)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => WebScreen(
                                      url: widget.url,
                                      title: widget.title))),
                          icon: const Icon(Icons.language),
                          label: const Text('Abrir na WebView'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (!_ready)
                const Center(child: CircularProgressIndicator())
              else if (c != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
                ),
              AnimatedOpacity(
                opacity: _ui ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_ui,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black87,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black87,
                        ],
                        stops: [0, 0.25, 0.7, 1],
                      ),
                    ),
                    child: Column(
                      children: [
                        SafeArea(
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              Expanded(
                                child: Text(widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (widget.provider.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 12),
                                  child: Text(widget.provider,
                                      style: const TextStyle(
                                          fontSize: 11, color: kGold)),
                                ),
                              IconButton(
                                tooltip: 'WebView',
                                icon: const Icon(Icons.language),
                                onPressed: () =>
                                    Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => WebScreen(
                                          url: widget.url,
                                          title: widget.title)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (c != null && c.value.isInitialized)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 34,
                                icon: const Icon(Icons.replay_10),
                                onPressed: () {
                                  final p = c.value.position -
                                      const Duration(seconds: 10);
                                  c.seekTo(p < Duration.zero
                                      ? Duration.zero
                                      : p);
                                  _scheduleHide();
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                iconSize: 56,
                                icon: Icon(c.value.isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled),
                                onPressed: () {
                                  c.value.isPlaying ? c.pause() : c.play();
                                  _scheduleHide();
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                iconSize: 34,
                                icon: const Icon(Icons.forward_10),
                                onPressed: () {
                                  c.seekTo(c.value.position +
                                      const Duration(seconds: 10));
                                  _scheduleHide();
                                },
                              ),
                            ],
                          ),
                        const Spacer(),
                        if (c != null && c.value.isInitialized)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Row(
                              children: [
                                Text(_fmt(c.value.position),
                                    style: const TextStyle(fontSize: 12)),
                                Expanded(
                                  child: Slider(
                                    value: c.value.position.inMilliseconds
                                        .toDouble()
                                        .clamp(
                                            0,
                                            c.value.duration.inMilliseconds
                                                .toDouble()),
                                    max: c.value.duration.inMilliseconds
                                        .toDouble()
                                        .clamp(1, double.infinity),
                                    activeColor: kGold,
                                    onChanged: (v) {
                                      c.seekTo(Duration(
                                          milliseconds: v.toInt()));
                                      _scheduleHide();
                                    },
                                  ),
                                ),
                                Text(_fmt(c.value.duration),
                                    style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================= WEBVIEW ===============================
const List<String> kAdHosts = [
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
    final ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageStarted: (_) => _inject(),
        onPageFinished: (_) => _inject(),
        onNavigationRequest: (req) {
          final url = req.url;
          if (url.startsWith('about:') ||
              url.startsWith('data:') ||
              url.startsWith('blob:')) {
            return NavigationDecision.navigate;
          }
          if (!url.startsWith('http')) {
            return NavigationDecision.navigate;
          }
          final host = Uri.tryParse(url)?.host ?? '';
          for (final ad in kAdHosts) {
            if (host.contains(ad)) return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
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
    final ctl = _ctl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (ctl != null)
            WebViewWidget(controller: ctl)
          else
            const Center(child: CircularProgressIndicator()),
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
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      tooltip: 'Tela cheia',
                      icon: Icon(_ui ? Icons.fullscreen : Icons.fullscreen_exit),
                      onPressed: () {
                        setState(() => _ui = false);
                      },
                    ),
                  ],
                ),
              ),
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
}
@@@END@@@

@@@PS@@@
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Write-Host '  -> Gerando identidade visual (TMC)...'
New-Item -ItemType Directory -Force -Path 'assets\icon' | Out-Null
New-Item -ItemType Directory -Force -Path 'android\app\src\main\res\drawable' | Out-Null

function New-TmcImage {
    param(
        [string]$Path,
        [int]$W,
        [int]$H,
        [bool]$Transparent = $false,
        [string]$Label = 'TMC',
        [double]$Scale = 0.26,
        [bool]$Accent = $true
    )
    $bmp = [System.Drawing.Bitmap]::new($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    if (-not $Transparent) {
        $rect = [System.Drawing.RectangleF]::new(0, 0, [float]$W, [float]$H)
        $c1 = [System.Drawing.Color]::FromArgb(255, 8, 12, 22)
        $c2 = [System.Drawing.Color]::FromArgb(255, 30, 74, 170)
        $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $c1, $c2, 45.0)
        $g.FillRectangle($brush, $rect)
        $brush.Dispose()
        $glow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(34, 245, 196, 81))
        $g.FillEllipse($glow, [float]($W * 0.58), [float](-$H * 0.18), [float]($W * 0.70), [float]($W * 0.70))
        $glow.Dispose()
        $glow2 = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(28, 61, 123, 255))
        $g.FillEllipse($glow2, [float](-$W * 0.20), [float]($H * 0.60), [float]($W * 0.70), [float]($W * 0.70))
        $glow2.Dispose()
    } else {
        $g.Clear([System.Drawing.Color]::Transparent)
    }

    $base = [Math]::Min($W, $H)
    $size = [float]($base * $Scale)
    $font = [System.Drawing.Font]::new('Arial', $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = [System.Drawing.StringFormat]::new()
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $fmt.FormatFlags = [System.Drawing.StringFormatFlags]::NoClip

    $full = [System.Drawing.RectangleF]::new(0, 0, [float]$W, [float]$H)
    $shRect = [System.Drawing.RectangleF]::new([float]($base * 0.010), [float]($base * 0.014), [float]$W, [float]$H)
    $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(135, 0, 0, 0))
    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $gold = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 245, 196, 81))

    $g.DrawString($Label, $font, $shadow, $shRect, $fmt)
    $g.DrawString($Label, $font, $white, $full, $fmt)

    if ($Accent) {
        $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 245, 196, 81), [float]($base * 0.016))
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $y = [float]($H * 0.5 + $size * 0.60)
        $g.DrawLine($pen, [float]($W * 0.5 - $base * 0.15), $y, [float]($W * 0.5 + $base * 0.15), $y)
        $pen.Dispose()
    }

    $g.Dispose()
    $font.Dispose(); $fmt.Dispose(); $shadow.Dispose(); $white.Dispose(); $gold.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

New-TmcImage -Path 'assets\icon\icon.png' -W 1024 -H 1024 -Transparent $false -Label 'TMC' -Scale 0.26
New-TmcImage -Path 'assets\icon\icon_fg.png' -W 1024 -H 1024 -Transparent $true -Label 'TMC' -Scale 0.24
New-TmcImage -Path 'android\app\src\main\res\drawable\tv_banner.png' -W 320 -H 180 -Transparent $false -Label 'TMC' -Scale 0.30

# ---------------- pubspec: config do launcher icons ----------------
$pubPath = 'pubspec.yaml'
$pub = [System.IO.File]::ReadAllText($pubPath)
if ($pub -notmatch 'flutter_launcher_icons:') {
    $block = "`r`n" + @"
flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  image_path: "assets/icon/icon.png"
  min_sdk_android: 21
  remove_alpha_ios: true
  adaptive_icon_background: "#0A0E18"
  adaptive_icon_foreground: "assets/icon/icon_fg.png"
"@
    [System.IO.File]::WriteAllText($pubPath, $pub + $block)
}

# ---------------- AndroidManifest: nome, permissoes e Android TV ----------------
$manPath = 'android\app\src\main\AndroidManifest.xml'
$man = [System.IO.File]::ReadAllText($manPath)

if ($man -notmatch 'android.permission.INTERNET') {
    $perm = '<uses-permission android:name="android.permission.INTERNET" />'
    $man = [regex]::Replace($man, '(<manifest[^>]*>)', ('$1' + "`r`n    " + $perm), 1)
}

$man = [regex]::Replace($man, 'android:label="[^"]*"', 'android:label="TMC"', 1)

if ($man -notmatch 'leanback') {
    $man = [regex]::Replace($man, '<application', '<application android:banner="@drawable/tv_banner" android:usesCleartextTraffic="true"', 1)
    $feats = "`r`n    " + '<uses-feature android:name="android.software.leanback" android:required="false" />' + "`r`n    " + '<uses-feature android:name="android.hardware.touchscreen" android:required="false" />'
    $man = [regex]::Replace($man, '(<manifest[^>]*>)', ('$1' + $feats), 1)
    $man = [regex]::Replace($man, '(<category android:name="android.intent.category.LAUNCHER"\s*/>)', ('$1' + "`r`n            " + '<category android:name="android.intent.category.LEANBACK_LAUNCHER" />'), 1)
}

[System.IO.File]::WriteAllText($manPath, $man)

Write-Host '  -> Icone, nome "TMC", Internet e suporte Android TV configurados.'
@@@ENDPS@@@