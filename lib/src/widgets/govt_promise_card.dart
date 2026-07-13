import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/govt_promise.dart';
import '../providers/govt_promise_providers.dart';
import '../theme/theme_providers.dart';
import '../utils/time_ago.dart';

class GovtPromiseCard extends ConsumerWidget {
  const GovtPromiseCard({super.key, required this.promise, required this.onTap});

  final GovtPromise promise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;
    final qualityColor = theme.implementationQualityColor(promise.implementationQuality);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: qualityColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _Badge(label: promise.currentStatus.label, color: theme.textMuted),
                          if (promise.implementationQuality != null)
                            _Badge(
                              label: promise.implementationQuality!.label,
                              color: qualityColor,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        promise.projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        promise.displaySummary(genz),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.account_balance_outlined, size: 14, color: theme.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              promise.announcingBody,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                            ),
                          ),
                          Text(
                            timeAgo(promise.lastUpdated),
                            style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
                          ),
                        ],
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final evidenceAsync = ref.watch(promiseEvidenceProvider(promise.id));
                          return evidenceAsync.maybeWhen(
                            data: (evidence) {
                              if (evidence.isEmpty) return const SizedBox.shrink();
                              final independentCount =
                                  evidence.where((e) => e.sourceType.isIndependent).length;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.fact_check_outlined, size: 14, color: theme.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${evidence.length} evidence'
                                      '${independentCount > 0 ? ' · $independentCount independent' : ''}',
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

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
