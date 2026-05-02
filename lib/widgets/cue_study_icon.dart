// lib/widgets/cue_study_icon.dart
//
// Shared CUE STUDY radiant icon — used by ltg_edit_screen and cue_study_fab.
// Draws a center amber circle with 4 cardinal rays (full opacity) and
// 4 diagonal rays (0.4 opacity). 22×22 by default.

import 'dart:math';
import 'package:flutter/material.dart';

const Color _csAmber = Color(0xFFF59E0B);

class CueStudyIcon extends StatelessWidget {
  final double size;
  const CueStudyIcon({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: CueStudyIconPainter(),
      );
}

class CueStudyIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Center filled circle
    canvas.drawCircle(
      Offset(cx, cy),
      4,
      Paint()..color = _csAmber,
    );

    // Cardinal rays (N/S/E/W) — length 6, strokeWidth 1.5, opacity 1.0
    final cardinalPaint = Paint()
      ..color = _csAmber
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const cardinalAngles = [0.0, pi / 2, pi, 3 * pi / 2];
    const innerR = 5.5;
    const cardinalLen = 6.0;

    for (final angle in cardinalAngles) {
      final x1 = cx + innerR * cos(angle);
      final y1 = cy + innerR * sin(angle);
      final x2 = cx + (innerR + cardinalLen) * cos(angle);
      final y2 = cy + (innerR + cardinalLen) * sin(angle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), cardinalPaint);
    }

    // Diagonal rays (NE/NW/SE/SW) — length 5, strokeWidth 1.2, opacity 0.4
    final diagPaint = Paint()
      ..color = _csAmber.withValues(alpha: 0.4)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    const diagAngles = [pi / 4, 3 * pi / 4, 5 * pi / 4, 7 * pi / 4];
    const diagLen = 5.0;

    for (final angle in diagAngles) {
      final x1 = cx + innerR * cos(angle);
      final y1 = cy + innerR * sin(angle);
      final x2 = cx + (innerR + diagLen) * cos(angle);
      final y2 = cy + (innerR + diagLen) * sin(angle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), diagPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
