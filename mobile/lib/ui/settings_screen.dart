// settings_screen.dart — единый экран настроек: оформление, ИИ, резервные
// модели, синхронизация и прогресс. Один полноценный скролл, без дублей.
import 'package:flutter/material.dart';

import '../ai.dart';
import '../main.dart';
import '../store.dart';
import 'ai_fallbacks.dart';
import 'app_background.dart';
import 'background_settings.dart';
import 'help.dart';
import 'theme.dart';
import 'widgets.dart';

/// showSettings — открыть настройки с любого экрана.
void showSettings(BuildContext context) {
  Navigator.of(context).push(pageRoute(const SettingsScreen()));
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  late final TextEditingController _base;
  late String _provider;

  @override
  void initState() {
    super.initState();
    _provider = findProvider(controller.config.provider).id;
    _key = TextEditingController(text: controller.config.apiKey);
    _model = TextEditingController(text: controller.config.model);
    _base = TextEditingController(text: controller.config.baseUrl);
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _base.dispose();
    super.dispose();
  }

  Future<void> _saveAi() async {
    controller.config.provider = _provider;
    controller.config.apiKey = _key.text.trim();
    controller.config.model = _model.text.trim();
    controller.config.baseUrl = _base.text.trim();
    await controller.saveConfig();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Настройки ИИ сохранены')));
  }

  void _pickTheme(String id) {
    controller.config.theme = id;
    controller.config.themeAuto = false; // выбор сделан осознанно
    C.p = presetById(id);
    setState(() {});
    controller.saveConfig(autofill: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Настройки',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              // ---------- оформление ----------
              _SectionTitle('Оформление'),
              _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Тема',
                          style: TextStyle(fontSize: 12.5, color: C.muted)),
                      const SizedBox(height: 10),
                      _ThemePicker(
                          selected: controller.config.theme,
                          onPick: _pickTheme),
                      const SizedBox(height: 14),
                      _LinkRow(
                        icon: Icons.wallpaper_outlined,
                        title: 'Фон приложения',
                        subtitle: controller.config.bgPhoto.isEmpty
                            ? 'Своё фото, размытие и затемнение'
                            : 'Фото выбрано · размытие ${controller.config.bgBlur.round()}',
                        onTap: () => Navigator.of(context)
                            .push(pageRoute(const BackgroundSettingsScreen())),
                      ),
                    ]),
              ),
              const SizedBox(height: 18),

              // ---------- ИИ ----------
              _SectionTitle('ИИ-провайдер'),
              _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _provider,
                        decoration:
                            const InputDecoration(labelText: 'Провайдер'),
                        items: providers
                            .map((p) => DropdownMenuItem(
                                value: p.id, child: Text(p.title)))
                            .toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          final p = findProvider(id);
                          setState(() {
                            _provider = p.id;
                            _base.text = p.baseUrl;
                            _model.text = p.defaultModel;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _key,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'API-ключ (sk-…)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _model,
                        decoration: const InputDecoration(
                            labelText: 'Модель (пусто — из пресета)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _base,
                        decoration: const InputDecoration(
                            labelText: 'Base URL (пусто — из пресета)'),
                      ),
                      const SizedBox(height: 12),
                      _LinkRow(
                        icon: Icons.swap_horiz_outlined,
                        title: 'Резервные модели',
                        subtitle: controller.config.fallbacks.isEmpty
                            ? 'Подстраховка, если основной провайдер откажет'
                            : 'Подключено резервных: ${controller.config.fallbacks.length}',
                        onTap: () => Navigator.of(context)
                            .push(pageRoute(const AiFallbacksScreen())),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _saveAi,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        child: const Text('Сохранить настройки ИИ'),
                      ),
                    ]),
              ),
              const SizedBox(height: 18),

              // ---------- синхронизация ----------
              _SectionTitle('Облачная синхронизация'),
              _Panel(
                child: ListenableBuilder(
                  listenable: controller.sync,
                  builder: (context, _) {
                    final s = controller.sync;
                    if (!s.supported) {
                      return Text(
                          'Google-синхронизация доступна на Android/iOS.',
                          style: TextStyle(
                              fontSize: 12, color: C.muted, height: 1.4));
                    }
                    if (!s.configured) {
                      return Text(
                          'Не настроена. Заполни lib/firebase_options.dart и Web client ID '
                          'в sync_config.dart — после этого здесь появится вход через Google.',
                          style: TextStyle(
                              fontSize: 12, color: C.muted, height: 1.4));
                    }
                    if (!s.signedIn) {
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Войди, чтобы прогресс, чаты и настройки переносились между устройствами.',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: C.muted,
                                    height: 1.4)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: s.busy
                                    ? null
                                    : () async {
                                        final msg =
                                            await controller.signInSync();
                                        if (context.mounted && msg.isNotEmpty) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                  SnackBar(content: Text(msg)));
                                        }
                                      },
                                icon: s.busy
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: C.accent))
                                    : const Icon(Icons.login, size: 17),
                                label: const Text('Войти через Google',
                                    style: TextStyle(fontSize: 13)),
                              ),
                            ),
                          ]);
                    }
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.check_circle_outline,
                                size: 18, color: C.good),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Вход выполнен: ${s.email}',
                                  style:
                                      TextStyle(fontSize: 12.5, color: C.text)),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          // Кнопки в столбик: на узких экранах длинная подпись
                          // «Синхронизировать» не влезала в половину ширины.
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final msg = await controller.syncNow();
                                if (context.mounted && msg.isNotEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)));
                                }
                              },
                              icon: const Icon(Icons.sync, size: 17),
                              label: const Text('Синхронизировать',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => controller.signOutSync(),
                              icon: const Icon(Icons.logout, size: 17),
                              label: const Text('Выйти из аккаунта',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                          if (s.error.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(s.error,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: C.danger,
                                    height: 1.35)),
                          ],
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () => _deleteCloud(context),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                alignment: Alignment.centerLeft),
                            icon: Icon(Icons.delete_outline,
                                size: 16, color: C.danger),
                            label: Text('Удалить облачные данные',
                                style:
                                    TextStyle(fontSize: 12, color: C.danger)),
                          ),
                        ]);
                  },
                ),
              ),
              const SizedBox(height: 18),

              // ---------- прогресс ----------
              _SectionTitle('Прогресс'),
              _Panel(
                child: Row(children: [
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
                      label: const Text('Сохранить',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _importProgress(context),
                      icon: const Icon(Icons.download_outlined, size: 17),
                      label:
                          const Text('Импорт', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 18),

              // ---------- справка ----------
              _Panel(
                child: Column(children: [
                  _LinkRow(
                    icon: Icons.menu_book_outlined,
                    title: 'Инструкция',
                    subtitle: 'Как учиться, что делают экраны и кнопки',
                    onTap: () => Navigator.of(context)
                        .push(pageRoute(const HelpScreen())),
                  ),
                  const SizedBox(height: 10),
                  _LinkRow(
                    icon: Icons.bug_report_outlined,
                    title: 'Диагностика',
                    subtitle: 'Журнал ошибок, если что-то работает не так',
                    onTap: () => _showDiag(context),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text('версия 1.15.7',
                    style:
                        TextStyle(fontSize: 11, color: C.muted.withAlpha(160))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteCloud(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить облачные данные?'),
        content: const Text('Из Firestore будет удалён прогресс, чаты и email. '
            'Локальная копия останется.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text('Отмена', style: TextStyle(color: C.muted))),
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
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.isEmpty ? 'Облачные данные удалены' : err)));
  }

  void _importProgress(BuildContext context) {
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
            style:
                TextStyle(fontSize: 11, fontFamily: 'monospace', color: C.text),
            decoration:
                const InputDecoration(hintText: 'вставь JSON экспорта…'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text('Отмена', style: TextStyle(color: C.muted))),
          FilledButton(
            onPressed: () async {
              final json = ctrl.text.trim();
              if (json.isEmpty) return;
              Navigator.pop(dctx);
              final err = await controller.importProgress(json);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(err.isEmpty ? 'Прогресс импортирован' : err)));
              }
            },
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }

  void _showDiag(BuildContext context) {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Диагностика'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: SelectableText(
              diagLog.isEmpty ? 'Ошибок не зафиксировано.' : diagLog.toString(),
              style: TextStyle(fontSize: 12, color: C.text, height: 1.4),
            ),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Закрыть'))
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: C.accent)),
      );
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: C.card, borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.card2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(icon, size: 20, color: C.accent),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: C.text)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 11.5, color: C.muted)),
                  ]),
            ),
            chevron(size: 22, color: C.muted),
          ]),
        ),
      ),
    );
  }
}

/// _ThemePicker — только две палитры: Dark Modern и «Синий».
class _ThemePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onPick;
  const _ThemePicker({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in themePresets)
          GestureDetector(
            onTap: () => onPick(p.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected == p.id ? p.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration:
                      BoxDecoration(color: p.accent, shape: BoxShape.circle),
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
