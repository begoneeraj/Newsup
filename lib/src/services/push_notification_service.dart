import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../providers/public_event_providers.dart';

/// Registers this device for push notifications on new crisis reports and
/// new app releases. The Supabase Edge Functions (supabase/functions/
/// notify-crisis, supabase/functions/notify-app-update) send via FCM
/// whenever a crisis_reports row is inserted or a GitHub release is
/// published; this side just needs a token on file in the device_tokens
/// table plus handlers for what each message type should do.
class PushNotificationService {
  PushNotificationService._();

  static const _updateUrlKey = 'update_url';

  static Future<void> initialize(ProviderContainer container) async {
    // Devices without working Google Play Services (common on some MIUI
    // builds/custom ROMs, or emulators/networks that can't reach Google's
    // backend) either throw here — e.g. getToken() failing with
    // SERVICE_NOT_AVAILABLE — or simply never resolve the underlying GMS
    // call. That must never block app startup: this is awaited directly in
    // main() before runApp(), so either an uncaught exception or a hang here
    // previously left the entire app stuck on a blank launch screen,
    // forever, with no error shown. Push is optional; boot is not.
    const gmsCallTimeout = Duration(seconds: 5);
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(gmsCallTimeout);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken().timeout(gmsCallTimeout);
      if (token != null) {
        await _registerToken(token);
      }
      messaging.onTokenRefresh.listen(_registerToken);

      // The app doesn't have general local-notification UI wired up, so a
      // foreground push shows no OS banner. For most pushes (new crisis
      // report) that's fine — just silently refresh the feed. An app-update
      // push is the exception: it's actionable, so surface it as a SnackBar
      // with a button to open the release page. Background/killed states
      // still get the OS notification tray banner from FCM directly.
      FirebaseMessaging.onMessage.listen((message) {
        final updateUrl = message.data[_updateUrlKey];
        if (updateUrl != null) {
          _showUpdateBanner(updateUrl, message.notification?.body);
        } else {
          container.invalidate(publicEventsProvider);
        }
      });

      // Tapping the OS notification (app backgrounded or killed) should open
      // the release page directly rather than just landing on the home screen.
      FirebaseMessaging.onMessageOpenedApp.listen(_openUpdateUrlIfPresent);
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _openUpdateUrlIfPresent(initialMessage);
      }
    } catch (_) {
      // Non-fatal: the app works fine without push.
    }
  }

  static void _openUpdateUrlIfPresent(RemoteMessage message) {
    final updateUrl = message.data[_updateUrlKey];
    if (updateUrl != null) {
      launchUrl(Uri.parse(updateUrl), mode: LaunchMode.externalApplication);
    }
  }

  static void _showUpdateBanner(String updateUrl, String? body) {
    NewsupApp.scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body ?? 'A new version is available'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'UPDATE',
          onPressed: () => launchUrl(Uri.parse(updateUrl), mode: LaunchMode.externalApplication),
        ),
      ),
    );
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
