import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/crisis_report.dart';
import '../theme/theme_providers.dart';
import '../utils/time_ago.dart';

class CrisisReportCard extends ConsumerWidget {
  const CrisisReportCard({super.key, required this.report, required this.onTap});

  final CrisisReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final color = theme.crisisStatusColor(report.status);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color),
                            ),
                            child: Text(
                              report.status.label.toUpperCase(),
                              style: theme.bodyFont(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Detected ${timeAgo(report.eventStartDate)}',
                            style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        report.title,
                        style: theme.displayFont(fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${report.daysSinceEvent} days unresolved',
                        style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                      ),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: theme.border),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.gavel_outlined, size: 14, color: theme.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '${report.remedialActionsCount} remedial actions',
                            style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                          ),
                          const SizedBox(width: 14),
                          Icon(Icons.description_outlined, size: 14, color: theme.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            'RTI ${report.rtiFilingsAnswered}/${report.rtiFilingsTotal}',
                            style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
