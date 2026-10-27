import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/catalog_grid.dart';
import '../widgets/favorites_grid.dart';
import 'catalog_screen.dart';
import 'history_screen.dart';
import 'search_screen.dart';
import 'tmc_app_screen.dart';

/// Navegação principal: Início | Filmes | Séries | TMC Apps.
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
  static const List<String> _titles = <String>[
    'Início',
    'Filmes',
    'Séries',
    'TMC Apps',
  ];

  int _index = 0;

  void _goToTab(int index) {
    if (index < 0 || index > 3) return;
    setState(() => _index = index);
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
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: <Widget>[
          IconButton(
            tooltip: 'Historico',
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          CatalogGrid(
            resolver: widget.resolver,
            repository: widget.repository,
            loader: ({required int page}) =>
                widget.repository.trending(page: page),
          ),
          CatalogScreen(
            isTv: false,
            repository: widget.repository,
            resolver: widget.resolver,
          ),
          CatalogScreen(
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goToTab,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.movie_rounded),
            label: 'Filmes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tv_rounded),
            label: 'Séries',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'TMC Apps',
          ),
        ],
      ),
    );
  }
}

/// Secao "Minha Lista" usada dentro de outras telas.
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
