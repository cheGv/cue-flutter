import 'package:flutter/material.dart';

class HeaderWavePainter extends CustomPainter {
  const HeaderWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF00695C), Color(0xFF00897B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..lineTo(0, size.height * 0.80)
      ..quadraticBezierTo(
        size.width * 0.28, size.height * 1.08,
        size.width * 0.52, size.height * 0.82,
      )
      ..quadraticBezierTo(
        size.width * 0.78, size.height * 0.58,
        size.width, size.height * 0.80,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
