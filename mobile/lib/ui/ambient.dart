// ambient.dart — кинематографичный живой туман: три параллакс-слоя туманных
// банков (дальний — медленный и бледный, ближний — плотный и быстрый),
// лунная подсветка из угла. Ничего тяжёлого: ~26 радиальных клобов на канве.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// AmbientBackground — туманная сцена.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});
  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 90))..repeat();
  late final List<_FogBlob> _blobs;

  @override
  void initState() {
    super.initState();
    final r = math.Random(5);
    _blobs = [];
    // дальний слой: мелкий, бледный, медленный — живёт выше
    for (var i = 0; i < 7; i++) {
      _blobs.add(_FogBlob(
        x: r.nextDouble(), y: 0.05 + r.nextDouble() * 0.55,
        radius: 0.16 + r.nextDouble() * 0.14,
        speed: 0.008 + r.nextDouble() * 0.008,
        amp: 0.012 + r.nextDouble() * 0.02,
        phase: r.nextDouble() * math.pi * 2,
        opacity: 0.022 + r.nextDouble() * 0.02,
      ));
    }
    // средний слой
    for (var i = 0; i < 6; i++) {
      _blobs.add(_FogBlob(
        x: r.nextDouble(), y: 0.25 + r.nextDouble() * 0.6,
        radius: 0.26 + r.nextDouble() * 0.18,
        speed: 0.02 + r.nextDouble() * 0.012,
        amp: 0.02 + r.nextDouble() * 0.03,
        phase: r.nextDouble() * math.pi * 2,
        opacity: 0.04 + r.nextDouble() * 0.025,
      ));
    }
    // ближний слой: крупный, плотный, быстрый — стелется по низу
    for (var i = 0; i < 5; i++) {
      _blobs.add(_FogBlob(
        x: r.nextDouble(), y: 0.55 + r.nextDouble() * 0.5,
        radius: 0.38 + r.nextDouble() * 0.24,
        speed: 0.035 + r.nextDouble() * 0.02,
        amp: 0.025 + r.nextDouble() * 0.035,
        phase: r.nextDouble() * math.pi * 2,
        opacity: 0.055 + r.nextDouble() * 0.035,
      ));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _FogScenePainter(t: _c.value, blobs: _blobs, repaint: _c),
      ),
    );
  }
}

class _FogBlob {
  final double x, y, radius, speed, amp, phase, opacity;
  _FogBlob({
    required this.x, required this.y, required this.radius,
    required this.speed, required this.amp, required this.phase,
    required this.opacity,
  });
}

/// _FogScenePainter — сцена: ночная база, лунный свет, параллакс-туман.
class _FogScenePainter extends CustomPainter {
  final double t;
  final List<_FogBlob> blobs;
  static const _spriteW = 256.0, _spriteH = 170.0;
  static final Paint _shaderPaint = Paint()
    ..shader = RadialGradient(colors: [
      const Color(0xFFC9D4DE),
      const Color(0xFFC9D4DE).withAlpha(0),
    ]).createShader(const Rect.fromLTWH(0, 0, _spriteW, _spriteH));
  static final Map<int, Paint> _paintCache = {};

  _FogScenePainter({required this.t, required this.blobs, required Listenable repaint})
      : super(repaint: repaint);

  Paint _paintFor(double opacity) {
    final bucket = (opacity * 40).round(); // 10 уровней прозрачности
    return _paintCache.putIfAbsent(bucket, () => Paint()
      ..shader = _shaderPaint.shader
      ..color = Colors.white.withAlpha((bucket / 40 * 255).round())
      ..blendMode = BlendMode.modulate);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ночная база: глубокий тёмно-нейтральный, чуть светлее кверху
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF14171D), const Color(0xFF0A0C10)],
        ).createShader(Offset.zero & size),
    );
    // лунная подсветка из верхнего левого угла
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.75, -0.85),
          radius: 1.3,
          colors: [const Color(0x33AFC4D8), const Color(0x000A0C10)],
        ).createShader(Offset.zero & size),
    );
    // луч света сквозь туман — косая светлая полоса
    canvas.save();
    canvas.translate(size.width * 0.32, -40);
    canvas.rotate(0.42);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * 0.16, size.height * 1.5),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [const Color(0x00AFC4D8), const Color(0x14AFC4D8), const Color(0x00AFC4D8)],
        ).createShader(Rect.fromLTWH(0, 0, size.width * 0.16, size.height * 1.5)),
    );
    canvas.restore();

    // туман: клобы с мягким радиальным затуханием, три слоя глубины
    for (final b in blobs) {
      final xx = (((b.x + t * b.speed) % 1.5) + 1.5) % 1.5 - 0.25; // запас за краями
      final yy = b.y + b.amp * math.sin(t * math.pi * 2 + b.phase);
      final rect = Rect.fromCenter(
        center: Offset(xx * size.width, yy * size.height),
        width: b.radius * size.width * 2.2,
        height: b.radius * size.width * 1.5,
      );
      canvas.save();
      canvas.translate(rect.left, rect.top);
      canvas.scale(rect.width / _spriteW, rect.height / _spriteH);
      canvas.drawRect(const Rect.fromLTWH(0, 0, _spriteW, _spriteH), _paintFor(b.opacity));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FogScenePainter old) => old.t != t;
}
