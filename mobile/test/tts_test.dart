import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termai/main.dart';
import 'package:termai/local_tts.dart';
import 'package:termai/models.dart';
import 'package:termai/tts_service.dart';
import 'package:termai/ui/local_tts_screen.dart';
import 'package:termai/ui/theme.dart';
import 'package:termai/ui/tts_settings.dart';

void main() {
  test('TTS sanitizer removes code, JSON, links and app actions', () {
    const raw = '''
## Итог
[Открой настройки](https://example.com) и проверь **Docker**.
```bash
docker run hello-world
```
<termai>{"name":"open_screen","args":{"screen":"settings"}}</termai>
{"solved": true, "comment": "не озвучивать"}
''';
    final clean = sanitizeForSpeech(raw);
    expect(clean, contains('Итог'));
    expect(clean, contains('Docker'));
    expect(clean, isNot(contains('docker run')));
    expect(clean, isNot(contains('termai')));
    expect(clean, isNot(contains('https://')));
    expect(clean, isNot(contains('solved')));
  });

  test('long answers are split into bounded chunks without losing words', () {
    final text = List.filled(90, 'слово').join(' ');
    final chunks = chunkForSpeech(text, maxChars: 80);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.length <= 80), isTrue);
    expect(chunks.join(' ').split(RegExp(r'\s+')).length, 90);
    expect(chunkForSpeech('  '), isEmpty);
  });

  test('TTS settings survive Config JSON round-trip', () {
    final c = Config()
      ..ttsEnabled = true
      ..ttsAutoChat = false
      ..ttsAutoCompletion = true
      ..ttsEngine = 'com.google.android.tts'
      ..ttsVoice = 'ru-ru-x-dfc-local'
      ..ttsLocale = 'ru-RU'
      ..ttsVariant = 'ru-RU'
      ..ttsRate = 0.7
      ..ttsPitch = 1.2
      ..ttsUseLocal = true
      ..ttsLocalModelId = 'piper-dmitri-int8';
    final back = Config.fromJson(c.toJson());
    expect(back.ttsEnabled, isTrue);
    expect(back.ttsAutoChat, isFalse);
    expect(back.ttsEngine, 'com.google.android.tts');
    expect(back.ttsVoice, 'ru-ru-x-dfc-local');
    expect(back.ttsRate, closeTo(0.7, 0.001));
    expect(back.ttsPitch, closeTo(1.2, 0.001));
    expect(back.ttsUseLocal, isTrue);
    expect(back.ttsLocalModelId, 'piper-dmitri-int8');
  });

  test('local TTS catalog uses explicit HTTPS downloads and real sizes', () {
    expect(localTtsCatalog, isNotEmpty);
    for (final m in localTtsCatalog) {
      expect(m.url, startsWith('https://'));
      expect(m.archiveName, endsWith('.tar.bz2'));
      expect(m.archiveBytes, greaterThan(10 * 1024 * 1024));
      expect(m.license, isNotEmpty);
    }
  });

  test('local TTS archive extracts model files without the root folder', () {
    final temp = Directory.systemTemp.createTempSync('termai-tts-tar-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final archive = Archive()
      ..addFile(ArchiveFile.string('vits-test/model.onnx', 'fake-onnx'))
      ..addFile(ArchiveFile.string('vits-test/tokens.txt', 'tokens'))
      ..addFile(ArchiveFile.string('vits-test/espeak-ng-data/ru_dict', 'dict'));
    final tar = TarEncoder().encode(archive);
    final bz2 = BZip2Encoder().encodeBytes(tar);
    final file = File('${temp.path}/voice.tar.bz2');
    file.writeAsBytesSync(bz2);
    final out = Directory('${temp.path}/out');

    expect(extractLocalTtsArchive(file.path, out.path), isTrue);
    expect(File('${out.path}/model.onnx').existsSync(), isTrue);
    expect(File('${out.path}/tokens.txt').existsSync(), isTrue);
    expect(File('${out.path}/espeak-ng-data/ru_dict').existsSync(), isTrue);
  });

  testWidgets('TTS settings screen renders without a native plugin',
      (tester) async {
    controller.config = Config()..ttsEnabled = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const TtsSettingsScreen(),
    ));
    await tester.pump();
    expect(find.text('Озвучивание'), findsOneWidget);
    expect(find.text('Озвучивать ответы'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabled TTS settings render controls on a narrow phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.config = Config()..ttsEnabled = true;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const TtsSettingsScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Озвучивать ответы'), findsOneWidget);
    expect(find.text('Прослушать'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local TTS catalog screen renders without downloading',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('termai-tts-');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return temp.path;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      temp.deleteSync(recursive: true);
    });
    controller.config = Config()..ttsEnabled = true;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const LocalTtsScreen(),
    ));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Локальные голоса'), findsOneWidget);
    expect(find.text('Дмитрий'), findsOneWidget);
    expect(find.text('Скачать'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
