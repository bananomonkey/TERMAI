// local_tts.dart — офлайн-голоса Piper (VITS) через sherpa-onnx.
//
// Модели не входят в APK и никогда не скачиваются автоматически: только
// по кнопке, с прогрессом/отменой/повтором и проверкой свободного места.
// Для русского используем голоса ru_RU dmitri/denis (данные CC0).
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:piper_phonemize/piper_phonemize.dart' as piper;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'download_manager.dart';
import 'models.dart';

class LocalTtsModel {
  final String id, title, subtitle, url, archiveName, license;
  final int archiveBytes, installedBytes;
  const LocalTtsModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.archiveName,
    required this.archiveBytes,
    required this.installedBytes,
    required this.license,
  });

  String get sizeLabel => '${(archiveBytes / (1024 * 1024)).round()} МБ';
}

const localTtsCatalog = <LocalTtsModel>[
  LocalTtsModel(
    id: 'piper-dmitri-int8',
    title: 'Дмитрий',
    subtitle: 'Piper · русский, мужской, medium',
    url:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-dmitri-medium-int8.tar.bz2',
    archiveName: 'vits-piper-ru_RU-dmitri-medium-int8.tar.bz2',
    archiveBytes: 21129441,
    installedBytes: 36 * 1024 * 1024,
    license: 'Piper MIT · голосовые данные CC0',
  ),
  LocalTtsModel(
    id: 'piper-denis-int8',
    title: 'Денис',
    subtitle: 'Piper · русский, мужской, medium',
    url:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-denis-medium-int8.tar.bz2',
    archiveName: 'vits-piper-ru_RU-denis-medium-int8.tar.bz2',
    archiveBytes: 21058905,
    installedBytes: 36 * 1024 * 1024,
    license: 'Piper MIT · голосовые данные CC0',
  ),
];

LocalTtsModel? localTtsModelById(String id) {
  for (final m in localTtsCatalog) {
    if (m.id == id) return m;
  }
  return null;
}

class LocalTtsService extends ChangeNotifier {
  LocalTtsService._();
  static final LocalTtsService instance = LocalTtsService._();

  final DownloadManager _downloads = DownloadManager.instance;
  final Set<String> _extracting = {};
  final Set<String> _failedExtract = {};
  final Set<String> _installed = {};
  AudioPlayer? _player;
  bool _bound = false;
  bool _speaking = false;
  int _token = 0;
  String _lastError = '';
  String _activeModel = '';

  bool get speaking => _speaking;
  String get lastError => _lastError;
  String get activeModel => _activeModel;

  Future<void> init() async {
    if (_bound) return;
    _bound = true;
    _downloads.addListener(_onDownloads);
    await reconcile();
  }

  void _onDownloads() {
    unawaited(reconcile());
    notifyListeners();
  }

