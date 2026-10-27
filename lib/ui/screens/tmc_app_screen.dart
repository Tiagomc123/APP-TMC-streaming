import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/cache_service.dart';
import '../../services/stream/providers/stream_provider.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/favorites_grid.dart';
import 'history_screen.dart';

/// Painel "TMC App": atalhos, saude das fontes e manutencao.
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
  bool _sweeping = false;
  int _freedMb = 0;

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
        _shortcuts(),
        _health(),
        const SectionTitle(text: 'MINHA LISTA'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FavoritesGrid(
            resolver: widget.resolver,
            repository: widget.repository,
            shrinkWrap: true,
          ),
        ),
        ContinueWatchingRow(
          resolver: widget.resolver,
          repository: widget.repository,
        ),
      ],
    );
  }

  Widget _shortcuts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          TvButton(label: 'HISTORICO', icon: Icons.history_rounded, onPressed: _openHistory),
          TvButton(
            label: _sweeping
                ? 'LIMPANDO...'
                : (_freedMb > 0 ? 'LIBERADO: ${_freedMb}MB' : 'LIMPAR CACHE'),
            icon: Icons.cleaning_services_rounded,
            onPressed: () => unawaited(_sweep()),
          ),
          TvButton(
            label: 'INICIO',
            icon: Icons.home_rounded,
            onPressed: () => widget.onGoToTab?.call(0),
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
    );
  }

  Widget _health() {
    final Map<String, double> scores = widget.resolver.healthScores();
    final List<StreamProvider> providers = widget.resolver.providers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'FONTES (API JSON)',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TvButton(
                label: 'ZERAR',
                icon: Icons.restart_alt,
                onPressed: () {
                  widget.resolver.resetHealth();
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final StreamProvider p in providers) _healthRow(p, scores[p.id] ?? 0.5),
        ],
      ),
    );
  }

  Widget _healthRow(StreamProvider provider, double score) {
    final double value = score.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              provider.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  value >= 0.6
                      ? AppTheme.green
                      : (value >= 0.35 ? AppTheme.gold : AppTheme.red),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}