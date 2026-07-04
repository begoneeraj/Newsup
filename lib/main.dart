import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/services/push_notification_service.dart';
import 'src/theme/theme_providers.dart';

/// Read at build/run time via `--dart-define=SUPABASE_URL=...
/// --dart-define=SUPABASE_PUBLISHABLE_KEY=...`. Never hardcode these — the
/// publishable key is safe to ship in a client build only because Supabase
/// RLS policies restrict it to read-only access (see supabase/schema.sql).
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabasePublishableKey);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  await PushNotificationService.initialize(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NewsupApp(),
    ),
  );
}
