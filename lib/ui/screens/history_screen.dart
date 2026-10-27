import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/progress_service.dart';
import '../../services/stream/video_resolver_service.dart';
import 'details_screen.dart';

/// Historico geral de navegacao/reproducao com limpeza individual e total.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.resolver,
    required this.repository,
  });

  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  void _open(WatchEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailsScreen(
          item: MediaItem(
            id: entry.ref.tmdbId,
            title: entry.ref.title,
            isTv: entry.ref.isTv,
            poster: entry.ref.poster,
            date: entry.ref.year,
          ),
          resolver: widget.resolver,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _remove(WatchEntry entry) async {
    await LibraryRepository.instance.removeFromHistory(entry.ref.key);
    if (mounted) setState(() {});
  }

  Future<void> _clearAll() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Limpar historico?'),
        content: const Text('Isso apaga o historico e o progresso de retomada.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('LIMPAR'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LibraryRepository.instance.clearAllHistory();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<WatchEntry> entries = LibraryRepository.instance.history;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Historico'),
        actions: <Widget>[
          if (entries.isNotEmpty)
            TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep, color: AppTheme.red),
              label: const Text('LIMPAR TUDO',
                  style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text('Nada no historico ainda.', style: TextStyle(color: Colors.white54)),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (BuildContext ctx, int i) => _row(entries[i]),
            ),
    );
  }

  Widget _row(WatchEntry entry) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: AppTheme.br,
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  entry.ref.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'parou em ${ProgressService.stamp(entry.position)}'
                  '${entry.duration > Duration.zero ? ' de ${ProgressService.stamp(entry.duration)}' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: entry.progress,
                    minHeight: 4,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.gold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _open(entry),
            child: const Text('ABRIR'),
          ),
          IconButton(
            tooltip: 'Apagar',
            icon: const Icon(Icons.delete_outline, color: AppTheme.red),
            onPressed: () => _remove(entry),
          ),
        ],
      ),
    );
  }
}