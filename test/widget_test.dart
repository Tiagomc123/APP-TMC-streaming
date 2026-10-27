import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mc/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('o app sobe e monta o MaterialApp', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const TmcApp());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}