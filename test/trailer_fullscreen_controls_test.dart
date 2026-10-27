import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc/ui/widgets/embedded_trailer.dart';

void main() {
  testWidgets('tela cheia do trailer oferece saída visível', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TrailerFullscreenScaffold(
                        title: 'Trailer',
                        player: Text('YouTube'),
                      ),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.byTooltip('Sair da tela cheia'), findsOneWidget);

    await tester.tap(find.byTooltip('Sair da tela cheia'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('YouTube'), findsNothing);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('YouTube'), findsNothing);
  });
}
