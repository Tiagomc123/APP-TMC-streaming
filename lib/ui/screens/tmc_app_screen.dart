import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/focus/dpad.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/cache_service.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/favorites_grid.dart';
import '../widgets/hero_carousel.dart';
import 'details_screen.dart';
import 'history_screen.dart';

/// Painel inicial "TMC App": destaques, retomada, atalhos e manutencao.
class TmcAppScreen extends StatefulWidget {
  const TmcAppScreen({
    super.key,
    required this.resolver,
    required this.repository,
    this.onGoToTab,
  });

  final VideoResolverService resolver;
  final TmdbRepository repository;
  final ValueChanged<int>? onGoToTab;

  @override
  State<TmcAppScreen> createState() => _TmcAppScreenState();
}

class _TmcAppScreenState extends State<TmcAppScreen> {
  List<MediaItem> _featured = <MediaItem>[];
  bool _loading = true;
  bool _sweeping = false;
  int _freedMb = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final TmdbPage page = await widget.repository.trending();
      if (!mounted) return;
      setState(() {
        _featured = page.items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _sweep() async {
    setState(() => _sweeping = true);
    final int freed = await CacheService.sweep(
      maxMb: AppConfig.cacheMaxMb,
      maxAge: AppConfig.cacheMaxAge,
    );
    if (!mounted) return;
    setState(() {
      _sweeping = false;
      _freedMb = (freed / (1024 * 1024)).round();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: <Widget>[
        if (_loading)
          const SizedBox(
            height: 300,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_featured.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
            child: HeroCarousel(items: _featured, onOpen: _open),
          ),
        ContinueWatchingRow(resolver: _noResolver, repository: _noRepository),
        _shortcuts(),
        const SectionTitle(text: 'MINHA LISTA'),
        FavoritesGrid(
          resolver: widget.resolver,
          repository: widget.repository,
          shrinkWrap: true,
        ),
      ],
    );
  }

  Widget _shortcuts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'ATALHOS',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              TvButton(
                label: 'HISTORICO',
                icon: Icons.history,
                onPressed: _openHistory,
              ),
              TvButton(
                label: _sweeping
                    ? 'LIMPANDO CACHE...'
                    : (_freedMb > 0
                          ? 'CACHE LIBERADO: ${_freedMb}MB'
                          : 'LIMPAR CACHE'),
                icon: Icons.cleaning_services,
                onPressed: () => unawaited(_sweep()),
              ),
              TvButton(
                label: 'FILMES',
                icon: Icons.movie_rounded,
                onPressed: () => widget.onGoToTab?.call(1),
              ),
              TvButton(
                label: 'SERIES',
                icon: Icons.tv_rounded,
                onPressed: () => widget.onGoToTab?.call(2),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Fontes: SuperFlix API, PobreFlix, WarezCDN, EmbedCine, PontoFinal. '
            'Extracao por HTTP com prioridade de audio PT-BR (dublado).',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// Constantes de conveniencia: os widgets filhos recebem as dependencias
// pelo construtor do HomeScreen, mas o carrossel nao precisa delas.
final VideoResolverService _noResolver = _NullResolver();
final TmdbRepository _noRepository = TmdbRepository();

class _NullResolver extends VideoResolverService {
  _NullResolver();
}
