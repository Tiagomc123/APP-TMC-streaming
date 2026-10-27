import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/poster_card.dart';
import 'details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.repository,
    required this.resolver,
  });

  final TmdbRepository repository;
  final VideoResolverService resolver;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _ctl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  bool _isTv = false;
  String _query = '';
  bool _busy = false;
  bool _loadingMore = false;
  bool _loadFailed = false;
  bool _loadMoreFailed = false;
  int _page = 0;
  int _totalPages = 1;
  int _requestId = 0;
  List<MediaItem> _items = <MediaItem>[];

  @override
  void dispose() {
    _ctl.dispose();
    _debounce?.cancel();
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  void _onChanged(String v) {
    _requestId++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _run(v.trim()));
  }

  Future<void> _run(String q) async {
    if (!mounted) return;
    final int requestId = ++_requestId;
    final bool isTv = _isTv;
    setState(() {
      _query = q;
      _busy = q.isNotEmpty;
      _loadingMore = false;
      _loadFailed = false;
      _loadMoreFailed = false;
      _page = 0;
      _totalPages = 1;
      _items = <MediaItem>[];
    });

    if (q.isEmpty) return;

    try {
      final TmdbPage result = await widget.repository.search(q, isTv, page: 1);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _items = result.items;
        _page = result.page;
        _totalPages = result.totalPages;
        _busy = false;
        _loadFailed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _busy = false;
        _loadFailed = true;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _busy ||
        _loadingMore ||
        _loadMoreFailed ||
        _page >= _totalPages ||
        _query.isEmpty) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 640) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_busy || _loadingMore || _page >= _totalPages || _query.isEmpty) return;
    final int requestId = _requestId;
    final int nextPage = _page + 1;
    final String query = _query;
    final bool isTv = _isTv;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });

    try {
      final TmdbPage result = await widget.repository.search(
        query,
        isTv,
        page: nextPage,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        final Set<String> seen = _items
            .map((MediaItem item) => item.key)
            .toSet();
        _items = <MediaItem>[
          ..._items,
          ...result.items.where((MediaItem item) => seen.add(item.key)),
        ];
        _page = result.page;
        _totalPages = result.totalPages;
        _loadingMore = false;
        _loadMoreFailed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
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
              if (_query.isNotEmpty) _run(_query);
            },
            child: Text(
              _isTv ? 'SERIES' : 'FILMES',
              style: const TextStyle(
                color: AppTheme.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _query.isEmpty
          ? const Center(
              child: Text(
                'Digite algo para buscar.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _loadFailed
                        ? 'Falha ao buscar "$_query".'
                        : 'Nada encontrado para "$_query".',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  if (_loadFailed)
                    TextButton.icon(
                      onPressed: () => _run(_query),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                ],
              ),
            )
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 60),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                childAspectRatio: 0.54,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
              ),
              itemCount:
                  _items.length + (_loadingMore || _loadMoreFailed ? 1 : 0),
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DetailsScreen(
                        item: _items[i],
                        resolver: widget.resolver,
                        repository: widget.repository,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
