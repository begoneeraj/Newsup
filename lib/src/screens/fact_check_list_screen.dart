import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../theme/app_voice.dart';
import '../theme/theme_providers.dart';
import '../utils/time_ago.dart';
import '../widgets/empty_state.dart';
import '../widgets/fact_check_card.dart';
import '../widgets/filter_tabs_bar.dart';
import '../widgets/staggered_fade_slide.dart';

class FactCheckListScreen extends ConsumerWidget {
  const FactCheckListScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
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
          IconButton(
            tooltip: voice == AppVoice.genz ? 'Switch to Normal voice' : 'Switch to Genz voice',
            icon: Icon(voice == AppVoice.genz ? Icons.mood : Icons.work_outline),
            onPressed: () => toggleVoiceMode(ref),
          ),
          IconButton(
            tooltip: brightness == Brightness.dark ? 'Switch to light mode' : 'Switch to dark mode',
            icon: Icon(brightness == Brightness.dark ? Icons.wb_sunny_outlined : Icons.nightlight_round),
            onPressed: () => toggleBrightness(ref),
          ),
        ],
      ),
      body: Column(
        children: [
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
                data: (factChecks) {
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
                    padding: const EdgeInsets.only(bottom: 12, top: 4),
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
