import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/fact_check.dart';
import '../providers/fact_check_providers.dart';
import '../providers/user_progress_provider.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/reality_feed/collectible_card.dart';

/// Replaces [FactCheckListScreen] when Genz voice is active — a swipeable
/// deck where the user guesses true/cap before the verdict is revealed.
class RealityFeedScreen extends ConsumerStatefulWidget {
  const RealityFeedScreen({super.key});

  @override
  ConsumerState<RealityFeedScreen> createState() => _RealityFeedScreenState();
}

class _RealityFeedScreenState extends ConsumerState<RealityFeedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dragController;
  Offset _dragOffset = Offset.zero;
  bool _dismissing = false;
  int _cursor = 0;

  static const _commitThreshold = 90.0;

  @override
  void initState() {
    super.initState();
    _dragController = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  }

  @override
  void dispose() {
    _dragController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _dragOffset += details.delta);
  }

  void _onPanEnd(DragEndDetails details, FactCheck fc, List<FactCheck> deck) {
    if (_dragOffset.dx.abs() < _commitThreshold) {
      _snapBack();
      return;
    }
    final guessedTrue = _dragOffset.dx > 0;
    _resolveGuess(fc, guessedTrue, deck);
  }

  void _snapBack() {
    HapticFeedback.selectionClick();
    final anim = Tween<Offset>(begin: _dragOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _dragController, curve: Curves.easeOutBack),
    );
    void tick() => setState(() => _dragOffset = anim.value);
    anim.addListener(tick);
    _dragController.forward(from: 0).whenComplete(() {
      anim.removeListener(tick);
      _dragController.reset();
    });
  }

  Future<void> _resolveGuess(FactCheck fc, bool guessedTrue, List<FactCheck> deck) async {
    HapticFeedback.lightImpact();
    setState(() => _dismissing = true);

    final actuallyTrue = fc.status.countsAsTrueForGuessing;
    final GuessOutcome outcome;
    if (actuallyTrue == null) {
      outcome = GuessOutcome.ungraded;
    } else if (actuallyTrue == guessedTrue) {
      outcome = GuessOutcome.correct;
    } else {
      outcome = GuessOutcome.wrong;
    }

    if (outcome == GuessOutcome.correct) {
      HapticFeedback.mediumImpact();
    }

    ref.read(userProgressProvider.notifier).recordGuess(outcome);

    await Future.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;

    setState(() {
      _cursor = (_cursor + 1).clamp(0, deck.length);
      _dragOffset = Offset.zero;
      _dismissing = false;
    });
  }

  Future<void> _onRefresh() async {
    ref.invalidate(factChecksProvider);
    await ref.read(factChecksProvider.future);
    if (!mounted) return;
    setState(() => _cursor = 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeDataProvider);
    final factChecksAsync = ref.watch(filteredFactChecksProvider);
    final progress = ref.watch(userProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reality Feed'),
        actions: [
          IconButton(
            tooltip: 'National data',
            icon: const Icon(Icons.query_stats, size: 20),
            onPressed: () => context.push('/national-data'),
          ),
          IconButton(
            tooltip: 'Switch to Normal voice',
            icon: const Icon(Icons.work_outline),
            onPressed: () => toggleVoiceMode(ref),
          ),
        ],
      ),
      body: Column(
        children: [
          _StatBar(progress: progress, theme: theme),
          Expanded(
            child: RefreshIndicator(
              color: theme.accent,
              backgroundColor: theme.surface,
              onRefresh: _onRefresh,
              child: factChecksAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 80),
                    Center(child: Text('Failed to load: $error')),
                  ],
                ),
                data: (deck) {
                  if (deck.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(
                          height: 480,
                          child: EmptyState(
                            icon: Icons.style_outlined,
                            headline: "You're all caught up",
                            subtext: 'Jury reconvenes soon 👨‍⚖️',
                          ),
                        ),
                      ],
                    );
                  }
                  if (_cursor >= deck.length) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(
                          height: 480,
                          child: EmptyState(
                            icon: Icons.style_outlined,
                            headline: "You're all caught up",
                            subtext: 'Pull down to check for new cards.',
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Stack(
                          children: [
                            for (var i = (deck.length - _cursor).clamp(0, 3) - 1; i >= 0; i--)
                              _buildStackedCard(deck, i),
                          ],
                        ),
                      ),
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

  Widget _buildStackedCard(List<FactCheck> deck, int depth) {
    final index = _cursor + depth;
    final fc = deck[index];
    final isTop = depth == 0;
    final scale = 1.0 - (depth * 0.045);
    final verticalOffset = depth * 14.0;

    final rotation = isTop ? (_dragOffset.dx / 800).clamp(-0.35, 0.35) : 0.0;
    final translation = isTop ? _dragOffset : Offset.zero;

    Widget card = Transform.translate(
      offset: Offset(translation.dx, verticalOffset + translation.dy * 0.3),
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: isTop && !_dismissing ? 1.0 : scale,
          child: CollectibleCard(
            factCheck: fc,
            revealed: false,
            dragOffsetX: isTop ? _dragOffset.dx : 0,
          ),
        ),
      ),
    );

    if (isTop) {
      card = GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: (d) => _onPanEnd(d, fc, deck),
        child: card,
      );
    }

    return AnimatedOpacity(
      opacity: isTop && _dismissing ? 0 : 1,
      duration: const Duration(milliseconds: 150),
      child: card,
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({required this.progress, required this.theme});

  final UserProgress progress;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StatChip(icon: '🔥', label: '${progress.streakDays}d streak', theme: theme),
            const SizedBox(width: 10),
            _StatChip(icon: '⚡', label: '${progress.xp} XP', theme: theme),
            const SizedBox(width: 10),
            _StatChip(icon: '🎯', label: '${progress.accuracyPercent}% acc', theme: theme),
            const SizedBox(width: 16),
            Text(progress.rank, style: theme.monoFont(fontSize: 11, color: theme.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.theme});

  final String icon;
  final String label;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.border),
      ),
      child: Text('$icon $label', style: theme.monoFont(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
