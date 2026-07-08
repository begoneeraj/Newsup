import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fact_check.dart';
import '../../providers/user_progress_provider.dart';
import '../../theme/app_theme_data.dart';
import '../../theme/theme_providers.dart';
import '../confidence_meter.dart';

/// Bottom sheet shown right after a swipe guess resolves. Tells the user
/// whether they were right, awards XP, and explains the verdict.
Future<void> showRevealSheet(
  BuildContext context,
  WidgetRef ref, {
  required FactCheck factCheck,
  required GuessOutcome outcome,
  required int xpAwarded,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => RevealSheet(factCheck: factCheck, outcome: outcome, xpAwarded: xpAwarded),
  );
}

class RevealSheet extends ConsumerStatefulWidget {
  const RevealSheet({super.key, required this.factCheck, required this.outcome, required this.xpAwarded});

  final FactCheck factCheck;
  final GuessOutcome outcome;
  final int xpAwarded;

  @override
  ConsumerState<RevealSheet> createState() => _RevealSheetState();
}

class _RevealSheetState extends ConsumerState<RevealSheet> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(milliseconds: 700));
    if (widget.outcome == GuessOutcome.correct) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  String get _voiceLine {
    switch (widget.outcome) {
      case GuessOutcome.correct:
        return 'YOOOO you cooked. Nice catch fr fr 🔥';
      case GuessOutcome.wrong:
        return '💀 Bro... you got baited. Here\'s why —';
      case GuessOutcome.ungraded:
        return "Still cooking — jury hasn't ruled on this one yet 👀";
    }
  }

  Color _bannerColor(AppThemeData theme) {
    switch (widget.outcome) {
      case GuessOutcome.correct:
        return theme.statusColor(FactCheckStatus.verified);
      case GuessOutcome.wrong:
        return theme.statusColor(FactCheckStatus.falseClaim);
      case GuessOutcome.ungraded:
        return theme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeDataProvider);
    final fc = widget.factCheck;
    final bannerColor = _bannerColor(theme);

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: theme.bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: theme.border),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: theme.border, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bannerColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: bannerColor),
                    ),
                    child: Row(
                      children: [
                        Text(
                          fc.status.genzBadgeLabel,
                          style: theme.bodyFont(fontSize: 15, fontWeight: FontWeight.w800, color: bannerColor),
                        ),
                        const Spacer(),
                        if (widget.xpAwarded > 0)
                          Text(
                            '+${widget.xpAwarded} XP',
                            style: theme.monoFont(fontSize: 13, fontWeight: FontWeight.w800, color: bannerColor),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _voiceLine,
                    style: theme.displayFont(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 18),
                  if (fc.expertAnalysis != null) ...[
                    Text(
                      fc.expertAnalysis!,
                      style: theme.bodyFont(fontSize: 14.5, color: theme.textMuted),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    children: [
                      Text('Truth Meter', style: theme.bodyFont(fontSize: 13, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      ConfidenceMeter(confidence: fc.evidenceConfidence, color: bannerColor),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (fc.sources.isNotEmpty) ...[
                    Text('Sources (${fc.sources.length})',
                        style: theme.bodyFont(fontSize: 13, fontWeight: FontWeight.w600, color: theme.textMuted)),
                    const SizedBox(height: 8),
                    ...fc.sources.take(4).map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '•  ${s.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyFont(fontSize: 13, color: theme.textMuted),
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Next card →', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 22,
            maxBlastForce: 16,
            minBlastForce: 6,
            gravity: 0.35,
            shouldLoop: false,
            colors: [theme.accent, theme.statusColor(FactCheckStatus.verified), theme.statusColor(FactCheckStatus.partlyTrue)],
          ),
        ),
      ],
    );
  }
}
