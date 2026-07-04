import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../widgets/share_card_sheet.dart';
import '../widgets/status_stamp.dart';

class FactCheckDetailScreen extends ConsumerWidget {
  const FactCheckDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factCheckAsync = ref.watch(factCheckByIdProvider(id));

    return factCheckAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Fact Check')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Fact Check')),
        body: Center(child: Text('Failed to load fact check: $error')),
      ),
      data: (factCheck) {
        if (factCheck == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Fact Check')),
            body: const Center(child: Text('Fact check not found.')),
          );
        }
        return _FactCheckDetailBody(factCheck: factCheck);
      },
    );
  }
}

class _FactCheckDetailBody extends ConsumerWidget {
  const _FactCheckDetailBody({required this.factCheck});

  final FactCheck factCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('d MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fact Check Detail'),
        actions: [
          IconButton(
            tooltip: 'Share verdict',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => showShareCardSheet(context, ref, factCheck),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              StatusStamp(status: factCheck.status),
              const Spacer(),
              Text(
                dateFormat.format(factCheck.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white54,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(factCheck.claimText, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            factCheck.origin,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatRow(
                    label: 'Evidence confidence',
                    value: '${factCheck.evidenceConfidence}%',
                  ),
                  _StatRow(
                    label: 'Source reliability',
                    value: factCheck.sourceReliability.label,
                  ),
                  _StatRow(
                    label: 'Independent confirmations',
                    value: '${factCheck.independentConfirmations}',
                  ),
                  _StatRow(
                    label: 'Official confirmation',
                    value: factCheck.officialConfirmation ? 'Yes' : 'No',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Expert Analysis'),
            initiallyExpanded: true,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                factCheck.expertAnalysis ?? 'No expert analysis available yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          ExpansionTile(
            title: Text('Sources (${factCheck.sources.length})'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (final source in factCheck.sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.title, style: Theme.of(context).textTheme.bodyMedium),
                      Text(
                        source.url,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white54,
                            ),
                      ),
                      Text(
                        dateFormat.format(source.publishedAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white38,
                            ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              )),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
