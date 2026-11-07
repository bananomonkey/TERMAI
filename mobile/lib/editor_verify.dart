// editor_verify.dart — детерминированная проверка YAML/кода без ИИ.
// Смотрит реальную структуру документа и возвращает позицию ошибки парсера.
import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'models.dart';

class EditorCheck {
  final bool ok;
  final String message;
  final int? line;
  final int? column;
  const EditorCheck(this.ok, this.message, {this.line, this.column});
}

EditorCheck verifyEditorTask(Task task, String text) {
  final raw = task.verify['checks'];
  final checks = raw is List ? raw.map((e) => _map(e)).toList() : [task.verify];
  final source = text.trim();
  if (source.isEmpty) {
    return const EditorCheck(false, 'Поле редактора пустое.');
  }
  if (raw is List && checks.isEmpty) {
    // Письменная работа: машинных проверок нет, работу оценивает ИИ
    // после «Отправить». Нейтральный статус, чтобы бейдж не был красным.
    return const EditorCheck(true, 'Работу проверит ИИ после «Отправить».');
  }
  final needsYaml = task.editorLanguage == 'yaml' ||
      checks.any((c) =>
          c.containsKey('yaml_path') ||
          c.containsKey('yaml_list_contains') ||
          c.containsKey('yaml_size_gte'));
  dynamic doc;
  if (needsYaml) {
    try {
      doc = _plain(loadYamlNode(source));
    } on YamlException catch (e) {
      final line = e.span == null ? null : e.span!.start.line + 1;
      final col = e.span == null ? null : e.span!.start.column + 1;
      return EditorCheck(
        false,
        'YAML не разобрался: ${e.message}. Строка $line, позиция $col.',
        line: line,
        column: col,
      );
    } catch (e) {
      return EditorCheck(false, 'YAML не разобрался: $e');
    }
    if (doc == null) {
      return const EditorCheck(false, 'YAML пустой.');
    }
  }

  for (final c in checks) {
    final regex = c['yaml_regex']?.toString() ?? c['text_regex']?.toString();
    if (regex != null) {
      RegExp re;
      try {
        re = RegExp(regex,
            caseSensitive: c['case_sensitive'] == true, multiLine: true);
      } catch (_) {
        return const EditorCheck(false, 'Ошибка в критерии проверки.');
      }
      if (!re.hasMatch(source)) {
        return EditorCheck(false,
            c['message']?.toString() ?? 'В тексте нет нужной структуры.');
      }
      continue;
    }
    final contains = c['text_contains']?.toString();
    if (contains != null) {
      if (!source.toLowerCase().contains(contains.toLowerCase())) {
        return EditorCheck(
            false, c['message']?.toString() ?? 'В тексте нет «$contains».');
      }
      continue;
    }
    final path = c['yaml_path']?.toString();
    if (path != null) {
      final actual = _path(doc, path);
      if (actual == _missing) {
        return EditorCheck(
            false, c['message']?.toString() ?? 'В YAML нет пути «$path».');
      }
      if (c.containsKey('equals') && !_same(actual, c['equals'])) {
        return EditorCheck(
          false,
          c['message']?.toString() ??
              'Значение «$path» = ${_short(actual)}, ожидается ${c['equals']}.',
        );
      }
      if (c.containsKey('contains')) {
        final needle = c['contains'].toString().toLowerCase();
        final hay = actual is List ? actual.join('\n') : actual.toString();
        if (!hay.toLowerCase().contains(needle)) {
          return EditorCheck(false,
              c['message']?.toString() ?? '«$path» не содержит «$needle».');
        }
      }
      if (c.containsKey('min_length') &&
          actual is List &&
          actual.length < (c['min_length'] as num)) {
        return EditorCheck(
            false,
            c['message']?.toString() ??
                'В «$path» мало элементов: ${actual.length}.');
      }
      if (c.containsKey('list_item_contains')) {
        if (actual is! List) {
          return EditorCheck(false,
              c['message']?.toString() ?? '«$path» должен быть списком.');
        }
        final needle = c['list_item_contains'].toString().toLowerCase();
        final found = actual.any(
            (item) => jsonEncode(_plain(item)).toLowerCase().contains(needle));
        if (!found) {
          return EditorCheck(false,
              c['message']?.toString() ?? 'В списке «$path» нет «$needle».');
        }
      }
    }
    final listPath =
        c['yaml_list_contains']?.toString() ?? c['yaml_list_path']?.toString();
    if (listPath != null) {
      final list = _path(doc, listPath);
      final needle = (c['value'] ?? c['contains'] ?? '').toString();
      if (list is! List) {
        return EditorCheck(false,
            c['message']?.toString() ?? '«$listPath» должен быть списком.');
      }
      final found = list.any((item) => jsonEncode(_plain(item))
          .toLowerCase()
          .contains(needle.toLowerCase()));
      if (!found) {
        return EditorCheck(false,
            c['message']?.toString() ?? 'В списке «$listPath» нет «$needle».');
      }
    }
  }
  return const EditorCheck(true, 'Проверка пройдена.');
}

const _missing = Object();

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};

dynamic _plain(dynamic n) {
  if (n is YamlScalar) return n.value;
  if (n is YamlList) return n.map(_plain).toList();
  if (n is YamlMap) {
    return n.map((k, v) => MapEntry(k.toString(), _plain(v)));
  }
  if (n is Map) {
    return n.map((k, v) => MapEntry(k.toString(), _plain(v)));
  }
  if (n is List) return n.map(_plain).toList();
  return n;
}

dynamic _path(dynamic root, String path) {
  dynamic cur = root;
  for (final part in path.split('.')) {
    if (part.isEmpty) continue;
    if (cur is Map) {
      if (!cur.containsKey(part)) return _missing;
      cur = cur[part];
    } else if (cur is List) {
      final i = int.tryParse(part);
      if (i == null || i < 0 || i >= cur.length) return _missing;
      cur = cur[i];
    } else {
      return _missing;
    }
  }
  return cur;
}

bool _same(dynamic actual, dynamic expected) {
  if (actual is num && expected is num) return actual == expected;
  if (actual is List && expected is List) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (!_same(actual[i], expected[i])) return false;
    }
    return true;
  }
  return actual.toString() == expected.toString();
}

String _short(dynamic v) {
  final s = jsonEncode(v);
  return s.length > 80 ? '${s.substring(0, 77)}…' : s;
}
