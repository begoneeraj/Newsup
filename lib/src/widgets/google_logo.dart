import 'package:flutter/material.dart';

/// The multicolor Google "G" mark, drawn as four stroked arcs plus the blue
/// crossbar — avoids shipping a raster/SVG asset just for one icon.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeWidth = w * 0.2;
    final rect = Rect.fromCircle(
      center: Offset(w / 2, h / 2),
      radius: (w - strokeWidth) / 2,
    );

    Paint arcPaint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Four quarter-ish arcs around the ring, each offset slightly to leave a
    // visible seam between colors, matching the real logo's segmentation.
    canvas.drawArc(rect, -0.35, 1.62, false, arcPaint(_blue));
    canvas.drawArc(rect, 1.34, 1.28, false, arcPaint(_green));
    canvas.drawArc(rect, 2.68, 1.05, false, arcPaint(_yellow));
    canvas.drawArc(rect, -2.83, 1.15, false, arcPaint(_red));

    // The crossbar that makes a "G" out of an "O".
    final barPaint = Paint()..color = _blue;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.5, h * 0.44, w * 0.46, h * 0.14),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleLogoPainter oldDelegate) => false;
}
