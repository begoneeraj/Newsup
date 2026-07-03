import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme_data.dart';
import 'app_voice.dart';

const _voiceKey = 'newsup.voiceMode';
const _brightnessKey = 'newsup.brightness';

/// Overridden in `main.dart` with the resolved instance before [runApp].
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final voiceModeProvider = StateProvider<AppVoice>((ref) {
  final stored = ref.watch(sharedPreferencesProvider).getString(_voiceKey);
  return stored == 'genz' ? AppVoice.genz : AppVoice.normal;
});

final brightnessProvider = StateProvider<Brightness>((ref) {
  final stored = ref.watch(sharedPreferencesProvider).getString(_brightnessKey);
  return stored == 'light' ? Brightness.light : Brightness.dark;
});

final appThemeDataProvider = Provider<AppThemeData>((ref) {
  final voice = ref.watch(voiceModeProvider);
  final brightness = ref.watch(brightnessProvider);
  return resolveAppTheme(voice, brightness);
});

void toggleVoiceMode(WidgetRef ref) {
  final next = ref.read(voiceModeProvider) == AppVoice.normal ? AppVoice.genz : AppVoice.normal;
  ref.read(voiceModeProvider.notifier).state = next;
  ref.read(sharedPreferencesProvider).setString(_voiceKey, next.name);
}

void toggleBrightness(WidgetRef ref) {
  final next =
      ref.read(brightnessProvider) == Brightness.dark ? Brightness.light : Brightness.dark;
  ref.read(brightnessProvider.notifier).state = next;
  ref.read(sharedPreferencesProvider).setString(_brightnessKey, next == Brightness.light ? 'light' : 'dark');
}
