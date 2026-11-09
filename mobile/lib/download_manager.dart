// download_manager.dart — единый менеджер загрузок моделей.
//
// Android: системный DownloadManager (переживает фон, смерть процесса и
// перезагрузку). Flutter хранит только метаданные задачи и systemId.
// Остальные платформы: HTTP Range-докачка в .part.
//
// В downloads.json никогда не попадают токены. Токен передаётся только в
// момент постановки запроса и хранится в защищённом хранилище.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'secret_store.dart';

enum DownloadStatus { queued, downloading, completed, failed, canceled }

extension DownloadStatusX on DownloadStatus {
  bool get active =>
      this == DownloadStatus.queued || this == DownloadStatus.downloading;

  bool get finished => this == DownloadStatus.completed;

  String get label => switch (this) {
        DownloadStatus.queued => 'В очереди',
        DownloadStatus.downloading => 'Скачивается',
        DownloadStatus.completed => 'Скачано',
        DownloadStatus.failed => 'Ошибка',
        DownloadStatus.canceled => 'Отменено',
      };
}

class DownloadJob {
  final String id, repoId, fileName, url;
  String finalPath;
  int totalBytes, receivedBytes;
  int? systemId;
  int createdAt, updatedAt;
  String error, etag;
  DownloadStatus status;

  DownloadJob({
    required this.id,
    required this.repoId,
    required this.fileName,
    required this.url,
    required this.finalPath,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.systemId,
    required this.createdAt,
    required this.updatedAt,
    this.error = '',
    this.etag = '',
    this.status = DownloadStatus.queued,
  });

