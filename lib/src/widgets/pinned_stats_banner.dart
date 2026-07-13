import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pinned_statistic.dart';
import '../providers/pinned_statistics_provider.dart';
import '../theme/theme_providers.dart';

/// Non-scrolling banner pinned above Crisis Tracker's list — modeled on
/// _StatBar/_StatChip in reality_feed_screen.dart. Shows a small set of
/// manually curated national stats (e.g. NCRB figures) with a source
/// citation, always visible regardless of scroll position.
class PinnedStatsBanner extends ConsumerWidget {
  const PinnedStatsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(pinnedStatisticsProvider);
    final theme = ref.watch(appThemeDataProvider);

    return statsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (stats) {
        if (stats.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.border))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final stat in stats) ...[
                  _PinnedStatChip(stat: stat),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PinnedStatChip extends ConsumerWidget {
  const _PinnedStatChip({required this.stat});

  final PinnedStatistic stat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final formattedValue = NumberFormat.decimalPattern('en_IN').format(stat.value);
    final hasSource = stat.sourceUrl != null && stat.sourceUrl!.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: hasSource
          ? () => launchUrl(Uri.parse(stat.sourceUrl!), mode: LaunchMode.externalApplication)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formattedValue,
              style: theme.monoFont(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 5),
            Text(
              stat.label,
              style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
            ),
            const SizedBox(width: 5),
            Text(
              '${stat.source} ${stat.year}',
              style: theme.bodyFont(fontSize: 10, color: theme.textMuted),
            ),
            if (hasSource) ...[
              const SizedBox(width: 3),
              Icon(Icons.open_in_new, size: 11, color: theme.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}
