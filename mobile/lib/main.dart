// main.dart — TERMAI mobile (Flutter). Сплэш → плашка ключа → карта курсов.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';
import 'ui/app_background.dart';
import 'ui/dock.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'ui/home.dart';
import 'ui/lesson.dart';
import 'ui/more.dart';
import 'ui/onboarding.dart';

final AppController controller = AppController();
bool diagAutoLesson = false;

void _appendDiag(String entry) {
  final ts = DateTime.now().toIso8601String().substring(11, 19);
  diagLog.writeln('[$ts] $entry');
  if (diagLog.length > 20000) {
    final s = diagLog.toString();
    diagLog.clear();
    diagLog.write(s.substring(s.length - 15000));
  }
}

void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _appendDiag('ОШИБКА: ' + details.exception.toString());
    if (details.stack != null) {
      final lines = details.stack.toString().split('\n').take(6).join('\n');
      diagLog.writeln(lines);
    }
  };
  PlatformDispatcher.instance.onError = (e, st) {
    _appendDiag('СБОЙ: ' + e.toString());
    diagLog.writeln(st.toString().split('\n').take(6).join('\n'));
    return true;
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const TermaiApp());
}

/// мост для store.dart: грузим встроенные курсы из бандла
Future<String> _loadCoursesAsset() async =>
    rootBundle.loadString('assets/courses.json');

class TermaiApp extends StatelessWidget {
  const TermaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // диагностика: TERMAI_FORCE_ANDROID=1 — мобильная раскладка на десктопе
    assert(() {
      if (const bool.fromEnvironment('TERMAI_FORCE_ANDROID')) {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
      }
      return true;
    }());
    return ListenableBuilder(
      // слушаем контроллер: смена темы в настройках перекрашивает всё приложение
      listenable: controller,
      builder: (context, _) => MaterialApp(
        key: ValueKey('theme-${C.p.id}'),
        title: 'TERMAI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const BootScreen(),
      ),
    );
  }
}

/// BootScreen — сплэш: логотип, инициализация, затем карта курсов.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});
  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200), value: 0)
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    loadCoursesAsset = _loadCoursesAsset;
    await controller.init();
    C.p = presetById(controller.config.theme);
    _scheduleReminder();
    // диагностика: авто-открытие урока на слайде терминала
    if (const bool.fromEnvironment('TERMAI_AUTO_LESSON')) diagAutoLesson = true;
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(pageRoute(
      controller.config.onboarded
          ? const HomeScreen()
          : const OnboardingScreen(),
    ));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.04).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/icon/termai.png',
                  width: 112,
                  height: 112,
                  cacheWidth: 224,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('тренажёр навыков с ИИ-наставником',
                style: TextStyle(color: C.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// _scheduleReminder — ежедневное напоминание в 20:00 (Барсик и серия).
Future<void> _scheduleReminder() async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
    }
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    await plugin.cancel(1);
    await plugin.zonedSchedule(
      1,
      'TERMAI — Барсик ждёт',
      controller.prog.streak > 0
          ? 'Серия ' +
              controller.prog.streak.toString() +
              ' дн. под угрозой — реши задачу дня!'
          : 'Заходи на задачу дня — начнём серию!',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails('reminders', 'Напоминания',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  } catch (_) {
    // уведомления не критичны
  }
}

/// HomeScreen — апбар (логотип, XP, «Ещё») + карта курсов.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    if (diagAutoLesson) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted)
          Navigator.of(context).push(pageRoute(const LessonScreen()));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: C.border),
                  ),
                  child: Text(
                      'ур.${controller.prog.level} · ${controller.prog.xp} XP',
                      style: TextStyle(fontSize: 11, color: C.muted)),
                ),
              ),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: () => showMoreSheet(context)),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackdrop(
        child: Stack(children: [
          const Positioned.fill(child: CourseGraphView()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Center(child: const GlassDock()),
            ),
          ),
        ]),
      ),
    );
  }
}

/// вспомогательное: диалог однострочного ввода («Задача от ИИ», «Курс от ИИ»)
Future<String?> askText(BuildContext context, String title, String hint,
    {String? initial}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size(40, 42)),
          child: const Text('Создать'),
        ),
      ],
    ),
  );
}

/// маленькая утилита: документы-путь для настроек импорта/экспорта не нужен тут,
/// но файл прогресса нам пригодится для статистики
Future<String> dataDirPath() async {
  final base = await getApplicationDocumentsDirectory();
  return base.path;
}

String prettyJson(Object? o) => const JsonEncoder.withIndent('  ').convert(o);
