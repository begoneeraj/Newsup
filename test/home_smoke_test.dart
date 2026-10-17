import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newsup/src/providers/auth_providers.dart';
import 'package:newsup/src/providers/bookmark_provider.dart';
import 'package:newsup/src/providers/fact_check_providers.dart';
import 'package:newsup/src/providers/live_articles_provider.dart';
import 'package:newsup/src/providers/public_event_providers.dart';
import 'package:newsup/src/providers/pinned_statistics_provider.dart';
import 'package:newsup/src/providers/slow_crisis_providers.dart';
import 'package:newsup/src/providers/underreported_topic_providers.dart';
import 'package:newsup/src/screens/home_screen.dart';
import 'package:newsup/src/screens/fact_check_detail_screen.dart';
import 'package:newsup/src/theme/theme_providers.dart';
import 'package:newsup/src/widgets/app_tour.dart';
import 'feed_pagination_test.dart' show sampleFact;
import 'test_theme.dart';

void main() {
  testWidgets(
      'Actual home completes tour across all tabs and opens a fact-check detail',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appThemeDataProvider.overrideWithValue(TestTheme()),
      currentUserProvider.overrideWith((ref) => null),
      factCheckPageLoaderProvider.overrideWithValue(
          (offset, limit) async => [sampleFact(1), sampleFact(2)]),
      publicEventsProvider.overrideWith((ref) async => []),
      pinnedStatisticsProvider.overrideWith((ref) async => []),
      slowCrisesProvider.overrideWith((ref) async => []),
      underreportedTopicsProvider.overrideWith((ref) async => []),
      liveArticlesProvider.overrideWith((ref, filter) => Stream.value([])),
      savedFactChecksProvider.overrideWith((ref) async => ref
          .watch(bookmarksProvider)
          .map((id) => sampleFact(int.parse(id)))
          .toList()),
      factCheckByIdProvider
          .overrideWith((ref, id) async => sampleFact(int.parse(id))),
      outletSourcesProvider.overrideWith((ref, id) async => []),
      coverageAnalysisProvider.overrideWith((ref, id) async => null),
      factCheckV2Provider.overrideWith((ref, id) async => null),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
          path: '/fact-check/:id',
          builder: (_, state) =>
              FactCheckDetailScreen(id: state.pathParameters['id']!)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('Your Spotlight feed'), findsOneWidget);
    for (var i = 1; i < appTourSteps.length; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(appTourSeenKey), isTrue);
    expect(find.text('Claim 1').hitTestable(), findsOneWidget);
    await tester.enterText(find.byType(TextField).hitTestable(), 'Claim 2');
    await tester.pumpAndSettle();
    expect(find.text('Claim 1').hitTestable(), findsNothing);
    final cardTitle = find
        .byWidgetPredicate(
            (widget) => widget is Text && widget.data == 'Claim 2')
        .hitTestable();
    expect(cardTitle, findsOneWidget);
    await tester.tap(cardTitle);
    await tester.pumpAndSettle();
    expect(find.text('AI-assisted analysis'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
