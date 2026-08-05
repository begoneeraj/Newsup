import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/underreported_topic.dart';
import '../theme/theme_providers.dart';
import 'app_card.dart';
import 'status_badge.dart';

class UnderreportedTopicCard extends ConsumerWidget {
  const UnderreportedTopicCard({super.key, required this.topic, required this.onTap});

  final UnderreportedTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final color = theme.gapScoreColor(topic.gapScore);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (topic.gapScore != null) ...[
                const SizedBox(width: 8),
                StatusBadge(label: topic.gapScoreLabel, color: color),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.gavel_outlined, size: 14, color: theme.textMuted),
              const SizedBox(width: 4),
              Text(
                '${topic.nicheCount ?? 0} official record${(topic.nicheCount ?? 0) == 1 ? '' : 's'}',
                style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
              ),
              const SizedBox(width: 8),
              Icon(Icons.newspaper_outlined, size: 14, color: theme.textMuted),
              const SizedBox(width: 4),
              Text(
                '${topic.mainstreamCount ?? 0} mainstream',
                style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
              ),
            ],
          ),
          if (topic.dataSource != null) ...[
            const SizedBox(height: 8),
            Text(
              topic.dataSource!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
