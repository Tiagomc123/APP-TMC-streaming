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
const Color kGoldSoft = Color(0x26F5C451);

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
    final ThemeData base = ThemeData.dark(useMaterial3: true);
    // Nao usamos GoogleFonts.poppinsTextTheme() aqui para evitar conflito
    // de tipos: pegamos apenas o fontFamily e aplicamos no TextTheme do tema.
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
    final String? d = date;
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
    final Map<String, String> params = <String, String>{
      'api_key': tmdbApiKey,
      'language': 'pt-BR',
    };
    if (q != null) params.addAll(q);
    final Uri uri =
        Uri.parse('$kTmdbBase$path').replace(queryParameters: params);
    final http.Response res =
        await http.get(uri).timeout(const Duration(seconds: 18));
    if (res.statusCode == 401) {
      throw TmdbException('Chave do TMDB invalida (401). Confira a tmdbApiKey.');
    }
    if (res.statusCode != 200) {
      throw TmdbException('Erro do TMDB: HTTP ${res.statusCode}');
    }
    return json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<List<MediaItem>> _list(String path, bool isTv,
      [Map<String, String>? q]) async {
    final Map<String, dynamic> data = await _get(path, q);
    final List<dynamic> results = (data['results'] as List<dynamic>?) ?? const [];
    return results
        .map((dynamic e) => MediaItem.fromJson(e as Map<String, dynamic>, isTv))
        .toList();
  }

  static Future<List<MediaItem>> popularMovies() =>
      _list('/movie/popular', false);

  static Future<List<MediaItem>> popularTv() => _list('/tv/popular', true);

  static Future<List<MediaItem>> trending() => _list('/trending/all/week', false);

  static Future<List<MediaItem>> search(String query, bool isTv) => _list(
        isTv ? '/search/tv' : '/search/movie',
        isTv,
        <String, String>{'query': query, 'include_adult': 'false'},
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

  static Future<http.Response?> _fetch(String url, String referer) async {
    try {
      final Map<String, String> headers = <String, String>{
        'User-Agent': kUserAgent,
      };
      if (referer.isNotEmpty) headers['Referer'] = referer;
      return await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  static Future<PlayTarget?> resolve(
      Provider p, bool isTv, int id, int season, int episode) async {
    final String pageUrl = p.build(isTv, id, season, episode);
    final http.Response? res = await _fetch(pageUrl, pageUrl);
    final String body = res?.body ?? '';

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

      final http.Response? r2 = await _fetch(src, pageUrl);
      final Match? m2 = _m3u8.firstMatch(r2?.body ?? '');
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
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFF1E4AAA), kAccent],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text(
                    'MC',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'TMC',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Buscar',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                );
              },
              icon: const Icon(Icons.search),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: kGold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: <Widget>[Tab(text: 'FILMES'), Tab(text: 'SERIES')],
          ),
        ),
        body: Column(
          children: <Widget>[
            if (tmdbApiKey == 'SUA_CHAVE_AQUI')
              Container(
                width: double.infinity,
                color: kGoldSoft,
                padding: const EdgeInsets.all(10),
                child: const Text(
                  'Cole a sua chave do TMDB na variavel tmdbApiKey no topo do lib/main.dart',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kGold, fontSize: 12),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
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

  const PosterGrid({
    super.key,
    required this.future,
    this.emptyMsg = 'Nada encontrado.',
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaItem>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<MediaItem>> snap) {
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
        final List<MediaItem> items = snap.data ?? const <MediaItem>[];
        if (items.isEmpty) {
          return Center(
            child: Text(emptyMsg,
                style: const TextStyle(color: Colors.white70)),
          );
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final int cols = (c.maxWidth / 150).floor().clamp(2, 8).toInt();
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 0.55,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (BuildContext context, int i) {
                return PosterCard(item: items[i], autofocus: i == 0);
              },
            );
          },
        );
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
      MaterialPageRoute<void>(builder: (_) => DetailsScreen(item: widget.item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String url = widget.item.posterUrl;
    return AnimatedScale(
      scale: _focused ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          autofocus: widget.autofocus,
          onFocusChange: (bool v) => setState(() => _focused = v),
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
                children: <Widget>[
                  _posterImage(url),
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
                      child: Text(
                        '★ ${widget.item.rating.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 10, color: kGold),
                      ),
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
                          colors: <Color>[Colors.black87, Colors.transparent],
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

  Widget _posterImage(String url) {
    if (url.isEmpty) {
      return Container(
        color: kSurface,
        child: const Icon(Icons.movie, color: Colors.white24, size: 40),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder:
          (BuildContext c, Widget w, ImageChunkEvent? p) {
        if (p == null) return w;
        return Container(
          color: kSurface,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (BuildContext c, Object e, StackTrace? s) {
        return Container(
          color: kSurface,
          child: const Icon(Icons.broken_image, color: Colors.white24),
        );
      },
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
      final String t = v.trim();
      setState(() {
        _q = t;
        _f = t.isEmpty
            ? Future<List<MediaItem>>.value(<MediaItem>[])
            : TmdbService.search(t, _isTv);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final Future<List<MediaItem>>? f = _f;
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
        actions: <Widget>[
          TextButton(
            onPressed: () {
              setState(() {
                _isTv = !_isTv;
                if (_q.isNotEmpty) _f = TmdbService.search(_q, _isTv);
              });
            },
            child: Text(
              _isTv ? 'SERIES' : 'FILMES',
              style: const TextStyle(color: kGold, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: f == null
          ? const Center(
              child: Text('Digite algo para buscar.',
                  style: TextStyle(color: Colors.white54)),
            )
          : PosterGrid(future: f),
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
  List<Map<String, dynamic>> _seasons = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _episodes = <Map<String, dynamic>>[];

  bool get _isTv => widget.item.isTv;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> d =
          await TmdbService.details(widget.item.id, _isTv);
      final List<Map<String, dynamic>> seasons = <Map<String, dynamic>>[];
      if (_isTv) {
        final List<dynamic> raw = (d['seasons'] as List<dynamic>?) ?? const [];
        for (final dynamic s in raw) {
          final Map<String, dynamic> m = s as Map<String, dynamic>;
          seasons.add(<String, dynamic>{
            'n': (m['season_number'] ?? 1) as int,
            'name': (m['name'] ?? 'Temporada').toString(),
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
      final Map<String, dynamic> d =
          await TmdbService.season(widget.item.id, _season);
      final List<Map<String, dynamic>> eps = <Map<String, dynamic>>[];
      final List<dynamic> raw = (d['episodes'] as List<dynamic>?) ?? const [];
      for (final dynamic e in raw) {
        final Map<String, dynamic> m = e as Map<String, dynamic>;
        eps.add(<String, dynamic>{
          'n': (m['episode_number'] ?? 1) as int,
          'name': (m['name'] ?? '').toString(),
        });
      }
      if (mounted) setState(() => _episodes = eps);
    } catch (_) {
      if (mounted) setState(() => _episodes = <Map<String, dynamic>>[]);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _play() async {
    setState(() {
      _busy = true;
      _status = 'Procurando servidor...';
    });

    final List<Provider> list =
        _server == -1 ? kProviders : <Provider>[kProviders[_server]];
    PlayTarget? direct;
    PlayTarget? page;

    for (final Provider p in list) {
      if (!mounted) break;
      setState(() => _status = 'Testando ${p.name}...');
      final PlayTarget? t =
          await Resolver.resolve(p, _isTv, widget.item.id, _season, _episode);
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

    final PlayTarget? target = direct ?? page;
    if (target == null) {
      _snack('Nenhum resolvedor respondeu. Tente novamente.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) {
          if (target.direct) {
            return VideoPlayerScreen(
              url: target.url,
              title: widget.item.title,
              provider: target.provider,
              referer: target.referer,
            );
          }
          return WebScreen(url: target.url, title: widget.item.title);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MediaItem item = widget.item;
    final Map<String, dynamic>? d = _d;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                backgroundColor: kBg,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(item.title,
                      maxLines: 2, style: const TextStyle(fontSize: 15)),
                  background: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (item.backdropUrl.isEmpty)
                        Container(color: kSurface)
                      else
                        Image.network(
                          item.backdropUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (BuildContext c, Object e,
                              StackTrace? s) {
                            return Container(color: kSurface);
                          },
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[Colors.transparent, kBg],
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
                  child: _buildBody(d),
                ),
              ),
            ],
          ),
          if (_busy) _buildBusy(),
        ],
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic>? d) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_err != null) {
      return Column(
        children: <Widget>[
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
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }
    return _buildInfo(d);
  }

  Widget _buildInfo(Map<String, dynamic>? d) {
    final MediaItem item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (item.year.isNotEmpty) _chip(item.year),
            _chip('★ ${item.rating.toStringAsFixed(1)}'),
            _chip(_isTv ? 'SERIE' : 'FILME'),
            if (d != null && d['runtime'] != null) _chip('${d['runtime']} min'),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _play,
          style: FilledButton.styleFrom(
            backgroundColor: kAccent,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text(
            'ASSISTIR',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ),
        const SizedBox(height: 10),
        const Text('Servidor:',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: <Widget>[
            _serverChip(-1, 'AUTO'),
            for (int i = 0; i < kProviders.length; i++)
              _serverChip(i, kProviders[i].name),
          ],
        ),
        if (_isTv) _buildTvPicker(),
        const SizedBox(height: 20),
        Text(
          (d?['overview'] ?? item.overview).toString().trim().isEmpty
              ? 'Sem sinopse disponivel.'
              : (d?['overview'] ?? item.overview).toString(),
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildTvPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 16),
        const Text('Temporada',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButton<int>(
          value: _season,
          dropdownColor: kSurface,
          isExpanded: true,
          items: _seasons.map((Map<String, dynamic> s) {
            final int n = s['n'] as int;
            return DropdownMenuItem<int>(
              value: n,
              child: Text('${s['name']} (T$n)',
                  style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: (int? v) async {
            if (v == null) return;
            setState(() {
              _season = v;
              _episode = 1;
              _episodes = <Map<String, dynamic>>[];
            });
            await _loadEpisodes();
          },
        ),
        const SizedBox(height: 12),
        const Text('Episodio',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _episodes.length,
            separatorBuilder: (BuildContext c, int i) =>
                const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int i) {
              final int n = _episodes[i]['n'] as int;
              return ChoiceChip(
                selected: n == _episode,
                label: Text('E$n'),
                selectedColor: kGold,
                onSelected: (bool _) => setState(() => _episode = n),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBusy() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(t, style: const TextStyle(fontSize: 12)),
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
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  String _fmt(Duration d) {
    final String m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
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
          Text(
            _err ?? '',
            maxLines: 3,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
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
          if (widget.provider.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(widget.provider,
                  style: const TextStyle(fontSize: 11, color: kGold)),
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
        const SizedBox(width: 8),
        IconButton(
          iconSize: 56,
          icon: Icon(c.value.isPlaying
              ? Icons.pause_circle_filled
              : Icons.play_circle_filled),
          onPressed: () {
            if (c.value.isPlaying) {
              c.pause();
            } else {
              c.play();
            }
            _scheduleHide();
          },
        ),
        const SizedBox(width: 8),
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
          Text(_fmt(c.value.position), style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: pos,
              max: max,
              activeColor: kGold,
              onChanged: (double v) {
                c.seekTo(Duration(milliseconds: v.toInt()));
                _scheduleHide();
              },
            ),
          ),
          Text(_fmt(c.value.duration), style: const TextStyle(fontSize: 12)),
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