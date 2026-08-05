import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/govt_promise.dart';
import '../providers/govt_promise_providers.dart';
import '../theme/theme_providers.dart';
import '../widgets/app_filter_chip.dart';
import '../widgets/empty_state.dart';
import '../widgets/govt_promise_card.dart';
import '../widgets/staggered_fade_slide.dart';

class GovtPromiseListScreen extends ConsumerWidget {
  const GovtPromiseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promisesAsync = ref.watch(filteredGovtPromisesProvider);
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Govt Promises')),
      body: RefreshIndicator(
        color: theme.accent,
        backgroundColor: theme.surface,
        onRefresh: () async {
          ref.invalidate(govtPromisesProvider);
          await ref.read(govtPromisesProvider.future);
        },
        child: Column(
          children: [
            const _GovtPromiseFilterBar(),
            Expanded(
              child: promisesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => ListView(
                  children: [
                    const SizedBox(height: 80),
                    Center(child: Text('Failed to load promises: $error')),
                  ],
                ),
                data: (promises) {
                  if (promises.isEmpty) {
                    return const EmptyState(
                      icon: Icons.handshake_outlined,
                      headline: 'No promises match this filter',
                      subtext:
                          'Government promises are tracked automatically from news, budget '
                          'documents, and manifesto pledges across monitored sources.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    itemCount: promises.length,
                    itemBuilder: (context, index) {
                      final promise = promises[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: StaggeredFadeSlide(
                          index: index,
                          child: GovtPromiseCard(
                            promise: promise,
                            onTap: () => context.push('/promise/${promise.id}'),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GovtPromiseFilterBar extends ConsumerWidget {
  const _GovtPromiseFilterBar();

  static const _statusOptions = <String, GovtPromiseStatus?>{
    'All': null,
    'Announced': GovtPromiseStatus.announced,
    'Started': GovtPromiseStatus.started,
    'Ongoing': GovtPromiseStatus.ongoing,
    'Delayed': GovtPromiseStatus.delayed,
    'Stalled': GovtPromiseStatus.stalled,
    'Completed': GovtPromiseStatus.completed,
  };

  static const _qualityOptions = <String, GovtPromiseImplementationQuality?>{
    'Any quality': null,
    'Fully Implemented': GovtPromiseImplementationQuality.fullyImplemented,
    'Partially Implemented': GovtPromiseImplementationQuality.partiallyImplemented,
    'On Paper Only': GovtPromiseImplementationQuality.onPaperOnly,
    'Poor Quality': GovtPromiseImplementationQuality.poorQualityImplementation,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final filter = ref.watch(govtPromiseFilterProvider);
    final allPromises = ref.watch(govtPromisesProvider).valueOrNull ?? const [];

    final parties = allPromises.map((p) => p.party).whereType<String>().toSet().toList()..sort();
    final years = allPromises.map((p) => p.electionYear).whereType<int>().toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        FilterChipRow(
          children: [
            for (final entry in _statusOptions.entries)
              AppFilterChip(
                label: entry.key,
                selected: filter.status == entry.value,
                color: theme.accent,
                onTap: () => ref.read(govtPromiseFilterProvider.notifier).state =
                    filter.copyWith(status: () => entry.value),
              ),
          ],
        ),
        FilterChipRow(
          children: [
            for (final entry in _qualityOptions.entries)
              AppFilterChip(
                label: entry.key,
                selected: filter.implementationQuality == entry.value,
                color: theme.implementationQualityColor(entry.value),
                onTap: () => ref.read(govtPromiseFilterProvider.notifier).state =
                    filter.copyWith(implementationQuality: () => entry.value),
              ),
          ],
        ),
        if (parties.isNotEmpty || years.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              children: [
                if (parties.isNotEmpty)
                  Expanded(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: filter.party,
                      hint: Text('Party', style: theme.bodyFont(fontSize: 13, color: theme.textMuted)),
                      items: [
                        DropdownMenuItem(value: null, child: Text('All parties', style: theme.bodyFont(fontSize: 13))),
                        for (final party in parties)
                          DropdownMenuItem(value: party, child: Text(party, style: theme.bodyFont(fontSize: 13))),
                      ],
                      onChanged: (value) => ref.read(govtPromiseFilterProvider.notifier).state =
                          filter.copyWith(party: () => value),
                    ),
                  ),
                if (parties.isNotEmpty && years.isNotEmpty) const SizedBox(width: 12),
                if (years.isNotEmpty)
                  Expanded(
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: filter.electionYear,
                      hint: Text('Election year', style: theme.bodyFont(fontSize: 13, color: theme.textMuted)),
                      items: [
                        DropdownMenuItem(value: null, child: Text('All years', style: theme.bodyFont(fontSize: 13))),
                        for (final year in years)
                          DropdownMenuItem(value: year, child: Text('$year', style: theme.bodyFont(fontSize: 13))),
                      ],
                      onChanged: (value) => ref.read(govtPromiseFilterProvider.notifier).state =
                          filter.copyWith(electionYear: () => value),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
