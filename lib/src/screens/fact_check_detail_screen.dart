import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../theme/theme_providers.dart';
import '../utils/safe_launch.dart';
import '../widgets/bookmark_button.dart';
import '../widgets/confidence_meter.dart';
import '../widgets/coverage_section.dart';
import '../widgets/fact_check_v2_section.dart';
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
    final theme = ref.watch(appThemeDataProvider);
    final color = theme.statusColor(factCheck.status);
    final dateFormat = DateFormat('d MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fact Check'),
        actions: [
          BookmarkButton(id: factCheck.id),
          IconButton(
            tooltip: 'Share verdict',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => showShareCardSheet(context, ref, factCheck),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              StatusStamp(status: factCheck.status),
              const Spacer(),
              Text(
                dateFormat.format(factCheck.createdAt),
                style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            factCheck.claimText,
            style: theme.displayFont(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            factCheck.origin,
            style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: theme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConfidenceMeter(
                  confidence: factCheck.evidenceConfidence,
                  color: color,
                  showLabel: true,
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: theme.border),
                const SizedBox(height: 12),
                _StatRow(label: 'Source reliability', value: factCheck.sourceReliability.label),
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
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Expert Analysis',
            initiallyExpanded: true,
            child: Text(
              factCheck.expertAnalysis ?? 'No expert analysis available yet.',
              style: theme.bodyFont(fontSize: 15, color: theme.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Sources (${factCheck.sources.length})',
            child: factCheck.sources.isEmpty
                ? Text(
                    'No linked source for this item yet.',
                    style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final source in factCheck.sources)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: source.url.isEmpty
                                ? null
                                : () => launchSecureUrl(source.url, mode: LaunchMode.externalApplication),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  source.title,
                                  style: theme.bodyFont(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                if (source.url.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          source.url,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.bodyFont(fontSize: 12, color: theme.accent),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.open_in_new, size: 12, color: theme.accent),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  dateFormat.format(source.publishedAt),
                                  style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          CoverageSection(factCheckId: factCheck.id),
          FactCheckV2Section(factCheckId: factCheck.id),
        ],
      ),
    );
  }
}

class _SectionCard extends ConsumerWidget {
  const _SectionCard({required this.title, required this.child, this.initiallyExpanded = false});

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(title, style: theme.displayFont(fontSize: 16, fontWeight: FontWeight.w600)),
          initiallyExpanded: initiallyExpanded,
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: [child],
        ),
      ),
    );
  }
}

class _StatRow extends ConsumerWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.bodyFont(fontSize: 13, color: theme.textMuted)),
          Text(value, style: theme.bodyFont(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
