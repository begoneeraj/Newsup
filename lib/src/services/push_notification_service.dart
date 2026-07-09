import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/public_event_providers.dart';

/// Registers this device for push notifications on new crisis reports.
/// The Supabase Edge Function (supabase/functions/notify-crisis) sends via
/// FCM whenever a row is inserted into crisis_reports; this side just needs
/// a token on file in the device_tokens table.
class PushNotificationService {
  PushNotificationService._();

  static Future<void> initialize(ProviderContainer container) async {
    // Devices without working Google Play Services (common on some MIUI
    // builds/custom ROMs) throw here — e.g. getToken() failing with
    // SERVICE_NOT_AVAILABLE. That must never block app startup: this is
    // awaited directly in main() before runApp(), so an uncaught exception
    // here previously left the entire app stuck on a black launch screen,
    // forever, with no error shown. Push is optional; boot is not.
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
      messaging.onTokenRefresh.listen(_registerToken);

      // The app doesn't have local-notification UI wired up, so a foreground
      // push shows no banner — instead just silently refresh the feed so the
      // new crisis report is there when the user next looks. Background/killed
      // states still get the OS notification tray banner from FCM directly.
      FirebaseMessaging.onMessage.listen((_) {
        container.invalidate(publicEventsProvider);
      });
    } catch (_) {
      // Non-fatal: the app works fine without push.
    }
  }

  static Future<void> _registerToken(String token) async {
    try {
      await Supabase.instance.client.from('device_tokens').upsert({
        'token': token,
        'platform': 'android',
      });
    } catch (_) {
      // Non-fatal: the app works fine without push, and this retries on next launch.
    }
  }
}
