import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import '../services/auth_service.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';

/// Same 36px circular tap target as [CircularIconButton] (see
/// widgets/circular_icon_button.dart) — dropped into each tab's own AppBar
/// actions row rather than floated as a page-level overlay, so it lines up
/// with the other action icons instead of sitting at a different height/
/// inset on every screen.
class AccountAvatarAction extends ConsumerWidget {
  const AccountAvatarAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final theme = ref.watch(appThemeDataProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: theme.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _showAccountSheet(context, user, theme),
            child: Tooltip(
              message: 'Account',
              child: CircleAvatar(
                radius: 18,
                backgroundColor: theme.surfaceVariant,
                backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                child: user?.photoURL == null
                    ? Icon(Icons.person_outline, size: 18, color: theme.textMuted)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAccountSheet(BuildContext context, User? user, AppThemeData theme) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _AccountSheet(user: user, theme: theme),
    );
  }
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.user, required this.theme});

  final User? user;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: theme.surfaceVariant,
              backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
              child: user?.photoURL == null
                  ? Icon(Icons.person_outline, size: 28, color: theme.textMuted)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              user?.displayName ?? 'Signed in',
              style: theme.displayFont(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (user?.email != null) ...[
              const SizedBox(height: 4),
              Text(
                user!.email!,
                style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await AuthService.instance.signOut();
                },
                icon: Icon(Icons.logout, size: 18, color: theme.error),
                label: Text(
                  'Sign out',
                  style: theme.bodyFont(fontSize: 14, fontWeight: FontWeight.w600, color: theme.error),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: theme.error.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
