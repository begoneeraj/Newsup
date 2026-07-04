import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Turns a 0-100 confidence score into a scannable horizontal bar instead of
/// bare floating text — the number stays, but the fill length is what a
/// user's eye actually compares across cards.
class ConfidenceMeter extends ConsumerWidget {
  const ConfidenceMeter({super.key, required this.confidence, required this.color});

  final int confidence;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final fraction = (confidence.clamp(0, 100)) / 100;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 54,
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(color: theme.border),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$confidence%',
          style: theme.monoFont(fontSize: 12, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
