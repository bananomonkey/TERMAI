// ambient.dart — кинематографичный туман, отрендеренный ОДИН РАЗ в статичную
// картинку (как фото): нулевая нагрузка в кадре. Рендер в половинном
// разрешении — туману мягкость только на пользу.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// AmbientBackground — туманная сцена-«фото».
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});
  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  ui.Image? _img;
  Size _renderedFor = Size.zero;
  int _renderToken = 0;

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      if ((w - _renderedFor.width).abs() > 1 || (h - _renderedFor.height).abs() > 1) {
        _renderedFor = Size(w, h);
        _renderScene(w, h);
      }
      final img = _img;
      if (img == null) return const ColoredBox(color: Color(0xFF120D0A));
      return SizedBox.expand(
        child: RawImage(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.low),
      );
    });
  }

  Future<void> _renderScene(double w, double h) async {
    final token = ++_renderToken;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    _paintScene(canvas, ui.Size(w, h));
    final picture = recorder.endRecording();
    final scale = 0.5; // полразрешения: туману мягкость не вредит
    final img = await picture.toImage(
        math.max(1, (w * scale).round()), math.max(1, (h * scale).round()));
    picture.dispose();
    if (!mounted || token != _renderToken) {
      img.dispose();
      return;
    }
    setState(() => _img = img);
  }

  void _paintScene(ui.Canvas canvas, ui.Size size) {
    final r = math.Random(5);

    // ночная база: чуть светлее кверху
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1A120D), const Color(0xFF0E0906)],
        ).createShader(Offset.zero & size),
    );
    // лунная подсветка из верхнего левого угла
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.75, -0.85),
          radius: 1.3,
          colors: [const Color(0x38C97E3C), const Color(0x000E0906)],
        ).createShader(Offset.zero & size),
    );
    // косой луч света сквозь туман
    canvas.save();
    canvas.translate(size.width * 0.32, -40);
    canvas.rotate(0.42);
    final shaft = Rect.fromLTWH(0, 0, size.width * 0.16, size.height * 1.5);
    canvas.drawRect(
      shaft,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [const Color(0x00D08C3C), const Color(0x20D08C3C), const Color(0x00D08C3C)],
        ).createShader(shaft),
    );
    canvas.restore();

    // туман: три слоя глубины — дальний бледный, средний, ближний плотный у земли
    final layers = <(int, double, double)>[
      (10, 0.16, 0.028),  // count, radius, alpha
      (9, 0.30, 0.048),
      (7, 0.44, 0.075),
    ];
    var layerIdx = 0;
    for (final (count, radius, alpha) in layers) {
      final yBase = layerIdx == 0 ? 0.05 : (layerIdx == 1 ? 0.25 : 0.55);
      for (var i = 0; i < count; i++) {
        final x = r.nextDouble();
        final y = yBase + r.nextDouble() * (layerIdx == 0 ? 0.55 : layerIdx == 1 ? 0.55 : 0.5);
        final rad = radius + r.nextDouble() * radius * 0.8;
        // «дыхание» — лёгкая вариация плотности внутри слоя
        final a = (alpha * (0.75 + r.nextDouble() * 0.5) * 255).round().clamp(0, 255);
        final rect = Rect.fromCenter(
          center: Offset(x * size.width, y * size.height),
          width: rad * size.width * 2.2,
          height: rad * size.width * 1.5,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              colors: [const Color(0xFFD9B48C).withAlpha(a), const Color(0xFFD9B48C).withAlpha(0)],
            ).createShader(rect),
        );
      }
      layerIdx++;
    }
  }
}
