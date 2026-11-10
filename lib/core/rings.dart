import 'package:flutter/material.dart';

import 'theme.dart';

/// Ondes qui s'étendent : utilisé uniquement sur l'écran d'alarme.
class PulsePainter extends CustomPainter {
  const PulsePainter(this.t, {this.color = DingColors.paper});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.4);
    final maxRadius = size.longestSide * 0.8;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      canvas.drawCircle(
        center,
        maxRadius * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - p) * 0.8),
      );
    }
    canvas.drawCircle(center, 10, Paint()..color = color);
  }

  @override
  bool shouldRepaint(PulsePainter old) => old.t != t;
}
