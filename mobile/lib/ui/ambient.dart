// ambient.dart — кинематографичный живой фон: глубокий градиент ночи/заката,
// парящая пыль (микрочастицы на CustomPainter, 60 FPS, лёгкая).
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// AmbientBackground — многослойный фон: ночь → фиолетовое свечение → тёплый
/// отблеск заката в углу + парящая пыль.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});
  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  late final List<_Dust> _dust;

  @override
  void initState() {
    super.initState();
    final r = math.Random(11);
    _dust = List.generate(44, (_) => _Dust(
      x: r.nextDouble(),
      y: r.nextDouble(),
      radius: 0.6 + r.nextDouble() * 1.1,      // 0.6–1.7 логических px
      speed: 0.015 + r.nextDouble() * 0.05,     // доля экрана за цикл
      drift: (r.nextDouble() * 2 - 1) * 0.02,
      phase: r.nextDouble() * math.pi * 2,
      opacity: 0.10 + r.nextDouble() * 0.30,    // 0.10–0.40
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // глубокая ночь
        const ColoredBox(color: Color(0xFF0E1220)),
        // мягкое фиолетовое свечение сверху справа
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.85, -0.75),
              radius: 1.25,
              colors: [Color(0x88403A6B), Color(0x000E1220)],
            ),
          ),
        ),
        // тёплый отблеск заката в нижнем левом углу
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.85, 0.85),
              radius: 1.15,
              colors: [Color(0x66C46A2B), Color(0x000E1220)],
            ),
          ),
        ),
        // парящая пыль
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _DustPainter(t: _c.value, dust: _dust, repaint: _c),
          ),
        ),
      ],
    );
  }
}

class _Dust {
  final double x, y, radius, speed, drift, phase, opacity;
  _Dust({
    required this.x, required this.y, required this.radius,
    required this.speed, required this.drift, required this.phase,
    required this.opacity,
  });
}

class _DustPainter extends CustomPainter {
  final double t;
  final List<_Dust> dust;
  _DustPainter({required this.t, required this.dust, required Listenable repaint})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (final d in dust) {
      // медленное парение вверх + лёгкий дрейф по синусоиде
      final yy = ((d.y - t * d.speed) % 1.0 + 1.0) % 1.0;
      final xx = ((d.x + d.drift * math.sin(t * math.pi * 2 + d.phase)) % 1.0 + 1.0) % 1.0;
      paint.color = Colors.white.withAlpha((d.opacity * 255).round());
      canvas.drawCircle(Offset(xx * size.width, yy * size.height), d.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) => old.t != t;
}
