// app_action.dart — протокол действий ИИ-наставника в приложении.
//
// Модель не имеет прямого доступа к Flutter, поэтому действия передаются
// служебными маркерами в ответе:
//   <termai>{"name":"open_screen","args":{"screen":"settings"}}</termai>
// Парсер вырезает их из текста, а AppActions выполняет. Это работает со
// всеми OpenAI-совместимыми провайдерами, даже без native tool calling.
import 'dart:convert';

class AppActionCall {
  final String name;
  final Map<String, dynamic> args;
  const AppActionCall(this.name, this.args);

  @override
  String toString() => '$name($args)';
}

typedef AppActionExecutor = Future<String> Function(AppActionCall call);

class ParsedAnswer {
  final String text;
  final List<AppActionCall> actions;
  const ParsedAnswer(this.text, this.actions);
}

/// Имена, которые умеет выполнять AppActions. Нужны, чтобы не вырезать
/// из ответа обычные JSON-блоки, не являющиеся вызовами.
const knownAppActions = <String>{
  'open_screen',
  'open_course',
  'open_lesson',
  'open_task',
  'open_chat',
  'new_chat',
  'open_interview',
  'select_course',
  'select_task',
  'next_task',
  'previous_task',
  'archive_course',
  'unarchive_course',
  'rename_course',
  'delete_course',
  'generate_course',
  'generate_task',
  'fill_course',
  'fill_terminal',
  'run_terminal',
  'clear_terminal',
  'undo_terminal',
  'submit_task',
  'show_solution',
  'open_terminal',
  'toggle_bookmark',
  'set_theme',
  'toggle_theme',
  'set_background',
  'set_button_brightness',
  'set_ai',
  'reset_usage',
  'open_more',
  // понятные синонимы — модели иногда называют действия по-своему
  'open_settings',
  'open_archive',
  'open_chats',
  'open_usage',
  'open_help',
  'open_background',
  'open_fallbacks',
  'open_review',
  'open_home',
  'write_terminal',
  'solve_task',
  'create_course',
  'create_task',
  'start_interview',
};

/// appActionsPrompt — компактный каталог для системного промпта.
/// Держим его рядом с парсером, чтобы список действий не расходился.
const appActionsPrompt = '''
Ты — Термай, ИИ-наставник приложения TERMAI. У тебя есть MCP-подобные действия, которые управляют приложением. Если пользователь просит что-то открыть, выбрать, вставить, выполнить или изменить — ВЫПОЛНИ действие, а не только опиши его.

Формат вызова — отдельной строкой, без markdown и без пояснений внутри:
<termai>{"name":"open_screen","args":{"screen":"settings"}}</termai>

Можно несколько вызовов подряд, но не больше трёх за ответ. В обычном тексте не показывай JSON и названия действий. Сначала одной короткой фразой скажи, что делаешь, затем вызов.

Действия и аргументы:
- open_screen {screen}: home, settings, archive, chats, usage, help, background, fallbacks, review, more, chat, interview, tasks, lesson.
- open_course {course}: открыть курс по названию или id.
- open_lesson {course?, task?}: открыть урок; без аргументов — текущую задачу.
- open_task {task, course?}: открыть конкретную задачу.
- open_chat {chat?}: открыть беседу по названию/id; без аргумента — текущий чат.
- new_chat: новый чат с текущей задачей.
- open_interview: собеседование.
- select_course {course}, select_task {task}, next_task, previous_task.
- archive_course {course}, unarchive_course {course}, rename_course {course, title}, delete_course {course}.
- generate_course {goal}: создать программу курсов по цели.
- generate_task {topic}: создать задачу по теме.
- fill_course {course?}: наполнить курс задачами от ИИ.
- fill_terminal {text}: вставить команду в поле ввода терминала, НЕ выполняя её.
- run_terminal {command}: выполнить команду в терминале.
- clear_terminal, undo_terminal.
- submit_task: проверить текущую задачу.
- show_solution: загрузить решение текущей задачи.
- open_terminal: открыть урок на слайде терминала.
- toggle_bookmark: добавить/убрать закладку текущей задачи.
- set_theme {theme}: dark (чёрная), light (светлая/дневная) или navy (синяя).
- toggle_theme: переключить светлую/тёмную тему.
- set_background {blur?, dim?}: размытие 0–40 и затемнение 0–0.9.
- set_button_brightness {value}: яркость кнопок 0.6–1.4 (1.0 — обычная).
- set_ai {provider?, model?, api_key?, base_url?}: изменить ИИ-подключение.
- reset_usage: обнулить счётчик токенов.
- open_more: открыть меню «Ещё».

Правила:
- «Открой настройки» → open_screen screen=settings. «Открой архив» → open_screen screen=archive.
- «Напиши в терминал …» → fill_terminal text=…; «выполни …» → run_terminal command=….
- «Покажи решение» → show_solution. «Создай курс …» → generate_course goal=….
- Удаляй курс только по прямой просьбе «удали». Не выдумывай аргументы и действия.
- Если нужен только ответ/объяснение — обычный текст без вызовов.
''';

