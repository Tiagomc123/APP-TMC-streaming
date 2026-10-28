import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc/ui/widgets/embedded_trailer.dart';

void main() {
  testWidgets('trailer oferece tela cheia e pode ser fechado', (
    WidgetTester tester,
  ) async {
    bool closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailerControls(
            playing: true,
            muted: false,
            positionLabel: '0:10 / 2:00',
            onTogglePlayback: () {},
            onToggleMute: () {},
            onFullscreen: () {},
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(find.text('TELA CHEIA'), findsOneWidget);
    expect(find.text('GIRAR TELA'), findsNothing);
    expect(find.text('FECHAR'), findsOneWidget);

    await tester.tap(find.text('FECHAR'));
    expect(closed, isTrue);
  });

  testWidgets('FECHAR na tela cheia retorna aos detalhes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: const Text('Detalhes do filme'),
            floatingActionButton: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const TrailerFullscreenScaffold(
                    title: 'Trailer',
                    player: Text('YouTube'),
                  ),
                ),
              ),
              child: const Text('Abrir tela cheia'),
            ),
          ),
        ),
      ),
    );

    for (int attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Abrir tela cheia'));
      await tester.pumpAndSettle();
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('FECHAR'), findsOneWidget);

      await tester.tap(find.text('FECHAR'));
      await tester.pumpAndSettle();
      expect(find.text('Detalhes do filme'), findsOneWidget);
      expect(find.text('YouTube'), findsNothing);
    }

    await tester.tap(find.text('Abrir tela cheia'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Detalhes do filme'), findsOneWidget);
  });
}
