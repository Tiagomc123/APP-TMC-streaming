import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/device/tv_detector.dart';
import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_ref.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/embedded_trailer.dart';
import 'player_screen.dart';
import '../../data/models/resolved_stream.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({
    super.key,
    required this.item,
    required this.resolver,
    required this.repository,
  });

  final MediaItem item;
  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  Map<String, dynamic>? _details;
  List<Map<String, dynamic>> _similar = const <Map<String, dynamic>>[];
  bool _loading = true;
  bool _fav = false;

  int _season = 1;
  int _episode = 1;
  String? _trailerKey;
  bool _trailerOpen = false;

  @override
  void initState() {
    super.initState();
    _fav = LibraryRepository.instance.isFavorite(widget.item.key);
    _load();
  }

  MediaRef get _ref => MediaRef(
    tmdbId: widget.item.id,
    isTv: widget.item.isTv,
    title: widget.item.title,
    season: _season,
    episode: _episode,
    year: widget.item.year,
  );

  Future<void> _load() async {
    final Map<String, dynamic>? d = widget.item.isTv
        ? await widget.repository.tvDetails(widget.item.id)
        : await widget.repository.movieDetails(widget.item.id);

    final List<Map<String, dynamic>> sim = await widget.repository.similar(
      widget.item.id,
      widget.item.isTv,
    );

    if (!mounted) return;
    setState(() {
      _details = d;
      _similar = sim;
      _trailerKey = _pickTrailer(d);
      _loading = false;
    });

    // pre-aquece a resolucao enquanto o usuario le a sinopse
    widget.resolver.prefetch(_ref);
  }

  /// Seleciona somente trailers hospedados no YouTube e retornados pelo TMDB.
  String? _pickTrailer(Map<String, dynamic>? d) {
    final dynamic videosNode = d?['videos'];
    final List<dynamic> videos = videosNode is Map
        ? ((videosNode['results'] as List<dynamic>?) ?? const <dynamic>[])
        : const <dynamic>[];
    if (videos.isEmpty) return null;

    final List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[];
    for (final dynamic v in videos) {
      if (v is! Map) continue;
      final Map<String, dynamic> m = v.cast<String, dynamic>();
      if (m['site'] != 'YouTube') continue;
      if (m['type'] != 'Trailer') continue;

      final String key = (m['key'] ?? '').toString();
      if (key.isEmpty) continue;
      candidates.add(m);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      int score(Map<String, dynamic> value) {
        final String language = value['iso_639_1']?.toString() ?? '';
        return (value['official'] == true ? 4 : 0) +
            (language == 'pt' ? 2 : 0) +
            (language == 'en' ? 1 : 0);
      }
      return score(b).compareTo(score(a));
    });
    return candidates.first['key']?.toString();
  }

  Future<void> _play() async {
    final MediaRef ref = _ref;
    final ResolvedStream? resolved = await widget.resolver.resolve(ref);
    if (!mounted) return;

    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma fonte respondeu. Tente novamente.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlayerScreen(stream: resolved, ref: ref, resolver: widget.resolver),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final String backdrop = (_details?['backdrop_path'] ?? widget.item.backdrop)
        .toString();
    final String overview = (_details?['overview'] ?? widget.item.overview)
        .toString()
        .trim();
    final String date =
        (_details?['release_date'] ??
                _details?['first_air_date'] ??
                widget.item.date)
            .toString();
    final double rating =
        ((_details?['vote_average'] ?? widget.item.rating) as num).toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      body: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              expandedHeight: TvDetector.isTv ? 340 : 260,
              pinned: true,
              backgroundColor: Colors.black,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (backdrop.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: '${AppConfig.tmdbImageBase}/w1280$backdrop',
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            Container(color: AppTheme.surface),
                      )
                    else
                      Container(color: AppTheme.surface),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        if (date.length >= 4)
                          Text(
                            date.substring(0, 4),
                            style: const TextStyle(color: Colors.white54),
                          ),
                        const SizedBox(width: 12),
                        const Icon(Icons.star, color: AppTheme.gold, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(width: 12),
                        if (widget.item.isTv)
                          Text(
                            'T$_season E$_episode',
                            style: const TextStyle(color: Colors.white54),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        TvButton(
                          label: 'ASSISTIR',
                          icon: Icons.play_arrow,
                          primary: true,
                          autofocus: true,
                          onPressed: () => _play(),
                        ),
                        if (_trailerKey != null)
                          TvButton(
                            label: _trailerOpen ? 'FECHAR TRAILER' : 'TRAILER',
                            icon: _trailerOpen
                                ? Icons.close
                                : Icons.movie_outlined,
                            onPressed: () =>
                                setState(() => _trailerOpen = !_trailerOpen),
                          ),
                        TvButton(
                          label: _fav ? 'NA LISTA' : 'MINHA LISTA',
                          icon: _fav ? Icons.favorite : Icons.favorite_border,
                          onPressed: () async {
                            await LibraryRepository.instance.toggleFavorite(
                              widget.item,
                            );
                            if (!mounted) return;
                            setState(
                              () => _fav = LibraryRepository.instance
                                  .isFavorite(widget.item.key),
                            );
                          },
                        ),
                      ],
                    ),
                    if (_trailerOpen && _trailerKey != null) ...<Widget>[
                      const SizedBox(height: 18),
                      const Text(
                        'TRAILER OFICIAL',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      EmbeddedTrailer(
                        videoKey: _trailerKey!,
                        title: widget.item.title,
                        autoPlay: true,
                        onClose: () => setState(() => _trailerOpen = false),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      'SINOPSE',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      overview.isEmpty ? 'Sem sinopse disponivel.' : overview,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                ),
              ),
            ),
            if (widget.item.isTv) SliverToBoxAdapter(child: _seasonsSection()),
            if (_similar.isNotEmpty)
              SliverToBoxAdapter(child: _similarSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _seasonsSection() {
    final List<dynamic> seasons =
        ((_details?['seasons'] as List<dynamic>?) ?? const <dynamic>[])
            .where((dynamic s) => ((s['season_number'] ?? 0) as int) > 0)
            .toList();

    if (seasons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'TEMPORADAS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (BuildContext ctx, int i) {
                final int n = seasons[i]['season_number'] as int;
                return TvButton(
                  label: 'T$n',
                  primary: n == _season,
                  onPressed: () => setState(() {
                    _season = n;
                    _episode = 1;
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'EPISODIOS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          _episodesGrid(),
        ],
      ),
    );
  }

  Widget _episodesGrid() {
    final int count = (_details?['number_of_episodes'] as int?) ?? 12;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: TvDetector.isTv ? 8 : 5,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: count,
      itemBuilder: (BuildContext ctx, int i) {
        final int n = i + 1;
        return TvButton(
          label: '$n',
          primary: n == _episode,
          onPressed: () {
            setState(() => _episode = n);
            _play();
          },
        );
      },
    );
  }

  Widget _similarSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'SEMELHANTES',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: TvDetector.isTv ? 250 : 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _similar.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (BuildContext ctx, int i) {
                final Map<String, dynamic> m = _similar[i];
                final String poster = (m['poster_path'] ?? '').toString();
                return SizedBox(
                  width: 130,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DetailsScreen(
                          item: MediaItem.fromJson(m, widget.item.isTv),
                          resolver: widget.resolver,
                          repository: widget.repository,
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: poster.isEmpty
                          ? Container(color: AppTheme.surface)
                          : CachedNetworkImage(
                              imageUrl:
                                  '${AppConfig.tmdbImageBase}/w342$poster',
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
