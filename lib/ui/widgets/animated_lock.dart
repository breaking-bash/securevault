import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A padlock whose shackle lifts open as [open] goes from 0 (locked) to 1.
class AnimatedLock extends StatelessWidget {
  final Animation<double> open;
  final Color color;
  final Color bodyColor;
  final double size;

  const AnimatedLock({
    super.key,
    required this.open,
    required this.color,
    required this.bodyColor,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: open,
      builder: (_, __) => CustomPaint(
        size: Size(size, size),
        painter: _LockPainter(open.value, color, bodyColor),
      ),
    );
  }
}

class _LockPainter extends CustomPainter {
  final double t;
  final Color color;
  final Color bodyColor;
  _LockPainter(this.t, this.color, this.bodyColor);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final bodyTop = h * 0.46;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.14, bodyTop, w * 0.72, h * 0.46),
      Radius.circular(w * 0.12),
    );

    // Shackle: left leg fixed, right leg lifts and the arc swings open.
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round;
    final lift = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
    canvas.save();
    final pivot = Offset(w * 0.3, bodyTop);
    canvas.translate(0, -lift * h * 0.14);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-lift * math.pi / 7);
    canvas.translate(-pivot.dx, -pivot.dy);
    final path = Path()
      ..moveTo(w * 0.3, bodyTop + h * 0.02)
      ..lineTo(w * 0.3, h * 0.3)
      ..arcToPoint(Offset(w * 0.7, h * 0.3),
          radius: Radius.circular(w * 0.2), clockwise: true)
      ..lineTo(w * 0.7, bodyTop + h * 0.02 - (lift * h * 0.06));
    canvas.drawPath(path, stroke);
    canvas.restore();

    canvas.drawRRect(bodyRect, Paint()..color = bodyColor);

    // Keyhole.
    final hole = Paint()..color = Colors.white.withValues(alpha: 0.92);
    final c = Offset(w * 0.5, bodyTop + h * 0.19);
    canvas.drawCircle(c, w * 0.06, hole);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: c.translate(0, h * 0.07), width: w * 0.05, height: h * 0.1),
        Radius.circular(w * 0.02),
      ),
      hole,
    );
  }

  @override
  bool shouldRepaint(_LockPainter o) =>
      o.t != t || o.color != color || o.bodyColor != bodyColor;
}

/// Fingerprint button with softly pulsing rings, 1Password-style.
class PulsingFingerprint extends StatefulWidget {
  final VoidCallback? onTap;
  final bool busy;
  const PulsingFingerprint({super.key, required this.onTap, this.busy = false});

  @override
  State<PulsingFingerprint> createState() => _PulsingFingerprintState();
}

class _PulsingFingerprintState extends State<PulsingFingerprint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: widget.busy ? null : widget.onTap,
      child: SizedBox(
        width: 88,
        height: 88,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _RingPainter(_c.value, color),
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                ),
                child: Icon(Icons.fingerprint, size: 34, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double t;
  final Color color;
  _RingPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      final r = 28 + p * 16;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - p) * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.t != t || o.color != color;
}
