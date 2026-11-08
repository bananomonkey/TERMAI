import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/main.dart';
import 'package:termai/models.dart';
import 'package:termai/ui/app_background.dart';
import 'package:termai/ui/chat.dart';
import 'package:termai/ui/home.dart';
import 'package:termai/ui/home_bottom_bar.dart';
import 'package:termai/ui/lesson.dart';
import 'package:termai/ui/onboarding.dart';
import 'package:termai/ui/progress_map.dart';
import 'package:termai/ui/settings_screen.dart';
import 'package:termai/ui/theme.dart';

void main() {
  setUp(() {
    controller.config = Config()
      ..directions = ['devops']
      ..activeDirection = 'devops';
    controller.prog = Progress();
    controller.courses = [
      Course(
          id: 'linux',
          title: 'Linux',
          category: 'professions',
          direction: 'devops',
          tasks: [
            Task(id: 't1', title: 'Первая команда', goal: 'ls'),
          ]),
    ];
    controller.allCourses = controller.courses;
    controller.courseIdx = 0;
  });

  testWidgets('home renders without a background photo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(body: AppBackdrop(child: CourseGraphView())),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Linux'), findsOneWidget);
    expect(find.text('0/1 · практика'), findsOneWidget);
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

  testWidgets('home has Terai launcher and no global floating panel',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.config = Config()..onboarded = true;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const HomeScreen(),
    ));
    await tester.pump();

    expect(find.byType(HomeBottomBar), findsOneWidget);
    expect(find.byTooltip('Открыть чат с Термаем'), findsOneWidget);
    expect(find.byTooltip('Статистика'), findsOneWidget);
    expect(find.byTooltip('Карта прогресса'), findsOneWidget);
    expect(find.byTooltip('Архив курсов'), findsOneWidget);
    expect(find.byTooltip('Расход токенов'), findsOneWidget);

    await tester.tap(find.byTooltip('Открыть чат с Термаем'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows compact direction switcher', (tester) async {
    controller.config = Config()
      ..directions = ['devops', 'english']
      ..activeDirection = 'devops';
    final devops = Course(
      id: 'linux',
      title: 'Linux',
      category: 'professions',
      direction: 'devops',
      tasks: [Task(id: 't1', title: 'Команда', goal: 'pwd')],
    );
    final english = Course(
      id: 'english-a1',
      title: 'English A1',
      category: 'languages',
      direction: 'english',
      mode: 'theory',
      tasks: [Task(id: 'e1', title: 'To be', goal: 'quiz')],
    );
    controller.allCourses = [devops, english];
    controller.courses = [devops];
    controller.courseIdx = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const HomeScreen(),
    ));
    await tester.pump();

    expect(find.text('DevOps'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.byTooltip('Добавить направление'), findsOneWidget);
    expect(find.text('Linux'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding offers multiple learning directions', (tester) async {
    controller.config = Config()..onboarded = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const OnboardingScreen(),
    ));
    await tester.pump();

    // Теперьа-дизайн выше тестового экрана: доскролливаем до кнопки.
    await tester.scrollUntilVisible(
      find.text('Выбрать направление'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Выбрать направление'));
    await tester.pumpAndSettle();

    expect(find.text('Что учим?'), findsOneWidget);
    expect(find.text('DevOps-инженер'), findsOneWidget);
    expect(find.text('Английский'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
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

  testWidgets('advanced model field expands without clipping', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.config = Config();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.dragUntilVisible(
      find.text('Дополнительно'),
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дополнительно'));
    await tester.pumpAndSettle();

    expect(find.text('Модель'), findsOneWidget);
    expect(find.text('Base URL'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Модель'),
        matching: find.byType(InputDecorator),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding skip button works', (tester) async {
    controller.config = Config()..onboarded = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const OnboardingScreen(),
    ));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Пропустить'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Пропустить'));
    // даём реальному I/O (запись termai.json) завершиться и доигрываем переход
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
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

  testWidgets('progress map nodes can be dragged independently',
      (tester) async {
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

  testWidgets('yaml editor validates structure and keeps a draft',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('termai-editor-');
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
    });
    controller.config = Config()
      ..directions = ['devops']
      ..activeDirection = 'devops';
    controller.prog = Progress();
    final task = Task(
      id: 'yaml',
      title: 'Workflow',
      kind: 'yaml',
      goal: 'Собери workflow',
      check: 'Нужен шаг checkout',
      editor: {
        'language': 'yaml',
        'starter': 'name: CI\non: [push]\n',
      },
      verify: {
        'checks': [
          {'yaml_path': 'jobs.build.runs-on', 'equals': 'ubuntu-latest'},
          {
            'yaml_path': 'jobs.build.steps',
            'list_item_contains': 'actions/checkout@v4',
          },
        ],
      },
    );
    final course = Course(
      id: 'cicd',
      title: 'CI/CD',
      category: 'professions',
      direction: 'devops',
      mode: 'theory',
      tasks: [task],
    );
    controller.courses = [course];
    controller.allCourses = [course];
    controller.courseIdx = 0;
    controller.viewIdx = 0;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const LessonScreen(),
    ));
    await tester.pump();
    await tester.tap(find.text('Редактор'));
    await tester.pump();

    final editor = find.byKey(const ValueKey('editor-field'));
    expect(editor, findsOneWidget);
    await tester.enterText(editor,
        'name: CI\non: [push]\njobs:\n  build:\n    runs-on: ubuntu-latest\n');
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.prog.drafts['cicd|yaml'], contains('runs-on'));
    expect(find.textContaining('В YAML нет пути'), findsOneWidget);

    await tester.enterText(
        editor,
        'name: CI\non: [push]\njobs:\n  build:\n    runs-on: ubuntu-latest\n'
        '    steps:\n      - uses: actions/checkout@v4\n');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Структура в порядке. Можно проверять задачу.'),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 220));
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