  Future<Directory> _ttsDir() async {
    final models = await _downloads.modelsDir();
    final dir = Directory('${models.path}/tts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> modelDir(String id) async =>
      Directory('${(await _ttsDir()).path}/$id');

  DownloadJob? jobFor(LocalTtsModel model) =>
      _downloads.jobFor('tts', model.archiveName);

  bool extractionFailed(String id) => _failedExtract.contains(id);

  Future<void> retryExtract(LocalTtsModel model) async {
    if (_extracting.contains(model.id)) return;
    _failedExtract.remove(model.id);
    _lastError = '';
    final archive = await _archiveFile(model);
    if (await archive.exists()) {
      _extracting.add(model.id);
      try {
        await _extractFromPath(model, archive.path);
        _installed.add(model.id);
      } catch (e) {
        _failedExtract.add(model.id);
        _lastError = 'Не удалось распаковать ${model.title}: $e';
      } finally {
        _extracting.remove(model.id);
        notifyListeners();
      }
      return;
    }
    await reconcile();
    notifyListeners();
  }

  Future<void> reconcile() async {
    for (final model in localTtsCatalog) {
      if (_failedExtract.contains(model.id)) continue;
      final job = jobFor(model);
      if (job == null || job.status != DownloadStatus.completed) continue;
      if (_extracting.contains(model.id)) continue;
      _extracting.add(model.id);
      try {
        await _extract(model, job);
        _installed.add(model.id);
        _failedExtract.remove(model.id);
      } catch (e) {
        _failedExtract.add(model.id);
        _lastError = 'Не удалось распаковать ${model.title}: $e';
      } finally {
        _extracting.remove(model.id);
        notifyListeners();
      }
    }
  }

  Future<bool> isInstalled(String id) async {
    if (_installed.contains(id)) return true;
    final dir = await modelDir(id);
    if (!await dir.exists()) return false;
    final files = _findTtsFiles(dir);
    if (files == null) return false;
    final marker = File('${dir.path}/.termai-voice-ready-v2');
    if (!await marker.exists()) {
      try {
        await _validateVoice(dir, files);
      } catch (e) {
        _lastError = 'Проверка локального голоса не пройдена: $e';
        return false;
      }
    }
    _installed.add(id);
    return true;
  }

  Future<List<String>> installedIds() async {
    final result = <String>[];
    for (final m in localTtsCatalog) {
      if (await isInstalled(m.id)) result.add(m.id);
    }
    return result;
  }

  Future<void> download(LocalTtsModel model) async {
    await init();
    _failedExtract.remove(model.id);
    _lastError = '';
    // DownloadManager сам проверяет свободное место и умеет отмену/повтор.
    await _downloads.start(
      repoId: 'tts',
      fileName: model.archiveName,
      url: model.url,
      expectedBytes: model.archiveBytes,
      etag: '',
    );
    notifyListeners();
  }

  Future<void> cancel(LocalTtsModel model) async {
    final job = jobFor(model);
    if (job != null) await _downloads.cancel(job.id);
  }

  Future<void> retry(LocalTtsModel model) async {
    final job = jobFor(model);
    if (job != null) {
      await _downloads.retry(job.id);
    } else {
      await download(model);
    }
    notifyListeners();
  }

  Future<void> delete(LocalTtsModel model) async {
    await stop();
    final job = jobFor(model);
    if (job != null && job.isActive) await _downloads.cancel(job.id);
    if (job != null) await _downloads.removeRecord(job.id);
    final dir = await modelDir(model.id);
    if (await dir.exists()) await dir.delete(recursive: true);
    final archive = await _archiveFile(model);
    if (await archive.exists()) await archive.delete();
    _installed.remove(model.id);
    _failedExtract.remove(model.id);
    notifyListeners();
  }

  Future<File> _archiveFile(LocalTtsModel model) async {
    final models = await _downloads.modelsDir();
    return File('${models.path}/${model.archiveName}');
  }

  Future<void> _extract(LocalTtsModel model, DownloadJob job) async {
    var archiveFile = File(job.finalPath);
    if (!await archiveFile.exists()) {
      // После перезапуска путь в метаданных иногда расходится с реальным
      // именем файла. Пробуем штатное место менеджера загрузок.
      final fallback = await _archiveFile(model);
      if (await fallback.exists()) archiveFile = fallback;
    }
    if (!await archiveFile.exists()) {
      throw Exception('архив не найден — скачай голос заново');
    }
    await _extractFromPath(model, archiveFile.path);
    // Архив больше не нужен; запись DownloadManager тоже, иначе при
    // следующем запуске он будет искать удалённый файл.
    try {
      await _downloads.removeRecord(job.id);
      if (await archiveFile.exists()) await archiveFile.delete();
    } catch (_) {}
  }

  Future<void> _extractFromPath(LocalTtsModel model, String archivePath) async {
    final dir = await modelDir(model.id);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final ok =
        await Isolate.run(() => extractLocalTtsArchive(archivePath, dir.path));
    if (!ok) throw Exception('пустой или повреждённый архив');
    // Проверяем не только факт распаковки, но и наличие файлов, которые
    // реально нужны sherpa-onnx. Иначе ошибка всплывала позже как
    // «файлы не найдены» уже во время озвучивания.
    final files = _findTtsFiles(dir);
    if (files == null) {
      throw Exception('в архиве нет модели или tokens.txt');
    }
    await _validateVoice(dir, files);
  }

  Future<void> _validateVoice(Directory dir, _TtsFiles files) async {
    final espeak = _findEspeakDir(dir);
    if (espeak == null) {
      throw Exception('в модели нет полных данных espeak-ng');
    }
    final testWav = File('${dir.path}/.termai-install-test.wav');
    try {
      final ok = await Isolate.run(() => _generateWav(
            modelPath: files.model,
            tokensPath: files.tokens,
            espeakDir: espeak.path,
            text: 'Проверка голоса Термай.',
            speed: 1.0,
            wavPath: testWav.path,
          ));
      if (!ok || !await testWav.exists() || await testWav.length() <= 44) {
        throw Exception('движок не смог создать тестовый WAV');
      }
      await File('${dir.path}/.termai-voice-ready-v2')
          .writeAsString('ok\n', flush: true);
    } finally {
      try {
        if (await testWav.exists()) await testWav.delete();
      } catch (_) {}
    }
  }

  Future<bool> speak(String text, Config config, {String? modelId}) async {
    final model = localTtsModelById(modelId ?? config.ttsLocalModelId);
    if (model == null || !await isInstalled(model.id)) return false;
    final token = ++_token;
    _lastError = '';
    _activeModel = model.id;
    await _player?.stop();
    final temp = await getTemporaryDirectory();
    final wav = File(
        '${temp.path}/termai_tts_${DateTime.now().microsecondsSinceEpoch}.wav');
    _speaking = true;
    notifyListeners();
    try {
      final dir = await modelDir(model.id);
      final files = _findTtsFiles(dir);
      if (files == null) {
        throw Exception('файлы голоса не найдены — распакуй модель заново');
      }
      // Архив модели уже содержит совместимые данные espeak-ng. Используем
      // именно их; asset-пакет остаётся запасным вариантом.
      var espeakDir = _findEspeakDir(dir)?.path ?? '';
      if (espeakDir.isEmpty) {
        try {
          espeakDir = await piper.extractEspeakNgData();
        } catch (_) {}
      }
      if (espeakDir.isEmpty) {
        throw Exception('espeak-ng-data не найден');
      }
      final speed = (0.65 + config.ttsRate * 0.7).clamp(0.6, 1.4);
      final ok = await Isolate.run(() => _generateWav(
            modelPath: files.model,
            tokensPath: files.tokens,
            espeakDir: espeakDir,
            text: text,
            speed: speed.toDouble(),
            wavPath: wav.path,
          ));
      if (!ok) throw Exception('движок не вернул звук');
      if (token != _token) return true;
      final player = AudioPlayer();
      _player = player;
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(config.ttsVolume.clamp(0.0, 1.0));
      await player.play(DeviceFileSource(wav.path));
      // Ждём завершения проигрывания с страховкой по времени. Future.timeout
      // здесь нельзя: его onTimeout обязан вернуть AudioEvent, и колбек
      // '() {}' падал типовой ошибкой после успешного проигрывания.
      final done = Completer<void>();
      final sub = player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      final guard = Timer(const Duration(minutes: 2), () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      guard.cancel();
      await sub.cancel();
      return true;
    } catch (e) {
      _lastError = 'Локальный голос не сработал: $e';
      return false;
    } finally {
      if (token == _token) {
        _speaking = false;
        _activeModel = '';
        notifyListeners();
      }
      try {
        if (await wav.exists()) await wav.delete();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _token++;
    try {
      await _player?.stop();
    } catch (_) {}
    _speaking = false;
    _activeModel = '';
    notifyListeners();
  }
}

/// extractLocalTtsArchive — распаковка .tar.bz2 в отдельном isolate.
/// Возвращает false для пустого/битого архива; наружу не выходит.
bool extractLocalTtsArchive(String archivePath, String targetDir) {
  final archiveFile = File(archivePath);
  if (!archiveFile.existsSync()) return false;
  try {
    final bytes = archiveFile.readAsBytesSync();
    final tarBytes = BZip2Decoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tarBytes);
    final files = archive.files.where((f) => f.isFile).toList();
    if (files.isEmpty) return false;
    // В архиве один корневой каталог вида vits-piper-.../ — убираем его.
    String? prefix;
    for (final f in files) {
      final i = f.name.indexOf('/');
      if (i > 0) {
        prefix ??= f.name.substring(0, i + 1);
      }
    }
    final dir = Directory(targetDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    for (final f in files) {
      var relative = f.name;
      if (prefix != null && relative.startsWith(prefix)) {
        relative = relative.substring(prefix.length);
      }
      if (relative.isEmpty || relative.contains('..')) continue;
      final target = File('${dir.path}/$relative');
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(f.content, flush: true);
    }
    return true;
  } catch (_) {
    return false;
  }
}

class _TtsFiles {
  final String model, tokens;
  const _TtsFiles(this.model, this.tokens);
}

/// Ищем файлы рекурсивно: архивы sherpa-onnx могут содержать один или
/// несколько вложенных каталогов. Раньше путь токенов жёстко предполагал
/// плоскую структуру, из-за чего озвучивание падало с «файлы не найдены».
_TtsFiles? _findTtsFiles(Directory dir) {
  if (!dir.existsSync()) return null;
  String model = '';
  String tokens = '';
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File) continue;
    final lower = e.path.toLowerCase();
    if (lower.endsWith('.onnx') && model.isEmpty) model = e.path;
    if (lower.endsWith('/tokens.txt') || lower.endsWith('\\tokens.txt')) {
      tokens = e.path;
    }
  }
  if (model.isEmpty || tokens.isEmpty) return null;
  if (File(model).lengthSync() < 1024 * 1024 || File(tokens).lengthSync() < 8) {
    return null;
  }
  return _TtsFiles(model, tokens);
}

Directory? _findEspeakDir(Directory dir) {
  if (!dir.existsSync()) return null;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! Directory || !e.path.endsWith('espeak-ng-data')) continue;
    final required = ['phontab', 'phondata', 'phonindex'];
    if (required.every((name) => File('${e.path}/$name').existsSync())) {
      return e;
    }
  }
  return null;
}

/// Выполняется в фоновом isolate: FFI-библиотеки инициализируются там.
bool _generateWav({
  required String modelPath,
  required String tokensPath,
  required String espeakDir,
  required String text,
  required double speed,
  required String wavPath,
}) {
  if (modelPath.isEmpty || !Directory(espeakDir).existsSync()) return false;
  sherpa.initBindings();
  piper.initBindings();
  final init = piper.PiperPhonemize.initialize(espeakDir);
  if (init < 0) return false;
  final sentences = piper.PiperPhonemize.phonemize(text, voice: 'ru')
      .where((s) => s.isNotEmpty)
      .toList();
  if (sentences.isEmpty) return false;
  final vits = sherpa.OfflineTtsVitsModelConfig(
    model: modelPath,
    tokens: tokensPath,
  );
  final tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(vits: vits, numThreads: 2),
    maxNumSentences: 1,
  ));
  try {
    final audio = tts.generateWithConfig(
      text: '',
      config: sherpa.OfflineTtsGenerationConfig(
        sid: 0,
        speed: speed,
        silenceScale: 0.2,
        phonemeCodepoints: sentences,
      ),
    );
    if (audio.samples.isEmpty) return false;
    return sherpa.writeWave(
      filename: wavPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
  } finally {
    tts.free();
  }
}
