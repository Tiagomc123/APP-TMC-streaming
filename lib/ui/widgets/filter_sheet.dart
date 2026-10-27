import 'package:flutter/material.dart';

import '../../core/focus/dpad.dart';
import '../../core/theme/app_theme.dart';

enum FilterLanguage { qualquer, dublado, legendado }

/// Estado de filtro do catalogo. Imutavel e com assinatura estavel, usada
/// como ValueKey para recarregar a grade somente quando algo muda.
class CatalogFilters {
  const CatalogFilters({
    this.minRating = 0,
    this.language = FilterLanguage.qualquer,
    this.genreId = 0,
    this.yearFrom = 0,
    this.yearTo = 0,
  });

  final double minRating;
  final FilterLanguage language;
  final int genreId;
  final int yearFrom;
  final int yearTo;

  bool get isClean =>
      minRating == 0 &&
      language == FilterLanguage.qualquer &&
      genreId == 0 &&
      yearFrom == 0 &&
      yearTo == 0;

  String get signature => '$minRating|${language.name}|$genreId|$yearFrom|$yearTo';

  CatalogFilters copyWith({
    double? minRating,
    FilterLanguage? language,
    int? genreId,
    int? yearFrom,
    int? yearTo,
  }) =>
      CatalogFilters(
        minRating: minRating ?? this.minRating,
        language: language ?? this.language,
        genreId: genreId ?? this.genreId,
        yearFrom: yearFrom ?? this.yearFrom,
        yearTo: yearTo ?? this.yearTo,
      );
}

/// Painel inferior minimalista: NOTA, IDIOMA, GENERO e ANO.
/// A grade so e atualizada quando o usuario toca em APLICAR.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.initial,
    required this.genres,
  });

  final CatalogFilters initial;
  final List<Map<String, dynamic>> genres;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  static const List<double> _ratings = <double>[0, 6, 7, 8, 9];
  static const List<String> _yearLabels = <String>[
    'QUALQUER', '2026', '2025', '2024', '2020-2023', '2015-2019', '2000-2014', 'ANTES DE 2000',
  ];
  static const List<List<int>> _yearRanges = <List<int>>[
    <int>[0, 0], <int>[2026, 2026], <int>[2025, 2025], <int>[2024, 2024],
    <int>[2020, 2023], <int>[2015, 2019], <int>[2000, 2014], <int>[1900, 1999],
  ];

  late CatalogFilters _draft = widget.initial;
  int _yearIndex = 0;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _yearRanges.length; i++) {
      if (_yearRanges[i][0] == _draft.yearFrom && _yearRanges[i][1] == _draft.yearTo) {
        _yearIndex = i;
        break;
      }
    }
  }

  void _apply() => Navigator.of(context).pop(_draft);

  void _reset() {
    setState(() {
      _draft = const CatalogFilters();
      _yearIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.of(context).size.height * 0.86;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'FILTROS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  TvButton(
                    label: 'LIMPAR',
                    icon: Icons.restart_alt,
                    onPressed: _reset,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _label('NOTA MINIMA'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final double value in _ratings)
                          _chip(
                            icon: value == 0 ? Icons.star_border_rounded : Icons.star_rounded,
                            label: value == 0 ? 'QUALQUER' : '${value.toStringAsFixed(0)}+',
                            selected: _draft.minRating == value,
                            onTap: () => setState(() => _draft = _draft.copyWith(minRating: value)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label('IDIOMA'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final FilterLanguage language in FilterLanguage.values)
                          _chip(
                            icon: language == FilterLanguage.legendado
                                ? Icons.subtitles_rounded
                                : (language == FilterLanguage.dublado
                                    ? Icons.record_voice_over_rounded
                                    : Icons.language_rounded),
                            label: language == FilterLanguage.qualquer
                                ? 'TANTO FAZ'
                                : language.name.toUpperCase(),
                            selected: _draft.language == language,
                            onTap: () => setState(() => _draft = _draft.copyWith(language: language)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label('ANO DE LANCAMENTO'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (int i = 0; i < _yearLabels.length; i++)
                          _chip(
                            label: _yearLabels[i],
                            selected: _yearIndex == i,
                            onTap: () => setState(() {
                              _yearIndex = i;
                              _draft = _draft.copyWith(
                                yearFrom: _yearRanges[i][0],
                                yearTo: _yearRanges[i][1],
                              );
                            }),
                          ),
                      ],
                    ),
                    if (widget.genres.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 18),
                      _label('GENERO'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _chip(
                            label: 'TODOS',
                            selected: _draft.genreId == 0,
                            onTap: () => setState(() => _draft = _draft.copyWith(genreId: 0)),
                          ),
                          for (final Map<String, dynamic> genre in widget.genres)
                            _chip(
                              label: (genre['name'] ?? '').toString().toUpperCase(),
                              selected: _draft.genreId == (genre['id'] ?? 0) as int,
                              onTap: () => setState(() =>
                                  _draft = _draft.copyWith(genreId: (genre['id'] ?? 0) as int)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TvButton(
                        label: 'APLICAR FILTROS',
                        icon: Icons.check_rounded,
                        primary: true,
                        onPressed: _apply,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return ChoiceChip(
      avatar: icon == null ? null : Icon(icon, size: 15, color: selected ? Colors.white : Colors.white54),
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
      shape: RoundedRectangleBorder(borderRadius: AppTheme.brLg),
    );
  }
}