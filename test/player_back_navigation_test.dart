import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc/ui/widgets/custom_video_player.dart';

void main() {
  testWidgets(
    'voltar do sistema fecha a rota do player na primeira tentativa',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: const Text('Detalhes do filme'),
              floatingActionButton: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext routeContext) => PlayerBackGuard(
                      onBack: () => Navigator.of(routeContext).pop(),
                      child: const Scaffold(body: Text('Player')),
                    ),
                  ),
                ),
                child: const Text('Abrir player'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir player'));
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Detalhes do filme'), findsOneWidget);
      expect(find.text('Player'), findsNothing);
    },
  );
}
