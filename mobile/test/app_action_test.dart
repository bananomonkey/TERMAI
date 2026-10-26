import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/app_action.dart';
import 'package:termai/app_actions.dart';
import 'package:termai/main.dart';
import 'package:termai/models.dart';
import 'package:termai/navigation.dart';
import 'package:termai/ui/lesson.dart';
import 'package:termai/ui/mentor_avatar.dart';
import 'package:termai/ui/settings_screen.dart';
import 'package:termai/ui/theme.dart';

void main() {
  test('action marker is stripped from the visible answer', () {
    final p = parseAppActions(
      'Открываю настройки.\n'
      '<termai>{"name":"open_screen","args":{"screen":"settings"}}</termai>',
    );
    expect(p.text, 'Открываю настройки.');
    expect(p.actions, hasLength(1));
    expect(p.actions.first.name, 'open_screen');
    expect(p.actions.first.args['screen'], 'settings');
  });

  test('multiple and fenced calls are parsed', () {
    final p = parseAppActions('''
Сейчас.
<termai>{"name":"open_screen","args":{"screen":"settings"}}</termai>
```termai
{"name":"set_theme","args":{"theme":"navy"}}
```
''');
    expect(p.text, 'Сейчас.');
    expect(p.actions.map((a) => a.name), ['open_screen', 'set_theme']);
  });

  test('OpenAI-like function call is parsed', () {
    final p = parseAppActions(
      'Открываю.\n'
      '```json\n'
      '{"type":"function","function":{"name":"open_screen","arguments":"{\\"screen\\":\\"archive\\"}"}}\n'
      '```',
    );
    expect(p.actions.single.name, 'open_screen');
    expect(p.actions.single.args['screen'], 'archive');
    expect(p.text, 'Открываю.');
  });

  test('ordinary code blocks stay in the answer', () {
    final p = parseAppActions('Пример:\n```bash\nls -la\n```');
    expect(p.actions, isEmpty);
    expect(p.text, contains('ls -la'));
  });

  test('unknown marker is still removed from the text', () {
    final p = parseAppActions(
      'Ок.\n<termai>{"name":"unknown_action","args":{}}</termai>',
    );
    expect(p.text, 'Ок.');
    expect(p.actions.single.name, 'unknown_action');
  });

  testWidgets('AI action opens settings and returns home', (tester) async {
    ScreenObserver.reset();
    controller.config = Config();
    controller.prog = Progress();
    controller.courses = [];
    controller.ai = null;

    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [screenObserver],
      theme: buildTheme(),
      home: const Scaffold(body: Text('home')),
    ));

    final actions = AppActions(controller);
    final open = actions.execute(
      const AppActionCall('open_screen', {'screen': 'settings'}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('home'), findsNothing);
    await open;

    final home = actions.execute(
      const AppActionCall('open_screen', {'screen': 'home'}),
    );
    await tester.pump();
    expect(find.text('home'), findsOneWidget);
    await home;
    ScreenObserver.reset();
  });

  testWidgets('AI action fills the terminal input', (tester) async {
    ScreenObserver.reset();
    controller.config = Config();
    controller.prog = Progress();
    controller.termInput.clear();
    controller.courses = [
      Course(id: 'linux', title: 'Linux', tasks: [
        Task(id: 't1', title: 'Первая команда', goal: 'ls'),
      ]),
    ];
    controller.allCourses = controller.courses;
    controller.courseIdx = 0;
    controller.viewIdx = 0;

    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [screenObserver],
      theme: buildTheme(),
      home: const Scaffold(body: Text('home')),
    ));

    final actions = AppActions(controller);
    final fill = actions.execute(
      const AppActionCall('fill_terminal', {'text': 'ls -la'}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await fill;

    expect(find.byType(LessonScreen), findsOneWidget);
    expect(controller.termInput.text, 'ls -la');
    controller.termInput.clear();
    ScreenObserver.reset();
  });

  testWidgets('avatar changes mouth while speaking', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(
        body: Center(child: MentorAvatar(speaking: true, size: 48)),
      ),
    ));

    String assetName() {
      final provider = tester.widget<Image>(find.byType(Image)).image;
      if (provider is ResizeImage) {
        return (provider.imageProvider as AssetImage).assetName;
      }
      return (provider as AssetImage).assetName;
    }

    expect(assetName(), 'assets/icon/termai_open.png');
    await tester.pump(const Duration(milliseconds: 150));
    expect(assetName(), 'assets/icon/termai_closed.png');
    await tester.pump(const Duration(milliseconds: 150));
    expect(assetName(), 'assets/icon/termai_open.png');
  });
}
