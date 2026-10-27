import 'package:flutter/material.dart';

import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/poster_card.dart';
import 'details_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.resolver,
    required this.repository,
  });

  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.bg,
          title: const Text(
            'TMC',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Buscar',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SearchScreen(repository: repository, resolver: resolver),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.gold,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppTheme.gold,
            tabs: <Widget>[
              Tab(text: 'INICIO'),
              Tab(text: 'FILMES'),
              Tab(text: 'SERIES'),
              Tab(text: 'MINHA LISTA'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _CatalogGrid(
              loader: repository.trending,
              resolver: resolver,
              repository: repository,
            ),
            _CatalogGrid(
              loader: repository.popularMovies,
              resolver: resolver,
              repository: repository,
            ),
            _CatalogGrid(
              loader: repository.popularTv,
              resolver: resolver,
              repository: repository,
            ),
            _FavoritesGrid(resolver: resolver, repository: repository),
          ],
        ),
      ),
    );
  }
}

class _CatalogGrid extends StatefulWidget {
  const _CatalogGrid({
    required this.loader,
    required this.resolver,
    required this.repository,
  });

  final Future<TmdbPage> Function({required int page}) loader;
  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  State<_CatalogGrid> createState() => _CatalogGridState();
}

class _CatalogGridState extends State<_CatalogGrid> {
  final ScrollController _scrollController = ScrollController();
  List<MediaItem> _items = <MediaItem>[];
  int _page = 0;
  int _totalPages = 1;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _initialLoadFailed = false;
  bool _loadMoreFailed = false;

  bool get _hasMore => _page < _totalPages;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _loadPage(1, replace: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    if (_loadingInitial) return;
    setState(() {
      _loadingInitial = true;
      _loadingMore = false;
      _initialLoadFailed = false;
      _loadMoreFailed = false;
      _items = <MediaItem>[];
      _page = 0;
      _totalPages = 1;
    });
    await _loadPage(1, replace: true);
  }

  Future<void> _loadNextPage() async {
    if (_loadingInitial || _loadingMore || !_hasMore) return;
    await _loadPage(_page + 1);
  }

  Future<void> _loadPage(int page, {bool replace = false}) async {
    if (replace) {
      // The initial page already owns the loading state.
    } else {
      setState(() {
        _loadingMore = true;
        _loadMoreFailed = false;
      });
    }

    try {
      final TmdbPage result = await widget.loader(page: page);
      if (!mounted) return;

      setState(() {
        final Set<String> seen = replace
            ? <String>{}
            : _items.map((MediaItem item) => item.key).toSet();
        final List<MediaItem> next = replace
            ? <MediaItem>[]
            : List<MediaItem>.of(_items);
        for (final MediaItem item in result.items) {
          if (seen.add(item.key)) next.add(item);
        }
        _items = next;
        _page = result.page;
        _totalPages = result.totalPages;
        _loadingInitial = false;
        _loadingMore = false;
        _initialLoadFailed = false;
        _loadMoreFailed = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingInitial = false;
        _loadingMore = false;
        _initialLoadFailed = replace;
        _loadMoreFailed = !replace;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _loadingInitial ||
        _loadingMore ||
        _loadMoreFailed ||
        !_hasMore) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 640) {
      _loadNextPage();
    }
  }

  void _open(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailsScreen(
          item: item,
          resolver: widget.resolver,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 48, color: AppTheme.gold),
            const SizedBox(height: 12),
            Text(
              _initialLoadFailed
                  ? 'Falha ao carregar o catálogo.'
                  : 'Nada carregado.',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 12),
            TvButton(
              label: 'TENTAR DE NOVO',
              icon: Icons.refresh,
              onPressed: _loadFirstPage,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 60),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        childAspectRatio: 0.54,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
      ),
      itemCount: _items.length + (_loadingMore || _loadMoreFailed ? 1 : 0),
      itemBuilder: (BuildContext ctx, int i) {
        if (i == _items.length) {
          if (_loadMoreFailed) {
            return Center(
              child: TextButton.icon(
                onPressed: _loadNextPage,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar carregar mais'),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        return PosterCard(
          item: _items[i],
          autofocus: i == 0,
          onTap: () => _open(_items[i]),
        );
      },
    );
  }
}

class _FavoritesGrid extends StatefulWidget {
  const _FavoritesGrid({required this.resolver, required this.repository});

  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  State<_FavoritesGrid> createState() => _FavoritesGridState();
}

class _FavoritesGridState extends State<_FavoritesGrid> {
  @override
  void initState() {
    super.initState();
    LibraryRepository.instance.revision.addListener(_tick);
  }

  @override
  void dispose() {
    LibraryRepository.instance.revision.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<MediaItem> favs = LibraryRepository.instance.favorites;
    if (favs.isEmpty) {
      return const Center(
        child: Text(
          'Sua lista esta vazia.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 60),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        childAspectRatio: 0.54,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
      ),
      itemCount: favs.length,
      itemBuilder: (BuildContext ctx, int i) => PosterCard(
        item: favs[i],
        autofocus: i == 0,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DetailsScreen(
              item: favs[i],
              resolver: widget.resolver,
              repository: widget.repository,
            ),
          ),
        ),
      ),
    );
  }
}