/// parseAppActions — вырезает служебные вызовы из ответа модели.
ParsedAnswer parseAppActions(String raw) {
  final actions = <AppActionCall>[];
  var text = raw;

  final marker = RegExp(
    r'<termai>\s*([\s\S]*?)\s*</termai>',
    caseSensitive: false,
  );
  text = text.replaceAllMapped(marker, (m) {
    actions.addAll(_parseCalls(m.group(1) ?? '', allowUnknown: true));
    return '';
  });

  // Модель иногда оборачивает вызов в ```termai / ```json.
  final fence = RegExp(
    r'```(?:termai|json|tool)?\s*\n?([\s\S]*?)```',
    caseSensitive: false,
  );
  text = text.replaceAllMapped(fence, (m) {
    final calls = _parseCalls(m.group(1) ?? '');
    if (calls.isEmpty) return m.group(0) ?? '';
    actions.addAll(calls);
    return '';
  });

  // Пустые блоки, оставшиеся после вырезания вызова.
  text = text.replaceAll(RegExp(r'```[a-zA-Z]*\s*```'), '');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return ParsedAnswer(text, actions);
}

List<AppActionCall> _parseCalls(String raw, {bool allowUnknown = false}) {
  final s = raw.trim();
  if (s.isEmpty) return const [];
  dynamic decoded;
  try {
    decoded = jsonDecode(s);
  } catch (_) {
    // Иногда модель кладёт несколько JSON-объектов на разные строки.
    final out = <AppActionCall>[];
    for (final line in s.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        out.addAll(_callsFrom(jsonDecode(t), allowUnknown: allowUnknown));
      } catch (_) {}
    }
    return out;
  }
  return _callsFrom(decoded, allowUnknown: allowUnknown);
}

List<AppActionCall> _callsFrom(dynamic decoded, {required bool allowUnknown}) {
  if (decoded is List) {
    return decoded
        .expand((e) => _callsFrom(e, allowUnknown: allowUnknown))
        .toList();
  }
  if (decoded is! Map) return const [];
  if (decoded['actions'] is List) {
    return _callsFrom(decoded['actions'], allowUnknown: allowUnknown);
  }
  // OpenAI-подобный tool call: {"function":{"name":...,"arguments":...}}
  if (decoded['function'] is Map) {
    return _callsFrom(decoded['function'], allowUnknown: allowUnknown);
  }

  final name = (decoded['name'] ?? decoded['action'] ?? decoded['tool'] ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_');
  if (name.isEmpty) return const [];
  if (!allowUnknown && !knownAppActions.contains(name)) return const [];

  var argsRaw = decoded['args'] ??
      decoded['arguments'] ??
      decoded['params'] ??
      decoded['parameters'] ??
      const <String, dynamic>{};
  if (argsRaw is String) {
    try {
      argsRaw = jsonDecode(argsRaw);
    } catch (_) {
      argsRaw = const <String, dynamic>{};
    }
  }
  final args = <String, dynamic>{};
  if (argsRaw is Map) {
    for (final e in argsRaw.entries) {
      args[e.key.toString()] = e.value;
    }
  }
  // Некоторые модели кладут аргументы рядом с name, а не в args.
  const reserved = {
    'name', 'action', 'tool', 'args', 'arguments', 'params', 'parameters',
    'actions', 'function', 'type', 'id',
  };
  for (final e in decoded.entries) {
    if (!reserved.contains(e.key.toString())) {
      args.putIfAbsent(e.key.toString(), () => e.value);
    }
  }
  return [AppActionCall(name, args)];
}
