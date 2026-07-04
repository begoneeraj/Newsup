import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/fact_check.dart';
import '../providers/onboarding_providers.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';

/// First-launch, 3-slide intro. Shown once (gated by [hasSeenOnboarding] via
/// the router's redirect) so a new user — most likely arriving from a shared
/// verdict card — has context before they hit the feed: what the app is,
/// how a verdict gets produced, and what the labels mean.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = 3;

  Future<void> _finish() async {
    await markOnboardingSeen(ref);
    if (mounted) context.go('/');
  }

  void _next() {
    if (_page == _pageCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      backgroundColor: theme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton(
                  onPressed: _page == _pageCount - 1 ? null : _finish,
                  child: Text(
                    'Skip',
                    style: theme.bodyFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _page == _pageCount - 1 ? Colors.transparent : theme.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (index) => setState(() => _page = index),
                children: [
                  _OnboardingSlide(
                    icon: Icons.shield_outlined,
                    title: 'Real fact checks, automatically',
                    body:
                        'NewsUp watches news, Reddit, and official statements for '
                        'claims and crises affecting Indian students — and verifies '
                        'them so you don\'t have to dig through a dozen articles.',
                  ),
                  _OnboardingSlide(
                    icon: Icons.route_outlined,
                    title: 'How a verdict gets made',
                    body:
                        'Raw posts and articles are pulled in continuously, checked for '
                        'duplicates, then read by an AI model that extracts the claim, '
                        'checks corroboration, and assigns a verdict — no human editor '
                        'in the loop, running every few hours.',
                    diagram: true,
                  ),
                  _VerdictLegendSlide(theme: theme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pageCount, (index) {
                  final isActive = index == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive ? theme.accent : theme.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_page == _pageCount - 1 ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide extends ConsumerWidget {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
    this.diagram = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool diagram;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accent.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 40, color: theme.accent),
          ),
          const SizedBox(height: 28),
          if (diagram) ...[
            _PipelineDiagram(theme: theme),
            const SizedBox(height: 20),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.displayFont(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.bodyFont(fontSize: 14, color: theme.textMuted, fontWeight: FontWeight.w500)
                .copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _PipelineDiagram extends StatelessWidget {
  const _PipelineDiagram({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    Widget step(String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.border),
          ),
          child: Text(label, style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w700)),
        );

    Widget arrow() => Icon(Icons.arrow_forward, size: 14, color: theme.textMuted);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        step('RSS'),
        const SizedBox(width: 6),
        arrow(),
        const SizedBox(width: 6),
        step('LLM'),
        const SizedBox(width: 6),
        arrow(),
        const SizedBox(width: 6),
        step('Verdict'),
      ],
    );
  }
}

class _VerdictLegendSlide extends StatelessWidget {
  const _VerdictLegendSlide({required this.theme});

  final AppThemeData theme;

  static const _labels = [
    FactCheckStatus.verified,
    FactCheckStatus.falseClaim,
    FactCheckStatus.misleading,
    FactCheckStatus.unverified,
  ];

  static const _descriptions = {
    FactCheckStatus.verified: 'Backed by concrete, corroborated evidence.',
    FactCheckStatus.falseClaim: 'Contradicted by available evidence.',
    FactCheckStatus.misleading: 'Technically true but framed to deceive.',
    FactCheckStatus.unverified: 'Not enough evidence yet either way.',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'What the verdicts mean',
              style: theme.displayFont(fontSize: 21, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 24),
          for (final status in _labels)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.statusColor(status),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.label,
                          style: theme.bodyFont(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _descriptions[status]!,
                          style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
