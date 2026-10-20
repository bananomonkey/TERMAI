// dock.dart — плавающая круглая панель главного экрана: три круглые кнопки
// без подписей (💬 чат с ментором, 📦 архив курсов, 💰 расход токенов).
// Панель — то же жидкое стекло, что и карточки курсов.
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
        radius: 44,
        blur: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DockButton(
              emoji: '💬',
              tooltip: 'Чат с ментором',
              onTap: () => Navigator.of(context).push(pageRoute(const ChatsScreen())),
            ),
            const SizedBox(width: 6),
            _DockButton(
              emoji: '📦',
              tooltip: 'Архив курсов',
              onTap: () => Navigator.of(context).push(pageRoute(const ArchiveScreen())),
            ),
            const SizedBox(width: 6),
            _DockButton(
              emoji: '💰',
              tooltip: 'Расход токенов',
              onTap: () => Navigator.of(context).push(pageRoute(const UsageScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final String emoji, tooltip;
  final VoidCallback onTap;
  const _DockButton({required this.emoji, required this.tooltip, required this.onTap});

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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withAlpha(46),
                C.accent.withAlpha(30),
                Colors.black.withAlpha(28),
              ],
            ),
            border: Border.all(color: Colors.white.withAlpha(40), width: 1),
          ),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 21, height: 1)),
            ),
          ),
        ),
      ),
    );
  }
}
