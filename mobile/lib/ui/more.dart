// more.dart — меню «Ещё»: быстрые действия, справка и переход в настройки.
// Синхронизация и настройки ИИ живут в одном экране SettingsScreen,
// поэтому дублирующих пунктов здесь больше нет.
import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'ai_fallbacks.dart';
import 'background_settings.dart';
import 'chat.dart';
import 'help.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

void showMoreSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: C.muted.withAlpha(90),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _SheetButton(
            icon: Icons.menu_book_outlined,
            title: 'Инструкция',
            subtitle: 'Как учиться и что делает каждый экран',
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(pageRoute(const HelpScreen()));
            },
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.bar_chart_outlined,
            title: 'Статистика и достижения',
            subtitle: 'XP, серия и открытые награды',
            onTap: () {
              Navigator.pop(ctx);
              _showStats(context);
            },
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.school_outlined,
            title: 'Курс от ИИ',
            subtitle: 'Опиши цель — соберу программу из курсов',
            onTap: () async {
              Navigator.pop(ctx);
              final goal = await askText(context, 'Новый курс от ИИ',
                  'например: английский с нуля или хочу стать DevOps-инженером');
              if (goal != null && goal.isNotEmpty) {
                final err = await controller.generateCourses(goal);
                if (err.isNotEmpty && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              }
            },
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.chat_bubble_outline,
            title: 'Ментор',
            subtitle: 'Спроси о задаче, синтаксисе, ошибке',
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(pageRoute(const ChatScreen()));
            },
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.wallpaper_outlined,
            title: 'Фон приложения',
            subtitle: 'Своё фото, размытие и затемнение',
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(pageRoute(const BackgroundSettingsScreen()));
            },
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.swap_horiz_outlined,
            title: 'Резервные модели',
            subtitle: controller.config.fallbacks.isEmpty
                ? 'Подстраховка, если основной провайдер откажет'
                : 'Подключено резервных: ${controller.config.fallbacks.length}',
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(pageRoute(const AiFallbacksScreen()));
            },
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.settings_outlined,
            title: 'Настройки',
            subtitle: 'Тема, ИИ, синхронизация и прогресс',
            onTap: () {
              Navigator.pop(ctx);
              showSettings(context);
            },
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.cleaning_services_outlined,
            title: 'Очистить генерацию курса',
            subtitle: 'Убрать задачи от ИИ из текущего курса',
            onTap: () {
              Navigator.pop(ctx);
              controller.clearGeneratedTasks();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Сгенерированные задачи курса удалены')));
            },
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.dangerous_outlined,
            title: 'Сбросить весь прогресс',
            subtitle: 'Удалить прогресс, курсы от ИИ и достижения',
            danger: true,
            onTap: () {
              Navigator.pop(ctx);
              _confirmReset(context);
            },
          ),
        ],
      ),
    ),
  );
}

void _confirmReset(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Сбросить весь прогресс?'),
      content: const Text('Весь прогресс, курсы от ИИ и достижения будут удалены безвозвратно.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: C.muted))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.danger),
          onPressed: () {
            Navigator.pop(ctx);
            controller.prog = Progress();
            controller.saveProgress();
            controller.termText = '';
            controller.chatMsgs = [];
            controller.notifyListeners();
          },
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;
  const _SheetButton({
    required this.icon,
    required this.title,
    this.subtitle,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            Icon(icon, size: 22, color: danger ? C.danger : C.accent),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: danger ? C.danger : C.text)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
            chevron(size: 22, color: danger ? C.danger : C.muted),
          ]),
        ),
      ),
    );
  }
}

void _showStats(BuildContext context) {
  final p = controller.prog;
  final ach = achievementList
      .map((a) => (p.achieved.containsKey(a.id) ? '✓ ' : '○ ') + a.title + ' — ' + a.desc)
      .join('\n');
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Статистика'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Уровень ${p.level} · ${p.xp} XP'),
          Text('Решено задач: ${p.solvedTotal}'),
          Text('Серия: ${p.streak} дн. подряд'),
          const SizedBox(height: 12),
          caption('Достижения', color: C.accent),
          const SizedBox(height: 6),
          Text(ach, style: TextStyle(fontSize: 12.5, height: 1.6, color: C.muted)),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Закрыть', style: TextStyle(color: C.accent)))
      ],
    ),
  );
}
