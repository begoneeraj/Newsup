import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Reassuring "all clear" placeholder — used whenever a feed or filter has
/// nothing to show. Deliberately not styled like an error state: a calm
/// icon + a sentence that explains *why* it's empty, not that something broke.
class EmptyState extends ConsumerWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.headline,
    required this.subtext,
  });

  final IconData icon;
  final String headline;
  final String subtext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.accent.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 34, color: theme.accent.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 20),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: theme.displayFont(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtext,
              textAlign: TextAlign.center,
              style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
