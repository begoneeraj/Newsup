import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/public_event.dart';
import '../theme/theme_providers.dart';

/// Small emoji+label pill for a PublicEvent's severity/status — modeled on
/// StatusStamp (lib/src/widgets/status_stamp.dart). Distinct from the
/// eventType badge already on PublicEventCard: that says *what kind* of
/// crisis this is, this says *how serious/current* it is.
class SeverityChip extends ConsumerWidget {
  const SeverityChip({super.key, this.severity, this.status});

  final PublicEventSeverity? severity;
  final PublicEventStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (severity == null && status == null) return const SizedBox.shrink();

    final theme = ref.watch(appThemeDataProvider);
    final color = theme.publicEventSeverityColor(severity);
    final emoji = switch (severity) {
      PublicEventSeverity.high => '🔴',
      PublicEventSeverity.medium => '🟡',
      PublicEventSeverity.low => '🟢',
      null => status == PublicEventStatus.ongoing ? '🟢' : '⚪',
    };
    final label = severity != null
        ? switch (severity!) {
            PublicEventSeverity.high => 'Major',
            PublicEventSeverity.medium => 'Moderate',
            PublicEventSeverity.low => 'Minor',
          }
        : (status?.label ?? '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.bodyFont(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
