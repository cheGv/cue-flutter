import 'package:flutter/material.dart';

/// A full-width dashed horizontal hairline. Shared by the LTG anchor's bottom
/// rule, the sparkline empty state, and any other dashed divider on the chart.
class DashedHLine extends StatelessWidget {
  final Color color;
  final double thickness;
  final double dashWidth;
  final double gap;

  const DashedHLine({
    super.key,
    required this.color,
    this.thickness = 0.5,
    this.dashWidth = 3,
    this.gap = 3,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thickness,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashedPainter(
          color: color,
          thickness: thickness,
          dashWidth: dashWidth,
          gap: gap,
        ),
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final double dashWidth;
  final double gap;

  _DashedPainter({
    required this.color,
    required this.thickness,
    required this.dashWidth,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color ||
      old.thickness != thickness ||
      old.dashWidth != dashWidth ||
      old.gap != gap;
}
