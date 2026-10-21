import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/main.dart';
import 'package:termai/models.dart';
import 'package:termai/ui/app_background.dart';
import 'package:termai/ui/home.dart';
import 'package:termai/ui/onboarding.dart';
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

  testWidgets('settings scrolls to the very bottom', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('ОФОРМЛЕНИЕ'), findsOneWidget);
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
}
