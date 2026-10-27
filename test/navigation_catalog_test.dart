import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc/data/models/media_item.dart';
import 'package:mc/data/repositories/tmdb_repository.dart';
import 'package:mc/services/stream/video_resolver_service.dart';
import 'package:mc/services/stream/providers/stream_provider.dart';
import 'package:mc/ui/screens/catalog_screen.dart';
import 'package:mc/ui/screens/home_screen.dart';
import 'package:mc/ui/widgets/hero_carousel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepository extends TmdbRepository {
  final List<({bool isTv, int? genreId, double minRating, String sort})>
  discoverCalls =
      <({bool isTv, int? genreId, double minRating, String sort})>[];

  TmdbPage _page(int page, {bool isTv = false}) => TmdbPage(
    items: List<MediaItem>.generate(
      6,
      (int i) => MediaItem(
        id: page * 10 + i,
        title: 'Título ${page * 10 + i}',
        isTv: isTv,
        date: '2025-01-01',
        rating: 8,
      ),
    ),
    page: page,
    totalPages: 1,
  );

  @override
  Future<TmdbPage> trending({int page = 1}) async => _page(page);

  @override
  Future<TmdbPage> discover({
    required bool isTv,
    int page = 1,
    int? genreId,
    double minRating = 0,
    String sort = 'popularity.desc',
    int? year,
  }) async {
    discoverCalls.add((
      isTv: isTv,
      genreId: genreId,
      minRating: minRating,
      sort: sort,
    ));
    return _page(page, isTv: isTv);
  }

  @override
  Future<List<Map<String, dynamic>>> genres(bool isTv) async =>
      <Map<String, dynamic>>[
        <String, dynamic>{'id': 28, 'name': 'Ação'},
        <String, dynamic>{'id': 35, 'name': 'Comédia'},
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeRepository repository;
  late VideoResolverService resolver;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repository = _FakeRepository();
    resolver = VideoResolverService(providers: const <StreamProvider>[]);
  });

  tearDown(() => resolver.dispose());

  testWidgets('abas ficam na ordem Início, Filmes, Séries e TMC Apps', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(resolver: resolver, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    final BottomNavigationBar nav = tester.widget(
      find.byType(BottomNavigationBar),
    );
    expect(
      nav.items.map((BottomNavigationBarItem item) => item.label).toList(),
      <String>['Início', 'Filmes', 'Séries', 'TMC Apps'],
    );
  });

  testWidgets('catálogo mostra cinco destaques e mantém filtros recolhidos', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogScreen(
            isTv: false,
            repository: repository,
            resolver: resolver,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final HeroCarousel carousel = tester.widget(find.byType(HeroCarousel));
    expect(carousel.items, hasLength(5));
    expect(find.byTooltip('Filtros'), findsOneWidget);
    expect(find.text('Gênero'), findsNothing);

    await tester.tap(find.byTooltip('Filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Gênero'), findsOneWidget);
    expect(find.text('Nota mínima'), findsOneWidget);
    expect(find.text('Ordenar por'), findsOneWidget);
    expect(find.text('Ano'), findsOneWidget);

    await tester.tap(find.text('Todos os gêneros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ação').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();
    expect(repository.discoverCalls.last.genreId, 28);
  });

  testWidgets('aba Séries usa cinco destaques de séries', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogScreen(
            isTv: true,
            repository: repository,
            resolver: resolver,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final HeroCarousel carousel = tester.widget(find.byType(HeroCarousel));
    expect(carousel.items, hasLength(5));
    expect(carousel.items.every((MediaItem item) => item.isTv), isTrue);
  });
}
