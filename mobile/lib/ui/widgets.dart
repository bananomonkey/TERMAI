// widgets.dart — общие элементы UI: карточки-«окна», подписи, плашки.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'theme.dart';

/// glass — «жидкое стекло»: размытие фона + градиентная линза + мягкая тень.
/// [glow] рисует свечение под элементом (у активного курса — зелёное).
/// [glowColor] переопределяет цвет свечения, [radius] — скругление.
Widget glass({
  required Widget child,
  double radius = 20,
  double blur = 36,
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
            blurRadius: 38,
            spreadRadius: -2,
            offset: const Offset(0, 10),
          ),
        BoxShadow(
          color: Colors.black.withAlpha(70),
          blurRadius: 24,
          offset: const Offset(0, 10),
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
            border: Border.all(color: Colors.white.withAlpha(26), width: 1),
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

/// cardBox — «окно»: скруглённая карточка с рамкой; [accent] подсвечивает активную.
Widget cardBox({required Widget child, Color? accent, EdgeInsets padding = const EdgeInsets.all(14)}) {
  return Container(
    decoration: BoxDecoration(
      color: C.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accent ?? C.border, width: accent != null ? 1.5 : 1),
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

/// statusGlyph — ✓ / ▶ / ○ для статуса задачи.
Widget statusGlyph(bool done, bool current, {double size = 15}) {
  final (glyph, color) = done
      ? ('✓', C.good)
      : current
          ? ('▶', C.accent)
          : ('○', C.muted);
  return Text(glyph, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700));
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

/// sectionHeader — «5 задач: тема» с разделителем, как в Coddy.
Widget sectionHeader(String text) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.accent)),
        const SizedBox(height: 8),
        const Divider(),
      ],
    );
