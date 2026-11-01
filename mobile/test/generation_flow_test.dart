import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:termai/ai.dart';
import 'package:termai/app_action.dart';
import 'package:termai/app_actions.dart';
import 'package:termai/main.dart';
import 'package:termai/models.dart';
import 'package:termai/navigation.dart';
import 'package:termai/store.dart';
import 'package:termai/ui/home.dart';
import 'package:termai/ui/theme.dart';

/// TestController не пишет на диск: проверяем реальную бизнес-логику и
/// сетевой цикл, не завися от path_provider в тестовом окружении.
class TestController extends AppController {
  @override
  Future<void> saveProgress() async {}
}

/// FakeAiTransport отвечает как OpenAI-совместимый провайдер. Это не заглушка
/// бизнес-логики: AIClient реально разбирает ответ, валидирует JSON и вызывает
/// инструменты, как с настоящим провайдером.
class FakeAiTransport {
  int taskSeq = 0;
  int courseRequests = 0;
  int nativeToolRounds = 0;

  Future<http.Response> handle(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    final hasTools = body['tools'] is List;
    if (hasTools) {
      nativeToolRounds++;
      if (nativeToolRounds == 1) {
        return _completion({
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call-course-1',
              'type': 'function',
              'function': {
                'name': 'generate_course',
                'arguments': jsonEncode({'goal': 'стать DevOps'}),
              },
            }
          ],
        });
      }
      return _completion({
        'role': 'assistant',
        'content': 'Курс создан и открыт.',
      });
    }
    final system = messages
        .where((m) => m['role'] == 'system')
        .map((m) => (m['content'] ?? '').toString())
        .join('\n');
    final user = messages
        .where((m) => m['role'] == 'user')
        .map((m) => (m['content'] ?? '').toString())
        .join('\n');

    Map<String, dynamic> payload;
    if (system.contains('методист') && user.contains('Цель студента')) {
      courseRequests++;
      payload = {
        'courses': [
          {
            'id': 'ai-test-a',
            'title': 'Тестовый курс A',
            'desc': 'Первый курс',
            'mode': 'terminal',
            'syllabus': ['cmd: основы', 'cmd: практика', 'quiz: проверка'],
          },
          {
            'id': 'ai-test-b',
            'title': 'Тестовый курс B',
            'desc': 'Второй курс',
            'mode': 'terminal',
            'syllabus': ['cmd: база', 'cmd: углубление'],
          },
        ],
      };
    } else if (system.contains('генератор учебных задач')) {
      taskSeq++;
      payload = {
        'id': 'generated-task-$taskSeq',
        'title': 'Сгенерированная задача $taskSeq',
        'kind': 'cmd',
        'difficulty': 2,
        'theory': ['Короткая теория'],
        'quiz': [
          {
            'question': 'Вопрос?',
            'options': ['да', 'нет', 'может'],
            'correct': 0,
          }
        ],
        'goal': 'Выполнить практику $taskSeq',
        'hints': ['Подсказка'],
        'check': 'Проверить результат',
        'start_state': {
          'workdir': '/workspace',
          'files': {},
          'images': {},
          'containers': {},
          'volumes': {},
          'networks': ['bridge', 'host', 'none'],
          'events': [],
        },
      };
    } else {
      return http.Response('unexpected prompt', 500);
    }

    return http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': jsonEncode(payload)}
          }
        ],
        'usage': {'prompt_tokens': 10, 'completion_tokens': 10},
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  http.Response _completion(Map<String, dynamic> message) {
    final encoded = jsonEncode({
      'choices': [
        {'message': message}
      ],
      'usage': {'prompt_tokens': 10, 'completion_tokens': 10},
    });
    return http.Response.bytes(utf8.encode(encoded), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

AIClient testAi() => AIClient(Config(
      provider: 'custom',
      apiKey: 'test',
      model: 'test-model',
      baseUrl: 'http://fake.local/v1',
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAiTransport transport;

  setUp(() {
    transport = FakeAiTransport();
    AIClient.httpClientFactory = () => MockClient(transport.handle);
  });

  tearDown(() {
    AIClient.httpClientFactory = null;
  });

  test('generateTask works while mentor/terminal busy and saves the task',
      () async {
    final c = TestController();
    c.config = Config(activeDirection: 'devops');
    c.prog = Progress();
    c.ai = testAi();
    c.courses = [
      Course(id: 'c1', title: 'Docker', tasks: [
        Task(id: 'old', title: 'Старая', goal: 'old goal'),
      ]),
    ];
    c.allCourses = c.courses;
    c.courseIdx = 0;
    c.viewIdx = 0;

    // Раньше эти флаги блокировали создание задачи пустым ответом.
    c.mentorBusy = true;
    c.termBusy = true;

    final before = c.cur.tasks.length;
    final err = await c.generateTask('проброс портов');

    expect(err, isEmpty);
    expect(c.cur.tasks.length, before + 1);
    expect(c.cur.tasks.last.title, contains('Сгенерированная задача'));
    expect(c.operations.isBusy, isFalse);
    expect(c.cur.tasks.map((t) => t.id).toSet().length, c.cur.tasks.length,
        reason: 'ids must stay unique');
  });

  test('generateCourses saves every course with at least five real tasks',
      () async {
    final c = TestController();
    c.config = Config(activeDirection: 'devops');
    c.prog = Progress();
    c.ai = testAi();
    c.courses = [
      Course(id: 'existing', title: 'Existing', tasks: [
        Task(id: 't1', title: 'Task', goal: 'goal'),
      ]),
    ];
    c.allCourses = List<Course>.of(c.courses);
    c.courseIdx = 0;
    // Нативный вызов generate_course приходит, когда чат уже занят.
    c.mentorBusy = true;

    final err = await c.generateCourses('стать DevOps');

    expect(err, isEmpty);
    expect(transport.courseRequests, 1);
    expect(c.courses.length, 3);
    expect(c.allCourses.length, 3);
    expect(c.prog.extraCourses.length, 2);
    for (final course in c.courses.skip(1)) {
      expect(course.tasks.length, greaterThanOrEqualTo(5));
      expect(course.tasks.every((t) => t.title.isNotEmpty), isTrue);
      expect(course.direction, 'devops');
    }
    expect(c.operations.isBusy, isFalse);
  });

  testWidgets('generate_course tool opens the saved course list',
      (tester) async {
    ScreenObserver.reset();
    // Экран TaskListScreen в приложении читает глобальный controller.
    controller.config = Config(onboarded: true, activeDirection: 'devops');
    controller.prog = Progress();
    controller.ai = testAi();
    controller.courses = [
      Course(id: 'existing', title: 'Existing', tasks: [
        Task(id: 't1', title: 'Task', goal: 'goal'),
      ]),
    ];
    controller.allCourses = List<Course>.of(controller.courses);
    controller.courseIdx = 0;
    controller.viewIdx = 0;

    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [screenObserver],
      theme: buildTheme(),
      home: const Scaffold(body: Text('home')),
    ));

    final actions = AppActions(controller);
    final pending = actions.executeTool(
      const AppActionCall('generate_course', {'goal': 'стать DevOps'}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final result = await pending;
    await tester.pump();

    expect(result.ok, isTrue, reason: result.message);
    expect(result.data['saved'], isTrue);
    expect(result.data['added_courses'], 2);
    expect(controller.courses.length, 3);
    expect(find.byType(TaskListScreen), findsOneWidget);
    expect(find.text('Тестовый курс A'), findsWidgets);
    ScreenObserver.reset();
  });

  testWidgets('native generate_course runs inside the real chat tool loop',
      (tester) async {
    ScreenObserver.reset();
    controller.config = Config(onboarded: true, activeDirection: 'devops');
    controller.prog = Progress();
    controller.ai = testAi();
    controller.courses = [
      Course(id: 'existing', title: 'Existing', tasks: [
        Task(id: 't1', title: 'Task', goal: 'goal'),
      ]),
    ];
    controller.allCourses = List<Course>.of(controller.courses);
    controller.courseIdx = 0;
    controller.viewIdx = 0;
    controller.chatMsgs = [];
    final actions = AppActions(controller);
    controller.toolExecutor = actions.executeTool;

    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [screenObserver],
      theme: buildTheme(),
      home: const Scaffold(body: Text('home')),
    ));

    // В момент нативного вызова чат уже занят: mentorBusy=true. Старый код
    // из-за этого возвращал пустую строку и не создавал курс.
    final pending = controller.sendChat('Создай курс, чтобы стать DevOps');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await pending;
    await tester.pump();
    // saveProgress откладывает запись на 160 мс; гасим таймер до конца теста.
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.courses.length, 3,
        reason:
            'курс должен сохраниться; чат: ${controller.chatMsgs.map((m) => '${m.text} [${m.details}]').join(' | ')}');
    expect(
        controller.courses.skip(1).every((c) => c.tasks.length >= 5), isTrue);
    expect(controller.mentorBusy, isFalse);
    expect(controller.activeGeneration, isNull);
    expect(find.byType(TaskListScreen), findsOneWidget);
    expect(
        controller.chatMsgs.any((m) =>
            m.text.contains('курс создан') || m.text.contains('Курс создан')),
        isTrue);
    expect(
        controller.chatMsgs.any((m) => m.text.contains('Не удалось выполнить')),
        isFalse);
    ScreenObserver.reset();
  });

  testWidgets('generate_course returns an explicit error and saves nothing',
      (tester) async {
    ScreenObserver.reset();
    final c = TestController();
    c.config = Config(onboarded: true, activeDirection: 'devops');
    c.prog = Progress();
    c.ai = testAi();
    c.courses = [
      Course(id: 'existing', title: 'Existing', tasks: [
        Task(id: 't1', title: 'Task', goal: 'goal'),
      ]),
    ];
    c.allCourses = c.courses;

    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [screenObserver],
      theme: buildTheme(),
      home: const Scaffold(body: Text('home')),
    ));

    final actions = AppActions(c);
    final result = await actions.executeTool(
      const AppActionCall('generate_course', {'goal': '   '}),
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('goal'));
    expect(c.courses.length, 1);
    expect(c.operations.isBusy, isFalse);
    ScreenObserver.reset();
  });
}
