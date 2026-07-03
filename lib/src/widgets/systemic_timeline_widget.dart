import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/crisis_report.dart';

class SystemicTimelineWidget extends StatelessWidget {
  const SystemicTimelineWidget({super.key, required this.events});

  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context) {
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
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                    ),
                    if (i != events.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.white24,
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
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.white54,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          events[i].title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          events[i].description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
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
