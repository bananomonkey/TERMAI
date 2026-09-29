// more.dart — меню «Ещё»: задача от ИИ, курс от ИИ, настройки, статистика.
import 'package:flutter/material.dart';
import '../ai.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'chat.dart';
import 'lesson.dart';
import 'review.dart';
import 'theme.dart';
import 'widgets.dart';

void showMoreSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetButton(
              icon: Icons.auto_awesome,
              title: 'Задача от ИИ',
              subtitle: 'Опиши тему — добавлю задачу в текущий курс',
              onTap: () async {
                Navigator.pop(ctx);
                final topic = await askText(context, 'Новая задача от ИИ', 'тема: например «проброс портов»');
                if (topic != null && topic.isNotEmpty) {
                  final err = await controller.generateTask(topic);
                  if (err.isNotEmpty && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            _SheetButton(
              icon: Icons.fact_check_outlined,
              title: 'Экзамен',
              subtitle: '5 задач по пройденному · оценка и бонус XP',
              onTap: () async {
                Navigator.pop(ctx);
                final err = await controller.startExam();
                if (err.isNotEmpty && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  return;
                }
                if (context.mounted) Navigator.of(context).push(pageRoute(const LessonScreen()));
              },
            ),
            const SizedBox(height: 8),
            _SheetButton(
              icon: Icons.refresh,
              title: 'Повторение',
              subtitle: 'Закладки, которые пора освежить',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(pageRoute(const ReviewScreen()));
              },
            ),
            const SizedBox(height: 8),
            _SheetButton(
              icon: Icons.work_history_outlined,
              title: 'Собеседование',
              subtitle: 'ИИ-техлид прогонит тебя по материалу курса',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(pageRoute(const ChatScreen(interview: true)));
              },
            ),
            const SizedBox(height: 8),
            _SheetButton(
              icon: Icons.cleaning_services_outlined,
              title: 'Очистить генерацию курса',
              subtitle: 'Убрать задачи от ИИ из текущего курса (если перепутались предметы)',
              onTap: () {
                Navigator.pop(ctx);
                controller.clearGeneratedTasks();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Сгенерированные задачи курса удалены')));
              },
            ),
            const SizedBox(height: 8),
            _SheetButton(
              icon: Icons.school_outlined,
              title: 'Курс от ИИ',
              subtitle: 'Опиши цель — соберу программу из курсов',
              onTap: () async {
                Navigator.pop(ctx);
                final goal = await askText(context, 'Новый курс от ИИ', 'например: хочу стать девопс-инженером');
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
              icon: Icons.bar_chart_outlined,
              title: 'Статистика и достижения',
              subtitle: null,
              onTap: () {
                Navigator.pop(ctx);
                _showStats(context);
              },
            ),
            const SizedBox(height: 8),
            _SheetButton(
              icon: Icons.settings_outlined,
              title: 'Настройки ИИ',
              subtitle: 'Провайдер, модель, ключ',
              onTap: () {
                Navigator.pop(ctx);
                _showSettings(context);
              },
            ),
            const SizedBox(height: 8),
            _SheetButton(
              icon: Icons.dangerous_outlined,
              title: 'Сбросить весь прогресс',
              subtitle: null,
              danger: true,
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: C.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Сбросить весь прогресс?'),
                    content: const Text('Весь прогресс, курсы от ИИ и достижения будут удалены безвозвратно.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена', style: TextStyle(color: C.muted))),
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
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;
  const _SheetButton({required this.icon, required this.title, this.subtitle, this.danger = false, required this.onTap});

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
                Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: danger ? C.danger : C.text)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
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
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Закрыть', style: TextStyle(color: C.accent)))],
    ),
  );
}

void _showSettings(BuildContext context) {
  final providerCtrl = TextEditingController(text: controller.config.provider);
  final keyCtrl = TextEditingController(text: controller.config.apiKey);
  final modelCtrl = TextEditingController(text: controller.config.model);
  final baseCtrl = TextEditingController(text: controller.config.baseUrl);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            caption('Тема оформления', color: C.accent),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: presetById(controller.config.theme).title,
              decoration: const InputDecoration(labelText: 'Палитра (применяется сразу)'),
              items: themePresets.map((p) => DropdownMenuItem(value: p.title, child: Text(p.title))).toList(),
              onChanged: (title) {
                final p = themePresets.firstWhere((x) => x.title == title);
                controller.config.theme = p.id;
                controller.saveConfig();
              },
            ),
            const SizedBox(height: 14),
            caption('Настройки ИИ-провайдера', color: C.accent),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: findProvider(providerCtrl.text).title,
              decoration: const InputDecoration(labelText: 'Провайдер'),
              items: providers.map((p) => DropdownMenuItem(value: p.title, child: Text(p.title))).toList(),
              onChanged: (title) {
                final p = providers.firstWhere((x) => x.title == title);
                setSheet(() {
                  providerCtrl.text = p.id;
                  baseCtrl.text = p.baseUrl;
                  modelCtrl.text = p.defaultModel;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API-ключ (sk-…)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelCtrl,
              decoration: const InputDecoration(labelText: 'Модель (пусто — из пресета)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: baseCtrl,
              decoration: const InputDecoration(labelText: 'Base URL (пусто — из пресета)'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final path = await controller.exportProgress();
                    if (ctx.mounted) {
                      showDialog(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          backgroundColor: C.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text('Экспорт готов'),
                          content: Text('Файл сохранён:\n' + path, style: const TextStyle(fontSize: 12.5)),
                          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Понятно'))],
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.upload_outlined, size: 17),
                  label: const Text('Экспорт', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final err = await controller.importProgress();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(err.isEmpty ? 'Прогресс импортирован' : err)));
                    }
                  },
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: const Text('Импорт', style: TextStyle(fontSize: 13)),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () async {
                controller.config.provider = providerCtrl.text;
                controller.config.apiKey = keyCtrl.text.trim();
                controller.config.model = modelCtrl.text.trim();
                controller.config.baseUrl = baseCtrl.text.trim();
                await controller.saveConfig();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Сохранить'),
            ),
          ],
          ),
        ),
      ),
    ),
  );
}
