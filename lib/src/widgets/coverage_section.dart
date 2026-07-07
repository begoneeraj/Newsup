import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coverage.dart';
import '../providers/fact_check_providers.dart';

/// Feature 2 (coverage count): neutral factual outlet-count data only — never
/// attach editorial language ("widely covered", "ignored by media") here.
class CoverageSection extends ConsumerWidget {
  const CoverageSection({super.key, required this.factCheckId});

  final String factCheckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverageAsync = ref.watch(coverageAnalysisProvider(factCheckId));
    final outletSourcesAsync = ref.watch(outletSourcesProvider(factCheckId));

    return coverageAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (coverage) {
        if (coverage == null || coverage.totalOutlets == 0) {
          return const SizedBox.shrink();
        }
        return ExpansionTile(
          title: Text('Reported by ${coverage.totalOutlets} outlets'),
          subtitle: Text(coverage.consensus.label),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            outletSourcesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (outlets) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final outlet in outlets) _OutletRow(outlet: outlet),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OutletRow extends StatelessWidget {
  const _OutletRow({required this.outlet});

  final OutletSource outlet;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(outlet.outletName, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  outlet.outletUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54),
                ),
              ],
            ),
          ),
          if (outlet.outletCredibilityScore != null) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${outlet.outletCredibilityScore!.round()}%',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'credibility',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white38),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
