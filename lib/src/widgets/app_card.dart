import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Design-system tappable card: surface-level-1 background, 1px border,
/// 16px radius, 16px padding. On tap: scales to 0.98 and swaps to
/// surface-level-2, 150ms ease-out — the single card primitive every list
/// screen should compose with instead of hand-rolling `Card`+`InkWell`.
class AppCard extends ConsumerStatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  ConsumerState<AppCard> createState() => _AppCardState();
}

class _AppCardState extends ConsumerState<AppCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeDataProvider);

    return Padding(
      padding: widget.margin,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: _pressed ? theme.surfaceVariant : theme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.border),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
