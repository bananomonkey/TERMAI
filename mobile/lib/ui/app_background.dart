// app_background.dart — фон приложения: ровный цвет темы или своё фото.
// Никакого тумана и градиентов: ровный цвет темы или чёткое фото.
// Размытие фото считается один раз в ui.Image, а не в каждом кадре.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../main.dart';
import 'theme.dart';

/// BackdropImage — фото фона, размытое один раз и отрисованное как картинка.
///
/// Готовые картинки кэшируются между экранами. Иначе при переходе новая
/// страница успевала показать чёрный прямоугольник, пока снова читала файл
/// с диска и размывала его — особенно заметно на своём фото.
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
  static final Map<String, ui.Image> _cache = <String, ui.Image>{};
  static const int _cacheLimit = 4;

  ui.Image? _img;
  String _key = '';
  int _token = 0;
  Timer? _debounce;

  static String _cacheKey(BackdropImage w) =>
      '${w.path}|${w.blur.round()}|${w.maxWidth}';

  /// Клонируем картинку: кэш владеет оригиналом, виджет — своей копией.
  static ui.Image? _cached(String key) {
    final image = _cache[key];
    if (image == null) return null;
    try {
      return image.clone();
    } catch (_) {
      final broken = _cache.remove(key);
      broken?.dispose();
      return null;
    }
  }

  static void _remember(String key, ui.Image image) {
    final old = _cache.remove(key);
    old?.dispose();
    _cache[key] = image;
    while (_cache.length > _cacheLimit) {
      final first = _cache.keys.first;
      final evicted = _cache.remove(first);
      evicted?.dispose();
    }
  }

  void _disposeLater(ui.Image? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  void _useCachedOrLoad({bool rebuild = true}) {
    final key = _cacheKey(widget);
    final cached = _cached(key);
    if (cached != null) {
      final old = _img;
      if (rebuild) {
        setState(() {
          _img = cached;
          _key = key;
        });
      } else {
        _img = cached;
        _key = key;
      }
      _disposeLater(old);
      return;
    }
    _load();
  }

  @override
  void initState() {
    super.initState();
    _useCachedOrLoad(rebuild: false);
  }

  @override
  void didUpdateWidget(BackdropImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _debounce?.cancel();
      _useCachedOrLoad();
    } else if (old.blur.round() != widget.blur.round()) {
      // слайдер двигают часто — не размываем на каждый тик
      _debounce?.cancel();
      final key = _cacheKey(widget);
      final cached = _cached(key);
      if (cached != null) {
        final previous = _img;
        setState(() {
          _img = cached;
          _key = key;
        });
        _disposeLater(previous);
      } else {
        _debounce = Timer(const Duration(milliseconds: 140), _load);
      }
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
    final syncKey = _cacheKey(widget);
    if (_img != null && _key == syncKey) return;

    final cached = _cached(syncKey);
    if (cached != null) {
      if (!mounted || token != _token) {
        cached.dispose();
        return;
      }
      final old = _img;
      setState(() {
        _img = cached;
        _key = syncKey;
      });
      _disposeLater(old);
      return;
    }

    try {
      final f = File(widget.path);
      if (!await f.exists()) {
        if (mounted && token == _token) setState(() => _img = null);
        return;
      }
      final bytes = await f.readAsBytes();
      final codec =
          await ui.instantiateImageCodec(bytes, targetWidth: widget.maxWidth);
      final frame = await codec.getNextFrame();
      codec.dispose();
      var image = frame.image;

      if (widget.blur > 0) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(
          image,
          Offset.zero,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: widget.blur * 1.4,
              sigmaY: widget.blur * 1.4,
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

      // Оригинал остаётся в кэше, а экран получает лёгкую копию.
      _remember(syncKey, image);
      final display = image.clone();
      final old = _img;
      setState(() {
        _img = display;
        _key = syncKey;
      });
      _disposeLater(old);
    } catch (_) {
      if (mounted && token == _token) setState(() => _img = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    // Прозрачная заглушка вместо чёрного прямоугольника: во время перехода
    // под новой страницей остаётся виден фон предыдущей.
    if (img == null) return const SizedBox.expand();
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
    // В тёмных темах фото приглушаем чёрной вуалью, в светлой — белой:
    // иначе тёмный текст на затемнённом фото становится нечитаемым.
    final veil = C.isLight ? Colors.white : C.bg;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: BackdropImage(path: _path, blur: _blur),
        ),
        ColoredBox(
          color: veil.withAlpha((_dim.clamp(0.0, 0.95) * 255).round()),
        ),
        widget.child,
      ],
    );
  }
}
