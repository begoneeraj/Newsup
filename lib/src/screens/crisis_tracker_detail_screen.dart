import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/public_event.dart';
import '../providers/public_event_providers.dart';
import '../theme/theme_providers.dart';
import '../widgets/systemic_timeline_widget.dart';

class CrisisTrackerDetailScreen extends ConsumerWidget {
  const CrisisTrackerDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(publicEventByIdProvider(id));

    return eventAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Crisis Tracker')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Crisis Tracker')),
        body: Center(child: Text('Failed to load event: $error')),
      ),
      data: (event) {
        if (event == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Crisis Tracker')),
            body: const Center(child: Text('Event not found.')),
          );
        }
        return _CrisisTrackerDetailBody(event: event);
      },
    );
  }
}

class _CrisisTrackerDetailBody extends ConsumerWidget {
  const _CrisisTrackerDetailBody({required this.event});

  final PublicEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final color = theme.publicEventSeverityColor(event.severity);
    final allSources = [
      ...event.officialSources,
      ...event.mediaSources,
      ...event.redditSources,
      ...event.youtubeSources,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Crisis Detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(event.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Chip(label: Text(event.eventType.label)),
              if (event.status != null) Chip(label: Text(event.status!.label)),
              if (event.state != null) Chip(label: Text(event.state!)),
            ],
          ),
          const SizedBox(height: 16),
          Text(event.summary, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  if (event.importanceScore != null)
                    _Stat(label: 'Importance', value: '${event.importanceScore}', color: color),
                  _Stat(label: 'Sources', value: '${allSources.length}'),
                  if (event.severity != null) _Stat(label: 'Severity', value: event.severity!.name, color: color),
                ],
              ),
            ),
          ),
          if (event.timeline.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SystemicTimelineWidget(events: event.timeline),
          ],
          if (allSources.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Sources', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final source in allSources)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '•  ${source.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                ),
              ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white54,
              ),
        ),
      ],
    );
  }
}
