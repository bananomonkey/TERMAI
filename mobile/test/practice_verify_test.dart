import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termai/editor_verify.dart';
import 'package:termai/k8s_sandbox.dart';
import 'package:termai/models.dart';

void main() {
  late List<Course> courses;
  setUpAll(() {
    final raw = File('assets/courses.json').readAsStringSync();
    courses = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Course.fromJson)
        .toList();
  });

  Task task(String courseId, String taskId) => courses
      .firstWhere((c) => c.id == courseId)
      .tasks
      .firstWhere((t) => t.id == taskId);

  test('all practical terminal courses have deterministic verifiers', () {
    for (final id in ['docker', 'linux', 'git']) {
      final course = courses.firstWhere((c) => c.id == id);
      expect(course.tasks.every((t) => t.verify.isNotEmpty), isTrue,
          reason: '$id должен иметь проверку для каждой практики');
    }
    final k8s = courses.firstWhere((c) => c.id == 'kubernetes');
    expect(
      k8s.tasks.where((t) => !t.isExam).every((t) => t.verify.isNotEmpty),
      isTrue,
    );
  });

  test('every quiz task has deterministic, valid answers', () {
    for (final c in courses) {
      for (final t in c.tasks.where((t) => t.isQuiz)) {
        expect(t.quiz.length, greaterThanOrEqualTo(2),
            reason: '${c.id}/${t.id}: мало вопросов');
        for (final q in t.quiz) {
          expect(q.options.length, greaterThanOrEqualTo(2),
              reason: '${c.id}/${t.id}: мало вариантов');
          expect(q.correct, inInclusiveRange(0, q.options.length - 1),
              reason: '${c.id}/${t.id}: неверный индекс ответа');
        }
      }
    }
  });

  test('YAML practice passes with real solution and reports errors', () {
    final editorTasks =
        courses.expand((c) => c.tasks.where((t) => t.hasEditor)).toList();
    expect(editorTasks.length, greaterThanOrEqualTo(9));
    for (final t in editorTasks) {
      final good = verifyEditorTask(t, t.solution);
      expect(good.ok, isTrue, reason: '${t.id}: ${good.message}');
      final bad = verifyEditorTask(t, t.editorStarter);
      expect(bad.ok, isFalse, reason: '${t.id} не должен проходить шаблон');
    }
    final broken = editorTasks.firstWhere((t) => t.id == 'cicd-14-repair');
    final parseError =
        verifyEditorTask(broken, 'jobs:\n  build:\n    runs-on: [\n');
    expect(parseError.ok, isFalse);
    expect(parseError.line, isNotNull);
  });

  test('editor drafts survive Progress JSON round-trip', () {
    final p = Progress()
      ..drafts = {'cicd|cicd-11-basic': 'name: CI\non: [push]\n'};
    final back = Progress.fromJson(p.toJson());
    expect(back.drafts['cicd|cicd-11-basic'], contains('name: CI'));
  });

  test('safe course rebuild tasks survive Progress JSON round-trip', () {
    final rebuilt = Task(
      id: 'kept-1',
      title: 'Сохранённая задача',
      goal: 'Проверка',
      kind: 'yaml',
      editor: {'language': 'yaml', 'starter': 'jobs: {}'},
    );
    final p = Progress()
      ..rebuiltTasks = {
        'cicd': [rebuilt]
      };
    final back = Progress.fromJson(p.toJson());
    expect(back.rebuiltTasks['cicd'], hasLength(1));
    expect(back.rebuiltTasks['cicd']!.first.id, 'kept-1');
    expect(back.rebuiltTasks['cicd']!.first.hasEditor, isTrue);
  });

  test('docker outcomes are checked against real container and image state',
      () {
    final st = SandboxState(
      containers: {
        'web': ContainerInfo(
          id: 'c1',
          name: 'web',
          image: 'nginx:alpine',
          status: 'running',
          ports: '8080->80/tcp',
        ),
      },
      images: {
        'myapp:1.0': ImageInfo(
          id: 'sha256:abc',
          repo: 'myapp',
          tag: '1.0',
          sizeMb: 100,
          layers: ['FROM python:3.12-slim', 'COPY app.py .'],
        ),
      },
      files: {
        'Dockerfile':
            'FROM python:3.12-slim\nCOPY app.py .\nCMD ["python", "app.py"]',
      },
    );

    expect(tryVerifyTask(task('docker', 'run-nginx'), st)?.ok, isTrue);
    expect(tryVerifyTask(task('docker', 'build-basics'), st)?.ok, isTrue);
    expect(tryVerifyTask(task('docker', 'hello-world'), st)?.ok, isFalse);
  });

  test('docker multi-stage is checked by image layers', () {
    final st = SandboxState(images: {
      'myapi:1.0': ImageInfo(
        id: 'sha256:def',
        repo: 'myapi',
        tag: '1.0',
        layers: [
          'FROM golang:1.22',
          'COPY --from=build /app/server /server',
          'FROM alpine:3.19',
        ],
      ),
    });
    expect(tryVerifyTask(task('docker', 'multi-stage'), st)?.ok, isTrue);
  });

  test('linux verifier inspects files and real command history', () {
    final st = SandboxState(files: {'notes.txt': 'first\nsecond\n'});
    expect(tryVerifyTask(task('linux', 'linux-03-files'), st)?.ok, isTrue);

    final log = SandboxState(files: {'old.log': 'ok'});
    expect(tryVerifyTask(task('linux', 'linux-05-copy-move'), log)?.ok, isTrue);

    final systemd = SandboxState();
    final check = tryVerifyTask(
      task('linux', 'linux-08-systemd'),
      systemd,
      history: [
        HistEntry(cmd: 'systemctl status ssh', out: 'active (running)'),
        HistEntry(cmd: 'systemctl enable ssh', out: ''),
      ],
    );
    expect(check?.ok, isTrue);
  });

  test('git verifier sees branch and hook changes', () {
    final branch = SandboxState();
    expect(
      tryVerifyTask(
        task('git', 'git-04-branch'),
        branch,
        history: [HistEntry(cmd: 'git branch feature', out: '')],
      )?.ok,
      isTrue,
    );

    final hook =
        SandboxState(files: {'.git/hooks/pre-commit': 'go test ./...'});
    expect(tryVerifyTask(task('git', 'git-12-hooks'), hook)?.ok, isTrue);
  });
}
