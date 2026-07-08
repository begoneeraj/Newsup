import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fact_check.dart';
import '../../theme/app_theme_data.dart';
import '../../theme/theme_providers.dart';

/// One card in the Reality Feed swipe deck. Shows the official headline and
/// the Gen Z translation; the verdict badge stays blurred until [revealed].
class CollectibleCard extends ConsumerWidget {
  const CollectibleCard({
    super.key,
    required this.factCheck,
    required this.revealed,
    this.dragOffsetX = 0,
  });

  final FactCheck factCheck;
  final bool revealed;

  /// Horizontal drag distance in logical pixels, used to tint the card's
  /// edge glow while the user is deciding. Only meaningful for the top card.
  final double dragOffsetX;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final statusColor = theme.statusColor(factCheck.status);

    // Lean the ambient glow toward a "true" green or "cap" red while dragging.
    final leanColor = dragOffsetX == 0
        ? theme.accent
        : (dragOffsetX > 0 ? theme.statusColor(FactCheckStatus.verified) : theme.statusColor(FactCheckStatus.falseClaim));
    final leanStrength = (dragOffsetX.abs() / 160).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.surface, Color.lerp(theme.surface, theme.bg, 0.6)!],
        ),
        border: Border.all(
          color: Color.lerp(theme.border, leanColor, leanStrength * 0.8)!,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: leanColor.withValues(alpha: 0.10 + leanStrength * 0.22),
            blurRadius: 32,
            spreadRadius: leanStrength * 4,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _VerdictChip(status: factCheck.status, revealed: revealed, theme: theme, color: statusColor),
              const Spacer(),
              Text(
                factCheck.origin,
                style: theme.monoFont(fontSize: 11, color: theme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            factCheck.claimText,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.bodyFont(fontSize: 17, fontWeight: FontWeight.w700, color: theme.textPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            'GEN Z TRANSLATION',
            style: theme.monoFont(fontSize: 10, fontWeight: FontWeight.w700, color: theme.accent)
                .copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            factCheck.genzSummary ?? factCheck.claimText,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.displayFont(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: theme.accent,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SwipeHint(label: '← CAP', color: theme.statusColor(FactCheckStatus.falseClaim), visible: dragOffsetX < -12),
              Icon(Icons.touch_app_outlined, size: 15, color: theme.textMuted.withValues(alpha: 0.5)),
              _SwipeHint(label: 'TRUE →', color: theme.statusColor(FactCheckStatus.verified), visible: dragOffsetX > 12),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.status, required this.revealed, required this.theme, required this.color});

  final FactCheckStatus status;
  final bool revealed;
  final AppThemeData theme;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.4),
      ),
      child: Text(
        revealed ? status.genzBadgeLabel : "❓ Jury's Out",
        style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w800, color: color),
      ),
    );

    if (revealed) return chip;

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: chip,
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.label, required this.color, required this.visible});

  final String label;
  final Color color;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5),
      ),
    );
  }
}
