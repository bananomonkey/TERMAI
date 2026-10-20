// more.dart — меню «Ещё»: задача от ИИ, курс от ИИ, настройки, статистика.
import 'package:flutter/material.dart';
import '../ai.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'ai_fallbacks.dart';
import 'background_settings.dart';
import 'chat.dart';
import 'theme.dart';
import 'widgets.dart';

void showMoreSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            _SheetButton(
              icon: Icons.bug_report_outlined,
              title: 'Диагностика',
              subtitle: 'Показать ошибки, если что-то работает не так',
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    backgroundColor: C.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Диагностика'),
                    content: SizedBox(
                      width: 320,
                      child: SelectableText(
                        diagLog.isEmpty
                            ? 'Ошибок не зафиксировано.'
                            : diagLog.toString(),
                        style: TextStyle(fontSize: 12, color: C.text, height: 1.4),
                      ),
                    ),
                    actions: [FilledButton(onPressed: () => Navigator.pop(dctx), child: const Text('Закрыть'))],
                  ),
                );
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
              icon: Icons.cloud_sync_outlined,
              title: 'Синхронизация прогресса',
              subtitle: controller.sync.signedIn
                  ? 'Вход: ${controller.sync.email}'
                  : 'Google-вход и облачная копия',
              onTap: () {
                Navigator.pop(ctx);
                _showSettings(context);
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
              icon: Icons.swap_horiz_outlined,
              title: 'Резервные модели',
              subtitle: controller.config.fallbacks.isEmpty
                  ? 'Если основной провайдер откажет — подстрахует резервный'
                  : 'Подключено резервных: ${controller.config.fallbacks.length}',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(pageRoute(const AiFallbacksScreen()));
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

/// _ThemePicker — выбор палитры: перекрашивает всё приложение сразу.
/// Тёмно-синяя тема — один из вариантов, а не основа.
class _ThemePicker extends StatelessWidget {
  final StateSetter setSheet;
  const _ThemePicker({required this.setSheet});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in themePresets)
          GestureDetector(
            onTap: () async {
              controller.config.theme = p.id;
              C.p = presetById(p.id);
              setSheet(() {});
              await controller.saveConfig(autofill: false);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: controller.config.theme == p.id ? p.accent : p.border,
                  width: controller.config.theme == p.id ? 2 : 1,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(p.title,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: p.text)),
              ]),
            ),
          ),
      ],
    );
  }
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
            const SizedBox(height: 14),
            caption('Тема оформления', color: C.accent),
            const SizedBox(height: 10),
            _ThemePicker(setSheet: setSheet),
            const SizedBox(height: 18),
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
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(pageRoute(const AiFallbacksScreen()));
              },
              icon: const Icon(Icons.swap_horiz_outlined, size: 18),
              label: Text(
                'Резервные модели (${controller.config.fallbacks.length})',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final path = await controller.exportProgressToFile();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(path.isEmpty
                          ? 'Не удалось сохранить файл прогресса'
                          : 'Сохранено и скопировано в буфер: $path'),
                      duration: const Duration(seconds: 4),
                    ));
                  },
                  icon: const Icon(Icons.save_alt_outlined, size: 17),
                  label: const Text('Сохранить', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final ctrl = TextEditingController();
                    showDialog(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        backgroundColor: C.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('Импорт прогресса'),
                        content: SizedBox(
                          width: 320,
                          child: TextField(
                            controller: ctrl,
                            maxLines: 6,
                            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: C.text),
                            decoration: const InputDecoration(
                                hintText: 'вставь JSON экспорта…'),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dctx), child: Text('Отмена', style: TextStyle(color: C.muted))),
                          FilledButton(
                            onPressed: () async {
                              final json = ctrl.text.trim();
                              if (json.isEmpty) return;
                              Navigator.pop(dctx);
                              final err = await controller.importProgress(json);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(err.isEmpty ? 'Прогресс импортирован' : err)));
                              }
                            },
                            child: const Text('Импортировать'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: const Text('Импорт', style: TextStyle(fontSize: 13)),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            caption('Облачная синхронизация', color: C.accent),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: controller.sync,
              builder: (_, __) {
                final s = controller.sync;
                if (!s.supported) {
                  return Text('Google-синхронизация доступна на Android/iOS.',
                      style: TextStyle(fontSize: 12, color: C.muted, height: 1.35));
                }
                if (!s.configured) {
                  return Text(
                      'Не настроена. Заполни lib/firebase_options.dart и Web client ID '
                      'в sync_config.dart — после этого здесь появится вход через Google.',
                      style: TextStyle(fontSize: 12, color: C.muted, height: 1.35));
                }
                if (!s.signedIn) {
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: s.busy
                          ? null
                          : () async {
                              final msg = await controller.signInSync();
                              if (context.mounted && msg.isNotEmpty) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text(msg)));
                              }
                            },
                      icon: s.busy
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                          : const Icon(Icons.login, size: 17),
                      label: const Text('Войти через Google', style: TextStyle(fontSize: 13)),
                    ),
                  );
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Вход выполнен: ${s.email}',
                      style: TextStyle(fontSize: 12.5, color: C.text)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final msg = await controller.syncNow();
                          if (context.mounted && msg.isNotEmpty) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(msg)));
                          }
                        },
                        icon: const Icon(Icons.sync, size: 17),
                        label: const Text('Синхронизировать', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => controller.signOutSync(),
                        icon: const Icon(Icons.logout, size: 17),
                        label: const Text('Выйти', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  ]),
                  if (s.error.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(s.error,
                        style: TextStyle(fontSize: 11.5, color: C.danger, height: 1.35)),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            backgroundColor: C.surface,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            title: const Text('Удалить облачные данные?'),
                            content: const Text(
                                'Из Firestore будет удалён прогресс, чаты и email. '
                                'Локальная копия останется.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(dctx, false),
                                  child: Text('Отмена',
                                      style: TextStyle(color: C.muted))),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: C.danger),
                                onPressed: () => Navigator.pop(dctx, true),
                                child: const Text('Удалить'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        final err = await controller.sync.deleteCloudData();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(err.isEmpty
                                  ? 'Облачные данные удалены'
                                  : err)));
                        }
                      },
                      icon: Icon(Icons.delete_outline, size: 16, color: C.danger),
                      label: Text('Удалить облачные данные',
                          style: TextStyle(fontSize: 12, color: C.danger)),
                    ),
                  ),
                ]);
              },
            ),
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
