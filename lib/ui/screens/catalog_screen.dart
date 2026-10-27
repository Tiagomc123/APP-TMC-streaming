import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/catalog_grid.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/hero_carousel.dart';
import 'details_screen.dart';

/// Aba de Filmes / Series: banner + grade limpa. Os filtros vivem em um
/// modal aberto pelo botao flutuante do shell.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.isTv,
    required this.repository,
    required this.resolver,
  });

  final bool isTv;
  final TmdbRepository repository;
  final VideoResolverService resolver;

  @override
  State<CatalogScreen> createState() => CatalogScreenState();
}

class CatalogScreenState extends State<CatalogScreen> {
  List<Map<String, dynamic>> _genres = const <Map<String, dynamic>>[];
  List<MediaItem> _launches = <MediaItem>[];
  CatalogFilters _filters = const CatalogFilters();

  @override
  void initState() {
    super.initState();
    _loadGenres();
    _loadLaunches();
  }

  Future<void> _loadGenres() async {
    final List<Map<String, dynamic>> genres = await widget.repository.genres(widget.isTv);
    if (!mounted) return;
    setState(() => _genres = genres);
  }

  Future<void> _loadLaunches() async {
    try {
      final TmdbPage page = await widget.repository.launches(isTv: widget.isTv);
      if (!mounted) return;
      setState(() => _launches = page.items.take(8).toList());
    } catch (_) {}
  }

  /// Abre o painel de filtros. So recarrega a grade ao aplicar.
  Future<void> openFilters() async {
    final CatalogFilters? result = await showModalBottomSheet<CatalogFilters>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => FilterSheet(initial: _filters, genres: _genres),
    );
    if (result == null || !mounted) return;

    AppConfig.preferDublado = result.language != FilterLanguage.legendado;
    setState(() => _filters = result);
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
    final bool hasBanner = _launches.isNotEmpty;

    return CatalogGrid(
      key: ValueKey<String>('${widget.isTv}_${_filters.signature}'),
      resolver: widget.resolver,
      repository: widget.repository,
      autofocusFirst: !hasBanner,
      loader: ({required int page}) => widget.repository.discover(
        isTv: widget.isTv,
        page: page,
        genreId: _filters.genreId == 0 ? null : _filters.genreId,
        minRating: _filters.minRating,
        yearFrom: _filters.yearFrom,
        yearTo: _filters.yearTo,
      ),
      header: hasBanner
          ? Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
              child: HeroCarousel(
                items: _launches,
                label: widget.isTv ? 'NO AR AGORA' : 'EM CARTAZ',
                height: 208,
                compact: true,
                onOpen: _open,
              ),
            )
          : const SizedBox(height: 8),
    );
  }
}