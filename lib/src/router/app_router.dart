import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/onboarding_providers.dart';
import '../screens/crisis_tracker_detail_screen.dart';
import '../screens/fact_check_detail_screen.dart';
import '../screens/govt_promise_detail_screen.dart';
import '../screens/home_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/slow_crisis_detail_screen.dart';
import '../theme/theme_providers.dart';

/// A [Provider] (rather than a top-level `final`) so the redirect closure
/// can read the onboarding flag via `ref` — it re-checks SharedPreferences
/// fresh on every navigation attempt rather than caching it, since the flag
/// flips exactly once (right after the user finishes onboarding) and that
/// flip must take effect on the very next redirect check.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final seen = hasSeenOnboarding(ref.read(sharedPreferencesProvider));
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!seen && !atOnboarding) return '/onboarding';
      if (seen && atOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/fact-check/:id',
        builder: (context, state) => FactCheckDetailScreen(
          id: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/crisis/:id',
        builder: (context, state) => CrisisTrackerDetailScreen(
          id: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/promise/:id',
        builder: (context, state) => GovtPromiseDetailScreen(
          id: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/slow-crisis/:id',
        builder: (context, state) => SlowCrisisDetailScreen(
          id: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});
