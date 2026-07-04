import 'package:flutter/material.dart';

/// Fades + slides a list item in with a small per-index delay, so a loaded
/// feed animates in as a stagger rather than every card popping in at once.
class StaggeredFadeSlide extends StatelessWidget {
  const StaggeredFadeSlide({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const _step = Duration(milliseconds: 40);
  static const _maxDelay = Duration(milliseconds: 320);
  static const _duration = Duration(milliseconds: 340);

  @override
  Widget build(BuildContext context) {
    final delay = Duration(
      milliseconds: (_step.inMilliseconds * index).clamp(0, _maxDelay.inMilliseconds),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _duration + delay,
      curve: Interval(
        (delay.inMilliseconds / (_duration + _maxDelay).inMilliseconds).clamp(0.0, 0.9),
        1.0,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
