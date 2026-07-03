import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/crisis_report_providers.dart';
import '../widgets/crisis_report_card.dart';

class CrisisTrackerListScreen extends ConsumerWidget {
  const CrisisTrackerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(crisisReportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Crisis Tracker')),
      body: reportsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Failed to load crisis reports: $error')),
        data: (reports) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            return CrisisReportCard(
              report: report,
              onTap: () => context.push('/crisis/${report.id}'),
            );
          },
        ),
      ),
    );
  }
}
