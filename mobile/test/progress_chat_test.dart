import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termai/models.dart';
import 'package:termai/ui/theme.dart';

void main() {
  test('MentorChat survives Progress JSON round-trip', () {
    final chat = MentorChat(
      id: 'chat-1',
      courseId: 'linux',
      taskId: 'task-1',
      taskTitle: 'Проброс портов',
      title: 'Мой чат',
      createdAt: '2026-01-01T10:00:00.000',
      updatedAt: '2026-01-01T10:05:00.000',
      messages: [
        ChatMsg('user', 'привет'),
        ChatMsg('mentor', 'ответ'),
      ],
    );
    final p = Progress()
      ..mentorChats = [chat]
      ..activeChatId = chat.id;

    final back = Progress.fromJson(p.toJson());

    expect(back.mentorChats, hasLength(1));
    expect(back.mentorChats.first.title, 'Мой чат');
    expect(back.mentorChats.first.taskTitle, 'Проброс портов');
    expect(back.mentorChats.first.messages, hasLength(2));
    expect(back.mentorChats.first.messages[1].role, 'mentor');
    expect(back.mentorChats.first.messages[1].text, 'ответ');
    expect(back.activeChatId, chat.id);
  });

  test('Course mode and onboarding flag survive JSON round-trip', () {
    final course = Course(id: 'english', title: 'English A1', mode: 'theory');
    final back = Course.fromJson(course.toJson());
    expect(back.isTheory, isTrue);

    final legacy = Course.fromJson({'id': 'linux', 'title': 'Linux'});
    expect(legacy.isTheory, isFalse);

    final cfg = Config()..onboarded = true;
    expect(Config.fromJson(cfg.toJson()).onboarded, isTrue);
  });

  test('built-in courses asset parses and has a theory course', () {
    final raw = File('assets/courses.json').readAsStringSync();
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final courses = list.map(Course.fromJson).toList();
    expect(courses.any((c) => c.isTheory), isTrue);
    final english = courses.firstWhere((c) => c.id == 'english-a1');
    expect(english.tasks, hasLength(3));
    expect(english.tasks.every((t) => t.isQuiz), isTrue);
    expect(english.tasks.every((t) => t.quiz.length == 2), isTrue);
  });

  test('archive list and token usage survive Progress JSON round-trip', () {
    final p = Progress()
      ..archived = ['linux', 'english-a1']
      ..aiUsage = {
        'deepseek-chat': [1200, 340],
        'gpt-4o-mini': [50, 10],
      };

    final back = Progress.fromJson(p.toJson());

    expect(back.archived, ['linux', 'english-a1']);
    expect(back.aiUsage['deepseek-chat'], [1200, 340]);
    expect(back.tokensIn, 1250);
    expect(back.tokensOut, 350);
    expect(back.tokensTotal, 1600);

    // старые файлы прогресса без новых полей читаются без ошибок
    final legacy = Progress.fromJson({'xp': 10});
    expect(legacy.archived, isEmpty);
    expect(legacy.aiUsage, isEmpty);
  });

  test('fallback endpoints and background photo survive Config JSON round-trip', () {
    final cfg = Config()
      ..theme = 'navy'
      ..fallbacks = [
        AiEndpoint(provider: 'openai', apiKey: 'sk-a', model: 'gpt-4o-mini'),
        AiEndpoint(provider: 'gemini', apiKey: 'g-key', model: 'gemini-2.0-flash', baseUrl: 'https://example.test/v1'),
      ]
      ..bgPhoto = '/tmp/photo.jpg'
      ..bgBlur = 12
      ..bgDim = 0.4;

    final back = Config.fromJson(cfg.toJson());

    expect(back.theme, 'navy');
    expect(back.fallbacks, hasLength(2));
    expect(back.fallbacks.first.ready, isTrue);
    expect(back.fallbacks[1].baseUrl, 'https://example.test/v1');
    expect(back.bgPhoto, '/tmp/photo.jpg');
    expect(back.bgBlur, 12);
    expect(back.bgDim, 0.4);

    // основа по-прежнему «какао»; тёмно-синяя — переключаемый вариант
    expect(Config().theme, 'cocoa');
    expect(Config.fromJson(const {}).theme, 'cocoa');
    expect(themePresets.any((p) => p.id == 'navy'), isTrue);
    expect(themePresets.any((p) => p.id == 'cocoa'), isTrue);
    expect(presetById('navy').title, 'Тёмно-синий');

    // прежние конфиги (без резервов и фона) читаются без ошибок
    final legacy = Config.fromJson({'theme': 'sage'});
    expect(legacy.fallbacks, isEmpty);
    expect(legacy.bgPhoto, isEmpty);
  });
}
