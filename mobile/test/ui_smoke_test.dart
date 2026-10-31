import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/main.dart';
import 'package:termai/models.dart';
import 'package:termai/ui/app_background.dart';
import 'package:termai/ui/home.dart';
import 'package:termai/ui/lesson.dart';
import 'package:termai/ui/mentor_launcher.dart';
import 'package:termai/ui/onboarding.dart';
import 'package:termai/ui/progress_map.dart';
import 'package:termai/ui/settings_screen.dart';
import 'package:termai/ui/theme.dart';

void main() {
  setUp(() {
    controller.config = Config();
    controller.courses = [
      Course(id: 'linux', title: 'Linux', tasks: [
        Task(id: 't1', title: 'Первая команда', goal: 'ls'),
      ]),
    ];
    controller.courseIdx = 0;
  });

  testWidgets('home renders without a background photo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(body: AppBackdrop(child: CourseGraphView())),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Linux'), findsOneWidget);
    expect(find.textContaining('0/1 уроков'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background photo is applied', (tester) async {
    controller.config.bgPhoto = 'assets/icon/termai.png';
    controller.config.bgBlur = 12;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(body: AppBackdrop(child: CourseGraphView())),
    ));
    // даём время декодировать и размыть картинку
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BackdropImage), findsOneWidget);
    expect(find.text('Linux'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home theme button switches the whole app to light',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('termai-test-');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return temp.path;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      temp.deleteSync(recursive: true);
      C.p = presetById('dark');
      C.buttonBrightness = 1.0;
    });
    controller.config = Config()..onboarded = true;
    C.p = presetById('dark');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const HomeScreen(),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Светлая тема'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    await tester.pumpAndSettle();

    expect(controller.config.theme, 'light');
    expect(C.isLight, isTrue);
    expect(find.byTooltip('Тёмная тема'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mentor avatar opens a compact quick-ask panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(
        body: Stack(children: [
          Positioned(left: 14, bottom: 100, child: MentorLauncher()),
        ]),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Быстрый вопрос'));
    await tester.pumpAndSettle();

    expect(find.text('Быстрый вопрос'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    expect(find.text('Быстрый вопрос'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings scrolls to the very bottom', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('ОФОРМЛЕНИЕ'), findsOneWidget);
    expect(find.text('Яркость кнопок'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    // нижний блок должен доскролливаться, а не обрезаться
    await tester.scrollUntilVisible(
      find.textContaining('версия'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('версия'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding skip button works', (tester) async {
    controller.config = Config()..onboarded = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const OnboardingScreen(),
    ));
    await tester.pump();

    await tester.tap(find.text('Пропустить'));
    // даём реальному I/O (запись termai.json) завершиться и доигрываем переход
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    await tester.pumpAndSettle();

    expect(find.text('Пропустить'), findsNothing);
    expect(find.text('Linux'), findsOneWidget);
    expect(controller.config.onboarded, isTrue);
  });

  testWidgets('progress map shows the route and stats', (tester) async {
    controller.config = Config()..onboarded = true;
    controller.courses = [
      Course(id: 'linux', title: 'Linux', tasks: [
        Task(id: 't1', title: 'Первая команда', goal: 'ls'),
        Task(id: 't2', title: 'Вторая команда', goal: 'pwd'),
      ]),
    ];
    controller.courseIdx = 0;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const ProgressMapScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Карта прогресса'), findsOneWidget);
    expect(find.text('МАРШРУТ'), findsOneWidget);
    expect(find.text('Первая команда'), findsOneWidget);
    expect(find.text('Вторая команда'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress map builds a real hierarchy of levels', (tester) async {
    controller.config = Config()..onboarded = true;
    controller.courses = [
      Course(
        id: 'tree',
        title: 'TreeCourse',
        syllabus: ['Mod A', 'Mod B'],
        tasks: [
          for (var i = 0; i < 5; i++)
            Task(id: 'a$i', title: 'A$i', goal: 'goal'),
          Task(id: 'b0', title: 'B0', goal: 'goal'),
        ],
      ),
    ];
    controller.courseIdx = 0;
    await tester.binding.setSurfaceSize(const Size(4000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const ProgressMapScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    final modA = tester.getTopLeft(find.text('Mod A'));
    final modB = tester.getTopLeft(find.text('Mod B'));
    final a0 = tester.getTopLeft(find.text('A0'));
    final a4 = tester.getTopLeft(find.text('A4'));
    final b0 = tester.getTopLeft(find.text('B0'));
    // Модули — один уровень; задачи — следующий, колонками под модулями.
    expect((modA.dy - modB.dy).abs(), lessThan(2.0));
    expect((modA.dx - modB.dx).abs(), greaterThan(40.0));
    expect((a0.dx - a4.dx).abs(), lessThan(2.0));
    expect((a0.dy - a4.dy).abs(), greaterThan(40.0));
    expect(a0.dy, greaterThan(modA.dy));
    expect((a0.dy - b0.dy).abs(), lessThan(2.0));
    expect((a0.dx - b0.dx).abs(), greaterThan(40.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress map nodes can be dragged independently', (tester) async {
    controller.config = Config()..onboarded = true;
    controller.courses = [
      Course(id: 'linux', title: 'Linux', tasks: [
        Task(id: 't1', title: 'Первая команда', goal: 'ls'),
        Task(id: 't2', title: 'Вторая команда', goal: 'pwd'),
      ]),
    ];
    controller.courseIdx = 0;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const ProgressMapScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    final a0 = tester.getTopLeft(find.text('Первая команда'));
    final b0 = tester.getTopLeft(find.text('Вторая команда'));
    // Задачи одного модуля — колонкой друг под другом, а не в одну строку.
    expect((a0.dx - b0.dx).abs(), lessThan(2.0));
    expect((a0.dy - b0.dy).abs(), greaterThan(40.0));
    await tester.drag(find.text('Первая команда'), const Offset(50, 30));
    await tester.pump(const Duration(milliseconds: 250));
    final a1 = tester.getTopLeft(find.text('Первая команда'));
    final b1 = tester.getTopLeft(find.text('Вторая команда'));
    expect(a1, isNot(a0));
    expect((b1 - b0).distance, lessThan(1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson switches slides without errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const LessonScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Справка'), findsOneWidget);
    await tester.tap(find.text('Задача'));
    await tester.pump();
    await tester.tap(find.text('Терминал'));
    await tester.pump();
    expect(find.text('Терминал'), findsWidgets);
    await tester.tap(find.text('Решение'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
