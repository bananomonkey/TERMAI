// app_background.dart — фон приложения: ровный цвет темы или своё фото.
// Никакого тумана и градиентов: чёткий коричневый/синий фон по выбору.
// Размытие фото считается один раз в ui.Image, а не в каждом кадре.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../main.dart';
import 'theme.dart';

/// BackdropImage — фото фона, размытое один раз и отрисованное как картинка.
class BackdropImage extends StatefulWidget {
  final String path;
  final double blur;
  final BoxFit fit;

  /// Ширина декодирования: для полноэкранного фона хватает 1280,
  /// для маленького предпросмотра — меньше (быстрее размытие).
  final int maxWidth;
  const BackdropImage({
    super.key,
    required this.path,
    this.blur = 0,
    this.fit = BoxFit.cover,
    this.maxWidth = 1280,
  });

  @override
  State<BackdropImage> createState() => _BackdropImageState();
}

class _BackdropImageState extends State<BackdropImage> {
  ui.Image? _img;
  String _key = '';
  int _token = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BackdropImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _load();
    } else if (old.blur.round() != widget.blur.round()) {
      // слайдер двигают часто — не размываем на каждый тик
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 140), _load);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _token++; // отменяем незавершённую загрузку
    _img?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    try {
      final f = File(widget.path);
      if (!await f.exists()) {
        if (mounted && token == _token) setState(() => _img = null);
        return;
      }
      final mtime = (await f.lastModified()).millisecondsSinceEpoch;
      final blur = widget.blur.round();
      final key = '${widget.path}|$mtime|$blur';
      if (key == _key && _img != null) return;

      final bytes = await f.readAsBytes();
      final codec =
          await ui.instantiateImageCodec(bytes, targetWidth: widget.maxWidth);
      final frame = await codec.getNextFrame();
      var image = frame.image;

      if (blur > 0) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(
          image,
          Offset.zero,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: blur * 1.4,
              sigmaY: blur * 1.4,
              tileMode: TileMode.clamp,
            ),
        );
        final picture = recorder.endRecording();
        final blurred = await picture.toImage(image.width, image.height);
        picture.dispose();
        image.dispose();
        image = blurred;
      }

      if (!mounted || token != _token) {
        image.dispose();
        return;
      }
      // старую картинку освобождаем после кадра: без утечек
      final old = _img;
      setState(() {
        _img = image;
        _key = key;
      });
      if (old != null && old != image) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } catch (_) {
      if (mounted && token == _token) setState(() => _img = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    if (img == null) return ColoredBox(color: C.bg);
    return SizedBox.expand(
      child: RawImage(
        image: img,
        fit: widget.fit,
        filterQuality: FilterQuality.low,
        key: ValueKey(_key),
      ),
    );
  }
}

/// AppBackdrop — оборачивает экран и рисует под ним ровный фон.
/// Слушает контроллер только ради смены фона/темы, а не каждой команды.
class AppBackdrop extends StatefulWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop> {
  String _path = '';
  double _blur = 0;
  double _dim = 0;
  String _theme = '';

  @override
  void initState() {
    super.initState();
    _capture();
    controller.addListener(_onController);
  }

  void _capture() {
    final cfg = controller.config;
    _path = cfg.bgPhoto;
    _blur = cfg.bgBlur;
    _dim = cfg.bgDim;
    _theme = C.p.id;
  }

  void _onController() {
    final cfg = controller.config;
    if (cfg.bgPhoto == _path &&
        cfg.bgBlur == _blur &&
        cfg.bgDim == _dim &&
        C.p.id == _theme) {
      return; // фон не изменился — не перерисовываем экран зря
    }
    setState(_capture);
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_path.isEmpty) {
      // ровный цвет темы, без градиентов и текстур
      return ColoredBox(color: C.bg, child: widget.child);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: BackdropImage(path: _path, blur: _blur),
        ),
        ColoredBox(
          color: C.bg.withAlpha((_dim.clamp(0.0, 0.95) * 255).round()),
        ),
        widget.child,
      ],
    );
  }
}
