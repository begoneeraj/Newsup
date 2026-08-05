import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Design-system top-bar action button: 36px circular tap target on a
/// surface-level-1 background, used for the trending/briefcase/theme-toggle
/// icons in each screen's AppBar actions.
class CircularIconButton extends ConsumerWidget {
  const CircularIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onTap: onPressed,
            child: Tooltip(
              message: tooltip ?? '',
              child: Icon(icon, size: 18, color: theme.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
