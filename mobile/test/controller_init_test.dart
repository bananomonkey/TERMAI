import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('старый пользователь получает DevOps и Kubernetes без потери курсов',
      () async {
    final temp = Directory.systemTemp.createTempSync('termai-init-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return temp.path;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      temp.deleteSync(recursive: true);
      loadCoursesAsset = () async => '[]';
    });

    loadCoursesAsset =
        () async => File('assets/courses.json').readAsStringSync();
    File('${temp.path}/termai-progress.json').writeAsStringSync(jsonEncode({
      'xp': 50,
      'solved_total': 1,
      'completed': {
        'docker': {'hello-world': true}
      },
      'last_course': 'docker',
    }));
    final c = AppController();
    await c.init();

    expect(c.config.directions, contains('devops'));
    expect(c.config.activeDirection, 'devops');
    expect(c.courses.any((x) => x.id == 'kubernetes'), isTrue);
    expect(c.courses.any((x) => x.id == 'linux'), isTrue);
    expect(c.courses.any((x) => x.id == 'english-a1'), isFalse);
    expect(c.prog.completed['docker']?['hello-world'], isTrue);
    expect(c.cur.id, 'docker');
    expect(c.prog.directionXp['devops'], greaterThan(0));

    await c.setDirections(['devops', 'english', 'go'], active: 'go');
    expect(c.config.directions, ['devops', 'english', 'go']);
    expect(c.config.activeDirection, 'go');
    expect(c.courses.map((x) => x.id), ['go-basics']);
    expect(c.prog.completed['docker']?['hello-world'], isTrue);

    await c.switchDirection('english');
    expect(c.config.activeDirection, 'english');
    expect(c.courses.map((x) => x.id), ['english-a1']);

    await c.switchDirection('devops');
    final first = c.courses.first.id;
    await c.reorderCourses(0, 2);
    expect(c.prog.courseOrderByDirection['devops']?.first, isNot(first));
    expect(c.prog.courseOrderByDirection['devops'], c.courses.map((x) => x.id));

    await Future<void>.delayed(const Duration(milliseconds: 250));
    c.dispose();
  });
}
