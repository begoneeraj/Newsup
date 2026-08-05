import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../theme/app_theme_data.dart';
import '../theme/app_voice.dart';
import '../theme/theme_providers.dart';
import '../utils/time_ago.dart';
import '../widgets/account_button.dart';
import '../widgets/app_filter_chip.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/circular_icon_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/fact_check_card.dart';
import '../widgets/filter_tabs_bar.dart';
import '../widgets/staggered_fade_slide.dart';
import '../utils/page_transitions.dart';
import 'govt_promise_list_screen.dart';
import 'reality_feed_screen.dart';
import 'science_data_list_screen.dart';

class FactCheckListScreen extends ConsumerStatefulWidget {
  const FactCheckListScreen({super.key});

  @override
  ConsumerState<FactCheckListScreen> createState() => _FactCheckListScreenState();
}

class _FactCheckListScreenState extends ConsumerState<FactCheckListScreen> {
  String _query = '';

  (IconData, String, String) _emptyStateFor(FactCheckStatus? filter) {
    switch (filter) {
      case null:
        return (
          Icons.shield_outlined,
          'Nothing flagged yet',
          'The pipeline is watching monitored sources — new fact checks will appear here as they\'re verified.',
        );
      case FactCheckStatus.verified:
        return (
          Icons.verified_outlined,
          'No verified claims yet',
          'Nothing has cleared verification in this feed so far.',
        );
      case FactCheckStatus.falseClaim:
        return (
          Icons.search_outlined,
          'No false claims flagged right now',
          'The pipeline is still watching — nothing debunked in this feed at the moment.',
        );
      case FactCheckStatus.misleading:
        return (
          Icons.search_outlined,
          'No misleading claims flagged right now',
          'The pipeline is still watching — this is a good sign, not a broken feed.',
        );
      default:
        return (
          Icons.hourglass_empty,
          'Nothing unverified right now',
          'Claims land here while evidence is still being gathered.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(voiceModeProvider) == AppVoice.genz) {
      return const RealityFeedScreen();
    }

    final factChecksAsync = ref.watch(filteredFactChecksProvider);
    final allFactChecksAsync = ref.watch(factChecksProvider);
    final filter = ref.watch(factCheckFilterProvider);
    final voice = ref.watch(voiceModeProvider);
    final brightness = ref.watch(brightnessProvider);
    final theme = ref.watch(appThemeDataProvider);

    final newest = allFactChecksAsync.valueOrNull?.fold<DateTime?>(
      null,
      (latest, fc) => latest == null || fc.createdAt.isAfter(latest) ? fc.createdAt : latest,
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Fact Checks'),
            if (newest != null)
              Text(
                'Updated ${timeAgo(newest)}',
                style: theme.bodyFont(fontSize: 11, fontWeight: FontWeight.w500, color: theme.textMuted),
              ),
          ],
        ),
        actions: [
          CircularIconButton(
            tooltip: 'National data',
            icon: Icons.query_stats,
            onPressed: () => context.push('/national-data'),
          ),
          CircularIconButton(
            tooltip: voice == AppVoice.genz ? 'Switch to Normal voice' : 'Switch to Genz voice',
            icon: voice == AppVoice.genz ? Icons.mood : Icons.work_outline,
            onPressed: () => toggleVoiceMode(ref),
          ),
          CircularIconButton(
            tooltip: brightness == Brightness.dark ? 'Switch to light mode' : 'Switch to dark mode',
            icon: brightness == Brightness.dark ? Icons.wb_sunny_outlined : Icons.nightlight_round,
            onPressed: () => toggleBrightness(ref),
          ),
          const AccountAvatarAction(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: AppSearchBar(
              hintText: 'Search fact checks…',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 6),
          FilterChipRow(
            children: [
              AppFilterChip(
                label: 'Government Promises',
                icon: Icons.handshake_rounded,
                selected: true,
                color: AppSectionColors.govtPromises,
                onTap: () => Navigator.of(context).push(
                  slideFadeRoute(const GovtPromiseListScreen()),
                ),
              ),
              AppFilterChip(
                label: 'Science & Data',
                icon: Icons.science_rounded,
                selected: true,
                color: theme.accent,
                onTap: () => Navigator.of(context).push(
                  slideFadeRoute(const ScienceDataListScreen()),
                ),
              ),
            ],
          ),
          const FilterTabsBar(),
          Expanded(
            child: RefreshIndicator(
              color: theme.accent,
              backgroundColor: theme.surface,
              onRefresh: () async {
                ref.invalidate(factChecksProvider);
                await ref.read(factChecksProvider.future);
              },
              child: factChecksAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => ListView(
                  children: [
                    const SizedBox(height: 80),
                    Center(child: Text('Failed to load fact checks: $error')),
                  ],
                ),
                data: (allFactChecks) {
                  final factChecks = _query.trim().isEmpty
                      ? allFactChecks
                      : allFactChecks
                          .where((fc) => fc.claimText.toLowerCase().contains(_query.trim().toLowerCase()))
                          .toList();
                  if (factChecks.isEmpty) {
                    final (icon, headline, subtext) = _emptyStateFor(filter);
                    return ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: EmptyState(icon: icon, headline: headline, subtext: subtext),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100, top: 4),
                    itemCount: factChecks.length,
                    itemBuilder: (context, index) {
                      final fc = factChecks[index];
                      return StaggeredFadeSlide(
                        index: index,
                        child: FactCheckCard(
                          factCheck: fc,
                          onTap: () => context.push('/fact-check/${fc.id}'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

