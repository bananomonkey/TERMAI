// notifications.dart — локальные напоминания и мотивация Термая.
//
// Ежедневное напоминание берётся из готовых коротких фраз, а
// мотивационные сообщения может заранее генерировать ИИ. Локальное
// уведомление не умеет вызывать сеть в момент доставки, поэтому текст
// готовится при открытии приложения и ставится в расписание.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const dailyReminders = <String>[
    'Термай ждёт: 10 минут практики сегодня?',
    'Маленький шаг сегодня — большой прогресс завтра.',
    'Не забудь про задачу дня. Термай рядом.',
    'Пара минут практики лучше, чем ещё один отложенный день.',
    'Сегодня хороший день, чтобы продвинуться на один урок.',
    'Термай сохранил твоё место. Продолжим?',
  ];

  Future<void> init() async {
    if (_initialized) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
    }
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// apply — пересобрать расписание под текущие настройки.
  Future<void> apply(
    Config config, {
    required String userName,
    required int streak,
    List<String>? motivation,
  }) async {
    try {
      await init();
      await _plugin.cancelAll();
      if (!config.notificationsEnabled) return;

      final permission = await requestPermission();
      if (!permission) return;

      if (config.dailyReminderEnabled) {
        await _scheduleDaily(config, userName: userName, streak: streak);
      }

      final messages = motivation ?? config.motivationQueue;
      if (config.aiMotivationEnabled && messages.isNotEmpty) {
        await _scheduleMotivation(messages);
      }
    } catch (_) {
      // уведомления не критичны для работы приложения
    }
  }

  Future<void> cancelAll() async {
    try {
      await init();
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> _scheduleDaily(
    Config config, {
    required String userName,
    required int streak,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      config.reminderHour,
      config.reminderMinute,
    );
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

    final day = DateTime.now().difference(DateTime(2020)).inDays;
    final base = dailyReminders[day % dailyReminders.length];
    final text = streak > 0
        ? '$userName, $base Серия: $streak дн.'
        : '$userName, $base';
    await _plugin.zonedSchedule(
      1,
      'TERMAI — Термай ждёт',
      text,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Напоминания',
          channelDescription: 'Ежедневное напоминание о занятии',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _scheduleMotivation(List<String> messages) async {
    final now = tz.TZDateTime.now(tz.local);
    // Не спамим: одно сообщение раз в несколько дней, в вечернее время.
    const offsets = [1, 4, 8];
    for (var i = 0; i < messages.length && i < offsets.length; i++) {
      var when = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + offsets[i],
        18,
      );
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        100 + i,
        'TERMAI — Термай',
        messages[i],
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'motivation',
            'Мотивация',
            channelDescription: 'Короткие сообщения от Термая',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}

final notificationService = NotificationService.instance;
