import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/suicide_stat_year.dart';
import '../providers/national_data_provider.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';

/// Reachable only via the small "National data" icon tucked into the Fact
/// Checks / Reality Feed app bars — deliberately not pinned to any main
/// feed, since this is sensitive content (suicide statistics) that
/// shouldn't be the first thing a user sees. Shows the 5-year NCRB ADSI
/// series from `suicide_stats_history` (see supabase/migrations/
/// 0019_suicide_stats_history.sql). Static figures, no live counter.
class NationalDataScreen extends ConsumerWidget {
  const NationalDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final historyAsync = ref.watch(suicideStatsHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('National Data')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load: $error', style: theme.bodyFont(color: theme.textMuted)),
          ),
        ),
        data: (rows) {
          final total = rows.where((r) => r.category == 'total_suicides').toList();
          final student = rows.where((r) => r.category == 'student_suicides').toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                'Suicide statistics, India',
                style: theme.displayFont(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'NCRB\'s Accidental Deaths & Suicides in India (ADSI) report is the '
                'only official source for this data. It publishes once a year, with '
                'a 1-2 year reporting lag, so there is no live or current-year count.',
                style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
              ),
              const SizedBox(height: 24),
              _YearSeries(title: 'Total suicides', rows: total, theme: theme),
              const SizedBox(height: 24),
              _YearSeries(title: 'Student suicides', rows: student, theme: theme),
              const SizedBox(height: 20),
              InkWell(
                onTap: () => launchUrl(Uri.parse('https://ncrb.gov.in'), mode: LaunchMode.externalApplication),
                child: Text(
                  'Source: ncrb.gov.in ↗',
                  style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _YearSeries extends StatelessWidget {
  const _YearSeries({required this.title, required this.rows, required this.theme});

  final String title;
  final List<SuicideStatYear> rows;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final numberFormat = NumberFormat.decimalPattern('en_IN');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.bodyFont(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${row.year}', style: theme.bodyFont(fontSize: 13, color: theme.textMuted)),
                  Text(
                    numberFormat.format(row.value),
                    style: theme.monoFont(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
