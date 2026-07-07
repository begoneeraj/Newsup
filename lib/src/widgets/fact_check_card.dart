import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../theme/theme_providers.dart';
import '../utils/time_ago.dart';
import 'confidence_meter.dart';
import 'share_card_sheet.dart';
import 'source_monogram.dart';
import 'status_stamp.dart';

class FactCheckCard extends ConsumerWidget {
  const FactCheckCard({super.key, required this.factCheck, required this.onTap});

  final FactCheck factCheck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;
    final color = theme.statusColor(factCheck.status);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusStamp(status: factCheck.status),
                          const Spacer(),
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => showShareCardSheet(context, ref, factCheck),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.share_outlined, size: 18, color: theme.textMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        factCheck.displayClaim(genz),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.displayFont(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SourceMonogram(origin: factCheck.origin),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              factCheck.origin,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                            ),
                          ),
                          Text(
                            timeAgo(factCheck.createdAt),
                            style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: theme.border),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.people_outline, size: 14, color: theme.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${factCheck.independentConfirmations} confirmations'
                              '${factCheck.officialConfirmation ? ' · official' : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                            ),
                          ),
                          ConfidenceMeter(confidence: factCheck.evidenceConfidence, color: color),
                        ],
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final coverageAsync = ref.watch(coverageAnalysisProvider(factCheck.id));
                          return coverageAsync.maybeWhen(
                            data: (coverage) {
                              if (coverage == null || coverage.totalOutlets == 0) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.newspaper_outlined, size: 14, color: theme.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reported by ${coverage.totalOutlets} outlets',
                                      style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                                    ),
                                  ],
                                ),
                              );
                            },
                            orElse: () => const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
