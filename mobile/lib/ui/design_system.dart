// design_system.dart — общие токены и компактные компоненты TERMAI.
// Экраны постепенно переводятся с самодельных вложенных контейнеров на
// эти элементы: так проще держать единый ритм отступов, радиусов и текста.
import 'package:flutter/material.dart';

import 'theme.dart';

/// Шаг сетки отступов. Значения намеренно небольшие: интерфейс мобильный.
class AppSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
}

class AppRadius {
  static const double chip = 10;
  static const double field = 12;
  static const double card = 16;
  static const double panel = 20;
  static const double dock = 22;
  static const double sheet = 24;
}

class AppDuration {
  static const fast = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}

/// Текстовая иерархия: один заголовок экрана, секции, основной текст,
/// вторичный текст. Не используем разный вес на каждом экране.
class AppText {
  static const TextStyle screenTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
  );

  static const TextStyle section = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.05,
  );

  static const TextStyle title = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle body = TextStyle(
    fontSize: 13,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 1.35,
  );

  static const TextStyle mono = TextStyle(
    fontSize: 12,
    fontFamily: 'monospace',
    height: 1.35,
  );
}

Widget appSectionTitle(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, AppSpace.x1, 2, AppSpace.x2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: AppText.section.copyWith(color: C.accent),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );

/// appCard — базовая поверхность. Без лишней рамки; акцент — только когда
/// он действительно несёт состояние (текущий курс, ошибка, экзамен).
Widget appCard({
  required Widget child,
  EdgeInsets padding = const EdgeInsets.all(AppSpace.x3),
  EdgeInsets? margin,
  Color? color,
  Color? accent,
  double radius = AppRadius.card,
  double? glowAlpha,
  Color? glowColor,
  VoidCallback? onTap,
}) {
  final decorated = Container(
    margin: margin,
    decoration: BoxDecoration(
      color: color ?? C.card,
      borderRadius: BorderRadius.circular(radius),
      border: accent == null ? null : Border.all(color: accent, width: 1.2),
      boxShadow: [
        if (glowAlpha != null && glowAlpha > 0)
          BoxShadow(
            color: (glowColor ?? C.accent)
                .withAlpha(glowAlpha.clamp(0, 160).round()),
            blurRadius: 30,
            spreadRadius: -7,
            offset: const Offset(0, 10),
          ),
      ],
    ),
    child: Padding(padding: padding, child: child),
  );
  if (onTap == null) return decorated;
  return Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: decorated),
  );
}

/// appRow — компактная строка-ссылка. Заменяет большие card-in-card блоки.
Widget appRow({
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
  Color? iconColor,
  bool danger = false,
}) {
  final fg = danger ? C.danger : C.text;
  return Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(AppRadius.field),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.x2,
          vertical: AppSpace.x3,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: iconColor ?? (danger ? C.danger : C.muted),
            ),
            const SizedBox(width: AppSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(color: fg),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: C.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpace.x2),
              trailing,
            ] else if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 21, color: C.muted),
          ],
        ),
      ),
    ),
  );
}

Widget appDivider() => Divider(color: C.border.withAlpha(120), height: 1);

Widget appEmptyState({
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? action,
}) =>
    Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: C.muted.withAlpha(170)),
            const SizedBox(height: AppSpace.x3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.title.copyWith(color: C.text),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpace.x1),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: C.muted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpace.x4),
              action,
            ],
          ],
        ),
      ),
    );

Widget appSheetHandle() => Center(
      child: Container(
        width: 42,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppSpace.x4),
        decoration: BoxDecoration(
          color: C.muted.withAlpha(90),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

/// appStatusPill — маленький статус без тяжёлой рамки.
Widget appStatusPill(
  String text, {
  Color? color,
  IconData? icon,
}) {
  final fg = color ?? C.accent;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: fg.withAlpha(C.isLight ? 16 : 24),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
