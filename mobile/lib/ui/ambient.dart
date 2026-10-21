// ambient.dart — кинематографичный туман, отрендеренный ОДИН РАЗ в статичную
// картинку (как фото): нулевая нагрузка в кадре. Рендер в половинном
// разрешении — туману мягкость только на пользу.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// AmbientBackground — туманная сцена-«фото».
class AmbientBackground extends StatefulWidget {
  /// Размытие фона в том же масштабе, что и у фото (0–40).
  final double blur;
  /// Идентификатор темы: при смене палитры туман перерисовывается.
  final String themeId;
  const AmbientBackground({super.key, this.blur = 0, this.themeId = ''});
  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  ui.Image? _img;
  Size _renderedFor = Size.zero;
  int _renderedBlur = -1;
  String _renderedTheme = '';
  int _renderToken = 0;
  Timer? _debounce;

  @override
  void didUpdateWidget(AmbientBackground old) {
    super.didUpdateWidget(old);
    if (old.themeId != widget.themeId) {
      _renderedFor = Size.zero;
    }
    if (old.blur.round() != widget.blur.round()) {
      // слайдер шлёт десятки значений — перерисовываем после паузы
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _renderedFor = Size.zero);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final b = widget.blur.round();
      if ((w - _renderedFor.width).abs() > 1 ||
          (h - _renderedFor.height).abs() > 1 ||
          b != _renderedBlur ||
          widget.themeId != _renderedTheme) {
        _renderedFor = Size(w, h);
        _renderedBlur = b;
        _renderedTheme = widget.themeId;
        _renderScene(w, h);
      }
      final img = _img;
      if (img == null) return ColoredBox(color: C.bg);
      return SizedBox.expand(
        child: RawImage(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.low),
      );
    });
  }

  Future<void> _renderScene(double w, double h) async {
    final token = ++_renderToken;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final blur = widget.blur;
    if (blur > 0.5) {
      canvas.saveLayer(
        Offset.zero & ui.Size(w, h),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blur * 0.7,
            sigmaY: blur * 0.7,
            tileMode: TileMode.clamp,
          ),
      );
    }
    _paintScene(canvas, ui.Size(w, h));
    if (blur > 0.5) canvas.restore();
    final picture = recorder.endRecording();
    final scale = 0.5; // полразрешения: туману мягкость не вредит
    final img = await picture.toImage(
        math.max(1, (w * scale).round()), math.max(1, (h * scale).round()));
    picture.dispose();
    if (!mounted || token != _renderToken) {
      img.dispose();
      return;
    }
    final old = _img;
    setState(() => _img = img);
    if (old != null && old != img) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _paintScene(ui.Canvas canvas, ui.Size size) {
    final r = math.Random(5);

    // ночная база в тоне темы: тёмная, без «молочного» свечения
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(Colors.black.withAlpha(12), C.bg),
            Color.alphaBlend(Colors.black.withAlpha(110), C.bg),
          ],
        ).createShader(Offset.zero & size),
    );
    // лунная подсветка из верхнего левого угла — акцентом темы
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.75, -0.85),
          radius: 1.3,
          colors: [C.accent.withAlpha(34), C.bg.withAlpha(0)],
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
          colors: [C.secondary.withAlpha(0), C.secondary.withAlpha(32), C.secondary.withAlpha(0)],
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
              colors: [C.secondary.withAlpha(a), C.secondary.withAlpha(0)],
            ).createShader(rect),
        );
      }
      layerIdx++;
    }
  }
}
