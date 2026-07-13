import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/data_story.dart';
import '../theme/theme_providers.dart';
import '../utils/time_ago.dart';

class DataStoryCard extends ConsumerWidget {
  const DataStoryCard({super.key, required this.story});

  final DataStory story;

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
            Row(
              children: [
                Icon(Icons.query_stats, size: 16, color: theme.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    story.datasetSource,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyFont(fontSize: 11, fontWeight: FontWeight.w700, color: theme.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              story.displayTitle(genz),
              style: theme.displayFont(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (story.headlineStat != null) ...[
              const SizedBox(height: 4),
              Text(
                story.headlineStat!,
                style: theme.displayFont(fontSize: 22, fontWeight: FontWeight.w700, color: theme.accent),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              story.displaySummary(genz),
              style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
            ),
            if (story.chartData.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < story.chartData.length; i++)
                            FlSpot(i.toDouble(), story.chartData[i].value),
                        ],
                        isCurved: true,
                        color: theme.accent,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: theme.accent.withValues(alpha: 0.12)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              timeAgo(story.publishedAt),
              style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
