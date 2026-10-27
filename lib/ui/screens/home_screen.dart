import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/catalog_grid.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/favorites_grid.dart';
import '../widgets/hero_carousel.dart';
import 'catalog_screen.dart';
import 'details_screen.dart';
import 'history_screen.dart';
import 'search_screen.dart';
import 'tmc_app_screen.dart';

/// Shell principal. Abas: Inicio | Filmes | Series | TMC App.
/// O botao de filtro (canto inferior direito) so aparece nas abas de catalogo.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.resolver,
    required this.repository,
  });

  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _titles = <String>['Inicio', 'Filmes', 'Series', 'TMC App'];

  final GlobalKey<CatalogScreenState> _moviesKey = GlobalKey<CatalogScreenState>();
  final GlobalKey<CatalogScreenState> _seriesKey = GlobalKey<CatalogScreenState>();

  int _index = 0;

  void _goToTab(int index) {
    if (index < 0 || index > 3) return;
    setState(() => _index = index);
  }

  void _openFilters() {
    final GlobalKey<CatalogScreenState> key = _index == 1 ? _moviesKey : _seriesKey;
    key.currentState?.openFilters();
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchScreen(
          repository: widget.repository,
          resolver: widget.resolver,
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          resolver: widget.resolver,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showFilter = _index == 1 || _index == 2;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: <Widget>[
          IconButton(
            tooltip: 'Historico',
            icon: const Icon(Icons.history_rounded),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search_rounded),
            onPressed: _openSearch,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          _HomeFeed(resolver: widget.resolver, repository: widget.repository),
          CatalogScreen(
            key: _moviesKey,
            isTv: false,
            repository: widget.repository,
            resolver: widget.resolver,
          ),
          CatalogScreen(
            key: _seriesKey,
            isTv: true,
            repository: widget.repository,
            resolver: widget.resolver,
          ),
          TmcAppScreen(
            resolver: widget.resolver,
            repository: widget.repository,
            onGoToTab: _goToTab,
          ),
        ],
      ),
      floatingActionButton: showFilter
          ? FloatingActionButton.small(
              onPressed: _openFilters,
              backgroundColor: AppTheme.card,
              foregroundColor: Colors.white,
              elevation: 6,
              tooltip: 'Filtros',
              child: const Icon(Icons.tune_rounded, size: 20),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goToTab,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.movie_rounded), label: 'Filmes'),
          BottomNavigationBarItem(icon: Icon(Icons.tv_rounded), label: 'Series'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'TMC App'),
        ],
      ),
    );
  }
}

/// Feed inicial: destaques, retomada e lista. Sem barras de filtro.
class _HomeFeed extends StatefulWidget {
  const _HomeFeed({required this.resolver, required this.repository});

  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  State<_HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<_HomeFeed> {
  List<MediaItem> _featured = <MediaItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final TmdbPage page = await widget.repository.trending();
      if (!mounted) return;
      setState(() => _featured = page.items.take(8).toList());
    } catch (_) {}
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
    return CatalogGrid(
      resolver: widget.resolver,
      repository: widget.repository,
      autofocusFirst: _featured.isEmpty,
      loader: ({required int page}) => widget.repository.trending(page: page),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_featured.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: HeroCarousel(
                items: _featured,
                label: 'DESTAQUES',
                onOpen: _open,
              ),
            ),
          ContinueWatchingRow(
            resolver: widget.resolver,
            repository: widget.repository,
          ),
          const SectionTitle(text: 'MINHA LISTA'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FavoritesGrid(
              resolver: widget.resolver,
              repository: widget.repository,
              shrinkWrap: true,
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

/// Secao "Minha Lista" reaproveitavel.
class FavoritesSection extends StatelessWidget {
  const FavoritesSection({
    super.key,
    required this.resolver,
    required this.repository,
  });

  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  Widget build(BuildContext context) {
    return FavoritesGrid(
      resolver: resolver,
      repository: repository,
      shrinkWrap: true,
    );
  }
}