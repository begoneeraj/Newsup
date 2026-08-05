import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/slow_crisis.dart';
import '../theme/theme_providers.dart';
import 'app_card.dart';
import 'status_badge.dart';

class SlowCrisisCard extends ConsumerWidget {
  const SlowCrisisCard({super.key, required this.crisis, required this.onTap});

  final SlowCrisis crisis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;
    final color = theme.slowCrisisSeverityColor(crisis.currentSeverity);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  crisis.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.displayFont(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (crisis.currentSeverity != null) ...[
                const SizedBox(width: 8),
                StatusBadge(label: crisis.currentSeverity!.label, color: color),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.category_outlined, size: 14, color: theme.textMuted),
              const SizedBox(width: 4),
              Text(crisis.category.label, style: theme.bodyFont(fontSize: 12, color: theme.textMuted)),
              if (crisis.region != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.place_outlined, size: 14, color: theme.textMuted),
                const SizedBox(width: 4),
                Text(crisis.region!, style: theme.bodyFont(fontSize: 12, color: theme.textMuted)),
              ],
            ],
          ),
          if (crisis.displayDescription(genz) != null) ...[
            const SizedBox(height: 8),
            Text(
              crisis.displayDescription(genz)!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
