import 'package:flutter/material.dart';

import '../../core/focus/dpad.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../screens/details_screen.dart';
import 'poster_card.dart';

typedef CatalogLoader = Future<TmdbPage> Function({required int page});

/// Grade paginada com carregamento infinito e cabecalho rolavel opcional
/// (banner). Sem nenhuma barra de filtro exposta.
class CatalogGrid extends StatefulWidget {
  const CatalogGrid({
    super.key,
    required this.loader,
    required this.resolver,
    required this.repository,
    this.progressOf,
    this.header,
    this.autofocusFirst = true,
  });

  final CatalogLoader loader;
  final VideoResolverService resolver;
  final TmdbRepository repository;
  final double Function(MediaItem item)? progressOf;
  final Widget? header;
  final bool autofocusFirst;

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
    final Widget? header = widget.header;

    if (_loadingInitial) {
      return CustomScrollView(
        controller: _scrollController,
        slivers: <Widget>[
          if (header != null) SliverToBoxAdapter(child: header),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return CustomScrollView(
        controller: _scrollController,
        slivers: <Widget>[
          if (header != null) SliverToBoxAdapter(child: header),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.filter_alt_off_rounded, size: 44, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text(
                    _initialLoadFailed
                        ? 'Falha ao carregar.'
                        : 'Nada encontrado com esses filtros.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TvButton(
                    label: 'TENTAR DE NOVO',
                    icon: Icons.refresh,
                    onPressed: _loadFirstPage,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: <Widget>[
        if (header != null) SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 70),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              childAspectRatio: 0.58,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext ctx, int i) => PosterCard(
                item: _items[i],
                autofocus: i == 0 && widget.autofocusFirst,
                progress: widget.progressOf?.call(_items[i]),
                onTap: () => _open(_items[i]),
              ),
              childCount: _items.length,
            ),
          ),
        ),
        if (_loadingMore || _loadMoreFailed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 70),
              child: _loadMoreFailed
                  ? Center(
                      child: TextButton.icon(
                        onPressed: _loadNextPage,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar carregar mais'),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}