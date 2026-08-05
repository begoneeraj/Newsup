import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_providers.dart';
import '../providers/onboarding_providers.dart';
import '../screens/crisis_tracker_detail_screen.dart';
import '../screens/fact_check_detail_screen.dart';
import '../screens/govt_promise_detail_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/national_data_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/slow_crisis_detail_screen.dart';
import '../screens/underreported_topic_detail_screen.dart';
import '../models/underreported_topic.dart';
import '../theme/theme_providers.dart';

/// Design-system screen transition: slide-in from the right + fade,
/// 250ms ease-in-out — replaces the default platform fade/zoom for every
/// route in the app so navigation feels consistent everywhere.
CustomTransitionPage<T> _slideFadePage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// A [Provider] (rather than a top-level `final`) so the redirect closure
/// can read the onboarding flag via `ref` — it re-checks SharedPreferences
/// fresh on every navigation attempt rather than caching it, since the flag
/// flips exactly once (right after the user finishes onboarding) and that
/// flip must take effect on the very next redirect check.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Watched here (not just read inside `redirect`) so the router itself is
  // rebuilt — which reruns the redirect for the current location — the
  // instant Firebase's auth state changes, e.g. right after sign-in/out.
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final seen = hasSeenOnboarding(ref.read(sharedPreferencesProvider));
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!seen && !atOnboarding) return '/onboarding';
      if (seen && atOnboarding) return '/';

      // First frame, before Firebase's persisted session has resolved —
      // SplashOverlay is still covering the screen at this point, so stay
      // put rather than flashing the login screen for an already-signed-in
      // user.
      if (authState.isLoading) return null;

      final signedIn = authState.valueOrNull != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn && !atLogin) return '/login';
      if (signedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _slideFadePage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _slideFadePage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _slideFadePage(state, const HomeScreen()),
      ),
      GoRoute(
        path: '/national-data',
        pageBuilder: (context, state) => _slideFadePage(state, const NationalDataScreen()),
      ),
      GoRoute(
        path: '/fact-check/:id',
        pageBuilder: (context, state) => _slideFadePage(
          state,
          FactCheckDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/crisis/:id',
        pageBuilder: (context, state) => _slideFadePage(
          state,
          CrisisTrackerDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/promise/:id',
        pageBuilder: (context, state) => _slideFadePage(
          state,
          GovtPromiseDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/slow-crisis/:id',
        pageBuilder: (context, state) => _slideFadePage(
          state,
          SlowCrisisDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/underreported-topic/:id',
        pageBuilder: (context, state) => _slideFadePage(
          state,
          UnderreportedTopicDetailScreen(topic: state.extra as UnderreportedTopic),
        ),
      ),
    ],
  );
});
