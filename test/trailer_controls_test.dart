import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc/ui/widgets/embedded_trailer.dart';

void main() {
  testWidgets('trailer pode ser fechado e nao oferece tela cheia', (
    WidgetTester tester,
  ) async {
    bool closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailerControls(
            playing: true,
            muted: false,
            rotated: true,
            positionLabel: '0:10 / 2:00',
            onTogglePlayback: () {},
            onToggleRotation: () {},
            onToggleMute: () {},
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(find.text('TELA CHEIA'), findsNothing);
    expect(find.text('FECHAR'), findsOneWidget);

    await tester.tap(find.text('FECHAR'));
    expect(closed, isTrue);
  });
}
