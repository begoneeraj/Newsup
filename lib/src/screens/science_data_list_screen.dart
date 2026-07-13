import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/data_story.dart';
import '../models/science_research.dart';
import '../providers/science_data_providers.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';
import '../widgets/data_story_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/science_research_card.dart';

class ScienceDataListScreen extends ConsumerWidget {
  const ScienceDataListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final researchAsync = ref.watch(scienceResearchReportsProvider);
    final storiesAsync = ref.watch(dataStoriesProvider);
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Science & Data')),
      body: RefreshIndicator(
        color: theme.accent,
        backgroundColor: theme.surface,
        onRefresh: () async {
          ref.invalidate(scienceResearchReportsProvider);
          ref.invalidate(dataStoriesProvider);
          await Future.wait([
            ref.read(scienceResearchReportsProvider.future),
            ref.read(dataStoriesProvider.future),
          ]);
        },
        child: researchAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(child: Text('Failed to load: $error')),
            ],
          ),
          data: (research) {
            return storiesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load data stories: $error')),
                ],
              ),
              data: (stories) {
                if (research.isEmpty && stories.isEmpty) {
                  return const EmptyState(
                    icon: Icons.insights_outlined,
                    headline: 'Nothing here yet',
                    subtext:
                        'Science & research coverage and data-driven stories are generated '
                        'automatically as new findings and dataset updates come in.',
                  );
                }
                return CustomScrollView(
                  slivers: [
                    const SliverPadding(padding: EdgeInsets.only(top: 8)),
                    if (stories.isNotEmpty) ..._dataStorySection(stories, theme),
                    if (research.isNotEmpty) ..._researchSection(research, theme),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<Widget> _dataStorySection(List<DataStory> stories, AppThemeData theme) {
    return [
      _sectionHeader('Data Stories', theme),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DataStoryCard(story: stories[index]),
          ),
          childCount: stories.length,
        ),
      ),
    ];
  }

  List<Widget> _researchSection(List<ScienceResearchReport> research, AppThemeData theme) {
    return [
      _sectionHeader('Science & Research', theme),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ScienceResearchCard(report: research[index]),
          ),
          childCount: research.length,
        ),
      ),
    ];
  }

  Widget _sectionHeader(String title, AppThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(
          title,
          style: theme.bodyFont(fontSize: 13, fontWeight: FontWeight.w800, color: theme.textMuted),
        ),
      ),
    );
  }
}
