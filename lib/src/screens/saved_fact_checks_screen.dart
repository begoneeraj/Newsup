import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/bookmark_provider.dart';
import '../providers/fact_check_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/fact_check_card.dart';
import '../widgets/staggered_fade_slide.dart';

/// The "Saved" tab — every fact check the user has bookmarked, newest first.
/// Bookmarks are a local-only id set (see BookmarksNotifier); this screen
/// just filters the same factChecksProvider list everyone else reads by
/// that id set, so a card's bookmark state (and this list) stay in sync
/// automatically with whatever BookmarkButton the user tapped elsewhere.
class SavedFactChecksScreen extends ConsumerWidget {
  const SavedFactChecksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider);
    final factChecksAsync = ref.watch(savedFactChecksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: factChecksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ListView(
          children: [
            const SizedBox(height: 80),
            Center(child: Text('Failed to load saved fact checks: $error')),
          ],
        ),
        data: (allFactChecks) {
          final saved =
              allFactChecks.where((fc) => bookmarks.contains(fc.id)).toList();
          if (saved.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: const EmptyState(
                    icon: Icons.bookmark_border_rounded,
                    headline: 'Nothing saved yet',
                    subtext:
                        'Tap the bookmark icon on any fact check to keep it here.',
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 100, top: 4),
            itemCount: saved.length,
            itemBuilder: (context, index) {
              final fc = saved[index];
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
    );
  }
}
