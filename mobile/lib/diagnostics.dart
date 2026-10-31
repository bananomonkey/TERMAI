// diagnostics.dart — проверка состояния TERMAI без вызова модели.
//
// Отчёт не содержит токенов, ключей, email и переписки. Технические детали
// показываются в раскрывающемся блоке, чтобы не засорять чат.
import 'dart:io';

import 'package:http/http.dart' as http;

import 'download_manager.dart';
import 'local_ai.dart';
import 'notifications.dart';
import 'secret_store.dart';
import 'store.dart';

enum DiagnosticLevel { ok, warning, error }

class DiagnosticItem {
  final String title;
  final DiagnosticLevel level;
  final String message;
  final String details;
  const DiagnosticItem({
    required this.title,
    required this.level,
    required this.message,
    this.details = '',
  });
}

class DiagnosticReport {
  final List<DiagnosticItem> items;
  const DiagnosticReport(this.items);

  String get summary {
    final b = StringBuffer('Диагностика TERMAI\n\n');
    for (final item in items) {
      final mark = switch (item.level) {
        DiagnosticLevel.ok => '✓',
        DiagnosticLevel.warning => '!',
        DiagnosticLevel.error => '✕',
      };
      b.writeln('$mark ${item.title} — ${item.message}');
    }
    return b.toString().trim();
  }

  String get details {
    final b = StringBuffer();
    for (final item in items) {
      b.writeln('${item.title}: ${item.message}');
      if (item.details.isNotEmpty) b.writeln(item.details);
      b.writeln();
    }
    return b.toString().trim();
  }
}

