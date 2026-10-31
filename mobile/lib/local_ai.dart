// local_ai.dart — on-device GGUF inference через llamadart (llama.cpp).
//
// Модель не отправляет данные в сеть: файл лежит в папке приложения и
// загружается в память по требованию. Это аналог PocketPal: выбрать GGUF,
// загрузить, общаться с ним как с обычным провайдером.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

class LocalAiService extends ChangeNotifier {
  LocalAiService._();

  static final LocalAiService instance = LocalAiService._();

  LlamaEngine? _engine;
  String _loadedPath = '';
  bool _loading = false;
  double _progress = 0;
  String _status = 'Локальная модель не загружена';
  String _error = '';

  bool get loading => _loading;
  bool get ready => _engine != null;
  bool get loaded => _engine != null;
  double get progress => _progress;
  String get status => _status;
  String get error => _error;
  String get loadedPath => _loadedPath;

  String get loadedName {
    if (_loadedPath.isEmpty) return '';
    final i = _loadedPath.lastIndexOf(Platform.pathSeparator);
    return i >= 0 ? _loadedPath.substring(i + 1) : _loadedPath;
  }

  Future<Directory> modelsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// load — загружает GGUF в память. Повторный вызов для того же файла
  /// ничего не делает.
  Future<String> load(String path, {int contextSize = 4096}) async {
    if (path.trim().isEmpty) return 'Модель не выбрана.';
    if (_engine != null && _loadedPath == path) return '';
    _loading = true;
    _progress = 0;
    _error = '';
    _status = 'Загружаю модель в память…';
    notifyListeners();
    try {
      final old = _engine;
      _engine = null;
      if (old != null) {
        try {
          await old.dispose();
        } catch (_) {}
      }
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.path(path)),
        params: ModelParams(
          contextSize: contextSize.clamp(512, 32768),
          gpuLayers: 0,
        ),
        onProgress: (p) {
          _progress = (p.fraction ?? 0).clamp(0.0, 1.0);
          notifyListeners();
        },
      );
      _engine = engine;
      _loadedPath = path;
      _status = 'Модель загружена';
      _progress = 1;
      return '';
    } catch (e) {
      _error = _msg(e);
      _status = 'Не удалось загрузить модель';
      _engine = null;
      _loadedPath = '';
      return _error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> unload() async {
    final old = _engine;
    _engine = null;
    _loadedPath = '';
    _status = 'Локальная модель не загружена';
    _progress = 0;
    notifyListeners();
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {}
    }
  }

  /// chat — текстовый запрос к локальной модели. Модель загружается
  /// автоматически, если ещё не в памяти.
  Future<String> chat(
    List<Map<String, dynamic>> messages, {
    required String modelPath,
    int contextSize = 4096,
    double temp = 0.7,
    int maxTokens = 1024,
  }) async {
    if (modelPath.trim().isEmpty) {
      throw Exception('Локальная модель не выбрана. Настрой её в «Локальный ИИ».');
    }
    if (_engine == null || _loadedPath != modelPath) {
      final err = await load(modelPath, contextSize: contextSize);
      if (err.isNotEmpty) throw Exception(err);
    }
    final msgs = <LlamaChatMessage>[];
    for (final m in messages) {
      final role = switch ((m['role'] ?? '').toString()) {
        'system' => LlamaChatRole.system,
        'assistant' => LlamaChatRole.assistant,
        _ => LlamaChatRole.user,
      };
      final text = _textOf(m['content']);
      if (text.trim().isEmpty) continue;
      msgs.add(LlamaChatMessage.fromText(role: role, text: text));
    }
    if (msgs.isEmpty) throw Exception('Пустой запрос к локальной модели.');
    final stream = _engine!.create(
      msgs,
      params: GenerationParams(
        maxTokens: maxTokens.clamp(32, 8192),
        temp: temp,
      ),
    );
    final answer = (await stream.text()).trim();
    if (answer.isEmpty) throw Exception('Локальная модель вернула пустой ответ.');
    return answer;
  }

  String _textOf(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final b = StringBuffer();
      for (final p in content) {
        if (p is Map && p['type'] == 'text') {
          b.writeln(p['text']?.toString() ?? '');
        } else if (p is Map) {
          b.writeln('[вложение: локальная модель работает с текстом]');
        }
      }
      return b.toString();
    }
    return content?.toString() ?? '';
  }

  /// downloadModel — скачивает GGUF в папку приложения с прогрессом.
  Future<String> downloadModel(
    String url,
    String fileName, {
    void Function(double fraction, int received, int total)? onProgress,
  }) async {
    final dir = await modelsDir();
    final target = File('${dir.path}/$fileName');
    final tmp = File('${target.path}.part');
    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw Exception('Сервер вернул ${res.statusCode}');
      }
      final total = res.contentLength ?? 0;
      var received = 0;
      sink = tmp.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0), received, total);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      return target.path;
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// copyIntoModels — копирует выбранный пользователем GGUF в папку приложения,
  /// чтобы путь не зависел от кэша файлового менеджера.
  Future<String> copyIntoModels(String sourcePath) async {
    final dir = await modelsDir();
    final name = sourcePath.split(Platform.pathSeparator).last;
    final target = File('${dir.path}/$name');
    if (sourcePath == target.path) return sourcePath;
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Future<void> deleteModel(String path) async {
    if (_loadedPath == path) await unload();
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    notifyListeners();
  }

  String _msg(Object e) {
    var s = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return s.length > 300 ? s.substring(0, 300) : s;
  }
}
