import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check.dart';
import '../theme/theme_providers.dart';

/// A verification-stamp treatment for [FactCheckStatus] — evokes the
/// RTI / notary ink-stamp motif. Flat and subtle in Normal voice; tilted
/// with a bolder ring in Genz voice.
class StatusStamp extends ConsumerWidget {
  const StatusStamp({super.key, required this.status});

  final FactCheckStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;
    final color = theme.statusColor(status);
    final label = genz ? status.genzLabel : status.label;

    Widget stamp = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: genz ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.approval_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.bodyFont(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );

    if (genz) {
      stamp = Transform.rotate(angle: -4 * math.pi / 180, child: stamp);
    }

    return stamp;
  }
}
