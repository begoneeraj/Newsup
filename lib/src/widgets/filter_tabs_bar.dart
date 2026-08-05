import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../theme/theme_providers.dart';
import 'app_filter_chip.dart';

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

    return FilterChipRow(
      children: [
        for (final entry in _options.entries)
          AppFilterChip(
            label: entry.key,
            selected: selected == entry.value,
            color: entry.value == null ? theme.accent : theme.statusColor(entry.value!),
            onTap: () => ref.read(factCheckFilterProvider.notifier).state = entry.value,
            trailing: _CountPill(
              count: countFor(entry.value),
              selected: selected == entry.value,
              color: entry.value == null ? theme.accent : theme.statusColor(entry.value!),
            ),
          ),
      ],
    );
  }
}

class _CountPill extends ConsumerWidget {
  const _CountPill({required this.count, required this.selected, required this.color});

  final int count;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: selected ? color.withValues(alpha: 0.28) : theme.border,
      ),
      child: Text(
        '$count',
        style: theme.monoFont(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? color : theme.textMuted,
        ),
      ),
    );
  }
}
