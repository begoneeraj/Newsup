import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../app.dart';
import '../providers/public_event_providers.dart';
import '../utils/safe_launch.dart';
import '../release_config.dart';
import '../theme/theme_providers.dart';

/// Registers this device for push notifications on new crisis reports and
/// new app releases. The Supabase Edge Functions (supabase/functions/
/// notify-crisis, supabase/functions/notify-app-update) send via FCM
/// whenever a crisis_reports row is inserted or a GitHub release is
/// published; this side just needs a token on file in the device_tokens
/// table plus handlers for what each message type should do.
class PushNotificationService {
  PushNotificationService._();

  static const _updateUrlKey = 'update_url';
  static const enabledKey = 'newsup.notificationsEnabled';
  static const pendingCleanupKey = 'newsup.notificationCleanupPending';
  static const _tokenKey = 'newsup.notificationToken';
  static StreamSubscription<String>? _tokenSubscription;
  static bool _handlersInstalled = false;
  static Future<void> _queue = Future.value();

  static Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<void> disable(SharedPreferences prefs) =>
      _serial(() => _disable(prefs));

  static Future<void> _disable(SharedPreferences prefs) async {
    // Stop refresh before removing data so no callback can register a new token.
    await prefs.setBool(enabledKey, false);
    await prefs.setBool(pendingCleanupKey, true);
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(false);
    // A failed server deletion is surfaced: never claim full deletion when
    // the backend is offline or the required migration is not deployed.
    final token = prefs.getString(_tokenKey) ??
        await messaging.getToken().timeout(const Duration(seconds: 10));
    if (token != null) {
      await prefs.setString(_tokenKey, token);
    }
    // Invalidate delivery even if server cleanup fails. Keep the old token
    // locally until its server row is removed so retries remain possible.
    await messaging.deleteToken().timeout(const Duration(seconds: 10));
    if (token != null) {
      await Supabase.instance.client.rpc('unregister_device_token',
          params: {'device_token': token}).timeout(const Duration(seconds: 10));
    }
    await prefs.remove(_tokenKey);
    await prefs.remove(pendingCleanupKey);
  }

  static Future<bool> enable(ProviderContainer container) async {
    final prefs = container.read(sharedPreferencesProvider);
    if (prefs.getBool(pendingCleanupKey) == true) {
      await disable(prefs);
    }
    final settings = await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }
    await prefs.setBool(enabledKey, true);
    try {
      await initialize(container, failOnError: true);
    } catch (_) {
      await prefs.setBool(enabledKey, false);
      rethrow;
    }
    return true;
  }

  static Future<void> initialize(ProviderContainer container,
          {bool failOnError = false}) =>
      _serial(() => _initialize(container, failOnError: failOnError));

  static Future<void> _initialize(ProviderContainer container,
      {bool failOnError = false}) async {
    final prefs = container.read(sharedPreferencesProvider);
    if (prefs.getString(ReleaseConfig.consentKey) !=
            ReleaseConfig.policyVersion ||
        prefs.getBool(enabledKey) != true) {
      return;
    }
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

      final settings =
          await messaging.getNotificationSettings().timeout(gmsCallTimeout);
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        await prefs.setBool(enabledKey, false);
        return;
      }

      await messaging.setAutoInitEnabled(true);

      final token = await messaging.getToken().timeout(gmsCallTimeout);
      if (token == null) throw StateError('Notification token unavailable');
      await _registerToken(token, prefs);
      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen((token) {
        if (prefs.getBool(enabledKey) == true) {
          unawaited(_serial(() => _registerToken(token, prefs))
              .catchError((Object _) {}));
        }
      });

      if (_handlersInstalled) return;
      _handlersInstalled = true;

      // The app doesn't have general local-notification UI wired up, so a
      // foreground push shows no OS banner. For most pushes (new crisis
      // report) that's fine — just silently refresh the feed. An app-update
      // push is the exception: it's actionable, so surface it as a SnackBar
      // with a button to open the release page. Background/killed states
      // still get the OS notification tray banner from FCM directly.
      FirebaseMessaging.onMessage.listen((message) {
        if (prefs.getBool(enabledKey) != true) return;
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
      if (failOnError) rethrow;
      // Non-fatal: the app works fine without push.
    }
  }

  static void _openUpdateUrlIfPresent(RemoteMessage message) {
    final updateUrl = message.data[_updateUrlKey];
    if (updateUrl != null) {
      launchSecureUrl(
          ReleaseConfig.playStore ? ReleaseConfig.storeUrl : updateUrl,
          mode: LaunchMode.externalApplication);
    }
  }

  static void _showUpdateBanner(String updateUrl, String? body) {
    NewsupApp.scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body ?? 'A new version is available'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'UPDATE',
          onPressed: () => launchSecureUrl(
              ReleaseConfig.playStore ? ReleaseConfig.storeUrl : updateUrl,
              mode: LaunchMode.externalApplication),
        ),
      ),
    );
  }

  static Future<void> _registerToken(
      String token, SharedPreferences prefs) async {
    if (prefs.getBool(enabledKey) != true) return;
    final oldToken = prefs.getString(_tokenKey);
    if (oldToken != null && oldToken != token) {
      await Supabase.instance.client.rpc('unregister_device_token', params: {
        'device_token': oldToken
      }).timeout(const Duration(seconds: 10));
    }
    await prefs.setString(_tokenKey, token);
    await Supabase.instance.client.from('device_tokens').upsert({
      'token': token,
      'platform': 'android',
    },
        onConflict: 'token',
        ignoreDuplicates: true).timeout(const Duration(seconds: 10));
  }
}
