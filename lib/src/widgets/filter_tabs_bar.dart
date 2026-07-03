import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../theme/theme_providers.dart';

/// Underline tabs: All / Verified / False / Misleading / Unverified.
/// Deliberately lighter-weight than bordered pills — less visual noise.
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

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 20),
          itemBuilder: (context, index) {
            final label = _options.keys.elementAt(index);
            final value = _options.values.elementAt(index);
            final isSelected = selected == value;
            final color = isSelected ? theme.accent : theme.textMuted;

            return InkWell(
              onTap: () => ref.read(factCheckFilterProvider.notifier).state = value,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? theme.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: theme.bodyFont(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