  bool get isActive => status.active;
  double get progress =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'repo_id': repoId,
        'file_name': fileName,
        'url': url,
        'final_path': finalPath,
        'total_bytes': totalBytes,
        'received_bytes': receivedBytes,
        'system_id': systemId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'error': error,
        'etag': etag,
        'status': status.name,
      };

  factory DownloadJob.fromJson(Map<String, dynamic> j) => DownloadJob(
        id: j['id'] as String? ?? '',
        repoId: j['repo_id'] as String? ?? '',
        fileName: j['file_name'] as String? ?? '',
        url: j['url'] as String? ?? '',
        finalPath: j['final_path'] as String? ?? '',
        totalBytes: (j['total_bytes'] as num?)?.toInt() ?? 0,
        receivedBytes: (j['received_bytes'] as num?)?.toInt() ?? 0,
        systemId: (j['system_id'] as num?)?.toInt(),
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
        error: j['error'] as String? ?? '',
        etag: j['etag'] as String? ?? '',
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => DownloadStatus.failed,
        ),
      );
}

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const _channelName = 'com.vlad.termai/downloads';
  static const MethodChannel _channel = MethodChannel(_channelName);

  final Map<String, DownloadJob> _jobs = {};
  final Map<String, http.Client> _dartClients = {};
  /// id задачи → (последнее число байт, когда оно изменилось). Нужно, чтобы
  /// отличить медленную загрузку от зависшей.
  final Map<String, (int, DateTime)> _progressMark = {};

  Timer? _poll;
  Timer? _saveTimer;
  bool _initialized = false;
  bool _disposed = false;
  Directory? _modelsDirCache;

  bool get initialized => _initialized;
  List<DownloadJob> get jobs =>
      _jobs.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  List<DownloadJob> get activeJobs => jobs.where((j) => j.isActive).toList();
  DownloadJob? jobFor(String repoId, String fileName) =>
      _jobs[_key(repoId, fileName)];

  /// Инициализация: поднимаем metadata, сверяем completed-файлы и
  /// восстанавливаем systemId после перезапуска приложения.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _load();
    for (final job in _jobs.values.toList()) {
      if (job.status == DownloadStatus.completed) {
        final f = File(job.finalPath);
        if (!await f.exists()) {
          job.status = DownloadStatus.failed;
          job.error = 'Файл модели не найден. Скачай заново.';
        } else if (job.totalBytes > 0 && await f.length() != job.totalBytes) {
          job.status = DownloadStatus.failed;
          job.error = 'Размер файла не совпадает с ожидаемым.';
        }
      } else if (job.status == DownloadStatus.downloading &&
          job.systemId == null) {
        // Dart-загрузка не пережила процесс: оставляем .part для докачки.
        job.status = DownloadStatus.queued;
      }
    }
    await _save();
    await refresh();
    _startPolling();
    unawaited(_resumeQueued());
  }

  Future<void> _resumeQueued() async {
    final queued =
        _jobs.values.where((j) => j.status == DownloadStatus.queued).toList();
    if (queued.isEmpty) return;
    final token = await SecretStore.readHfToken();
    for (final job in queued) {
      if (job.status != DownloadStatus.queued) continue;
      job.status = DownloadStatus.downloading;
      notifyListeners();
      await _startTransport(job, token);
    }
  }

  Future<Directory> modelsDir() async {
    if (_modelsDirCache != null) return _modelsDirCache!;
    Directory? dir;
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          dir = Directory('${ext.path}/Download/models');
        }
      } catch (_) {}
    }
    dir ??= Directory(
      '${(await getApplicationDocumentsDirectory()).path}/models',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    _modelsDirCache = dir;
    return dir;
  }

  /// Свободное место в папке моделей; null, если платформа не умеет.
  Future<int?> freeBytes() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('freeSpace');
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    for (final job in _jobs.values.toList()) {
      if (!job.isActive || job.systemId == null) continue;
      await _refreshAndroid(job);
    }
    _startPolling();
    notifyListeners();
  }

  /// Начинает загрузку или возвращает уже существующую задачу.
  /// expectedBytes используется только для проверки уже готового файла.
  Future<DownloadJob> start({
    required String repoId,
    required String fileName,
    required String url,
    String token = '',
    int expectedBytes = 0,
    String etag = '',
  }) async {
    if (!_initialized) await init();
    final key = _key(repoId, fileName);
    final dir = await modelsDir();
    final target = File('${dir.path}/${_safeName(fileName)}');
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = _jobs[key];
    if (existing != null) {
      if (existing.status == DownloadStatus.downloading) return existing;
      if (existing.status == DownloadStatus.completed) {
        final f = File(existing.finalPath);
        if (await f.exists() &&
            (existing.totalBytes <= 0 ||
                await f.length() == existing.totalBytes)) {
          return existing;
        }
      }
    }

    if (await target.exists()) {
      final size = await target.length();
      if (size > 0 && (expectedBytes <= 0 || size == expectedBytes)) {
        final job = DownloadJob(
          id: key,
          repoId: repoId,
          fileName: fileName,
          url: url,
          finalPath: target.path,
          totalBytes: size,
          receivedBytes: size,
          createdAt: now,
          updatedAt: now,
          status: DownloadStatus.completed,
        );
        _jobs[key] = job;
        await _save();
        notifyListeners();
        return job;
      }
    }

    final free = await freeBytes();
    if (expectedBytes > 0 &&
        free != null &&
        free < expectedBytes + 100 * 1024 * 1024) {
      final job = DownloadJob(
        id: key,
        repoId: repoId,
        fileName: fileName,
        url: url,
        finalPath: target.path,
        totalBytes: expectedBytes,
        receivedBytes: 0,
        etag: etag,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        status: DownloadStatus.failed,
        error: 'Недостаточно свободного места: нужно ещё '
            '${((expectedBytes + 100 * 1024 * 1024 - free) / (1024 * 1024)).round()} МБ.',
      );
      _jobs[key] = job;
      await _save();
      notifyListeners();
      return job;
    }
    final job = DownloadJob(
      id: key,
      repoId: repoId,
      fileName: fileName,
      url: url,
      finalPath: target.path,
      totalBytes: expectedBytes,
      receivedBytes: 0,
      etag: etag,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    _jobs[key] = job;
    job.status = DownloadStatus.downloading;
    await _save();
    notifyListeners();
    await _startTransport(job, token);
    return job;
  }

  Future<void> cancel(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    if (job.systemId != null) {
      try {
        await _channel.invokeMethod<void>('cancel', {'id': job.systemId});
      } catch (_) {}
    }
    try {
      _dartClients.remove(id)?.close();
    } catch (_) {}
    job.status = DownloadStatus.canceled;
    job.error = '';
    job.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _dartClients.remove(id);
    // Отмена — явное действие пользователя. Временный файл можно удалить.
    try {
      final part = File('${job.finalPath}.part');
      if (await part.exists()) await part.delete();
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  Future<void> retry(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    job.status = DownloadStatus.queued;
    job.error = '';
    job.receivedBytes = 0;
    job.systemId = null;
    job.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _save();
    notifyListeners();
    final token = await _tokenForRetry();
    await start(
      repoId: job.repoId,
      fileName: job.fileName,
      url: job.url,
      token: token,
      expectedBytes: job.totalBytes,
      etag: job.etag,
    );
  }

  /// Убирает запись о загрузке. Скачанный файл при этом НЕ удаляется:
  /// установленная модель живёт в отдельном списке и удаляется отдельно.
  Future<void> removeRecord(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    if (job.isActive) await cancel(id);
    _jobs.remove(id);
    await _save();
    notifyListeners();
  }

  Future<void> _startTransport(DownloadJob job, String token) async {
    if (Platform.isAndroid) {
      try {
        await _startAndroid(job, token);
        return;
      } on MissingPluginException {
        // Тесты и сборки без нативной части: используем Dart-докачку.
      } catch (e) {
        job.status = DownloadStatus.failed;
        job.error = _msg(e);
        job.updatedAt = DateTime.now().millisecondsSinceEpoch;
        await _save();
        notifyListeners();
        return;
      }
    }
    unawaited(_startDart(job, token));
  }

  Future<void> _startAndroid(DownloadJob job, String token) async {
    final headers = <String, String>{
      'User-Agent': 'TERMAI-model-download',
      if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
    };
    final result = await _channel.invokeMapMethod<String, dynamic>('enqueue', {
      'url': job.url,
      'fileName': _safeName(job.fileName),
      'headers': headers,
      'expectedBytes': job.totalBytes,
    });
    if (result == null) throw Exception('DownloadManager не вернул задачу');
    if (result['alreadyExists'] == true) {
      final path = (result['path'] ?? job.finalPath).toString();
      final size = (result['size'] as num?)?.toInt() ?? 0;
      if (job.totalBytes > 0 && size != job.totalBytes) {
        job
          ..finalPath = path
          ..receivedBytes = size
          ..status = DownloadStatus.failed
          ..error = 'Файл уже существует, но его размер не совпадает.'
          ..updatedAt = DateTime.now().millisecondsSinceEpoch;
      } else {
        job
          ..finalPath = path
          ..receivedBytes = size
          ..totalBytes = size
          ..status = DownloadStatus.completed
          ..error = ''
          ..updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
      await _save();
      notifyListeners();
      return;
    }
    job.systemId = (result['systemId'] as num?)?.toInt();
    job.finalPath = (result['path'] ?? job.finalPath).toString();
    job.status = DownloadStatus.downloading;
    job.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _save();
    _startPolling();
    notifyListeners();
  }

  /// _promoteCompleted — страховка от «зависания» DownloadManager на
  /// последних процентах. На части прошивок системная загрузка дописывает
  /// файл (в проводнике он выглядит скачанным), но COLUMN_STATUS ещё долго
  /// остаётся RUNNING или прогресс не доходит до 100%. Если файл на диске уже
  /// нужного размера — завершаем задачу сами.
  Future<bool> _promoteCompleted(DownloadJob job) async {
    Future<bool> check(File f) async {
      if (!await f.exists()) return false;
      final size = await f.length();
      if (size <= 0) return false;
      if (job.totalBytes > 0 && size != job.totalBytes) return false;
      _progressMark.remove(job.id);
      job
        ..receivedBytes = size
        ..totalBytes = size
        ..status = DownloadStatus.completed
        ..error = ''
        ..systemId = null
        ..updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
      notifyListeners();
      return true;
    }

    final target = File(job.finalPath);
    if (await check(target)) return true;
    final part = File('${job.finalPath}.part');
    if (!await part.exists()) return false;
    final size = await part.length();
    if (size <= 0) return false;
    if (job.totalBytes > 0 && size != job.totalBytes) return false;
    try {
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } catch (_) {
      return false;
    }
    return check(target);
  }

  Future<void> _refreshAndroid(DownloadJob job) async {
    final id = job.systemId;
    if (id == null) return;
    // Сначала проверяем, не дописан ли файл до конца: это дешевле запроса
    // к системе и работает даже если DownloadManager «завис».
    if (await _promoteCompleted(job)) return;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'status',
        {'id': id, 'finalPath': job.finalPath},
      );
      if (result == null) return;
      final status = (result['status'] ?? '').toString();
      final received = (result['received'] as num?)?.toInt() ?? 0;
      final total = (result['total'] as num?)?.toInt() ?? 0;
      final path = (result['path'] ?? '').toString();
      if (path.isNotEmpty) job.finalPath = path;
      if (total > 0) job.totalBytes = total;
      if (received > 0) job.receivedBytes = received;
      switch (status) {
        case 'successful':
          final f = File(job.finalPath);
          if (!await f.exists()) {
            // Системный загрузчик отрапортовал успех, но файла нет: часть
            // прошивок не пишет в Android/data. Докачиваем своим клиентом —
            // сохранённый .part будет использован для Range-докачки.
            job.systemId = null;
            _stripPartSuffix(job);
            job.updatedAt = DateTime.now().millisecondsSinceEpoch;
            await _save();
            unawaited(_startDart(job, await _tokenForRetry()));
            return;
          }
          final size = await f.length();
          if (job.totalBytes > 0 && size != job.totalBytes) {
            job.status = DownloadStatus.failed;
            job.error = 'Размер файла не совпадает с ожидаемым.';
          } else {
            job.receivedBytes = size;
            job.totalBytes = size;
            job.status = DownloadStatus.completed;
            job.error = '';
          }
          job.systemId = null;
        case 'failed':
          final nativeMsg = (result['message'] as String?)?.trim() ?? '';
          final reason = (result['reason'] as num?)?.toInt() ?? 0;
          if (reason == -2) {
            // Переезд файла внутри нативного слоя не удался — свой клиент
            // качает напрямую в finalPath, минуя капризы DownloadManager.
            job.systemId = null;
            _stripPartSuffix(job);
            job.updatedAt = DateTime.now().millisecondsSinceEpoch;
            await _save();
            unawaited(_startDart(job, await _tokenForRetry()));
            return;
          }
          job.status = DownloadStatus.failed;
          job.error = nativeMsg.isEmpty
              ? _reasonText(reason)
              : 'Системная загрузка: $nativeMsg (код $reason).';
          job.systemId = null;
        case 'paused':
          job.status = DownloadStatus.failed;
          job.error = 'Система приостановила загрузку. Нажми «Повторить».';
          job.systemId = null;
        default:
          job.status = DownloadStatus.downloading;
          // Watchdog: системная загрузка может «повиснуть» на последних
          // процентах. Если байты не меняются 2 минуты — переходим на свой
          // HTTP-клиент, он устойчивее к таким зависаниям.
          final now = DateTime.now();
          final mark = _progressMark[job.id];
          if (mark == null || mark.$1 != received) {
            _progressMark[job.id] = (received, now);
          } else if (now.difference(mark.$2) > const Duration(minutes: 2)) {
            _progressMark.remove(job.id);
            await _recoverStalled(job);
            return;
          }
      }
      job.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
    } catch (_) {
      // Нативный слой может быть недоступен в тестах.
    }
  }

  /// _recoverStalled — снимает зависшую системную загрузку и докачивает файл
  /// собственным клиентом (Range), не теряя уже скачанные байты, если они на
  /// диске и доступны.
  Future<void> _recoverStalled(DownloadJob job) async {
    final id = job.systemId;
    if (id != null) {
      try {
        await _channel.invokeMethod<void>('cancel', {'id': id});
      } catch (_) {}
    }
    job.systemId = null;
    _stripPartSuffix(job);
    job.status = DownloadStatus.downloading;
    job.error = '';
    job.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _save();
    notifyListeners();
    unawaited(_startDart(job, await _tokenForRetry()));
  }

  /// _stripPartSuffix — нативный слой может вернуть путь .part, если
  /// переезд не состоялся; дартовский докачиватель сам добавляет суффикс.
  void _stripPartSuffix(DownloadJob job) {
    if (job.finalPath.endsWith('.part')) {
      job.finalPath =
          job.finalPath.substring(0, job.finalPath.length - '.part'.length);
    }
  }

  Future<void> _startDart(DownloadJob job, String token) async {
    if (_dartClients.containsKey(job.id)) return;
    final part = File('${job.finalPath}.part');
    var received = await part.exists() ? await part.length() : 0;
    if (job.totalBytes > 0 && received > job.totalBytes) {
      try {
        await part.delete();
      } catch (_) {}
      received = 0;
    }
    final client = http.Client();
    _dartClients[job.id] = client;
    job
      ..status = DownloadStatus.downloading
      ..receivedBytes = received
      ..error = ''
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(job.url));
      request.headers['User-Agent'] = 'TERMAI-model-download';
      if (token.trim().isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${token.trim()}';
      }
      if (received > 0) {
        request.headers['Range'] = 'bytes=$received-';
        if (job.etag.isNotEmpty) request.headers['If-Range'] = job.etag;
      }
      final response = await client.send(request);
      if (response.statusCode == 416) {
        // Частичный файл уже полный или не совпал с сервером.
        final size = await part.exists() ? await part.length() : 0;
        if (job.totalBytes > 0 && size == job.totalBytes) {
          await _finishDart(job, part);
          return;
        }
        if (await part.exists()) await part.delete();
        throw Exception('Сервер не принял докачку. Попробуй ещё раз.');
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Сервер вернул ${response.statusCode}');
      }
      final append = response.statusCode == 206 && received > 0;
      if (!append) {
        received = 0;
        if (await part.exists()) await part.delete();
      }
      final total = _totalBytes(response, received);
      if (total > 0) job.totalBytes = total;
      final etag = response.headers['etag'] ?? '';
      if (etag.isNotEmpty) job.etag = etag;
      sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      var lastSaved = received;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        job.receivedBytes = received;
        if (received - lastSaved > 1024 * 1024) {
          lastSaved = received;
          _saveSoon();
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (job.totalBytes > 0 && received != job.totalBytes) {
        throw Exception(
            'Загрузка оборвалась: $received из ${job.totalBytes} байт');
      }
      await _finishDart(job, part);
    } catch (e) {
      if (job.status == DownloadStatus.canceled) return;
      job.status = DownloadStatus.failed;
      job.error = _msg(e);
      job.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
      notifyListeners();
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      _dartClients.remove(job.id);
    }
  }

  Future<void> _finishDart(DownloadJob job, File part) async {
    final target = File(job.finalPath);
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    final size = await target.length();
    job
      ..receivedBytes = size
      ..totalBytes = size
      ..status = DownloadStatus.completed
      ..error = ''
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _save();
    notifyListeners();
  }

  int _totalBytes(http.StreamedResponse response, int already) {
    final range = response.headers['content-range'] ?? '';
    final match = RegExp(r'/(\d+)$').firstMatch(range);
    if (match != null) return int.tryParse(match.group(1)!) ?? 0;
    final len = response.contentLength ?? 0;
    return len > 0 ? already + len : 0;
  }

  Future<String> _tokenForRetry() async {
    try {
      return await SecretStore.readHfToken();
    } catch (_) {
      return '';
    }
  }

  void _startPolling() {
    if (_disposed) return;
    final active = _jobs.values.any((j) => j.isActive);
    if (!active) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      await refresh();
    });
  }

  Future<void> _load() async {
    try {
      final file = await _metaFile();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as List?;
      if (raw == null) return;
      for (final item in raw) {
        if (item is Map) {
          final job = DownloadJob.fromJson(item.cast<String, dynamic>());
          if (job.id.isNotEmpty) _jobs[job.id] = job;
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      final file = await _metaFile();
      await file.writeAsString(jsonEncode(
        _jobs.values.map((j) => j.toJson()).toList(),
        toEncodable: (o) => o.toString(),
      ));
    } catch (_) {}
  }

  void _saveSoon() {
    if (_saveTimer?.isActive == true) return;
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_save());
    });
  }

  Future<File> _metaFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/downloads.json');
  }

  String _key(String repoId, String fileName) =>
      '${repoId.trim()}::${_safeName(fileName)}';

  String _safeName(String name) {
    final base = name.split('/').last;
    return base.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _msg(Object e) {
    var s = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return s.length > 240 ? '${s.substring(0, 240)}…' : s;
  }

  String _reasonText(int reason) => switch (reason) {
        1001 => 'Недостаточно места на устройстве.',
        1004 => 'Нет сети.',
        1006 => 'Файл уже существует.',
        1007 => 'Сервер не поддерживает докачку.',
        1008 => 'Не удалось открыть файл.',
        1009 => 'Нет доступа к папке загрузок.',
        _ => 'Системная загрузка завершилась с ошибкой ($reason).',
      };

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _saveTimer?.cancel();
    for (final c in _dartClients.values) {
      try {
        c.close();
      } catch (_) {}
    }
    _dartClients.clear();
    super.dispose();
  }
}
