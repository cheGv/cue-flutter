// lib/widgets/cue_study_icon.dart
//
// Shared CUE STUDY radiant icon — used by ltg_edit_screen and cue_study_fab.
// Draws a centre amber circle with 4 cardinal rays (full opacity) and
// 4 diagonal rays (0.4 opacity). 22×22 canvas.

import 'dart:math';
import 'package:flutter/material.dart';

const Color _iconAmber = Color(0xFFF59E0B);

class CueStudyIcon extends StatelessWidget {
  const CueStudyIcon({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(22, 22),
        painter: CueStudyIconPainter(),
      );
}

class CueStudyIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Centre filled circle
    canvas.drawCircle(
      Offset(cx, cy),
      4,
      Paint()..color = _iconAmber,
    );

    // Cardinal rays (N/S/E/W) — length 6, strokeWidth 1.5, full opacity
    final cardinalPaint = Paint()
      ..color = _iconAmber
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const innerR       = 5.5;
    const cardinalLen  = 6.0;
    const diagLen      = 5.0;
    const cardinalAngles = [0.0, pi / 2, pi, 3 * pi / 2];
    const diagAngles     = [pi / 4, 3 * pi / 4, 5 * pi / 4, 7 * pi / 4];

    for (final angle in cardinalAngles) {
      canvas.drawLine(
        Offset(cx + innerR * cos(angle), cy + innerR * sin(angle)),
        Offset(cx + (innerR + cardinalLen) * cos(angle),
               cy + (innerR + cardinalLen) * sin(angle)),
        cardinalPaint,
      );
    }

    // Diagonal rays (NE/NW/SE/SW) — length 5, strokeWidth 1.2, opacity 0.4
    final diagPaint = Paint()
      ..color = _iconAmber.withValues(alpha: 0.4)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (final angle in diagAngles) {
      canvas.drawLine(
        Offset(cx + innerR * cos(angle), cy + innerR * sin(angle)),
        Offset(cx + (innerR + diagLen) * cos(angle),
               cy + (innerR + diagLen) * sin(angle)),
        diagPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
