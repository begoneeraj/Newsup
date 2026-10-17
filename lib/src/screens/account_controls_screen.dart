import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/bookmark_provider.dart';
import '../providers/user_progress_provider.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../theme/theme_providers.dart';

class AccountControlsScreen extends ConsumerStatefulWidget {
  const AccountControlsScreen({super.key});
  @override
  ConsumerState<AccountControlsScreen> createState() =>
      _AccountControlsScreenState();
}

class _AccountControlsScreenState extends ConsumerState<AccountControlsScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Could not complete the request. Check your connection and retry. '
                'For deletion, choose the same Google account when asked. If the problem continues, contact support; deletion has not been confirmed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.read(sharedPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & account controls')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text(
            'Notifications are optional. Enabling them sends a device token to Firebase and Supabase to deliver crisis and app updates.'),
        SwitchListTile(
            title: const Text('Push notifications'),
            value: prefs.getBool(PushNotificationService.enabledKey) == true,
            onChanged: _busy
                ? null
                : (enabled) => _run(() async {
                      if (enabled) {
                        final allowed = await PushNotificationService.enable(
                            ProviderScope.containerOf(context));
                        if (!allowed && mounted) {
                          setState(() => _message =
                              'Notification permission was not granted. You can change it in Android settings.');
                        }
                      } else {
                        await PushNotificationService.disable(prefs);
                      }
                    })),
        TextButton(
            onPressed: _busy ? null : () => context.push('/legal'),
            child: const Text('Privacy, terms, support & corrections')),
        if (prefs.getBool(PushNotificationService.pendingCleanupKey) == true)
          TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => PushNotificationService.disable(prefs)),
              child: const Text('Retry removal of notification data')),
        const Divider(height: 40),
        Text('Delete account', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
            'Permanently delete your TruthLens India Firebase profile, this device’s notification registration, bookmarks and reading progress. '
            'Your Google account will remain. Other devices may retain local data until you clear it there. '
            'You will be asked to confirm your identity with Google.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            icon: const Icon(Icons.delete_forever),
            label: const Text('Delete my account'),
            onPressed: _busy
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                              title: const Text(
                                  'Permanently delete your account?'),
                              content: const Text(
                                  'This cannot be undone. Your Google account is not deleted.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete account')),
                              ],
                            ));
                    if (confirmed != true || !context.mounted) return;
                    final container = ProviderScope.containerOf(context);
                    await _run(() async {
                      await AuthService.instance.deleteAccount(prefs);
                      container.invalidate(bookmarksProvider);
                      container.invalidate(userProgressProvider);
                      if (context.mounted) context.go('/consent');
                    });
                  }),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_message != null)
          Padding(
              padding: const EdgeInsets.only(top: 16), child: Text(_message!)),
      ]),
    );
  }
}
