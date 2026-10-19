import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termai/models.dart';

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
}
