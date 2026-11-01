import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/main.dart';
import 'package:termai/models.dart';
import 'package:termai/ui/stats_screen.dart';
import 'package:termai/ui/theme.dart';

void main() {
  test('progress keeps real daily history and study time', () {
    final p = Progress();
    final at = DateTime(2026, 10, 3, 12, 30);
    p.recordSolved(
      courseId: 'linux',
      taskId: 't1',
      direction: 'devops',
      xp: 45,
      at: at,
    );
    p.recordStudy(direction: 'devops', seconds: 90, at: at);

    final back = Progress.fromJson(p.toJson());
    expect(back.dailySolved['2026-10-03'], 1);
    expect(back.dailyXp['2026-10-03'], 45);
    expect(back.dailySeconds['2026-10-03'], 90);
    expect(back.dailyDirectionSolved['2026-10-03']?['devops'], 1);
    expect(back.dailyDirectionXp['2026-10-03']?['devops'], 45);
    expect(back.dailyDirectionSeconds['2026-10-03']?['devops'], 90);
    expect(back.solvedAt['linux|t1'], isNotNull);
  });

  testWidgets('statistics screen uses real totals and switches views',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final course = Course(
      id: 'linux',
      title: 'Linux',
      category: 'professions',
      direction: 'devops',
      tasks: [
        Task(id: 't1', title: 'Первая команда', goal: 'ls'),
        Task(id: 't2', title: 'Вторая команда', goal: 'pwd'),
      ],
    );
    controller.config = Config()
      ..directions = ['devops']
      ..activeDirection = 'devops';
    final p = Progress()
      ..xp = 75
      ..solvedTotal = 4
      ..directionXp = {'devops': 75}
      ..directionSolved = {'devops': 4}
      ..completed = {
        'linux': {'t1': true}
      };
    final now = DateTime.now();
    p.recordSolved(
      courseId: 'linux',
      taskId: 't1',
      direction: 'devops',
      xp: 45,
      at: now,
    );
    p.recordStudy(direction: 'devops', seconds: 125, at: now);
    controller.prog = p;
    controller.courses = [course];
    controller.allCourses = [course];
    controller.courseIdx = 0;

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const StatsScreen(),
    ));
    await tester.pump();

    expect(find.text('Статистика'), findsOneWidget);
    expect(find.text('Весь прогресс'), findsOneWidget);
    expect(find.text('Уроки'), findsOneWidget);
    expect(find.text('Практика'), findsOneWidget);
    expect(find.text('График активности'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('По направлениям'));
    await tester.pumpAndSettle();
    expect(find.text('DevOps-инженер'), findsWidgets);

    await tester.tap(find.text('Всё время'));
    await tester.pumpAndSettle();
    expect(find.text('График активности'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Общая'));
    await tester.pumpAndSettle();
    expect(find.text('Весь прогресс'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home bottom bar opens statistics', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.config = Config()
      ..onboarded = true
      ..directions = ['devops']
      ..activeDirection = 'devops';
    controller.prog = Progress();
    controller.courses = [
      Course(
        id: 'linux',
        title: 'Linux',
        category: 'professions',
        direction: 'devops',
        tasks: [Task(id: 't1', title: 'Команда', goal: 'ls')],
      ),
    ];
    controller.allCourses = controller.courses;
    controller.courseIdx = 0;

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const HomeScreen(),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('Статистика'));
    await tester.pumpAndSettle();

    expect(find.byType(StatsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
