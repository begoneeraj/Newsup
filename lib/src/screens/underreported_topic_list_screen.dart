import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/underreported_topic_providers.dart';
import '../theme/theme_providers.dart';
import '../widgets/account_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/underreported_topic_card.dart';

class UnderreportedTopicListScreen extends ConsumerWidget {
  const UnderreportedTopicListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(underreportedTopicsProvider);
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Underreported'),
        actions: const [AccountAvatarAction(), SizedBox(width: 4)],
      ),
      body: RefreshIndicator(
        color: theme.accent,
        backgroundColor: theme.surface,
        onRefresh: () async {
          ref.invalidate(underreportedTopicsProvider);
          await ref.read(underreportedTopicsProvider.future);
        },
        child: topicsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(child: Text('Failed to load underreported topics: $error')),
            ],
          ),
          data: (topics) {
            if (topics.isEmpty) {
              return const EmptyState(
                icon: Icons.search_off_outlined,
                headline: 'No gaps computed yet',
                subtext:
                    'This compares real PRS/Parliament/CAG records against mainstream news '
                    'coverage for a fixed set of civic topics — check back after the next daily run.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemCount: topics.length,
              itemBuilder: (context, index) {
                final topic = topics[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: UnderreportedTopicCard(
                    topic: topic,
                    onTap: () => context.push('/underreported-topic/${topic.id}', extra: topic),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
