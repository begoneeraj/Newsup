import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/public_event.dart';
import '../theme/theme_providers.dart';
import '../utils/time_ago.dart';
import 'severity_chip.dart';

class PublicEventCard extends ConsumerWidget {
  const PublicEventCard({super.key, required this.event, required this.onTap});

  final PublicEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final color = theme.publicEventSeverityColor(event.severity);

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
                              event.eventType.label.toUpperCase(),
                              style: theme.bodyFont(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SeverityChip(severity: event.severity, status: event.status),
                          const Spacer(),
                          Text(
                            'Updated ${timeAgo(event.lastUpdated)}',
                            style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.displayFont(fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                      ),
                      if (event.status != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          event.status!.label,
                          style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Divider(height: 1, color: theme.border),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.newspaper_outlined, size: 14, color: theme.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '${event.totalSources} source${event.totalSources == 1 ? '' : 's'}',
                            style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                          ),
                          if (event.importanceScore != null) ...[
                            const SizedBox(width: 14),
                            Icon(Icons.trending_up, size: 14, color: theme.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              'Importance ${event.importanceScore}',
                              style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                            ),
                          ],
                          if (event.state != null) ...[
                            const SizedBox(width: 14),
                            Icon(Icons.place_outlined, size: 14, color: theme.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              event.state!,
                              style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                            ),
                          ],
                          const Spacer(),
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => Share.share(
                              '${event.title}\n\n${event.summary}\n\n'
                              '${event.sourceUrl.isNotEmpty ? event.sourceUrl : ''}',
                              subject: event.title,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.share_outlined, size: 16, color: theme.textMuted),
                            ),
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
