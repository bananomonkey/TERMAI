// settings_screen.dart — единый экран настроек: оформление, ИИ, резервные
// модели, синхронизация и прогресс. Один полноценный скролл, без дублей.
import 'dart:async';

import 'package:flutter/material.dart';

import '../ai.dart';
import '../main.dart';
import '../notifications.dart';
import '../store.dart';
import '../theme_refresh.dart';
import '../update_service.dart';
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

class SettingsScreen extends StatefulWidget implements PreserveOnTheme {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  late final TextEditingController _base;
  late final TextEditingController _name;
  late String _provider;
  bool _showKey = false;
  Timer? _nameTimer;

  @override
  void initState() {
    super.initState();
    _provider = findProvider(controller.config.provider).id;
    _key = TextEditingController(text: controller.config.apiKey);
    _model = TextEditingController(text: controller.config.model);
    _base = TextEditingController(text: controller.config.baseUrl);
    _name = TextEditingController(text: controller.config.userName);
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    _key.dispose();
    _model.dispose();
    _base.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await controller.setUserName(_name.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Имя сохранено')));
  }

  Future<void> _testNotification() async {
    final ok = await notificationService.showTest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Тестовое уведомление отправлено'
          : 'Уведомления запрещены — разреши их в настройках Android'),
    ));
  }

  Future<void> _pickReminderTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: controller.config.reminderHour,
        minute: controller.config.reminderMinute,
      ),
      helpText: 'Время напоминания',
    );
    if (t == null) return;
    await controller.setReminderTime(t.hour, t.minute);
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
    setState(() {});
    controller.saveConfig(autofill: false);
  }

  Future<void> _generateTheme(BuildContext context) async {
    final ctrl = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Тема по описанию'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Например: тёмная тема в стиле киберпанка, '
                'неоновый бирюзовый акцент, мягкий графит',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text('Отмена', style: TextStyle(color: C.muted))),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (prompt == null || prompt.isEmpty || !context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: C.surface,
        content: Row(children: [
          SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
          const SizedBox(width: 14),
          const Expanded(child: Text('ИИ собирает палитру…')),
        ]),
      ),
    );
    final err = await controller.generateCustomTheme(prompt);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err.isEmpty
          ? 'Тема создана и сохранена'
          : err),
    ));
  }

  Future<void> _checkUpdates(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: C.surface,
        content: Row(children: [
          SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
          const SizedBox(width: 14),
          const Expanded(child: Text('Проверяю обновления…')),
        ]),
      ),
    );
    try {
      final info = await UpdateService.check();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (!info.available) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('У тебя последняя версия ${info.current}')));
        return;
      }
      final open = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: C.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Доступна версия ${info.latest}'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Text(
                info.notes.isEmpty
                    ? 'Скачай новый APK и установи поверх старой версии.'
                    : info.notes,
                style: TextStyle(fontSize: 12.5, color: C.text, height: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: Text('Позже', style: TextStyle(color: C.muted))),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Скачать'),
            ),
          ],
        ),
      );
      if (open == true) {
        final url = info.apkUrl.isNotEmpty ? info.apkUrl : info.releaseUrl;
        final ok = await UpdateService.open(url);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Не удалось открыть браузер для скачивания')));
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось проверить обновления: $e')));
    }
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
                      const SizedBox(height: 8),
                      _CustomThemes(
                        selected: controller.config.theme,
                        onPick: _pickTheme,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _generateTheme(context),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft),
                        icon: Icon(Icons.auto_awesome, size: 18, color: C.accent),
                        label: Text('Сгенерировать тему ИИ',
                            style: TextStyle(fontSize: 12.5, color: C.accent)),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Показывать Термая',
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: C.text)),
                        subtitle: Text(
                          'Плавающий персонаж на экранах приложения',
                          style:
                              TextStyle(fontSize: 11.5, color: C.muted),
                        ),
                        value: controller.config.mascotVisible,
                        activeThumbColor: C.accent,
                        onChanged: controller.setMascotVisible,
                      ),
                      const SizedBox(height: 16),
                      Text('Яркость кнопок',
                          style: TextStyle(fontSize: 12.5, color: C.muted)),
                      Row(children: [
                        Expanded(
                          child: Slider(
                            value: controller.config.buttonBrightness,
                            min: 0.6,
                            max: 1.4,
                            divisions: 16,
                            label:
                                '${(controller.config.buttonBrightness * 100).round()}%',
                            onChanged: (v) {
                              controller.setButtonBrightness(v);
                            },
                            onChangeEnd: (v) {
                              controller.setButtonBrightness(v, persist: true);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                              '${(controller.config.buttonBrightness * 100).round()}%',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 13, color: C.muted)),
                        ),
                      ]),
                      Text(
                          'Док, быстрые кнопки и основные действия: темнее или светлее.',
                          style: TextStyle(
                              fontSize: 11.5, color: C.muted, height: 1.35)),
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

              // ---------- профиль ----------
              _SectionTitle('Профиль'),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration:
                          const InputDecoration(labelText: 'Как тебя зовут'),
                      onChanged: (v) {
                        // автосохранение: не нужно каждый раз жать кнопку
                        _nameTimer?.cancel();
                        _nameTimer = Timer(const Duration(milliseconds: 800),
                            () => controller.setUserName(v));
                      },
                      onSubmitted: (_) => _saveName(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Термай обращается по имени в чате и уведомлениях. '
                      'Можно оставить пустым.',
                      style: TextStyle(
                          fontSize: 11.5, color: C.muted, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _saveName,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44)),
                      child: const Text('Сохранить имя'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ---------- уведомления ----------
              _SectionTitle('Уведомления'),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Напоминания',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: C.text)),
                      subtitle: Text(
                        'Ежедневное напоминание и редкие сообщения от Термая',
                        style: TextStyle(fontSize: 11.5, color: C.muted),
                      ),
                      value: controller.config.notificationsEnabled,
                      activeThumbColor: C.accent,
                      onChanged: (v) =>
                          controller.setNotificationsEnabled(v),
                    ),
                    Divider(color: C.border, height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Ежедневное напоминание',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: C.text)),
                      subtitle: Text(
                        'Короткая готовая фраза в выбранное время',
                        style: TextStyle(fontSize: 11.5, color: C.muted),
                      ),
                      value: controller.config.dailyReminderEnabled,
                      activeThumbColor: C.accent,
                      onChanged: controller.config.notificationsEnabled
                          ? (v) => controller.setDailyReminderEnabled(v)
                          : null,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: controller.config.notificationsEnabled &&
                          controller.config.dailyReminderEnabled,
                      onTap: controller.config.notificationsEnabled &&
                              controller.config.dailyReminderEnabled
                          ? _pickReminderTime
                          : null,
                      title: Text('Время напоминания',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: C.text)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          '${controller.config.reminderHour.toString().padLeft(2, '0')}:'
                          '${controller.config.reminderMinute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: C.accent),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.schedule_outlined,
                            size: 18, color: C.muted),
                      ]),
                    ),
                    Divider(color: C.border, height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Мотивация от ИИ',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: C.text)),
                      subtitle: Text(
                        'Иногда Термай заранее составит уникальное сообщение',
                        style: TextStyle(fontSize: 11.5, color: C.muted),
                      ),
                      value: controller.config.aiMotivationEnabled,
                      activeThumbColor: C.accent,
                      onChanged: controller.config.notificationsEnabled
                          ? (v) => controller.setAiMotivationEnabled(v)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _testNotification,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42)),
                      icon: const Icon(Icons.notifications_active_outlined,
                          size: 17),
                      label: const Text('Проверить уведомление',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
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
                        obscureText: !_showKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'API-ключ (sk-…)',
                          suffixIcon: IconButton(
                            tooltip:
                                _showKey ? 'Скрыть ключ' : 'Показать ключ',
                            icon: Icon(
                              _showKey
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: C.muted,
                            ),
                            onPressed: () =>
                                setState(() => _showKey = !_showKey),
                          ),
                        ),
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
                          // Переключатель отправки ключей в облако.
                          // По умолчанию включено: ключи и фолбэки уходят в
                          // Google-облако вместе с прогрессом. Можно выключить,
                          // тогда ключи останутся только на этом устройстве.
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Синхронизировать ключи ИИ в облако',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: C.text)),
                            subtitle: Text(
                              'apiKey и резервные модели будут доступны на '
                              'других устройствах после входа в аккаунт.',
                              style: TextStyle(
                                  fontSize: 11.5, color: C.muted, height: 1.3),
                            ),
                            value: controller.config.syncKeysToCloud,
                            activeColor: C.accent,
                            onChanged: (v) async {
                              controller.config.syncKeysToCloud = v;
                              await controller.saveConfig(autofill: false);
                              if (v && controller.sync.signedIn) {
                                final msg = await controller.syncConfig();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(msg.isEmpty
                                              ? 'Настройки и ключи сохранены в облако'
                                              : msg)));
                                }
                              } else if (controller.sync.signedIn) {
                                // Сразу перезаписываем облако конфигом без ключей.
                                final msg =
                                    await controller.syncConfig(pullFirst: false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(msg.isEmpty
                                              ? 'Ключи удалены из облака и больше не отправляются'
                                              : msg)));
                                }
                              } else if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Ключи больше не отправляются в облако')));
                              }
                            },
                          ),
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
              _Panel(
                child: _LinkRow(
                  icon: Icons.system_update_alt,
                  title: 'Проверить обновления',
                  subtitle: 'Скачать свежий APK с GitHub',
                  onTap: () => _checkUpdates(context),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text('версия 1.18.1',
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
        content: const Text('Из Firestore будет удалён прогресс, чаты, '
            'настройки и email. Локальная копия останется.'),
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
  Widget build(BuildContext context) => Material(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: child,
        ),
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
      color: C.button2,
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

/// _CustomThemes — палитры, созданные ИИ. Можно выбрать или удалить.
class _CustomThemes extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onPick;
  const _CustomThemes({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final themes = controller.config.customThemes;
    if (themes.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in themes)
          Builder(builder: (context) {
            final p = presetFromCustom(t);
            final active = selected == t.id;
            return GestureDetector(
              onTap: () => onPick(t.id),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? p.accent : p.border,
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
                  Text(t.title,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: p.text)),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () async {
                      await controller.deleteCustomTheme(t.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Тема удалена')));
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14, color: p.muted),
                    ),
                  ),
                ]),
              ),
            );
          }),
      ],
    );
  }
}

/// _ThemePicker — три палитры: Dark Modern, «Синий» и «Светлая».
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected == p.id ? p.accent : p.border,
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
