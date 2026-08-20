import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/fact_check.dart';
import '../providers/auth_providers.dart';
import '../providers/fact_check_providers.dart';
import '../providers/onboarding_providers.dart';
import '../theme/app_theme_data.dart';
import '../theme/app_voice.dart';
import '../theme/theme_providers.dart';
import '../utils/greeting.dart';
import '../utils/time_ago.dart';
import '../widgets/account_button.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/category_nav_card.dart';
import '../widgets/circular_icon_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/fact_check_card.dart';
import '../widgets/filter_tabs_bar.dart';
import '../widgets/genz_coach_mark.dart';
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
  final _genzToggleLink = LayerLink();
  OverlayEntry? _genzCoachMark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowGenzCoachMark());
  }

  @override
  void dispose() {
    _genzCoachMark?.remove();
    super.dispose();
  }

  void _maybeShowGenzCoachMark() {
    if (!mounted) return;
    final prefs = ref.read(sharedPreferencesProvider);
    if (hasSeenGenzCoachMark(prefs)) return;
    if (ref.read(voiceModeProvider) == AppVoice.genz) return;

    _genzCoachMark = GenzCoachMark.show(
      context: context,
      link: _genzToggleLink,
      theme: ref.read(appThemeDataProvider),
      onDismiss: _dismissGenzCoachMark,
    );
  }

  void _dismissGenzCoachMark() {
    _genzCoachMark = null;
    if (mounted) markGenzCoachMarkSeen(ref);
  }

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

    final user = ref.watch(currentUserProvider);
    final firstName = firstNameFrom(displayName: user?.displayName, email: user?.email);
    final greeting = timeOfDayGreeting(DateTime.now());

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          firstName == null ? '$greeting 👋' : '$greeting, $firstName 👋',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodyFont(fontSize: 14, fontWeight: FontWeight.w600, color: theme.textMuted),
                        ),
                      ),
                      CircularIconButton(
                        tooltip: 'Notifications',
                        icon: Icons.notifications_none_rounded,
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("You're all caught up")),
                        ),
                      ),
                      CircularIconButton(
                        tooltip: 'National data',
                        icon: Icons.query_stats,
                        onPressed: () => context.push('/national-data'),
                      ),
                      CircularIconButton(
                        tooltip: brightness == Brightness.dark ? 'Switch to light mode' : 'Switch to dark mode',
                        icon: brightness == Brightness.dark ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                        onPressed: () => toggleBrightness(ref),
                      ),
                      const AccountAvatarAction(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Fact', style: theme.displayFont(fontSize: 28, fontWeight: FontWeight.w800)),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [theme.accent, AppSectionColors.underreported],
                        ).createShader(bounds),
                        child: Text(
                          'Check',
                          style: theme.displayFont(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      CompositedTransformTarget(
                        link: _genzToggleLink,
                        child: CircularIconButton(
                          tooltip: voice == AppVoice.genz ? 'Switch to Normal voice' : 'Switch to Genz voice',
                          icon: voice == AppVoice.genz ? Icons.mood : Icons.gpp_good_rounded,
                          onPressed: () {
                            if (_genzCoachMark != null) {
                              _genzCoachMark!.remove();
                              _dismissGenzCoachMark();
                            }
                            toggleVoiceMode(ref);
                          },
                        ),
                      ),
                    ],
                  ),
                  Text(
                    newest != null ? 'Trusted facts. Updated ${timeAgo(newest)}.' : 'Trusted facts. Clearer world.',
                    style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w500, color: theme.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AppSearchBar(
              hintText: 'Search fact checks…',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: CategoryNavCard(
                    label: 'Government Promises',
                    icon: Icons.account_balance_rounded,
                    color: AppSectionColors.govtPromises,
                    onTap: () => Navigator.of(context).push(
                      slideFadeRoute(const GovtPromiseListScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CategoryNavCard(
                    label: 'Science & Data',
                    icon: Icons.science_rounded,
                    color: theme.accent,
                    onTap: () => Navigator.of(context).push(
                      slideFadeRoute(const ScienceDataListScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
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

