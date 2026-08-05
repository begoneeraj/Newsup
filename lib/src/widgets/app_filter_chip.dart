import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Design-system filter/category pill. Unselected: surface-level-1 bg,
/// secondary text, 1px border. Selected: accent @ 20% opacity bg, accent
/// text, accent border. Named `AppFilterChip` (not `FilterChip`) to avoid
/// colliding with Flutter's built-in Material chip.
class AppFilterChip extends ConsumerWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;

  /// Optional trailing widget (e.g. a count pill) shown after the label.
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final accent = color ?? theme.accent;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? accent.withValues(alpha: 0.20) : theme.surface,
          border: Border.all(
            color: selected ? accent : theme.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? accent : theme.textMuted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.bodyFont(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent : theme.textMuted,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontally-scrolling row of chips with 8px gaps and a fade-out
/// gradient on both edges, so chips cut off by the viewport read as
/// intentionally scrollable rather than clipped.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({super.key, required this.children, this.height = 44});

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.03, 0.94, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) => children[index],
        ),
      ),
    );
  }
}
