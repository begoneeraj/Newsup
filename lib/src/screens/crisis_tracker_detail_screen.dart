import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/crisis_report.dart';
import '../providers/crisis_report_providers.dart';
import '../widgets/evidence_vault_sheet.dart';
import '../widgets/systemic_timeline_widget.dart';

class CrisisTrackerDetailScreen extends ConsumerWidget {
  const CrisisTrackerDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(crisisReportByIdProvider(id));

    return reportAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Crisis Tracker')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Crisis Tracker')),
        body: Center(child: Text('Failed to load crisis report: $error')),
      ),
      data: (report) {
        if (report == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Crisis Tracker')),
            body: const Center(child: Text('Crisis report not found.')),
          );
        }
        return _CrisisTrackerDetailBody(report: report);
      },
    );
  }
}

class _CrisisTrackerDetailBody extends StatelessWidget {
  const _CrisisTrackerDetailBody({required this.report});

  final CrisisReport report;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crisis Detail')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => EvidenceVaultSheet.show(context, report.evidenceItems),
        icon: const Icon(Icons.folder_outlined),
        label: const Text('Evidence Vault'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(report.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            report.status.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  _Stat(label: 'Days since event', value: '${report.daysSinceEvent}'),
                  _Stat(
                    label: 'Remedial actions',
                    value: '${report.remedialActionsCount}',
                  ),
                  _Stat(
                    label: 'RTI filings answered',
                    value: '${report.rtiFilingsAnswered}/${report.rtiFilingsTotal}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Systemic Timeline', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SystemicTimelineWidget(events: report.timelineEvents),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
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
