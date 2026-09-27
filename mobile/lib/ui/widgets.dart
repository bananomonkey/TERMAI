// widgets.dart — общие элементы UI: карточки-«окна», подписи, плашки.
import 'package:flutter/material.dart';
import 'theme.dart';

/// cardBox — «окно»: скруглённая карточка с рамкой; [accent] подсвечивает активную.
Widget cardBox({required Widget child, Color? accent, EdgeInsets padding = const EdgeInsets.all(14)}) {
  return Container(
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accent ?? kBorder, width: accent != null ? 1.5 : 1),
    ),
    child: Padding(padding: padding, child: child),
  );
}

Widget caption(String text, {Color color = kMuted}) => Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
    ).addColor(color);

extension TextColorX on Text {
  Text addColor(Color c) {
    final s = style ?? const TextStyle();
    return Text(data ?? '', style: s.copyWith(color: c));
  }
}

/// statusGlyph — ✓ / ▶ / ○ для статуса задачи.
Widget statusGlyph(bool done, bool current, {double size = 15}) {
  final (glyph, color) = done
      ? ('✓', kGood)
      : current
          ? ('▶', kAccent)
          : ('○', kMuted);
  return Text(glyph, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700));
}

/// dots — полоска сложности ●●●○○.
Widget difficultyDots(int d, {Color? color}) {
  d = d.clamp(1, 5);
  return Text(
    '●' * d + '○' * (5 - d),
    style: TextStyle(fontSize: 10, color: color ?? kMuted, letterSpacing: 1.5),
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
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kAccent)),
        const SizedBox(height: 8),
        const Divider(),
      ],
    );
