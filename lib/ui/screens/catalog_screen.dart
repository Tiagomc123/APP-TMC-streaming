import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../services/stream/video_resolver_service.dart';
import '../widgets/catalog_grid.dart';

/// Aba de Filmes / Series com filtro rapido por genero, nota e ordenacao.
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

  List<Map<String, dynamic>> _genres = const <Map<String, dynamic>>[];
  int _genreId = 0;
  double _minRating = 0;
  int _sortIndex = 0;

  List<Map<String, String>> get _sorts => <Map<String, String>>[
        <String, String>{'id': 'popularity.desc', 'label': 'POPULARES'},
        <String, String>{'id': 'vote_average.desc', 'label': 'MELHOR NOTA'},
        <String, String>{
          'id': widget.isTv ? 'first_air_date.desc' : 'primary_release_date.desc',
          'label': 'RECENTES',
        },
        <String, String>{
          'id': widget.isTv ? 'name.asc' : 'original_title.asc',
          'label': 'A-Z',
        },
      ];

  String get _signature =>
      '${widget.isTv}_${_genreId}_${_minRating}_${_sorts[_sortIndex]['id']}';

  @override
  void initState() {
    super.initState();
    _loadGenres();
  }

  Future<void> _loadGenres() async {
    final List<Map<String, dynamic>> genres = await widget.repository.genres(widget.isTv);
    if (!mounted) return;
    setState(() => _genres = genres);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _genreRow(),
        _ratingRow(),
        _sortRow(),
        const Divider(height: 1),
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
            ),
          ),
        ),
      ],
    );
  }

  Widget _genreRow() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        itemCount: _genres.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext ctx, int i) {
          if (i == 0) {
            return _chip(
              label: 'TODOS OS GENEROS',
              selected: _genreId == 0,
              onTap: () => setState(() => _genreId = 0),
            );
          }
          final Map<String, dynamic> genre = _genres[i - 1];
          final int id = (genre['id'] ?? 0) as int;
          return _chip(
            label: (genre['name'] ?? '').toString().toUpperCase(),
            selected: _genreId == id,
            onTap: () => setState(() => _genreId = id),
          );
        },
      ),
    );
  }

  Widget _ratingRow() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        itemCount: _ratings.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext ctx, int i) {
          final double value = _ratings[i];
          return _chip(
            label: value == 0 ? 'QUALQUER NOTA' : '${value.toStringAsFixed(0)}+ ESTRELAS',
            selected: _minRating == value,
            onTap: () => setState(() => _minRating = value),
          );
        },
      ),
    );
  }

  Widget _sortRow() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        itemCount: _sorts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext ctx, int i) => _chip(
          label: _sorts[i]['label'] ?? '',
          selected: _sortIndex == i,
          onTap: () => setState(() => _sortIndex = i),
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Center(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : Colors.white60,
        ),
        backgroundColor: AppTheme.card,
        selectedColor: AppTheme.accent,
        side: const BorderSide(color: Colors.white12),
      ),
    );
  }
}