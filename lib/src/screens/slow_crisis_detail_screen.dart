import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/slow_crisis.dart';
import '../providers/slow_crisis_providers.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';

class SlowCrisisDetailScreen extends ConsumerWidget {
  const SlowCrisisDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crisisAsync = ref.watch(slowCrisisByIdProvider(id));

    return crisisAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Slow Crisis')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Slow Crisis')),
        body: Center(child: Text('Failed to load crisis: $error')),
      ),
      data: (crisis) {
        if (crisis == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Slow Crisis')),
            body: const Center(child: Text('Crisis not found.')),
          );
        }
        return _SlowCrisisDetailBody(crisis: crisis);
      },
    );
  }
}

class _SlowCrisisDetailBody extends ConsumerWidget {
  const _SlowCrisisDetailBody({required this.crisis});

  final SlowCrisis crisis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;
    final color = theme.slowCrisisSeverityColor(crisis.currentSeverity);
    final dataPointsAsync = ref.watch(crisisDataPointsProvider(crisis.id));
    final narrativeAsync = ref.watch(crisisNarrativeUpdatesProvider(crisis.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Slow Crisis')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(crisis.title, style: theme.displayFont(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Chip(label: Text(crisis.category.label)),
              if (crisis.region != null) Chip(label: Text(crisis.region!)),
              if (crisis.currentSeverity != null)
                Chip(
                  label: Text(crisis.currentSeverity!.label),
                  backgroundColor: color.withValues(alpha: 0.16),
                ),
            ],
          ),
          if (crisis.displayDescription(genz) != null) ...[
            const SizedBox(height: 16),
            Text(crisis.displayDescription(genz)!, style: theme.bodyFont(fontSize: 14)),
          ],
          if (crisis.dataSource != null) ...[
            const SizedBox(height: 8),
            Text(
              'Source: ${crisis.dataSource}',
              style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
            ),
          ],
          const SizedBox(height: 20),
          Text('Trend', style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          dataPointsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(
              'Failed to load trend data: $error',
              style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
            ),
            data: (points) {
              if (points.isEmpty) {
                return Text(
                  'No readings recorded yet.',
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                );
              }
              if (points.length == 1) {
                final only = points.first;
                return Text(
                  'Latest reading: ${only.value.toStringAsFixed(0)} ${only.unit} '
                  '(${only.recordedDate}). '
                  'Trend will appear once more readings come in.',
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                );
              }
              return _TrendChart(points: points, theme: theme, color: color);
            },
          ),
          const SizedBox(height: 20),
          Text('Narrative Updates', style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          narrativeAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(
              'Failed to load updates: $error',
              style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
            ),
            data: (updates) {
              if (updates.isEmpty) {
                return Text(
                  'No narrative updates yet.',
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                );
              }
              return Column(
                children: [
                  for (final update in updates) _NarrativeTile(update: update, genz: genz, theme: theme),
                ],
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.theme, required this.color});

  final List<CrisisDataPoint> points;
  final AppThemeData theme;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value),
              ],
              isCurved: true,
              color: color,
              barWidth: 2.5,
              dotData: FlDotData(show: points.length <= 15),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NarrativeTile extends StatelessWidget {
  const _NarrativeTile({required this.update, required this.genz, required this.theme});

  final CrisisNarrativeUpdate update;
  final bool genz;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('MMM d, yyyy').format(update.generatedAt.toLocal()),
              style: theme.bodyFont(fontSize: 11, fontWeight: FontWeight.w700, color: theme.textMuted),
            ),
            const SizedBox(height: 4),
            Text(update.display(genz), style: theme.bodyFont(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
