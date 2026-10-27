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

/// Shell principal. Ordem exata das abas: TMC App | Inicio | Filmes | Series.
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
  static const List<String> _titles = <String>['TMC App', 'Inicio', 'Filmes', 'Series'];

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
          TmcAppScreen(
            resolver: widget.resolver,
            repository: widget.repository,
            onGoToTab: _goToTab,
          ),
          CatalogGrid(
            resolver: widget.resolver,
            repository: widget.repository,
            loader: ({required int page}) => widget.repository.trending(page: page),
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
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goToTab,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'TMC App',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.movie_rounded),
            label: 'Filmes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tv_rounded),
            label: 'Series',
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