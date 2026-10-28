// widgets.dart — общие элементы UI: карточки-«окна», подписи, плашки.
import 'package:flutter/material.dart';
import '../theme_refresh.dart';
import 'theme.dart';

/// glass — карточка в стиле «стекла»: полупрозрачная заливка и мягкая тень.
/// Без BackdropFilter: размытие на каждой плитке списка сильно тормозило
/// прокрутку и переключения. Визуально то же стекло, но дешевле для GPU.
Widget glass({
  required Widget child,
  double radius = 20,
  double blur = 0,
  EdgeInsets padding = const EdgeInsets.all(0),
  Color? glow,
  Color? tint,
  Color? background,
  bool lens = true,
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: (background ?? C.card).withAlpha(228),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        if (glow != null)
          BoxShadow(
            color: glow,
            blurRadius: 26,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        BoxShadow(
          color: Colors.black.withAlpha(55),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
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
Widget cardBox(
    {required Widget child,
    Color? accent,
    EdgeInsets padding = const EdgeInsets.all(14),
    Duration duration = Duration.zero}) {
  return AnimatedContainer(
    duration: duration,
    curve: Curves.easeOutCubic,
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
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
    ).addColor(color ?? C.muted);

extension TextColorX on Text {
  Text addColor(Color c) {
    final s = style ?? const TextStyle();
    return Text(data ?? '', style: s.copyWith(color: c));
  }
}

/// statusGlyph — аккуратный круглый статус задачи:
/// ✓ выполнено, ▶ текущая, ○ впереди. Фиксированный размер не даёт
/// иконке «плавать» относительно заголовка.
Widget statusGlyph(bool done, bool current, {double size = 24}) {
  final color = done
      ? C.good
      : current
          ? C.accent
          : C.muted;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withAlpha(done || current ? 34 : 12),
      border: Border.all(
        color: color.withAlpha(done || current ? 150 : 80),
        width: 1.2,
      ),
      boxShadow: current
          ? [
              BoxShadow(
                color: color.withAlpha(45),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ]
          : null,
    ),
    child: Icon(
      done
          ? Icons.check_rounded
          : current
              ? Icons.play_arrow_rounded
              : Icons.circle_outlined,
      size: size * 0.62,
      color: color,
    ),
  );
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
PageRouteBuilder<T> pageRoute<T>(Widget page, {String? name}) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: name ?? page.runtimeType.toString()),
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    // Обёртка перекрашивает страницу при смене темы, не сбрасывая стек
    // навигации. Ключ меняется только вместе с палитрой.
    pageBuilder: (_, __, ___) => ValueListenableBuilder<int>(
      valueListenable: themeRevision,
      builder: (_, rev, __) => KeyedSubtree(
        // Страницы, которые сами слушают controller, не сбрасываем.
        key: ValueKey(page is PreserveOnTheme
            ? 'page-${page.runtimeType}'
            : 'theme-$rev-${C.p.id}'),
        child: page,
      ),
    ),
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutQuint);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// sectionHeader — заголовок секции без лишних линий-обводок.
Widget sectionHeader(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(text,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: C.accent)),
    );
