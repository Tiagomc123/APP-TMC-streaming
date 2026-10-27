import 'package:flutter/material.dart';

import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../screens/details_screen.dart';
import 'poster_card.dart';

class FavoritesGrid extends StatefulWidget {
  const FavoritesGrid({
    super.key,
    required this.resolver,
    required this.repository,
    this.shrinkWrap = false,
  });

  final VideoResolverService resolver;
  final TmdbRepository repository;
  final bool shrinkWrap;

  @override
  State<FavoritesGrid> createState() => _FavoritesGridState();
}

class _FavoritesGridState extends State<FavoritesGrid> {
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

  @override
  Widget build(BuildContext context) {
    final List<MediaItem> favs = LibraryRepository.instance.favorites;
    if (favs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: Text('Sua lista esta vazia.', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 60),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 172,
        childAspectRatio: 0.54,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
      ),
      itemCount: favs.length,
      itemBuilder: (BuildContext ctx, int i) => PosterCard(
        item: favs[i],
        autofocus: i == 0 && !widget.shrinkWrap,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DetailsScreen(
              item: favs[i],
              resolver: widget.resolver,
              repository: widget.repository,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rotulo padrao das secoes horizontais.
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}