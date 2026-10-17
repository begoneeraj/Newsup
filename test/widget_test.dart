import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newsup/src/release_config.dart';
import 'package:newsup/src/screens/consent_screen.dart';
import 'package:newsup/src/screens/legal_screen.dart';
import 'package:newsup/src/theme/theme_providers.dart';

void main() {
  testWidgets(
      'Consent requires adult confirmation and agreement; policies accessible before both',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(initialLocation: '/consent', routes: [
      GoRoute(path: '/consent', builder: (_, __) => const ConsentScreen()),
      GoRoute(path: '/legal', builder: (_, __) => const LegalScreen()),
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Accepted'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(routerConfig: router)));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester
        .tap(find.text('Read privacy policy, terms & publisher details'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy, terms & publisher'), findsOneWidget);
    expect(prefs.getString(ReleaseConfig.consentKey), isNull);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
        prefs.getString(ReleaseConfig.consentKey), ReleaseConfig.policyVersion);
    expect(find.text('Accepted'), findsOneWidget);
  });
  testWidgets('Consent scrolls on a small screen with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: const ConsentScreen())));
    await tester.scrollUntilVisible(find.byType(FilledButton), 250);
    expect(tester.takeException(), isNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
}
