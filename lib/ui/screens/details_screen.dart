import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/device/tv_detector.dart';
import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_ref.dart';
import '../../data/models/resolved_stream.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/progress_service.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/embedded_trailer.dart';
import 'player_screen.dart';

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
  bool _busy = false;
  String _status = '';

  int _season = 1;
  int _episode = 1;
  String _imdb = '';
  String? _trailerKey;
  bool _trailerOpen = false;
  Duration _resume = Duration.zero;

  @override
  void initState() {
    super.initState();
    _fav = LibraryRepository.instance.isFavorite(widget.item.key);
    _refreshResume();
    _load();
  }

  MediaRef get _ref => MediaRef(
    tmdbId: widget.item.id,
    isTv: widget.item.isTv,
    title: widget.item.title,
    season: _season,
    episode: _episode,
    year: widget.item.year,
    imdbId: _imdb,
    poster: widget.item.poster,
  );

  void _refreshResume() {
    _resume = LibraryRepository.instance.positionOf(_ref.key);
  }

  Future<void> _load() async {
    final Map<String, dynamic>? details = widget.item.isTv
        ? await widget.repository.tvDetails(widget.item.id)
        : await widget.repository.movieDetails(widget.item.id);

    final List<Map<String, dynamic>> similar = await widget.repository.similar(
      widget.item.id,
      widget.item.isTv,
    );

    if (!mounted) return;
    setState(() {
      _details = details;
      _similar = similar;
      _imdb = (details?['external_ids']?['imdb_id'] ?? '').toString();
      _trailerKey = _pickTrailer(details);
      _loading = false;
    });

    widget.resolver.prefetch(_ref);
  }

  String? _pickTrailer(Map<String, dynamic>? details) {
    final dynamic videosNode = details?['videos'];
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
            (language == 'pt' ? 3 : 0) +
            (language == 'en' ? 1 : 0);
      }
      return score(b).compareTo(score(a));
    });
    return candidates.first['key']?.toString();
  }

  Future<void> _play() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Procurando fonte...';
    });

    final StreamSubscription<ResolverStatus> sub =
        widget.resolver.status.listen((ResolverStatus s) {
      if (mounted) setState(() => _status = s.message);
    });

    ResolvedStream? stream;
    try {
      stream = await widget.resolver
          .resolveDirect(_ref)
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      stream = null;
    }

    await sub.cancel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '';
    });

    if (stream == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma API respondeu. Tente novamente.')),
      );
      return;
    }

    await LibraryRepository.instance.addHistory(_ref, _resume, Duration.zero);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          stream: stream!,
          ref: _ref,
          resolver: widget.resolver,
        ),
      ),
    );
    if (mounted) setState(_refreshResume);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final String backdrop =
        (_details?['backdrop_path'] ?? widget.item.backdrop).toString();
    final String overview =
        (_details?['overview'] ?? widget.item.overview).toString().trim();
    final String date = (_details?['release_date'] ??
            _details?['first_air_date'] ??
            widget.item.date)
        .toString();
    final double rating =
        ((_details?['vote_average'] ?? widget.item.rating) as num).toDouble();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              expandedHeight: TvDetector.isTv ? 330 : 250,
              pinned: true,
              backgroundColor: AppTheme.bg,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (backdrop.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: '${AppConfig.tmdbImageBase}/w1280$backdrop',
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(color: AppTheme.surface),
                      )
                    else
                      Container(color: AppTheme.surface),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Colors.transparent, AppTheme.bg],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        if (date.length >= 4)
                          Text(date.substring(0, 4),
                              style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 12),
                        const Icon(Icons.star_rounded, color: AppTheme.gold, size: 16),
                        const SizedBox(width: 4),
                        Text(rating.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 12),
                        if (widget.item.isTv)
                          Text('T$_season E$_episode',
                              style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_busy) ...<Widget>[
                      Row(
                        children: <Widget>[
                          const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _status.isEmpty ? 'Procurando fonte...' : _status,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        TvButton(
                          label: _resume.inSeconds > 5
                              ? ProgressService.resumeLabel(_resume)
                              : 'ASSISTIR',
                          icon: Icons.play_arrow_rounded,
                          primary: true,
                          autofocus: true,
                          onPressed: () => unawaited(_play()),
                        ),
                        if (_trailerKey != null)
                          TvButton(
                            label: _trailerOpen ? 'FECHAR TRAILER' : 'TRAILER',
                            icon: _trailerOpen ? Icons.close_rounded : Icons.movie_outlined,
                            onPressed: () => setState(() => _trailerOpen = !_trailerOpen),
                          ),
                        TvButton(
                          label: _fav ? 'NA LISTA' : 'MINHA LISTA',
                          icon: _fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          onPressed: () async {
                            await LibraryRepository.instance.toggleFavorite(widget.item);
                            if (!mounted) return;
                            setState(() =>
                                _fav = LibraryRepository.instance.isFavorite(widget.item.key));
                          },
                        ),
                      ],
                    ),
                    if (_trailerOpen && _trailerKey != null) ...<Widget>[
                      const SizedBox(height: 16),
                      EmbeddedTrailer(
                        videoKey: _trailerKey!,
                        title: widget.item.title,
                        autoPlay: true,
                        onClose: () => setState(() => _trailerOpen = false),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      overview.isEmpty ? 'Sem sinopse disponivel.' : overview,
                      style: const TextStyle(color: Colors.white60, height: 1.5, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            if (widget.item.isTv) SliverToBoxAdapter(child: _seasonsSection()),
            if (_similar.isNotEmpty) SliverToBoxAdapter(child: _similarSection()),
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
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'TEMPORADAS',
            style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2),
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
                    _refreshResume();
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'EPISODIOS',
            style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2),
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
            setState(() {
              _episode = n;
              _refreshResume();
            });
            unawaited(_play());
          },
        );
      },
    );
  }

  Widget _similarSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: SizedBox(
        height: TvDetector.isTv ? 250 : 205,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: _similar.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (BuildContext ctx, int i) {
            final Map<String, dynamic> m = _similar[i];
            final String poster = (m['poster_path'] ?? '').toString();
            return SizedBox(
              width: 126,
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
                  borderRadius: AppTheme.br,
                  child: poster.isEmpty
                      ? Container(color: AppTheme.surface)
                      : CachedNetworkImage(
                          imageUrl: '${AppConfig.tmdbImageBase}/w342$poster',
                          fit: BoxFit.cover,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}