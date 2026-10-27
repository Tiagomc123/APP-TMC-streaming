import 'package:flutter/material.dart';

import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../screens/details_screen.dart';
import 'poster_card.dart';

typedef CatalogLoader = Future<TmdbPage> Function({required int page});

/// Grade de catalogo paginada, com foco D-Pad e carregamento infinito.
class CatalogGrid extends StatefulWidget {
  const CatalogGrid({
    super.key,
    required this.loader,
    required this.resolver,
    required this.repository,
    this.progressOf,
  });

  final CatalogLoader loader;
  final VideoResolverService resolver;
  final TmdbRepository repository;
  final double Function(MediaItem item)? progressOf;

  @override
  State<CatalogGrid> createState() => _CatalogGridState();
}

class _CatalogGridState extends State<CatalogGrid> {
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
    if (!replace) {
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
        final List<MediaItem> next =
            replace ? <MediaItem>[] : List<MediaItem>.of(_items);
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
              _initialLoadFailed ? 'Falha ao carregar o catalogo.' : 'Nada carregado.',
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
        maxCrossAxisExtent: 172,
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
          progress: widget.progressOf?.call(_items[i]),
          onTap: () => _open(_items[i]),
        );
      },
    );
  }
}