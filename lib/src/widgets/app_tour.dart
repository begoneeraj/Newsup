import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

const appTourSeenKey = 'newsup.hasSeenAppTour.v1';
final appTourActiveProvider = StateProvider<bool>((ref) => false);
final appTourTargetsProvider = Provider((ref) => AppTourTargets());

class AppTourTargets {
  final _keys = <String, GlobalKey>{};
  GlobalKey key(String name) =>
      _keys.putIfAbsent(name, () => GlobalKey(debugLabel: 'tour-$name'));
}

class AppTourTarget extends ConsumerWidget {
  const AppTourTarget({super.key, required this.name, required this.child});
  final String name;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => KeyedSubtree(
        key: ref.read(appTourTargetsProvider).key(name),
        child: child,
      );
}

class AppTourStep {
  const AppTourStep(this.target, this.title, this.description, {this.tab = 0});
  final String target;
  final String title;
  final String description;
  final int tab;
}

const appTourSteps = [
  AppTourStep('nav-0', 'Your Spotlight feed',
      'Start here for AI-assisted claim checks. Tap a card to read its evidence and original source links. A verdict can be wrong; read the sources before relying on it.'),
  AppTourStep('search', 'Find a topic',
      'Type a word or phrase to search the loaded fact checks. Clear the search to see the full feed again.'),
  AppTourStep('filters', 'Explore the verdicts',
      'Use these filters to show verified, false, misleading or unverified claims. Unverified means there is not enough evidence yet.'),
  AppTourStep('categories', 'Explore promises and science',
      'Government Promises tracks commitments and evidence. Science & Data opens research and data stories.'),
  AppTourStep('voice', 'Choose your reading style',
      'This button switches between the standard feed and Gen Z mode, where you can swipe and guess a claim’s verdict. The underlying evidence stays the same.'),
  AppTourStep('appearance', 'Light or dark',
      'Use this button to change the appearance. Your choice is saved on this device.'),
  AppTourStep('account', 'Your account and privacy',
      'Open your profile for privacy information, optional notifications and account deletion. You can also replay this tour from that menu.'),
  AppTourStep('nav-1', 'Crisis Tracker',
      'Follow developing public-interest events and open an item for its timeline and sources. This is a news tracker, not an emergency-alert service.',
      tab: 1),
  AppTourStep('nav-2', 'Silent Signals',
      'Explore longer-running issues such as air quality, groundwater and public services. Open a card to inspect its data and updates.',
      tab: 2),
  AppTourStep('nav-3', 'Overlooked stories',
      'See topics the app identifies as receiving limited coverage. These automated assessments are estimates, not a complete measure of the news.',
      tab: 3),
  AppTourStep('nav-4', 'Save it for later',
      'Use the bookmark icon on a fact check to save it. Find saved items here; bookmarks stay on this device. You’re ready to explore.',
      tab: 4),
];

/// The highlight uses the live control's layout, never fixed phone coordinates.
/// The child is blocked while the tour is open so Next cannot trigger a
/// destructive action or accidentally navigate behind the explanation.
class AppTourHost extends ConsumerStatefulWidget {
  const AppTourHost(
      {super.key, required this.child, required this.onTabRequested});
  final Widget child;
  final ValueChanged<int> onTabRequested;
  @override
  ConsumerState<AppTourHost> createState() => _AppTourHostState();
}

class _AppTourHostState extends ConsumerState<AppTourHost> {
  final _hostKey = GlobalKey();
  int _index = 0;
  Rect? _highlight;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(appTourActiveProvider)) {
        _show(0);
      } else if (ref.read(sharedPreferencesProvider).getBool(appTourSeenKey) !=
          true) {
        ref.read(appTourActiveProvider.notifier).state = true;
      }
    });
  }

  void _show(int index) {
    setState(() {
      _index = index;
      _highlight = null;
    });
    widget.onTabRequested(appTourSteps[index].tab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final target = ref
        .read(appTourTargetsProvider)
        .key(appTourSteps[_index].target)
        .currentContext
        ?.findRenderObject();
    final host = _hostKey.currentContext?.findRenderObject();
    if (target is RenderBox &&
        target.attached &&
        target.hasSize &&
        host is RenderBox &&
        host.hasSize) {
      final origin = target.localToGlobal(Offset.zero, ancestor: host);
      setState(() => _highlight =
          (origin & target.size).inflate(5).intersect(Offset.zero & host.size));
    }
  }

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved =
        await ref.read(sharedPreferencesProvider).setBool(appTourSeenKey, true);
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
        _error = 'Could not save your choice. Please try again.';
      });
      return;
    }
    ref.read(appTourActiveProvider.notifier).state = false;
    widget.onTabRequested(0);
    setState(() {
      _saving = false;
      _index = 0;
      _highlight = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(appTourActiveProvider);
    ref.listen<bool>(appTourActiveProvider, (previous, next) {
      if (next && previous != true) _show(0);
    });
    final step = appTourSteps[_index];
    return Stack(key: _hostKey, fit: StackFit.expand, children: [
      ExcludeSemantics(excluding: active, child: widget.child),
      if (active)
        Positioned.fill(child: LayoutBuilder(builder: (context, constraints) {
          final padding = MediaQuery.paddingOf(context);
          final cardAtTop = (_highlight?.center.dy ?? constraints.maxHeight) >
              constraints.maxHeight * .55;
          return Material(
              color: Colors.transparent,
              child: Stack(children: [
                Positioned.fill(
                    child: GestureDetector(
                        onTap: () {},
                        child: CustomPaint(painter: _TourShade(_highlight)))),
                Positioned(
                    left: 16,
                    right: 16,
                    top: cardAtTop ? padding.top + 16 : null,
                    bottom: cardAtTop ? null : padding.bottom + 16,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight:
                              math.max(180, constraints.maxHeight * .58)),
                      child: Card(
                          child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: SingleChildScrollView(
                                  child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                      liveRegion: true,
                                      child: Text(
                                          'Step ${_index + 1} of ${appTourSteps.length}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge)),
                                  const SizedBox(height: 10),
                                  Text(step.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 10),
                                  Text(step.description),
                                  if (_highlight == null)
                                    const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                            'This control appears in the standard Spotlight feed.')),
                                  if (_error != null) Text(_error!),
                                  const SizedBox(height: 16),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    TextButton(
                                        onPressed: _saving ? null : _finish,
                                        child: const Text('Skip tour')),
                                    if (_index > 0)
                                      TextButton(
                                          onPressed: _saving
                                              ? null
                                              : () => _show(_index - 1),
                                          child: const Text('Back')),
                                    FilledButton(
                                        onPressed: _saving
                                            ? null
                                            : () => _index ==
                                                    appTourSteps.length - 1
                                                ? _finish()
                                                : _show(_index + 1),
                                        child: Text(
                                            _index == appTourSteps.length - 1
                                                ? 'Done'
                                                : 'Next')),
                                  ]),
                                ],
                              )))),
                    )),
              ]));
        })),
    ]);
  }
}

class _TourShade extends CustomPainter {
  const _TourShade(this.highlight);
  final Rect? highlight;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (highlight != null && !highlight!.isEmpty) {
      path.addRRect(
          RRect.fromRectAndRadius(highlight!, const Radius.circular(14)));
    }
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .72));
    if (highlight != null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(highlight!, const Radius.circular(14)),
          Paint()
            ..color = const Color(0xFF5DE3D3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
  }

  @override
  bool shouldRepaint(_TourShade oldDelegate) =>
      highlight != oldDelegate.highlight;
}
