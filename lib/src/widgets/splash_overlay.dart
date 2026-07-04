import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Brief branded intro shown once on launch: a shield-and-checkmark motif
/// traces itself in, the wordmark fades/scales in behind it, then the whole
/// overlay cross-fades away to reveal the Fact Checks feed underneath.
/// Lives as a Stack overlay (via MaterialApp.router's `builder`) rather than
/// a real route, so it never delays go_router's own navigation.
class SplashOverlay extends ConsumerStatefulWidget {
  const SplashOverlay({super.key});

  @override
  ConsumerState<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends ConsumerState<SplashOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _fadingOut = false;
  bool _hidden = false;

  static const _drawDuration = Duration(milliseconds: 1000);
  static const _holdDuration = Duration(milliseconds: 150);
  static const _fadeOutDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _drawDuration)..forward();
    Future.delayed(_drawDuration + _holdDuration, () {
      if (!mounted) return;
      setState(() => _fadingOut = true);
      Future.delayed(_fadeOutDuration, () {
        if (!mounted) return;
        setState(() => _hidden = true);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    final theme = ref.watch(appThemeDataProvider);

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _fadingOut ? 0 : 1,
        duration: _fadeOutDuration,
        child: ColoredBox(
          color: theme.bg,
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final shieldProgress = (t / 0.65).clamp(0.0, 1.0);
                final checkProgress = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
                final wordmarkOpacity = ((t - 0.6) / 0.4).clamp(0.0, 1.0);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: CustomPaint(
                        painter: _ShieldCheckPainter(
                          shieldProgress: shieldProgress,
                          checkProgress: checkProgress,
                          color: theme.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Opacity(
                      opacity: wordmarkOpacity,
                      child: Transform.scale(
                        scale: 0.92 + (0.08 * wordmarkOpacity),
                        child: Text(
                          'NewsUp',
                          style: theme.displayFont(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldCheckPainter extends CustomPainter {
  _ShieldCheckPainter({
    required this.shieldProgress,
    required this.checkProgress,
    required this.color,
  });

  final double shieldProgress;
  final double checkProgress;
  final Color color;

  Path _shieldPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.5, h * 0.04)
      ..lineTo(w * 0.86, h * 0.2)
      ..lineTo(w * 0.86, h * 0.54)
      ..cubicTo(w * 0.86, h * 0.8, w * 0.66, h * 0.93, w * 0.5, h * 0.98)
      ..cubicTo(w * 0.34, h * 0.93, w * 0.14, h * 0.8, w * 0.14, h * 0.54)
      ..lineTo(w * 0.14, h * 0.2)
      ..close();
  }

  Path _checkPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.31, h * 0.52)
      ..lineTo(w * 0.45, h * 0.66)
      ..lineTo(w * 0.71, h * 0.36);
  }

  void _drawPartial(Canvas canvas, Path path, double progress, Paint paint) {
    if (progress <= 0) return;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    _drawPartial(canvas, _shieldPath(size), shieldProgress, paint);
    _drawPartial(canvas, _checkPath(size), checkProgress, paint);
  }

  @override
  bool shouldRepaint(covariant _ShieldCheckPainter oldDelegate) =>
      oldDelegate.shieldProgress != shieldProgress || oldDelegate.checkProgress != checkProgress;
}
