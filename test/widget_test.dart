import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:newsup/src/app.dart';

void main() {
  testWidgets('Newsup launches to the Fact Checks tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: NewsupApp()));
    await tester.pumpAndSettle();

    expect(find.text('Fact Checks'), findsWidgets);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });
}
