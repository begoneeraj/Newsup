import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/slow_crisis_providers.dart';
import '../theme/theme_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/slow_crisis_card.dart';

class SlowCrisisListScreen extends ConsumerWidget {
  const SlowCrisisListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crisesAsync = ref.watch(slowCrisesProvider);
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Slow Crises')),
      body: RefreshIndicator(
        color: theme.accent,
        backgroundColor: theme.surface,
        onRefresh: () async {
          ref.invalidate(slowCrisesProvider);
          await ref.read(slowCrisesProvider.future);
        },
        child: crisesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(child: Text('Failed to load slow crises: $error')),
            ],
          ),
          data: (crises) {
            if (crises.isEmpty) {
              return const EmptyState(
                icon: Icons.trending_down_outlined,
                headline: 'No tracked crises yet',
                subtext:
                    'Slow crises track structural problems — air quality, water, court '
                    'backlogs — using official data, not breaking news.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              itemCount: crises.length,
              itemBuilder: (context, index) {
                final crisis = crises[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SlowCrisisCard(
                    crisis: crisis,
                    onTap: () => context.push('/slow-crisis/${crisis.id}'),
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
