// app_background.dart — единый фон приложения: своё фото пользователя или
// туман темы, поверх — затемнение. Размытие применяется ко всему фону и
// считается ОДИН раз в ui.Image (кэш), а не каждой перерисовкой кадра.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../main.dart';
import 'ambient.dart';
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
      // декодируем с запасом под экран — меньше памяти и быстрее blur
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
      // старую картинку этого же виджета освобождаем после кадра: без утечек
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

/// AppBackdrop — оборачивает экран: под контентом всегда есть фон
/// (фото или туман темы), затемнение и только потом сам контент.
class AppBackdrop extends StatelessWidget {
  final Widget child;

  /// false — не рисовать туман темы (например, на служебных экранах).
  final bool includeAmbient;
  const AppBackdrop(
      {super.key, required this.child, this.includeAmbient = true});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cfg = controller.config;
        final path = cfg.bgPhoto;
        final blur = cfg.bgBlur;
        final dim = cfg.bgDim.clamp(0.0, 0.95);
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: path.isNotEmpty
                  ? BackdropImage(path: path, blur: blur)
                  : (cfg.ambient && includeAmbient
                      ? AmbientBackground(blur: blur, themeId: C.p.id)
                      : ColoredBox(color: C.bg)),
            ),
            // затемнение поверх любого фона — фото и тумана одинаково
            ColoredBox(color: C.bg.withAlpha((dim * 255).round())),
            child,
          ],
        );
      },
    );
  }
}
