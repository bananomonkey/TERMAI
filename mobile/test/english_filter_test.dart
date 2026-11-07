import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('у направления english отображается курс english-a1', () async {
    final temp = Directory.systemTemp.createTempSync('termai-eng-');
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
    final c = AppController();
    await c.init();
    await c.switchDirection('english');
    expect(c.config.directions, contains('english'));
    expect(c.courses.map((x) => x.id), contains('english-a1'),
        reason: 'курсы: ${c.courses.map((x) => x.id)}');
  });
}
