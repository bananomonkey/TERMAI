// dock.dart — плавающая круглая панель главного экрана: три круглые кнопки
// без подписей. Иконки — из того же монохромного набора Material, что и
// рядом с названиями курсов (никаких разноцветных эмодзи).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'archive.dart';
import 'chats.dart';
import 'theme.dart';
import 'usage_screen.dart';
import 'widgets.dart';

class GlassDock extends StatelessWidget {
  const GlassDock({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: glass(
        radius: 22,
        blur: 0,
        background: C.button,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DockButton(
              icon: Icons.forum_outlined,
              tooltip: 'Чат с Термаем',
              onTap: () =>
                  Navigator.of(context).push(pageRoute(const ChatsScreen())),
            ),
            const SizedBox(width: 6),
            _DockButton(
              icon: Icons.inventory_2_outlined,
              tooltip: 'Архив курсов',
              onTap: () =>
                  Navigator.of(context).push(pageRoute(const ArchiveScreen())),
            ),
            const SizedBox(width: 6),
            _DockButton(
              icon: Icons.payments_outlined,
              tooltip: 'Расход токенов',
              onTap: () =>
                  Navigator.of(context).push(pageRoute(const UsageScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _DockButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: C.button2,
          ),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Icon(icon, size: 22, color: C.text),
          ),
        ),
      ),
    );
  }
}
