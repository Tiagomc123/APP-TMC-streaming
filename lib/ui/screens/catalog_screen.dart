import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/catalog_grid.dart';
import '../widgets/hero_carousel.dart';
import 'details_screen.dart';

/// Catálogo de filmes e séries com cinco destaques e filtros recolhidos.
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
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  static const List<double> _ratings = <double>[0, 6, 7, 8, 9];
  static const int _allYears = 0;

  List<Map<String, dynamic>> _genres = const <Map<String, dynamic>>[];
  List<MediaItem> _banners = const <MediaItem>[];
  int _genreId = 0;
  double _minRating = 0;
  int _sortIndex = 0;
  int _year = _allYears;

  List<Map<String, String>> get _sorts => <Map<String, String>>[
    <String, String>{'id': 'popularity.desc', 'label': 'Populares'},
    <String, String>{'id': 'vote_average.desc', 'label': 'Melhor nota'},
    <String, String>{
      'id': widget.isTv ? 'first_air_date.desc' : 'primary_release_date.desc',
      'label': 'Recentes',
    },
    <String, String>{
      'id': widget.isTv ? 'name.asc' : 'original_title.asc',
      'label': 'A–Z',
    },
  ];

  String get _signature =>
      '${widget.isTv}_${_genreId}_${_minRating}_${_sorts[_sortIndex]['id']}_$_year';

  int get _activeFilterCount =>
      (_genreId == 0 ? 0 : 1) +
      (_minRating == 0 ? 0 : 1) +
      (_sortIndex == 0 ? 0 : 1) +
      (_year == _allYears ? 0 : 1);

  @override
  void initState() {
    super.initState();
    _loadGenres();
    _loadBanners();
  }

  Future<void> _loadGenres() async {
    final List<Map<String, dynamic>> genres = await widget.repository.genres(
      widget.isTv,
    );
    if (mounted) setState(() => _genres = genres);
  }

  Future<void> _loadBanners() async {
    try {
      final TmdbPage page = await widget.repository.discover(
        isTv: widget.isTv,
        page: 1,
        sort: 'popularity.desc',
      );
      if (mounted) setState(() => _banners = page.items.take(5).toList());
    } catch (_) {
      if (mounted) setState(() => _banners = const <MediaItem>[]);
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

  Future<void> _openFilters() async {
    int genre = _genreId;
    double rating = _minRating;
    int sort = _sortIndex;
    int year = _year;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.card,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          final int currentYear = DateTime.now().year;
          final List<int> years = <int>[
            _allYears,
            for (int value = currentYear; value >= 1980; value--) value,
          ];

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .82,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.tune_rounded, color: AppTheme.gold),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Filtrar catálogo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar filtros',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _dropdown<int>(
                      label: 'Gênero',
                      value: genre,
                      items: <DropdownMenuItem<int>>[
                        const DropdownMenuItem<int>(
                          value: 0,
                          child: Text('Todos os gêneros'),
                        ),
                        for (final Map<String, dynamic> item in _genres)
                          DropdownMenuItem<int>(
                            value: (item['id'] as num?)?.toInt() ?? 0,
                            child: Text((item['name'] ?? '').toString()),
                          ),
                      ],
                      onChanged: (int? value) =>
                          setSheetState(() => genre = value ?? 0),
                    ),
                    const SizedBox(height: 12),
                    _dropdown<double>(
                      label: 'Nota mínima',
                      value: rating,
                      items: <DropdownMenuItem<double>>[
                        for (final double value in _ratings)
                          DropdownMenuItem<double>(
                            value: value,
                            child: Text(
                              value == 0
                                  ? 'Qualquer nota'
                                  : '${value.toStringAsFixed(0)} ou mais',
                            ),
                          ),
                      ],
                      onChanged: (double? value) =>
                          setSheetState(() => rating = value ?? 0),
                    ),
                    const SizedBox(height: 12),
                    _dropdown<int>(
                      label: 'Ordenar por',
                      value: sort,
                      items: <DropdownMenuItem<int>>[
                        for (int i = 0; i < _sorts.length; i++)
                          DropdownMenuItem<int>(
                            value: i,
                            child: Text(_sorts[i]['label']!),
                          ),
                      ],
                      onChanged: (int? value) =>
                          setSheetState(() => sort = value ?? 0),
                    ),
                    const SizedBox(height: 12),
                    _dropdown<int>(
                      label: 'Ano',
                      value: year,
                      items: <DropdownMenuItem<int>>[
                        const DropdownMenuItem<int>(
                          value: _allYears,
                          child: Text('Todos os anos'),
                        ),
                        for (final int value in years.skip(1))
                          DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value'),
                          ),
                      ],
                      onChanged: (int? value) =>
                          setSheetState(() => year = value ?? _allYears),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _genreId = 0;
                                _minRating = 0;
                                _sortIndex = 0;
                                _year = _allYears;
                              });
                              Navigator.of(sheetContext).pop();
                            },
                            child: const Text('Limpar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _genreId = genre;
                                _minRating = rating;
                                _sortIndex = sort;
                                _year = year;
                              });
                              Navigator.of(sheetContext).pop();
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Aplicar filtros'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppTheme.card,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppTheme.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String sort = _sorts[_sortIndex]['label']!;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: <Widget>[
              Tooltip(
                message: 'Filtros',
                child: OutlinedButton.icon(
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('Filtros'),
                      if (_activeFilterCount > 0) ...<Widget>[
                        const SizedBox(width: 7),
                        CircleAvatar(
                          radius: 9,
                          backgroundColor: AppTheme.gold,
                          child: Text(
                            '$_activeFilterCount',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: const BorderSide(color: Colors.white24),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _activeFilterCount == 0
                      ? 'Populares • $sort'
                      : '$_activeFilterCount filtros aplicados',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        if (_banners.length >= 5)
          HeroCarousel(height: 250, items: _banners, onOpen: _open),
        Expanded(
          child: CatalogGrid(
            key: ValueKey<String>(_signature),
            resolver: widget.resolver,
            repository: widget.repository,
            loader: ({required int page}) => widget.repository.discover(
              isTv: widget.isTv,
              page: page,
              genreId: _genreId == 0 ? null : _genreId,
              minRating: _minRating,
              sort: _sorts[_sortIndex]['id'] ?? 'popularity.desc',
              year: _year == _allYears ? null : _year,
            ),
          ),
        ),
      ],
    );
  }
}
