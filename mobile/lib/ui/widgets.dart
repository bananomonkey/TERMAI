// widgets.dart — общие элементы UI: карточки-«окна», подписи, плашки.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'theme.dart';

/// glass — «жидкое стекло»: размытие фона + градиентная линза + мягкая тень.
/// [glow] рисует свечение под элементом (у активного курса — зелёное).
/// Без рамки: секции курсов не должны иметь обводок.
Widget glass({
  required Widget child,
  double radius = 20,
  double blur = 22,
  EdgeInsets padding = const EdgeInsets.all(0),
  Color? glow,
  Color? tint,
  bool lens = true,
}) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        if (glow != null)
          BoxShadow(
            color: glow,
            blurRadius: 30,
            spreadRadius: -3,
            offset: const Offset(0, 8),
          ),
        BoxShadow(
          color: Colors.black.withAlpha(60),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: tint != null && !lens
                  ? [tint.withAlpha(40), tint.withAlpha(14)]
                  : C.glassGradient,
              stops: const [0.0, 0.45, 0.78, 1.0],
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// chevron — единый выразительный шеврон «›» для строк и плиток.
Widget chevron({double size = 26, Color? color}) => Icon(
      Icons.chevron_right_rounded,
      size: size,
      color: color ?? C.muted,
    );

/// cardBox — «окно»: скруглённая карточка; [accent] подсвечивает активную.
/// По умолчанию без рамки — лишние обводки у секций не нужны.
Widget cardBox({required Widget child, Color? accent, EdgeInsets padding = const EdgeInsets.all(14)}) {
  return Container(
    decoration: BoxDecoration(
      color: C.card,
      borderRadius: BorderRadius.circular(16),
      border: accent != null ? Border.all(color: accent, width: 1.4) : null,
    ),
    child: Padding(padding: padding, child: child),
  );
}

Widget caption(String text, {Color? color}) => Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
    ).addColor(color ?? C.muted);

extension TextColorX on Text {
  Text addColor(Color c) {
    final s = style ?? const TextStyle();
    return Text(data ?? '', style: s.copyWith(color: c));
  }
}

/// statusGlyph — ✓ / ▶ / ○ для статуса задачи (монохромные иконки,
/// как и остальные символы интерфейса).
Widget statusGlyph(bool done, bool current, {double size = 15}) {
  final (icon, color) = done
      ? (Icons.check_circle_outline, C.good)
      : current
          ? (Icons.play_circle_outline, C.accent)
          : (Icons.radio_button_unchecked, C.muted);
  return Icon(icon, size: size + 2, color: color);
}

/// dots — полоска сложности ●●●○○.
Widget difficultyDots(int d, {Color? color}) {
  d = d.clamp(1, 5);
  return Text(
    '●' * d + '○' * (5 - d),
    style: TextStyle(fontSize: 10, color: color ?? C.muted, letterSpacing: 1.5),
  );
}

/// pageRoute — переход снизу с fade, как в Coddy.
PageRouteBuilder<T> pageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// sectionHeader — заголовок секции без лишних линий-обводок.
Widget sectionHeader(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.accent)),
    );
