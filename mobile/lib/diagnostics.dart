// diagnostics.dart — проверка состояния TERMAI без вызова модели.
//
// Отчёт не содержит токенов, ключей, email и переписки. Технические детали
// показываются в раскрывающемся блоке, чтобы не засорять чат.
import 'download_manager.dart';
import 'notifications.dart';
import 'shared_ai.dart';
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

  // Основной ИИ.
  if (c.ai == null || !c.ai!.ready) {
    items.add(const DiagnosticItem(
      title: 'ИИ-провайдер',
      level: DiagnosticLevel.error,
      message: 'не настроен',
      details: 'Нет готового endpoint. Добавь API-ключ в настройках ИИ.',
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

  // Общий доступ TERMAI.
  final shared = SharedAiService.instance;
  if (shared.proxyConfigured) {
    if (shared.loading) {
      items.add(const DiagnosticItem(
        title: 'Общий доступ TERMAI',
        level: DiagnosticLevel.warning,
        message: 'проверяется',
        details: 'Запрашиваю условия акции с серверного шлюза.',
      ));
    } else if (shared.promo == null) {
      items.add(DiagnosticItem(
        title: 'Общий доступ TERMAI',
        level: DiagnosticLevel.warning,
        message: 'сервер недоступен',
        details: _redact(shared.error),
      ));
    } else {
      final active = shared.isUsable(c.config);
      items.add(DiagnosticItem(
        title: 'Общий доступ TERMAI',
        level: active ? DiagnosticLevel.ok : DiagnosticLevel.warning,
        message: active
            ? 'включён (${shared.model})'
            : (!shared.signedIn
                ? 'нужен вход через Google'
                : (shared.promo!.active
                    ? 'выключен пользователем'
                    : 'акция завершена')),
        details: [
          'Модель: ${shared.model}',
          'До: ${shared.endsAt ?? '—'}',
          'Остаток: ${shared.remainingLabel}',
          'Вход через Google: ${shared.signedIn ? 'да' : 'нет'}',
          'Личный провайдер: ${c.config.provider}',
        ].join('\n'),
      ));
    }
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
