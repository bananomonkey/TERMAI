// diag.dart — глобальный журнал ошибок для экрана «Диагностика».
import 'dart:convert';

final StringBuffer diagLog = StringBuffer();

DateTime _lastAt = DateTime.now();

void appendDiag(String entry) {
  final now = DateTime.now();
  final ts = now.toIso8601String().substring(11, 19);
  diagLog.writeln('[$ts] $entry');
  _lastAt = now;
  if (diagLog.length > 24000) {
    final s = diagLog.toString();
    diagLog.clear();
    diagLog.write(s.substring(s.length - 18000));
  }
}

String diagDump() {
  if (diagLog.isEmpty) {
    final idle = DateTime.now().difference(_lastAt).inMinutes;
    return idle > 5
        ? 'Ошибок за последние $idle мин не зафиксировано.'
        : 'Ошибок не зафиксировано.';
  }
  return diagLog.toString();
}

String diagAsJson() => const JsonEncoder.withIndent('  ').convert({
      'captured_at': DateTime.now().toIso8601String(),
      'log': diagLog.toString(),
    });
