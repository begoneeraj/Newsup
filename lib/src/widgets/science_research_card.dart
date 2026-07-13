import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/science_research.dart';
import '../theme/theme_providers.dart';
import '../utils/time_ago.dart';

class ScienceResearchCard extends ConsumerWidget {
  const ScienceResearchCard({super.key, required this.report});

  final ScienceResearchReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(label: Text(report.field.label)),
                if (report.institution != null) Chip(label: Text(report.institution!)),
                if (report.indiaRelevance)
                  Chip(
                    label: const Text('India'),
                    backgroundColor: theme.accent.withValues(alpha: 0.15),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              report.displaySummary(genz),
              style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (report.whatThisMeans != null) ...[
              const SizedBox(height: 6),
              Text(
                report.whatThisMeans!,
                style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              timeAgo(report.processedAt),
              style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
