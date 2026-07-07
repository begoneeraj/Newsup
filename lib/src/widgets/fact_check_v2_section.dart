import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check_v2.dart';
import '../providers/fact_check_providers.dart';

/// Feature 3 (legally-safe truthfulness scoring). Renders exactly what
/// fact_checks_v2 stores — claim, status, official-source evidence, and (if
/// DISPUTED) both perspectives equally. Never renders outlet-accusatory
/// language; that constraint lives in the Groq prompt
/// (src/ai_processor/groq_processor.py::_FACT_CHECK_V2_SYSTEM_PROMPT), not here.
class FactCheckV2Section extends ConsumerWidget {
  const FactCheckV2Section({super.key, required this.factCheckId});

  final String factCheckId;

  Color _statusColor(FactCheckV2Status status) {
    switch (status) {
      case FactCheckV2Status.verified:
        return const Color(0xFF22C55E);
      case FactCheckV2Status.disputed:
        return const Color(0xFFF59E0B);
      case FactCheckV2Status.needsMoreInfo:
        return const Color(0xFF60A5FA);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v2Async = ref.watch(factCheckV2Provider(factCheckId));

    return v2Async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (v2) {
        if (v2 == null) return const SizedBox.shrink();
        final color = _statusColor(v2.status);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: color.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '${v2.status.emoji} ${v2.status.label}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: color, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(v2.confidence * 100).round()}% confidence',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(v2.claim, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(v2.verdict, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            if (v2.evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text('Official Evidence (${v2.evidence.length})'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [for (final item in v2.evidence) _EvidenceRow(item: item)],
              ),
            ],
            if (v2.status == FactCheckV2Status.disputed && v2.perspectives != null) ...[
              const SizedBox(height: 12),
              Text('Perspectives', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PerspectiveCard(
                      label: 'Pro',
                      perspective: v2.perspectives!.pro,
                      color: const Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PerspectiveCard(
                      label: 'Against',
                      perspective: v2.perspectives!.against,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.item});

  final EvidenceItemV2 item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.source,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (item.url != null) const Icon(Icons.open_in_new, size: 16, color: Colors.white54),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '"${item.extractedQuote}"',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}

class _PerspectiveCard extends StatelessWidget {
  const _PerspectiveCard({required this.label, required this.perspective, required this.color});

  final String label;
  final Perspective perspective;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(perspective.summary, style: Theme.of(context).textTheme.bodySmall),
          if (perspective.sources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              perspective.sources.join(', '),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54),
            ),
          ],
        ],
      ),
    );
  }
}
