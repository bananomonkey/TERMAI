// app_background.dart — фон приложения: своё фото пользователя с регулируемым
// размытием и затемнением. Если фото нет — обычный фон темы (и туман на карте).
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../main.dart';
import 'theme.dart';

/// AppBackdrop — оборачивает содержимое экрана: под ним фото (или ничего).
class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final path = controller.config.bgPhoto;
        if (path.isEmpty) return child;
        final blur = controller.config.bgBlur;
        final dim = controller.config.bgDim;
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blur,
                    sigmaY: blur,
                    tileMode: TileMode.decal,
                  ),
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) => ColoredBox(color: C.bg),
                  ),
                ),
              ),
            ),
            ColoredBox(color: C.bg.withAlpha((dim * 255).round().clamp(0, 255))),
            child,
          ],
        );
      },
    );
  }
}
