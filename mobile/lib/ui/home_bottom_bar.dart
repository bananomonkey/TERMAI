// home_bottom_bar.dart — одна нижняя панель главного экрана:
// Термай и навигация (Статистика, Карта, Архив, Расход) в одном стекле.
// Глобальной плавающей панели нет — остальные экраны не перекрываются.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models.dart';
import 'archive.dart';
import 'chat.dart';
import 'mentor_avatar.dart';
import 'progress_map.dart';
import 'stats_screen.dart';
import 'theme.dart';
import 'usage_screen.dart';
import 'widgets.dart';

class HomeBottomBar extends StatelessWidget {
  const HomeBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: glass(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        background: C.button,
        child: Row(
          children: const [
            Expanded(child: _TeraiItem()),
            Expanded(
              child: _BarItem(
                icon: Icons.insights_outlined,
                label: 'Статистика',
                tooltip: 'Статистика',
                destination: StatsScreen(),
              ),
            ),
            Expanded(
              child: _BarItem(
                icon: Icons.route_outlined,
                label: 'Карта',
                tooltip: 'Карта прогресса',
                destination: ProgressMapScreen(),
              ),
            ),
            Expanded(
              child: _BarItem(
                icon: Icons.inventory_2_outlined,
                label: 'Архив',
                tooltip: 'Архив курсов',
                destination: ArchiveScreen(),
              ),
            ),
            Expanded(
              child: _BarItem(
                icon: Icons.payments_outlined,
                label: 'Расход',
                tooltip: 'Расход токенов',
                destination: UsageScreen(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeraiItem extends StatelessWidget {
  const _TeraiItem();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.mentorBusy ||
            controller.termBusy ||
            controller.generating;
        return Semantics(
          button: true,
          label: 'Открыть чат с Термаем',
          child: Tooltip(
            message: 'Открыть чат с Термаем',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(
                    pageRoute(const ChatScreen(scope: ChatScope.general)));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MentorAvatar(size: 28, speaking: busy, glow: busy),
                    const SizedBox(height: 2),
                    Text(
                      'Термай',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: busy ? C.accent : C.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Widget destination;
  const _BarItem({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(pageRoute(destination));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  child: Icon(icon, size: 21, color: C.text),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: C.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
