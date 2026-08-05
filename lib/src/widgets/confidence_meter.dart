import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Turns a 0-100 confidence score into a scannable animated bar + a human
/// label ("High Confidence") instead of bare floating text — the number
/// stays, but the label and fill length are what a user's eye compares
/// across cards.
class ConfidenceMeter extends ConsumerWidget {
  const ConfidenceMeter({
    super.key,
    required this.confidence,
    required this.color,
    this.showLabel = false,
  });

  final int confidence;
  final Color color;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final fraction = (confidence.clamp(0, 100)) / 100;

    final bar = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, value, _) => SizedBox(
        width: 56,
        height: 6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              Container(color: theme.surfaceVariant),
              FractionallySizedBox(
                widthFactor: value,
                child: Container(color: color),
              ),
            ],
          ),
        ),
      ),
    );

    if (!showLabel) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          bar,
          const SizedBox(width: 8),
          Text(
            '$confidence%',
            style: theme.monoFont(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          theme.confidenceLabel(confidence.toDouble()),
          style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textMuted),
        ),
        const SizedBox(width: 8),
        bar,
        const SizedBox(width: 8),
        Text(
          '$confidence%',
          style: theme.monoFont(fontSize: 12, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
