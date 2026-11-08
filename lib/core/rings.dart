import 'package:flutter/material.dart';

import 'theme.dart';

/// Le motif de l'app : des ondes autour d'une personne.
class RingSource {
  const RingSource(this.dx, this.dy, this.rings, this.color);
  final double dx;
  final double dy;
  final int rings;
  final Color color;
}

class RingsPainter extends CustomPainter {
  const RingsPainter(this.sources);
  final List<RingSource> sources;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.shortestSide * 0.11;
    for (final s in sources) {
      final center = Offset(size.width * s.dx, size.height * s.dy);
      for (var i = 1; i <= s.rings; i++) {
        final alpha = (0.9 - i * (0.8 / (s.rings + 1))).clamp(0.08, 1.0);
        canvas.drawCircle(
          center,
          step * i,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = s.color.withValues(alpha: alpha),
        );
      }
      canvas.drawCircle(center, 9, Paint()..color = s.color);
    }
  }

  @override
  bool shouldRepaint(RingsPainter old) => old.sources != sources;
}

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
