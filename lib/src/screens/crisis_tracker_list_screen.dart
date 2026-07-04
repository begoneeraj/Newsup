import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/crisis_report_providers.dart';
import '../theme/theme_providers.dart';
import '../widgets/crisis_report_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/staggered_fade_slide.dart';

class CrisisTrackerListScreen extends ConsumerWidget {
  const CrisisTrackerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(crisisReportsProvider);
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Crisis Tracker')),
      body: RefreshIndicator(
        color: theme.accent,
        backgroundColor: theme.surface,
        onRefresh: () async {
          ref.invalidate(crisisReportsProvider);
          await ref.read(crisisReportsProvider.future);
        },
        child: reportsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(child: Text('Failed to load crisis reports: $error')),
            ],
          ),
          data: (reports) {
            if (reports.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const EmptyState(
                      icon: Icons.monitor_heart_outlined,
                      headline: 'No active crisis alerts',
                      subtext:
                          'Crisis reports are generated automatically when keywords like '
                          'paper leaks, court orders, or RTI escalations are detected '
                          'across monitored sources.',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return StaggeredFadeSlide(
                  index: index,
                  child: CrisisReportCard(
                    report: report,
                    onTap: () => context.push('/crisis/${report.id}'),
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
