import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/underreported_topic.dart';
import '../providers/underreported_topic_providers.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';

class UnderreportedTopicDetailScreen extends ConsumerWidget {
  const UnderreportedTopicDetailScreen({super.key, required this.topic});

  final UnderreportedTopic topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final color = theme.gapScoreColor(topic.gapScore);
    final pointsAsync = ref.watch(underreportedTopicPointsProvider(topic.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Underreported Topic')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(topic.title, style: theme.displayFont(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              if (topic.gapScore != null)
                Chip(
                  label: Text('Gap score ${(topic.gapScore! * 100).round()}%'),
                  backgroundColor: color.withValues(alpha: 0.16),
                ),
              Chip(label: Text('${topic.nicheCount ?? 0} official records')),
              Chip(label: Text('${topic.mainstreamCount ?? 0} mainstream articles')),
            ],
          ),
          if (topic.dataSource != null) ...[
            const SizedBox(height: 8),
            Text(
              'Source: ${topic.dataSource}',
              style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
            ),
          ],
          const SizedBox(height: 20),
          Text('Coverage Gap Trend', style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          pointsAsync.when(
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
                  'No daily readings recorded yet.',
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                );
              }
              if (points.length == 1) {
                final only = points.first;
                return Text(
                  'Latest reading (${only.recordedDate}): ${only.nicheCount} official vs. '
                  '${only.mainstreamCount} mainstream. Trend will appear once more days are recorded.',
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                );
              }
              return _TrendChart(points: points, theme: theme, color: color);
            },
          ),
          const SizedBox(height: 20),
          Text('Official / Niche Sources', style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          pointsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
            data: (points) {
              final latest = points.isEmpty ? null : points.last;
              final sources = latest?.exampleNicheSources ?? const [];
              if (sources.isEmpty) {
                return Text(
                  'No matching official record today.',
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                );
              }
              return Column(
                children: [for (final link in sources) _SourceTile(link: link, theme: theme)],
              );
            },
          ),
          const SizedBox(height: 20),
          Text('Mainstream Coverage Found', style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          pointsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
            data: (points) {
              final latest = points.isEmpty ? null : points.last;
              final sources = latest?.exampleMainstreamSources ?? const [];
              if (sources.isEmpty) {
                return Text(
                  'No matching mainstream article found today — this is what "underreported" means here.',
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                );
              }
              return Column(
                children: [for (final link in sources) _SourceTile(link: link, theme: theme)],
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

  final List<UnderreportedTopicPoint> points;
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
                for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].gapScore),
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

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.link, required this.theme});

  final SourceLink link;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: link.url.isEmpty ? null : () => launchUrl(Uri.parse(link.url)),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(link.title, style: theme.bodyFont(fontSize: 13, fontWeight: FontWeight.w600)),
                    if (link.source != null) ...[
                      const SizedBox(height: 2),
                      Text(link.source!, style: theme.bodyFont(fontSize: 11, color: theme.textMuted)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.open_in_new, size: 16, color: theme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
