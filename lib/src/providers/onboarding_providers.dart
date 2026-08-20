import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_providers.dart';

const onboardingSeenKey = 'newsup.hasSeenOnboarding';

/// Whether the 3-slide first-launch intro has been shown. Reads fresh from
/// [prefs] each call (never cached) — the flag flips exactly once, right
/// after the user finishes onboarding, and that flip must be visible on the
/// very next check (the router's redirect in particular).
bool hasSeenOnboarding(SharedPreferences prefs) {
  return prefs.getBool(onboardingSeenKey) ?? false;
}

Future<void> markOnboardingSeen(WidgetRef ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  await prefs.setBool(onboardingSeenKey, true);
}

const genzCoachMarkSeenKey = 'newsup.hasSeenGenzCoachMark';

/// Whether the one-time "try Gen Z mode" coach mark has been shown/dismissed.
/// Gen Z voice has no other discovery path besides this app-bar icon, so the
/// coach mark points new users at it exactly once.
bool hasSeenGenzCoachMark(SharedPreferences prefs) {
  return prefs.getBool(genzCoachMarkSeenKey) ?? false;
}

Future<void> markGenzCoachMarkSeen(WidgetRef ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  await prefs.setBool(genzCoachMarkSeenKey, true);
}
