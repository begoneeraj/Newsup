import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newsup/src/widgets/app_tour.dart';
import 'package:newsup/src/theme/theme_providers.dart';

Widget harness(ProviderContainer container, List<int> tabs,
        {double scale = 1}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: AppTourHost(
              onTabRequested: tabs.add,
              child: Scaffold(
                  body: Wrap(children: [
                for (final step in appTourSteps)
                  AppTourTarget(
                      name: step.target,
                      child: SizedBox(
                          width: 40, height: 40, child: Text(step.target))),
              ])))),
    );

void main() {
  testWidgets(
      'Skip persists, does not show again, and replay resets to step one',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tabs = <int>[];
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container, tabs));
    await tester.pumpAndSettle();
    expect(find.text('Your Spotlight feed'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Find a topic'), findsOneWidget);
    await tester.tap(find.text('Skip tour'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(appTourSeenKey), isTrue);
    expect(find.text('Skip tour'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(harness(container, tabs));
    await tester.pumpAndSettle();
    expect(find.text('Skip tour'), findsNothing);
    container.read(appTourActiveProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 11'), findsOneWidget);
  });

  testWidgets('Back, all steps and Done work and return to Spotlight',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tabs = <int>[];
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container, tabs));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 11'), findsOneWidget);
    for (var i = 0; i < appTourSteps.length - 1; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Step 11 of 11'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(appTourSeenKey), isTrue);
    expect(tabs, containsAllInOrder([0, 1, 2, 3, 4, 0]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tour fits a small screen with large text and can be skipped',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container, [], scale: 1.5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip tour'));
    await tester.tap(find.text('Skip tour'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(appTourSeenKey), isTrue);
    expect(tester.takeException(), isNull);
  });
}
