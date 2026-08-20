import 'package:flutter/material.dart';

import '../theme/app_theme_data.dart';

/// One-time speech-bubble pointing at the Gen Z voice toggle, so the feature
/// has a discovery path beyond "notice the icon and guess what it does".
/// Shown once via [show]; dismissed by tapping anywhere (including the
/// toggle itself, which also flips the voice).
class GenzCoachMark {
  const GenzCoachMark._();

  static OverlayEntry show({
    required BuildContext context,
    required LayerLink link,
    required AppThemeData theme,
    required VoidCallback onDismiss,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GenzCoachMarkOverlay(
        link: link,
        theme: theme,
        onDismiss: () {
          entry.remove();
          onDismiss();
        },
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }
}

class _GenzCoachMarkOverlay extends StatelessWidget {
  const _GenzCoachMarkOverlay({required this.link, required this.theme, required this.onDismiss});

  final LayerLink link;
  final AppThemeData theme;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topRight,
          offset: const Offset(18, 10),
          child: Material(
            type: MaterialType.transparency,
            child: _Bubble(theme: theme, onDismiss: onDismiss),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.theme, required this.onDismiss});

  final AppThemeData theme;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 22),
          child: CustomPaint(
            size: const Size(16, 8),
            painter: _ArrowPainter(color: theme.surface, borderColor: theme.accent),
          ),
        ),
        Container(
          width: 220,
          margin: const EdgeInsets.only(top: 0),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.accent, width: 1.2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: GestureDetector(
            onTap: onDismiss,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEW',
                        style: theme.monoFont(fontSize: 10, fontWeight: FontWeight.w800, color: theme.accent)
                            .copyWith(letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap here for Gen Z mode — swipe-guess fact checks in slang.',
                        style: theme
                            .bodyFont(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.textPrimary)
                            .copyWith(height: 1.3),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 15, color: theme.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderColor != borderColor;
}
