import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/progress_service.dart';
import '../../services/stream/video_resolver_service.dart';
import '../screens/details_screen.dart';
import 'favorites_grid.dart';

/// Fila horizontal de retomada, com barra de progresso por titulo.
class ContinueWatchingRow extends StatefulWidget {
  const ContinueWatchingRow({
    super.key,
    required this.resolver,
    required this.repository,
  });

  final VideoResolverService resolver;
  final TmdbRepository repository;

  @override
  State<ContinueWatchingRow> createState() => _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends State<ContinueWatchingRow> {
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

  @override
  Widget build(BuildContext context) {
    final List<WatchEntry> items = LibraryRepository.instance.continueWatching;
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionTitle(text: 'CONTINUAR ASSISTINDO'),
        SizedBox(
          height: 198,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (BuildContext ctx, int i) => _card(items[i], i == 0),
          ),
        ),
      ],
    );
  }

  Widget _card(WatchEntry entry, bool autofocus) {
    final Duration left = entry.duration > entry.position
        ? entry.duration - entry.position
        : Duration.zero;

    return SizedBox(
      width: 152,
      child: Focus(
        autofocus: autofocus,
        child: GestureDetector(
          onTap: () => _open(entry),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: AppTheme.br,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (entry.ref.poster.isEmpty)
                        Container(color: AppTheme.card)
                      else
                        CachedNetworkImage(
                          imageUrl: '${AppConfig.tmdbImageBase}/w342${entry.ref.poster}',
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Container(color: AppTheme.card),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: entry.progress,
                          minHeight: 4,
                          backgroundColor: Colors.black45,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.gold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.ref.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                entry.ref.isTv
                    ? 'T${entry.ref.season} E${entry.ref.episode} - faltam ${ProgressService.stamp(left)}'
                    : 'faltam ${ProgressService.stamp(left)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}