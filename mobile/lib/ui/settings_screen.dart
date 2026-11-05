// settings_screen.dart — единый экран настроек: оформление, ИИ, резервные
// модели, синхронизация и прогресс. Один полноценный скролл, без дублей.
import 'dart:async';

import 'package:flutter/material.dart';

import '../ai.dart';
import '../main.dart';
import '../models.dart';
import '../notifications.dart';
import '../shared_ai.dart';
import '../theme_refresh.dart';
import '../update_service.dart';
import 'ai_fallbacks.dart';
import 'app_background.dart';
import 'background_settings.dart';
import 'design_system.dart';
import 'dialogs.dart';
import 'direction_picker.dart';
import 'help.dart';
import 'shared_ai_consent.dart';
import 'theme.dart';
import 'tts_settings.dart';
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

  Future<void> _pickDirections() async {
    final selected = await showDirectionPicker(
      context,
      selected: controller.config.directions.toSet(),
    );
    if (selected == null || !mounted) return;
    await controller.setDirections(
      selected,
      active: controller.config.activeDirection,
    );
    if (mounted) setState(() {});
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
    final profile = AiEndpoint(
      provider: _provider,
      apiKey: _key.text.trim(),
      model: _model.text.trim(),
      baseUrl: _base.text.trim(),
    );
    controller.config.providerProfiles[_provider] = profile;
    controller.config.provider = _provider;
    controller.config.apiKey = profile.apiKey;
    controller.config.model = profile.model;
    controller.config.baseUrl = profile.baseUrl;
    await controller.saveConfig();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Настройки ИИ сохранены')));
  }

  void _rememberProvider() {
    controller.config.providerProfiles[_provider] = AiEndpoint(
      provider: _provider,
      apiKey: _key.text.trim(),
      model: _model.text.trim(),
      baseUrl: _base.text.trim(),
    );
  }

  Future<void> _toggleShared(bool value) async {
    final service = SharedAiService.instance;
    if (value && !service.signedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Общий доступ включается после входа через Google — войди ниже в разделе синхронизации.'),
        ));
      }
      return;
    }
    if (value &&
        controller.config.sharedAiConsentVersion < service.noticeVersion) {
      final ok = await askSharedAiConsent(
        context,
        reConsent: controller.config.sharedAiConsentVersion > 0,
      );
      if (!ok) return;
      controller.config.sharedAiConsentVersion = service.noticeVersion;
    }
    controller.config.sharedAiEnabled = value;
    if (!value) controller.config.sharedAiConsentVersion = -1;
    await controller.saveConfig(autofill: false);
    if (mounted) setState(() {});
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
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
          const SizedBox(width: 14),
          const Expanded(child: Text('ИИ собирает палитру…')),
        ]),
      ),
    );
    final err = await controller.generateCustomTheme(prompt);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err.isEmpty ? 'Тема создана и сохранена' : err),
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
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
          const SizedBox(width: 14),
          const Expanded(child: Text('Проверяю обновления…')),
        ]),
      ),
    );
    try {
      final info = await controller.checkUpdates(force: true);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (info == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(controller.updateError.isEmpty
                ? 'Не удалось проверить обновления'
                : controller.updateError)));
        return;
      }
      if (!info.available) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('У тебя последняя версия ${info.current}')));
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
        title: const Text('Настройки', style: AppText.screenTitle),
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
                        icon:
                            Icon(Icons.auto_awesome, size: 18, color: C.accent),
                        label: Text('Сгенерировать тему ИИ',
                            style: TextStyle(fontSize: 12.5, color: C.accent)),
                      ),
                      const SizedBox(height: 8),
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

              // ---------- направления ----------
              _SectionTitle('Направления'),
              _Panel(
                child: _LinkRow(
                  icon: Icons.route_outlined,
                  title: controller.selectedDirections
                      .map((d) => d.shortTitle)
                      .join(' · '),
                  subtitle:
                      'Выбрано: ${controller.selectedDirections.length}. Можно учить несколько параллельно.',
                  onTap: _pickDirections,
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
                      onChanged: (v) => controller.setNotificationsEnabled(v),
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
                        Icon(Icons.schedule_outlined, size: 18, color: C.muted),
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

              // ---------- озвучивание ----------
              _SectionTitle('Озвучивание'),
              _Panel(
                child: _LinkRow(
                  icon: Icons.volume_up_outlined,
                  title: 'Голос Термая',
                  subtitle: controller.config.ttsEnabled
                      ? 'Системный TTS · ${controller.config.ttsVariant}'
                      : 'Выключено · системный русский голос Android',
                  onTap: () => Navigator.of(context)
                      .push(pageRoute(const TtsSettingsScreen())),
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
                            .where((p) => p.id != 'termai')
                            .map((p) => DropdownMenuItem(
                                value: p.id, child: Text(p.title)))
                            .toList(),
                        onChanged: (id) {
                          if (id == null || id == _provider) return;
                          _rememberProvider();
                          final p = findProvider(id);
                          final saved =
                              controller.config.providerProfiles[p.id];
                          setState(() {
                            _provider = p.id;
                            _key.text = saved?.apiKey ?? '';
                            _base.text = saved?.baseUrl ?? p.baseUrl;
                            _model.text = saved?.model ?? p.defaultModel;
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
                          labelText: 'API-ключ',
                          hintText: 'sk-…',
                          suffixIcon: IconButton(
                            tooltip: _showKey ? 'Скрыть ключ' : 'Показать ключ',
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
                      const SizedBox(height: 6),
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 2),
                          // Нулевой childrenPadding ставил поле вплотную к
                          // заголовку: всплывающий label «Модель» уходил
                          // под header. Верхний inset — часть раскрытия.
                          childrenPadding:
                              const EdgeInsets.only(top: AppSpace.x3),
                          clipBehavior: Clip.none,
                          iconColor: C.muted,
                          collapsedIconColor: C.muted,
                          title: Text(
                            'Дополнительно',
                            style: AppText.caption.copyWith(
                              color: C.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: [
                            TextField(
                              controller: _model,
                              decoration: const InputDecoration(
                                  labelText: 'Модель',
                                  hintText: 'пусто — из пресета'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _base,
                              decoration: const InputDecoration(
                                  labelText: 'Base URL',
                                  hintText: 'пусто — из пресета'),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      appRow(
                        icon: Icons.swap_horiz_outlined,
                        title: 'Резервные модели',
                        subtitle: controller.config.fallbacks.isEmpty
                            ? 'Подстраховка при отказе провайдера'
                            : 'Подключено: ${controller.config.fallbacks.length}',
                        onTap: () => Navigator.of(context)
                            .push(pageRoute(const AiFallbacksScreen())),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _saveAi,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(150, 42),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          child: const Text('Сохранить ИИ'),
                        ),
                      ),
                    ]),
              ),
              const SizedBox(height: 18),

              // ---------- общий доступ ----------
              _SectionTitle('Общий доступ TERMAI'),
              _Panel(
                child: ListenableBuilder(
                  listenable: SharedAiService.instance,
                  builder: (context, _) {
                    final service = SharedAiService.instance;
                    final promo = service.promo;
                    if (!service.proxyConfigured) {
                      return Text(
                        'В этой сборке сервер общего доступа не указан. '
                        'Личный ИИ работает как обычно.',
                        style: AppText.caption.copyWith(color: C.muted),
                      );
                    }
                    if (service.loading && promo == null) {
                      return Row(children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: C.accent)),
                        const SizedBox(width: 10),
                        Text('Проверяю условия акции…',
                            style: AppText.caption.copyWith(color: C.muted)),
                      ]);
                    }
                    if (promo == null || !promo.enabled) {
                      return Text(
                        service.error.isEmpty
                            ? 'Общий доступ сейчас выключен на сервере.'
                            : service.error,
                        style: AppText.caption.copyWith(color: C.muted),
                      );
                    }
                    final expired = !promo.active;
                    final consentOk =
                        controller.config.sharedAiConsentVersion >=
                            promo.noticeVersion;
                    final signedIn = service.signedIn;
                    final enabled = controller.config.sharedAiEnabled &&
                        consentOk &&
                        signedIn &&
                        !expired;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            expired ? 'Акция завершена' : 'Бесплатный общий ИИ',
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: C.text),
                          ),
                          subtitle: Text(
                            expired
                                ? 'Запросы снова идут только через твой личный ключ.'
                                : '${promo.model} · ${service.remainingLabel}\n'
                                    'Запросы идут через внешний шлюз Token Harbor. '
                                    'Ключ хранится только на сервере.',
                            style: TextStyle(
                                fontSize: 11.5, color: C.muted, height: 1.35),
                          ),
                          value: enabled,
                          activeThumbColor: C.accent,
                          onChanged: expired ? null : _toggleShared,
                        ),
                        if (!expired && !signedIn) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            Icon(Icons.lock_outline, size: 16, color: C.warn),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Общий доступ работает только после входа через Google. Войди в разделе «Облачная синхронизация» ниже.',
                                style: AppText.caption.copyWith(color: C.warn),
                              ),
                            ),
                          ]),
                        ],
                        if (!expired && signedIn)
                          Row(children: [
                            Icon(
                              enabled
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              size: 16,
                              color: enabled ? C.good : C.warn,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                enabled
                                    ? 'Общий доступ включён. Личные настройки не изменяются.'
                                    : 'Общий доступ выключен — используется твой провайдер.',
                                style: AppText.caption.copyWith(
                                    color: enabled ? C.good : C.muted),
                              ),
                            ),
                          ]),
                        if (service.privacyUrl.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            service.privacyUrl,
                            style: AppText.caption
                                .copyWith(color: C.accent, fontSize: 10.5),
                          ),
                        ],
                      ],
                    );
                  },
                ),
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
                          // Отправка секретов — только явный opt-in.
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Синхронизировать ключи ИИ в облако',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: C.text)),
                            subtitle: Text(
                              'Выключено по умолчанию. При включении личные '
                              'ключи и резервные подключения сохраняются в '
                              'твоём документе Firebase для переноса устройств.',
                              style: TextStyle(
                                  fontSize: 11.5, color: C.muted, height: 1.3),
                            ),
                            value: controller.config.syncKeysToCloud,
                            activeThumbColor: C.accent,
                            onChanged: (v) async {
                              if (v) {
                                final ok = await showConfirmDialog(
                                  context,
                                  title: 'Синхронизировать API-ключи?',
                                  message:
                                      'Личные ключи основного и резервных провайдеров будут отправлены в Firebase твоего аккаунта. Серверный ключ TERMAI туда не попадает. Включить?',
                                );
                                if (!ok) return;
                              }
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
                                final msg = await controller.syncConfig(
                                    pullFirst: false);
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
                    subtitle: 'Как учиться и что делает каждый экран',
                    onTap: () => Navigator.of(context)
                        .push(pageRoute(const HelpScreen())),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Проверять обновления',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: C.text)),
                      subtitle: Text(
                        'При запуске и в фоне, не чаще раза в 6 часов',
                        style: TextStyle(fontSize: 11.5, color: C.muted),
                      ),
                      value: controller.config.updatesAutoCheck,
                      activeThumbColor: C.accent,
                      onChanged: (v) => controller.setUpdatesAutoCheck(v),
                    ),
                    Divider(color: C.border, height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Уведомлять о новой версии',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: C.text)),
                      subtitle: Text(
                        'Один раз на версию, без автоматической установки',
                        style: TextStyle(fontSize: 11.5, color: C.muted),
                      ),
                      value: controller.config.updatesNotifications,
                      activeThumbColor: C.accent,
                      onChanged: controller.config.updatesAutoCheck
                          ? (v) => controller.setUpdatesNotifications(v)
                          : null,
                    ),
                    Divider(color: C.border, height: 1),
                    _LinkRow(
                      icon: Icons.system_update_alt,
                      title: 'Проверить обновления',
                      subtitle: controller.updateChecking
                          ? 'Проверяю GitHub…'
                          : 'Скачать свежий APK с GitHub',
                      onTap: controller.updateChecking
                          ? () {}
                          : () => _checkUpdates(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text('версия 1.22.0',
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
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить облачные данные?',
      message: 'Из Firestore будет удалён прогресс, чаты, настройки и email. '
          'Локальная копия останется.',
    );
    if (!ok) return;
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
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x3),
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
  Widget build(BuildContext context) => appRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
      );
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
