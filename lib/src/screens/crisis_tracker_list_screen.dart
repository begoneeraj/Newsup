import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/public_event.dart';
import '../providers/public_event_providers.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/pinned_stats_banner.dart';
import '../widgets/public_event_card.dart';
import '../widgets/staggered_fade_slide.dart';

/// Reads from public_events (dual-written from fact_checks/crisis_reports/
/// crises — see src/pipeline/public_events.py), not crisis_reports directly.
/// crisis_reports only ever gets rows from the Reddit-sourced crisis-hunting
/// fetcher, which can be (and has been) structurally empty if that source
/// goes quiet/blocked; public_events is populated from every source.
///
/// Cards are grouped into three sections — Active Crises (weather/disaster/
/// violence, highest visibility), Exam Issues (leaks/delays, developing
/// over days-to-weeks rather than acute), and everything else — over the
/// already-deduped list from publicEventsProvider (dedup itself happens
/// server-side, see src/pipeline/public_events.py::find_or_merge_public_event).
///
/// Below those Supabase-backed sections is a separate "Live Sources" feed,
/// independently backed by the Firestore `raw_articles` collection that the
/// fetchGdeltArticles/crisisClassifier Cloud Functions write to (see
/// functions/src/fetchGdeltArticles.ts). It has its own source filter and
/// its own query/stream — deliberately not merged into the sections above,
/// since raw_articles documents (title/url/published_at/source_system) are
/// a different shape than PublicEvent and aren't deduped against it.
const _activeCrisisTypes = {
  PublicEventType.flood,
  PublicEventType.cyclone,
  PublicEventType.earthquake,
  PublicEventType.heatwave,
  PublicEventType.weatherAlert,
  PublicEventType.weatherDisaster,
  PublicEventType.genderViolence,
  PublicEventType.suicideSpree,
  PublicEventType.studentSuicide,
};
const _examIssueTypes = {PublicEventType.examLeak, PublicEventType.examDelay};

enum NewsSourceFilter { all, newsApi, gdelt }

class CrisisTrackerListScreen extends ConsumerStatefulWidget {
  const CrisisTrackerListScreen({super.key});

  @override
  ConsumerState<CrisisTrackerListScreen> createState() => _CrisisTrackerListScreenState();
}

class _CrisisTrackerListScreenState extends ConsumerState<CrisisTrackerListScreen> {
  Set<NewsSourceFilter> _selectedFilter = {NewsSourceFilter.all};

