import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/ai.dart';
import 'package:termai/download_manager.dart';
import 'package:termai/hugging_face.dart';
import 'package:termai/models.dart';
import 'package:termai/ui/attachment_view.dart';
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
    final course = Course(
        id: 'english',
        title: 'English A1',
        mode: 'theory',
        category: 'languages',
        direction: 'english');
    final back = Course.fromJson(course.toJson());
    expect(back.isTheory, isTrue);
    expect(back.direction, 'english');
    expect(back.category, 'languages');

    final legacy = Course.fromJson({'id': 'linux', 'title': 'Linux'});
    expect(legacy.isTheory, isFalse);

    final cfg = Config()
      ..onboarded = true
      ..directions = ['devops', 'english']
      ..activeDirection = 'english';
    final cfgBack = Config.fromJson(cfg.toJson());
    expect(cfgBack.onboarded, isTrue);
    expect(cfgBack.directions, ['devops', 'english']);
    expect(cfgBack.activeDirection, 'english');
  });

  test('built-in courses asset parses and has a theory course', () {
    final raw = File('assets/courses.json').readAsStringSync();
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final courses = list.map(Course.fromJson).toList();
    expect(courses.any((c) => c.isTheory), isTrue);
    final english = courses.firstWhere((c) => c.id == 'english-a1');
    expect(english.tasks.length, greaterThanOrEqualTo(12));
    expect(english.tasks.every((t) => t.isQuiz), isTrue);
    expect(english.tasks.every((t) => t.quiz.length >= 2), isTrue);
    final k8s = courses.firstWhere((c) => c.id == 'kubernetes');
    expect(k8s.tasks.length, greaterThanOrEqualTo(32));
    expect(k8s.tasks.where((t) => t.verify.isNotEmpty).length,
        greaterThanOrEqualTo(30));
  });

  test('archive list and token usage survive Progress JSON round-trip', () {
    final p = Progress()
      ..archived = ['linux', 'english-a1']
      ..courseOrderByDirection = {
        'devops': ['linux', 'docker']
      }
      ..activeCourseByDirection = {'devops': 'docker'}
      ..directionXp = {'devops': 120}
      ..directionSolved = {'devops': 4}
      ..aiUsage = {
        'deepseek-chat': [1200, 340],
        'gpt-4o-mini': [50, 10],
      };

    final back = Progress.fromJson(p.toJson());

    expect(back.archived, ['linux', 'english-a1']);
    expect(back.courseOrderByDirection['devops'], ['linux', 'docker']);
    expect(back.activeCourseByDirection['devops'], 'docker');
    expect(back.directionXp['devops'], 120);
    expect(back.directionSolved['devops'], 4);
    expect(back.aiUsage['deepseek-chat'], [1200, 340]);
    expect(back.tokensIn, 1250);
    expect(back.tokensOut, 350);
    expect(back.tokensTotal, 1600);

    // старые файлы прогресса без новых полей читаются без ошибок
    final legacy = Progress.fromJson({'xp': 10});
    expect(legacy.archived, isEmpty);
    expect(legacy.aiUsage, isEmpty);
  });

  test('fallback endpoints and background photo survive Config JSON round-trip',
      () {
    final cfg = Config()
      ..theme = 'navy'
      ..fallbacks = [
        AiEndpoint(provider: 'openai', apiKey: 'sk-a', model: 'gpt-4o-mini'),
        AiEndpoint(
            provider: 'gemini',
            apiKey: 'g-key',
            model: 'gemini-2.0-flash',
            baseUrl: 'https://example.test/v1'),
      ]
      ..bgPhoto = '/tmp/photo.jpg'
      ..bgBlur = 12
      ..bgDim = 0.4
      ..buttonBrightness = 1.25;

    final back = Config.fromJson(cfg.toJson());

    expect(back.theme, 'navy');
    expect(back.fallbacks, hasLength(2));
    expect(back.fallbacks.first.ready, isTrue);
    expect(back.fallbacks[1].baseUrl, 'https://example.test/v1');
    expect(back.bgPhoto, '/tmp/photo.jpg');
    expect(back.bgBlur, 12);
    expect(back.bgDim, 0.4);
    expect(back.buttonBrightness, 1.25);

    // основа — VS Code Dark Modern; синяя и светлая — допустимые варианты
    expect(Config().theme, 'dark');
    expect(Config.fromJson(const {}).theme, 'dark');
    expect(themePresets, hasLength(3));
    expect(themePresets.any((p) => p.id == 'navy'), isTrue);
    expect(themePresets.any((p) => p.id == 'dark'), isTrue);
    expect(themePresets.any((p) => p.id == 'light'), isTrue);
    expect(presetById('navy').title, 'Синий');
    expect(presetById('dark').title, 'Dark Modern');
    expect(presetById('light').title, 'Светлая');
    expect(presetById('dark').bg, const Color(0xFF000000));
    expect(presetById('dark').accent, const Color(0xFF0078D4));
    expect(presetById('light').brightness, Brightness.light);
    expect(Config.fromJson(const {}).buttonBrightness, 1.0);
    expect(
        Config.fromJson(const <String, dynamic>{'button_brightness': 2.0})
            .buttonBrightness,
        1.4);

    // осознанный выбор синей темы сохраняется, авто-тема — нет
    final chosen = Config()
      ..theme = 'navy'
      ..themeAuto = false;
    final chosenBack = Config.fromJson(chosen.toJson());
    expect(chosenBack.theme, 'navy');
    expect(chosenBack.themeAuto, isFalse);
    expect(Config.fromJson(const {}).themeAuto, isTrue);

    // прежние конфиги (без резервов и фона) читаются без ошибок
    final legacy = Config.fromJson({'theme': 'sage'});
    expect(legacy.fallbacks, isEmpty);
    expect(legacy.bgPhoto, isEmpty);
  });

  test('name and notification settings survive Config JSON round-trip', () {
    final cfg = Config()
      ..userName = 'Влад'
      ..notificationsEnabled = false
      ..dailyReminderEnabled = false
      ..reminderHour = 9
      ..reminderMinute = 30
      ..aiMotivationEnabled = false
      ..motivationQueue = ['Раз, два']
      ..motivationGeneratedAt = '2026-10-29T09:00:00.000'
      ..launcherX = 0.2
      ..launcherY = 0.7;

    final back = Config.fromJson(cfg.toJson());
    expect(back.userName, 'Влад');
    expect(back.notificationsEnabled, isFalse);
    expect(back.dailyReminderEnabled, isFalse);
    expect(back.reminderHour, 9);
    expect(back.reminderMinute, 30);
    expect(back.aiMotivationEnabled, isFalse);
    expect(back.motivationQueue, ['Раз, два']);
    expect(back.launcherX, 0.2);
    expect(back.launcherY, 0.7);
  });

  test('general chat has no task binding and errors stay human-readable', () {
    final chat = MentorChat(
      id: 'chat-general',
      courseId: '',
      taskId: '',
      taskTitle: '',
      title: 'Термай',
      createdAt: '2026-10-29T10:00:00.000',
      updatedAt: '2026-10-29T10:00:00.000',
    );
    expect(chat.isGeneral, isTrue);
    expect(chat.courseId, isEmpty);
    expect(chat.taskId, isEmpty);

    final error = ChatMsg('error', 'Модель или адрес не найдены.',
        details: 'Ошибка ИИ 404: {"error":"not found"}');
    final back = ChatMsg.fromJson(error.toJson());
    expect(back.isError, isTrue);
    expect(back.text, isNot(contains('404')));
    expect(back.details, contains('404'));

    expect(friendlyAiError(Exception('Ошибка ИИ 404: not found')),
        contains('Модель или адрес не найдены'));
    expect(friendlyAiError(Exception('Ошибка ИИ 401: unauthorized')),
        contains('API-ключ'));
    expect(rawError(Exception('Ошибка ИИ 404: not found')), contains('404'));
  });

  test('cloud config keeps non-secret fields and strips keys on opt-out', () {
    final cfg = Config()
      ..userName = 'Влад'
      ..theme = 'navy'
      ..apiKey = 'sk-main'
      ..fallbacks = [
        AiEndpoint(provider: 'openai', apiKey: 'sk-fb', model: 'gpt-4o-mini'),
      ];
    final withKeys = cfg.toCloudJson(includeKeys: true);
    expect(withKeys['api_key'], 'sk-main');
    expect(((withKeys['fallbacks'] as List).first as Map)['api_key'], 'sk-fb');
    expect(withKeys.containsKey('bg_photo'), isFalse);

    final without = cfg.toCloudJson(includeKeys: false);
    expect(without.containsKey('api_key'), isFalse);
    expect(((without['fallbacks'] as List).first as Map).containsKey('api_key'),
        isFalse);
    expect(without['user_name'], 'Влад');
    expect(without['theme'], 'navy');
  });

  test('chat attachments survive JSON round-trip', () {
    final msg = ChatMsg('user', 'смотри', attachments: [
      ChatAttachment(
        type: 'image',
        path: '/tmp/a.jpg',
        name: 'a.jpg',
        mime: 'image/jpeg',
        size: 123,
      ),
    ]);
    final back = ChatMsg.fromJson(msg.toJson());
    expect(back.attachments, hasLength(1));
    expect(back.attachments.first.isImage, isTrue);
    expect(back.attachments.first.name, 'a.jpg');
  });

  test('local config never writes AI keys to disk', () {
    final cfg = Config()
      ..apiKey = 'sk-main'
      ..fallbacks = [
        AiEndpoint(provider: 'openai', apiKey: 'sk-fb', model: 'gpt-4o-mini'),
      ];
    final local = cfg.toLocalJson();
    expect(local.containsKey('api_key'), isFalse);
    expect(((local['fallbacks'] as List).first as Map).containsKey('api_key'),
        isFalse);
    expect(cfg.toCloudJson(includeKeys: true)['api_key'], 'sk-main');
  });

  test('download metadata survives restart and never stores a token', () {
    final job = DownloadJob(
      id: 'repo::file.gguf',
      repoId: 'owner/repo',
      fileName: 'file.gguf',
      url: 'https://huggingface.co/owner/repo/resolve/main/file.gguf',
      finalPath: '/models/file.gguf',
      totalBytes: 100,
      receivedBytes: 40,
      systemId: 7,
      createdAt: 1,
      updatedAt: 2,
      status: DownloadStatus.downloading,
    );
    final json = job.toJson();
    expect(json.containsKey('token'), isFalse);
    expect(json.containsKey('authorization'), isFalse);
    final back = DownloadJob.fromJson(json);
    expect(back.systemId, 7);
    expect(back.status, DownloadStatus.downloading);
    expect(back.progress, 0.4);
  });

  test('HF LFS size prefers the real blob size and labels are compact', () {
    final file = HFFile.fromJson({
      'path': 'model-q4_k_m.gguf',
      'size': 135,
      'lfs': {'size': 491400032},
    });
    expect(file.size, 491400032);
    expect(file.quantization, 'Q4_K_M');
    final a = ChatAttachment(
      type: 'image',
      path: '/tmp/very-long-name.jpg',
      name: 'очень-длинное-имя-файла.jpg',
      mime: 'image/jpeg',
      size: 2048,
    );
    expect(attachmentTypeLabel(a), 'Фото');
    expect(attachmentSize(2048), '2 КБ');
  });

  test('exam task kind survives JSON round-trip', () {
    final t = Task(id: 'e1', title: 'Экзамен', goal: 'проверка', kind: 'exam');
    final back = Task.fromJson(t.toJson());
    expect(back.isExam, isTrue);
    expect(back.isQuiz, isFalse);
  });
}
