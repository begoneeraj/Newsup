import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/govt_promise.dart';
import '../providers/govt_promise_providers.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';

class GovtPromiseDetailScreen extends ConsumerWidget {
  const GovtPromiseDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promiseAsync = ref.watch(govtPromiseByIdProvider(id));

    return promiseAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Govt Promise')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Govt Promise')),
        body: Center(child: Text('Failed to load promise: $error')),
      ),
      data: (promise) {
        if (promise == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Govt Promise')),
            body: const Center(child: Text('Promise not found.')),
          );
        }
        return _GovtPromiseDetailBody(promise: promise);
      },
    );
  }
}

class _GovtPromiseDetailBody extends ConsumerWidget {
  const _GovtPromiseDetailBody({required this.promise});

  final GovtPromise promise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;
    final qualityColor = theme.implementationQualityColor(promise.implementationQuality);
    final evidenceAsync = ref.watch(promiseEvidenceProvider(promise.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Govt Promise')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(promise.projectName, style: theme.displayFont(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Chip(label: Text(promise.category.label)),
              Chip(label: Text(promise.currentStatus.label)),
              if (promise.party != null) Chip(label: Text(promise.party!)),
              if (promise.state != null) Chip(label: Text(promise.state!)),
              if (promise.electionYear != null) Chip(label: Text('${promise.electionYear}')),
            ],
          ),
          const SizedBox(height: 16),
          Text(promise.displaySummary(genz), style: theme.bodyFont(fontSize: 14)),
          if (promise.brokenPromiseFlag && promise.brokenPromiseDetail != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.implementationQualityColor(GovtPromiseImplementationQuality.poorQualityImplementation)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18,
                      color: theme.implementationQualityColor(
                          GovtPromiseImplementationQuality.poorQualityImplementation)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(promise.brokenPromiseDetail!, style: theme.bodyFont(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  if (promise.implementationQuality != null)
                    _Stat(
                      label: 'Implementation',
                      value: promise.implementationQuality!.label,
                      color: qualityColor,
                    ),
                  _Stat(
                    label: 'Confidence',
                    value: promise.verificationConfidence.name,
                  ),
                  if (promise.budgetAllocatedCrore != null)
                    _Stat(
                      label: 'Budget (₹ crore)',
                      value: promise.budgetSpentCrore != null
                          ? '${promise.budgetSpentCrore} / ${promise.budgetAllocatedCrore}'
                          : '${promise.budgetAllocatedCrore}',
                    ),
                ],
              ),
            ),
          ),
          if (promise.officialClaim != null || promise.groundReality != null) ...[
            const SizedBox(height: 20),
            Text('Official Claim vs. Ground Reality',
                style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (promise.officialClaim != null)
              _ClaimCard(
                icon: Icons.campaign_outlined,
                label: 'Official claim',
                text: promise.officialClaim!,
                theme: theme,
              ),
            if (promise.groundReality != null) ...[
              const SizedBox(height: 8),
              _ClaimCard(
                icon: Icons.fact_check_outlined,
                label: 'Ground reality',
                text: promise.groundReality!,
                theme: theme,
              ),
            ],
          ],
          if (promise.nextMilestone != null) ...[
            const SizedBox(height: 20),
            Text('Next Milestone', style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(promise.nextMilestone!, style: theme.bodyFont(fontSize: 13, color: theme.textMuted)),
          ],
          const SizedBox(height: 20),
          Text('Evidence Timeline', style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          evidenceAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(
              'Failed to load evidence: $error',
              style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
            ),
            data: (evidence) {
              if (evidence.isEmpty) {
                return Text(
                  'No independent evidence recorded yet.',
                  style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                );
              }
              return Column(
                children: [for (final item in evidence) _EvidenceTile(evidence: item, theme: theme)],
              );
            },
          ),
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({required this.icon, required this.label, required this.text, required this.theme});

  final IconData icon;
  final String label;
  final String text;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.bodyFont(fontSize: 11, fontWeight: FontWeight.w700, color: theme.textMuted)),
                const SizedBox(height: 4),
                Text(text, style: theme.bodyFont(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.evidence, required this.theme});

  final PromiseEvidence evidence;
  final AppThemeData theme;

  IconData get _sourceIcon {
    switch (evidence.sourceType) {
      case PromiseEvidenceSourceType.parliamentQa:
        return Icons.gavel_outlined;
      case PromiseEvidenceSourceType.cagReport:
        return Icons.receipt_long_outlined;
      case PromiseEvidenceSourceType.prsLegislative:
        return Icons.menu_book_outlined;
      case PromiseEvidenceSourceType.newsArticle:
        return Icons.newspaper_outlined;
      case PromiseEvidenceSourceType.officialPib:
        return Icons.account_balance_outlined;
      case PromiseEvidenceSourceType.mygovSchemePage:
        return Icons.public_outlined;
      case PromiseEvidenceSourceType.manifestoPdf:
        return Icons.description_outlined;
      case PromiseEvidenceSourceType.budgetDocument:
        return Icons.request_quote_outlined;
      case PromiseEvidenceSourceType.other:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stanceColor = theme.promiseEvidenceStanceColor(evidence.stance);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_sourceIcon, size: 16, color: theme.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        evidence.sourceType.label,
                        style: theme.bodyFont(fontSize: 11, fontWeight: FontWeight.w700, color: theme.textMuted),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: stanceColor),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM d, yyyy').format(evidence.observedAt.toLocal()),
                        style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(evidence.excerptSummary, style: theme.bodyFont(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
