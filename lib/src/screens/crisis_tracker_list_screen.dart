import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/public_event_providers.dart';
import '../theme/theme_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/public_event_card.dart';
import '../widgets/staggered_fade_slide.dart';

/// Reads from public_events (dual-written from fact_checks/crisis_reports/
/// crises — see src/pipeline/public_events.py), not crisis_reports directly.
/// crisis_reports only ever gets rows from the Reddit-sourced crisis-hunting
/// fetcher, which can be (and has been) structurally empty if that source
/// goes quiet/blocked; public_events is populated from every source.
class CrisisTrackerListScreen extends ConsumerWidget {
  const CrisisTrackerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(publicEventsProvider);
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Crisis Tracker')),
      body: RefreshIndicator(
        color: theme.accent,
        backgroundColor: theme.surface,
        onRefresh: () async {
          ref.invalidate(publicEventsProvider);
          await ref.read(publicEventsProvider.future);
        },
        child: eventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(child: Text('Failed to load crisis alerts: $error')),
            ],
          ),
          data: (events) {
            if (events.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const EmptyState(
                      icon: Icons.monitor_heart_outlined,
                      headline: 'No active crisis alerts',
                      subtext:
                          'Public events are generated automatically from news, RTI '
                          'escalations, and crisis-relevant keywords across monitored '
                          'sources.',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return StaggeredFadeSlide(
                  index: index,
                  child: PublicEventCard(
                    event: event,
                    onTap: () => context.push('/crisis/${event.id}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
