import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check.dart';
import '../theme/theme_providers.dart';
import 'status_badge.dart';

/// FactCheckStatus-specific wrapper around the generic [StatusBadge] design
/// system primitive — evokes the RTI / notary ink-stamp motif via a slight
/// tilt in Genz voice.
class StatusStamp extends ConsumerWidget {
  const StatusStamp({super.key, required this.status});

  final FactCheckStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;
    final color = theme.statusColor(status);
    final label = genz ? status.genzLabel : status.label;
    final icon = switch (status) {
      FactCheckStatus.verified => Icons.check_circle_rounded,
      FactCheckStatus.falseClaim => Icons.cancel_rounded,
      FactCheckStatus.misleading => Icons.warning_rounded,
      FactCheckStatus.partlyTrue => Icons.warning_rounded,
      FactCheckStatus.outOfContext => Icons.info_rounded,
      FactCheckStatus.satire => Icons.theater_comedy_rounded,
      FactCheckStatus.unverified => Icons.help_rounded,
    };

    Widget stamp = StatusBadge(label: label, color: color, icon: icon);

    if (genz) {
      stamp = Transform.rotate(angle: -4 * math.pi / 180, child: stamp);
    }

    return stamp;
  }
}