  /// Composite index required for the newsApi/gdelt branches:
  /// (source_system ASC, published_at DESC) on `raw_articles`. Defined in
  /// functions/src/fetchGdeltArticles.ts's header comment and merged into
  /// firestore.indexes.json — deploy with `firebase deploy --only
  /// firestore:indexes` before these filtered queries will work.
  Query<Map<String, dynamic>> _buildQuery() {
    final collection = FirebaseFirestore.instance.collection('raw_articles');

    switch (_selectedFilter.first) {
      case NewsSourceFilter.all:
        return collection.orderBy('published_at', descending: true);
      case NewsSourceFilter.newsApi:
        return collection
            .where('source_system', isEqualTo: 'newsapi')
            .orderBy('published_at', descending: true);
      case NewsSourceFilter.gdelt:
        return collection
            .where('source_system', isEqualTo: 'gdelt')
            .orderBy('published_at', descending: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(publicEventsProvider);
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Crisis Tracker')),
      body: Column(
        children: [
          const PinnedStatsBanner(),
          Expanded(
            child: RefreshIndicator(
              color: theme.accent,
              backgroundColor: theme.surface,
              onRefresh: () async {
                ref.invalidate(publicEventsProvider);
                await ref.read(publicEventsProvider.future);
              },
              child: eventsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => ListView(
                  children: [
                    const SizedBox(height: 80),
                    Center(child: Text('Failed to load crisis alerts: $error')),
                  ],
                ),
                data: (events) {
                  final active = events.where((e) => _activeCrisisTypes.contains(e.eventType)).toList();
                  final exams = events.where((e) => _examIssueTypes.contains(e.eventType)).toList();
                  final more = events
                      .where((e) => !_activeCrisisTypes.contains(e.eventType) && !_examIssueTypes.contains(e.eventType))
                      .toList();

                  return CustomScrollView(
                    slivers: [
                      const SliverPadding(padding: EdgeInsets.only(top: 8)),
                      if (events.isEmpty)
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: const EmptyState(
                              icon: Icons.monitor_heart_outlined,
                              headline: 'No active crisis alerts',
                              subtext:
                                  'Public events are generated automatically from news, RTI '
                                  'escalations, and crisis-relevant keywords across monitored '
                                  'sources.',
                            ),
                          ),
                        ),
                      if (active.isNotEmpty) ..._section('Active Crises', active, theme),
                      if (exams.isNotEmpty) ..._section('Exam Issues', exams, theme),
                      if (more.isNotEmpty) ..._section('More', more, theme),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                          child: Text(
                            'Live Sources',
                            style: theme.bodyFont(fontSize: 13, fontWeight: FontWeight.w800, color: theme.textMuted),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _SourceFilterBar(
                            selected: _selectedFilter,
                            onSelectionChanged: (selection) => setState(() => _selectedFilter = selection),
                          ),
                        ),
                      ),
                      const SliverPadding(padding: EdgeInsets.only(top: 8)),
                      _liveSourcesSliver(theme),
                      const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveSourcesSliver(AppThemeData theme) {
    return SliverToBoxAdapter(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            final isMissingIndex = error is FirebaseException && error.code == 'failed-precondition';

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                isMissingIndex
                    ? 'Index not ready — run: firebase deploy --only firestore:indexes'
                    : 'Failed to load live sources: $error',
                style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                'No live articles for this source yet.',
                style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
              ),
            );
          }

          return Column(
            children: [
              for (final doc in docs) _LiveArticleTile(data: doc.data(), theme: theme),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _section(String title, List<PublicEvent> events, AppThemeData theme) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            title,
            style: theme.bodyFont(fontSize: 13, fontWeight: FontWeight.w800, color: theme.textMuted),
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final event = events[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: StaggeredFadeSlide(
                index: index,
                child: PublicEventCard(
                  event: event,
                  onTap: () => context.push('/crisis/${event.id}'),
                ),
              ),
            );
          },
          childCount: events.length,
        ),
      ),
    ];
  }
}

class _SourceFilterBar extends StatelessWidget {
  const _SourceFilterBar({required this.selected, required this.onSelectionChanged});

  final Set<NewsSourceFilter> selected;
  final ValueChanged<Set<NewsSourceFilter>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<NewsSourceFilter>(
      segments: const [
        ButtonSegment(value: NewsSourceFilter.all, label: Text('All')),
        ButtonSegment(value: NewsSourceFilter.newsApi, label: Text('NewsAPI')),
        ButtonSegment(value: NewsSourceFilter.gdelt, label: Text('GDELT')),
      ],
      selected: selected,
      multiSelectionEnabled: false,
      emptySelectionAllowed: false,
      showSelectedIcon: false,
      onSelectionChanged: onSelectionChanged,
    );
  }
}

class _LiveArticleTile extends StatelessWidget {
  const _LiveArticleTile({required this.data, required this.theme});

  final Map<String, dynamic> data;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] as String?)?.trim();
    final source = (data['source'] as String?)?.trim();
    final sourceSystem = (data['source_system'] as String?)?.trim();
    final publishedAt = data['published_at'] as String?;

    String? relativeTime;
    if (publishedAt != null) {
      final parsed = DateTime.tryParse(publishedAt);
      if (parsed != null) {
        relativeTime = DateFormat('MMM d, HH:mm').format(parsed.toLocal());
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (title == null || title.isEmpty) ? '(untitled)' : title,
              style: theme.bodyFont(fontSize: 14, fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (sourceSystem != null && sourceSystem.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      sourceSystem,
                      style: theme.monoFont(fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(width: 8),
                if (source != null && source.isNotEmpty)
                  Expanded(
                    child: Text(
                      source,
                      style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (relativeTime != null)
                  Text(
                    relativeTime,
                    style: theme.bodyFont(fontSize: 11, color: theme.textMuted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