Future<DiagnosticReport> runDiagnostics(AppController c) async {
  final items = <DiagnosticItem>[];
  final provider = c.config.provider;
  final localPath = c.config.localModelPath;

  // Основной ИИ.
  if (c.ai == null || !c.ai!.ready) {
    items.add(const DiagnosticItem(
      title: 'ИИ-провайдер',
      level: DiagnosticLevel.error,
      message: 'не настроен',
      details: 'Нет готового endpoint. Добавь API-ключ или локальную модель.',
    ));
  } else {
    final result = await c.testEndpoint(-1);
    items.add(DiagnosticItem(
      title: 'ИИ-провайдер',
      level: result.ok ? DiagnosticLevel.ok : DiagnosticLevel.error,
      message: result.ok ? 'работает (${c.ai!.model})' : 'ошибка подключения',
      details: [
        'Провайдер: $provider',
        'Модель: ${c.ai!.model}',
        'Ответ: ${_redact(result.reply)}',
        if (!result.ok) 'Ошибка: ${_redact(result.error)}',
      ].join('\n'),
    ));
  }

  // Локальный ИИ.
  final local = LocalAiService.instance;
  final installed = await local.installedModels();
  final file = localPath.isEmpty ? null : File(localPath);
  final exists = file == null ? false : await file.exists();
  if (localPath.isEmpty) {
    items.add(DiagnosticItem(
      title: 'Локальный ИИ',
      level: DiagnosticLevel.warning,
      message: 'не настроен',
      details: installed.isEmpty
          ? 'GGUF-файлов нет.'
          : 'Найдено файлов: ${installed.length}, но активная модель не выбрана.',
    ));
  } else if (!exists) {
    items.add(DiagnosticItem(
      title: 'Локальный ИИ',
      level: DiagnosticLevel.error,
      message: 'файл модели не найден',
      details: 'Путь: $localPath\nФайл удалён или перемещён.',
    ));
  } else {
    final size = await file.length();
    items.add(DiagnosticItem(
      title: 'Локальный ИИ',
      level: local.ready ? DiagnosticLevel.ok : DiagnosticLevel.warning,
      message: local.ready ? 'модель загружена' : 'модель не загружена',
      details: [
        'Файл: ${file.path.split('/').last}',
        'Размер: ${_mb(size)}',
        'Контекст: ${c.config.localContextSize}',
        'Установлено моделей: ${installed.length}',
        if (local.error.isNotEmpty) 'Ошибка: ${_redact(local.error)}',
      ].join('\n'),
    ));
  }

  // Hugging Face. Проверяем только метаданные, не веса.
  try {
    final token = await SecretStore.readHfToken();
    final res = await http.get(
      Uri.parse('https://huggingface.co/api/models?limit=1'),
      headers: {
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      items.add(DiagnosticItem(
        title: 'Hugging Face',
        level: DiagnosticLevel.ok,
        message: 'доступен',
        details: 'API метаданных отвечает. Токен: ${SecretStore.mask(token)}.',
      ));
    } else if (res.statusCode == 401 || res.statusCode == 403) {
      items.add(DiagnosticItem(
        title: 'Hugging Face',
        level: DiagnosticLevel.warning,
        message: 'токен не принят',
        details: 'HTTP ${res.statusCode}. Проверь HF token для gated-моделей.',
      ));
    } else {
      items.add(DiagnosticItem(
        title: 'Hugging Face',
        level: DiagnosticLevel.warning,
        message: 'HTTP ${res.statusCode}',
        details: 'API доступен, но вернул неожиданный статус.',
      ));
    }
  } catch (e) {
    items.add(DiagnosticItem(
      title: 'Hugging Face',
      level: DiagnosticLevel.error,
      message: 'недоступен',
      details: _redact(e.toString()),
    ));
  }

  // Загрузки моделей.
  final jobs = DownloadManager.instance.jobs;
  final active = jobs.where((j) => j.isActive).length;
  final failed = jobs.where((j) => j.status == DownloadStatus.failed).length;
  final completed =
      jobs.where((j) => j.status == DownloadStatus.completed).length;
  final jobLines = jobs
      .take(10)
      .map((j) =>
          '${j.fileName}: ${j.status.name} ${j.receivedBytes}/${j.totalBytes}')
      .join('\n');
  items.add(DiagnosticItem(
    title: 'Загрузки моделей',
    level: failed > 0 ? DiagnosticLevel.warning : DiagnosticLevel.ok,
    message: failed > 0
        ? '$failed с ошибкой'
        : (active > 0 ? '$active активных' : 'ошибок нет'),
    details: [
      'Активных: $active, завершено: $completed, ошибок: $failed',
      if (jobLines.isNotEmpty) jobLines,
    ].join('\n'),
  ));

  // Firebase.
  final sync = c.sync;
  if (!sync.supported) {
    items.add(const DiagnosticItem(
      title: 'Синхронизация',
      level: DiagnosticLevel.warning,
      message: 'недоступна на этой платформе',
    ));
  } else if (!sync.configured) {
    items.add(DiagnosticItem(
      title: 'Синхронизация',
      level: DiagnosticLevel.warning,
      message: 'Firebase не настроен',
      details: _redact(sync.error),
    ));
  } else if (!sync.signedIn) {
    items.add(const DiagnosticItem(
      title: 'Синхронизация',
      level: DiagnosticLevel.warning,
      message: 'вход не выполнен',
    ));
  } else {
    items.add(DiagnosticItem(
      title: 'Синхронизация',
      level: sync.error.isEmpty ? DiagnosticLevel.ok : DiagnosticLevel.error,
      message: sync.error.isEmpty ? 'работает' : 'ошибка',
      details: sync.error.isEmpty
          ? 'Пользователь вошёл, облачные данные доступны.'
          : _redact(sync.error),
    ));
  }

  // Уведомления.
  try {
    final enabled = await notificationService.areEnabled();
    items.add(DiagnosticItem(
      title: 'Уведомления',
      level: enabled ? DiagnosticLevel.ok : DiagnosticLevel.warning,
      message: enabled ? 'разрешены' : 'запрещены',
      details: enabled
          ? 'Локальные напоминания могут доставляться.'
          : 'Разреши уведомления в настройках Android.',
    ));
  } catch (e) {
    items.add(DiagnosticItem(
      title: 'Уведомления',
      level: DiagnosticLevel.warning,
      message: 'не удалось проверить',
      details: _redact(e.toString()),
    ));
  }

  if (diagLog.isNotEmpty) {
    final log = diagLog.toString();
    items.add(DiagnosticItem(
      title: 'Журнал ошибок',
      level: DiagnosticLevel.warning,
      message: 'есть записи',
      details:
          _redact(log.length > 1600 ? log.substring(log.length - 1600) : log),
    ));
  }

  return DiagnosticReport(items);
}

String _mb(int n) => '${(n / (1024 * 1024)).toStringAsFixed(1)} МБ';

String _redact(String value) {
  var s = value;
  s = s.replaceAll(
    RegExp(r'(sk-[A-Za-z0-9_\-]{6,}|hf_[A-Za-z0-9]{6,})'),
    '••••',
  );
  s = s.replaceAll(RegExp(r'Bearer\s+[^\s]+'), 'Bearer ••••');
  s = s.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '••••@••••');
  if (s.length > 800) s = '${s.substring(0, 800)}…';
  return s;
}
