import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/crisis_report.dart';
import '../theme/theme_providers.dart';

class SystemicTimelineWidget extends ConsumerWidget {
  const SystemicTimelineWidget({super.key, required this.events});

  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final dateFormat = DateFormat('d MMM yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: events[i].statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.border, width: 2),
                      ),
                    ),
                    if (i != events.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: theme.border,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFormat.format(events[i].date),
                          style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textMuted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          events[i].title,
                          style: theme.displayFont(fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          events[i].description,
                          style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
