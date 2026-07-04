import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../theme/theme_providers.dart';

/// Color-coded pill/segmented filter tabs with live counts per verdict, so
/// users can see the distribution of the feed without tapping into each tab.
class FilterTabsBar extends ConsumerWidget {
  const FilterTabsBar({super.key});

  static const _options = <String, FactCheckStatus?>{
    'All': null,
    'Verified': FactCheckStatus.verified,
    'False': FactCheckStatus.falseClaim,
    'Misleading': FactCheckStatus.misleading,
    'Unverified': FactCheckStatus.unverified,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(factCheckFilterProvider);
    final theme = ref.watch(appThemeDataProvider);
    final allFactChecks = ref.watch(factChecksProvider).valueOrNull ?? const [];

    int countFor(FactCheckStatus? status) {
      if (status == null) return allFactChecks.length;
      return allFactChecks.where((fc) => fc.status == status).length;
    }

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: _options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = _options.keys.elementAt(index);
          final value = _options.values.elementAt(index);
          final isSelected = selected == value;
          final count = countFor(value);
          final color = value == null ? theme.accent : theme.statusColor(value);

          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => ref.read(factCheckFilterProvider.notifier).state = value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: isSelected ? color.withValues(alpha: 0.18) : theme.surface,
                border: Border.all(
                  color: isSelected ? color : theme.border,
                  width: isSelected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.bodyFont(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? color : theme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: isSelected ? color.withValues(alpha: 0.28) : theme.border,
                    ),
                    child: Text(
                      '$count',
                      style: theme.monoFont(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? color : theme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
