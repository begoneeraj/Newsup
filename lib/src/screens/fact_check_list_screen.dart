import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/fact_check_providers.dart';
import '../theme/app_voice.dart';
import '../theme/theme_providers.dart';
import '../widgets/fact_check_card.dart';
import '../widgets/filter_tabs_bar.dart';

class FactCheckListScreen extends ConsumerWidget {
  const FactCheckListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factChecksAsync = ref.watch(filteredFactChecksProvider);
    final voice = ref.watch(voiceModeProvider);
    final brightness = ref.watch(brightnessProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fact Checks'),
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
          const SizedBox(height: 8),
          Expanded(
            child: factChecksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(child: Text('Failed to load fact checks: $error')),
              data: (factChecks) => factChecks.isEmpty
                  ? const Center(child: Text('No fact checks match this filter.'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12, top: 4),
                      itemCount: factChecks.length,
                      itemBuilder: (context, index) {
                        final fc = factChecks[index];
                        return FactCheckCard(
                          factCheck: fc,
                          onTap: () => context.push('/fact-check/${fc.id}'),
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
