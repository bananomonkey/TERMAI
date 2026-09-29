// ai.dart — клиент OpenAI-совместимого API и роли ИИ (порт ai.go):
// симулятор терминала, проверяющий, ментор, генератор задач и курсов.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class ProviderPreset {
  final String id, title, baseUrl, defaultModel;
  final List<String> models;
  final String auth; // bearer | apikey
  const ProviderPreset(this.id, this.title, this.baseUrl, this.defaultModel, this.models, {this.auth = 'bearer'});
}

const providers = <ProviderPreset>[
  ProviderPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com', 'deepseek-chat', ['deepseek-chat', 'deepseek-reasoner']),
  ProviderPreset('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini', ['gpt-4o-mini', 'gpt-4o', 'gpt-4.1-mini', 'gpt-4.1', 'o3-mini']),
  ProviderPreset('gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai/', 'gemini-2.0-flash', ['gemini-2.0-flash', 'gemini-2.5-flash', 'gemini-2.5-pro']),
  ProviderPreset('qwen', 'Qwen (DashScope)', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus', ['qwen-plus', 'qwen-max', 'qwen-turbo', 'qwen2.5-72b-instruct']),
  ProviderPreset('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1', 'deepseek/deepseek-chat', ['deepseek/deepseek-chat', 'anthropic/claude-3.5-sonnet', 'meta-llama/llama-3.3-70b-instruct']),
  ProviderPreset('groq', 'Groq', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile', ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant']),
  ProviderPreset('mistral', 'Mistral', 'https://api.mistral.ai/v1', 'mistral-large-latest', ['mistral-large-latest', 'mistral-small-latest']),
  ProviderPreset('gigachat', 'GigaChat (Сбер)', 'https://gigachat.devices.sberbank.ru/api/v1', 'GigaChat', ['GigaChat', 'GigaChat-Pro'],
      auth: 'bearer'), // в поле ключа — Access Token из OAuth GigaChat
  ProviderPreset('yandex', 'YandexGPT', 'https://openai-compat.llm.api.cloud.yandex.net/v1', 'yandexgpt-lite', ['yandexgpt-lite', 'yandexgpt-pro'],
      auth: 'apikey'), // в поле ключа — API-ключ Яндекс.Облака
  ProviderPreset('ollama', 'Ollama (локально)', 'http://localhost:11434/v1', 'llama3.1', ['llama3.1', 'llama3.2', 'qwen2.5', 'mistral']),
  ProviderPreset('custom', 'Свой (OpenAI-совместимый)', '', '', []),
];

ProviderPreset findProvider(String id) =>
    providers.firstWhere((p) => p.id == id, orElse: () => providers.first);

String stateSummary(SandboxState st) {
  String orNone(List<String> items) => items.isEmpty ? '—' : items.join(', ');
  final cons = st.containers.entries.map((e) => '${e.key} (${e.value.status})').toList();
  return 'Песочница: workdir=${st.workdir}; файлы: ${orNone(st.files.keys.toList())}; '
      'образы: ${orNone(st.images.keys.toList())}; контейнеры: ${orNone(cons)}; '
      'томов: ${st.volumes.length}; сети: ${st.networks.join(', ')}.\n';
}

String formatHist(List<HistEntry> hist, int maxOut) {
  if (hist.isEmpty) return '(пусто)';
  final b = StringBuffer();
  for (final h in hist) {
    var out = h.out;
    if (out.length > maxOut) out = '${out.substring(0, maxOut)}…';
    b.write('\$ ${h.cmd}\n$out\n---\n');
  }
  return b.toString();
}

class AIClient {
  final String base, key, model, auth;
  AIClient._(this.base, this.key, this.model, this.auth);

  factory AIClient(Config cfg) {
    final p = findProvider(cfg.provider);
    final b = cfg.baseUrl.trim().isNotEmpty ? cfg.baseUrl.trim() : p.baseUrl;
    var k = cfg.apiKey.trim();
    if (k.isEmpty && (p.id == 'ollama' || b.contains('localhost') || b.contains('127.0.0.1'))) {
      k = 'local';
    }
    final m = cfg.model.trim().isNotEmpty ? cfg.model.trim() : p.defaultModel;
    return AIClient._(b, k, m, p.auth);
  }

  bool get ready => key.isNotEmpty && base.isNotEmpty && model.isNotEmpty;

  Uri get _uri => Uri.parse('$base/chat/completions');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': '${auth == 'apikey' ? 'Api-Key' : 'Bearer'} $key',
      };

  Future<Map<String, dynamic>> _chat(List<Map<String, String>> messages, double temp, {bool jsonMode = true}) async {
    Future<http.Response> post(bool strict) => http.post(_uri,
        headers: _headers,
        body: jsonEncode({
          'model': model,
          'messages': strict && jsonMode
              ? [
                  ...messages,
                ]
              : messages,
          'temperature': temp,
          if (jsonMode && strict) 'response_format': {'type': 'json_object'},
        })).timeout(const Duration(seconds: 180));

    var resp = await post(true);
    if (resp.statusCode != 200) resp = await post(false);
    if (resp.statusCode != 200) {
      throw Exception('Ошибка ИИ ${resp.statusCode}: ${resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) throw Exception('пустой ответ модели');
    return ((choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>).cast<String, dynamic>();
  }

  /// chatJSON — просим строгий JSON, при ошибке повторяем без response_format.
  Future<Map<String, dynamic>> chatJSON(String system, String user, double temp) async {
    var msg = await _chat([
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ], temp);
    var content = (msg['content'] as String?)?.trim() ?? '';
    if (!_looksLikeJson(content)) {
      msg = await _chat([
        {'role': 'system', 'content': '$system\nОтвечай ТОЛЬКО валидным JSON, без markdown и пояснений.'},
        {'role': 'user', 'content': user},
      ], temp);
      content = (msg['content'] as String?)?.trim() ?? '';
    }
    content = _cleanJSON(content);
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('модель вернула не-JSON');
    }
  }

  bool _looksLikeJson(String s) {
    final t = s.trim();
    return t.startsWith('{') || t.startsWith('```');
  }

  String _cleanJSON(String s) {
    var t = s.trim();
    if (t.startsWith('```json')) t = t.substring(7);
    if (t.startsWith('```')) t = t.substring(3);
    if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    return t.trim();
  }

  Future<String> chatText(String system, String user, double temp) async {
    final msg = await _chat([
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ], temp, jsonMode: false);
    return ((msg['content'] as String?) ?? '').trim();
  }

  // ---------- роль 1: симулятор ----------

  static const _sysSimulator =
      'Ты — симулятор терминала Linux с установленным Docker и Git внутри учебного тренажёра. Ты не настоящий терминал: ты вычисляешь правдоподобный вывод команд и поддерживаешь виртуальное состояние песочницы.\n\n'
      'Правила:\n'
      '1. Пользователь вводит ОДНУ строку. Если задача — практика (cmd), ответь тем, что напечатал бы реальный терминал: таблицы docker ps / docker images, шаги сборки, ошибки вида "docker: Error response from daemon", "bash: foo: command not found". Без markdown, без пояснений от себя.\n'
      '2. Если задача — тест (quiz): ввод пользователя это ОТВЕТ НА ВОПРОС, не исполняй его как команду. Оцени ответ: верно — output "✓ Верно." и короткое пояснение (2-3 предложения), solved=true; неточно — output "✗ Не совсем." и мягкий наводящий намёк БЕЗ раскрытия правильного ответа, solved=false; совсем мимо — output "✗ Неверно." и намёк, solved=false.\n'
      '3. Поддерживай состояние: docker pull/run/create/build добавляют образы и контейнеры; rm/rmi/stop/kill/start/exec/logs/volume/network/compose меняют их; bash-команды (ls, cat, echo, cd, pwd, mkdir, touch, rm, cp, mv, grep, git init/add/commit/branch/merge/…) работают с files и events. Перенаправление и heredoc (cat > file <<EOF) записывают файл. docker logs ставит logs_viewed=true у контейнера; docker exec добавляет команду в execs контейнера.\n'
      '4. docker build читает Dockerfile из files, парсит FROM/RUN/COPY/ENV/WORKDIR/CMD/ENTRYPOINT/EXPOSE/HEALTHCHECK/ARG, создаёт образ: layers, env, entrypoint, cmd, size_mb правдоподобно (alpine ~7, slim ~55, ubuntu ~78, golang ~340).\n'
      '5. docker run создаёт контейнер: имя из --name или случайное, status=running с -d. Порты "8080->80/tcp". -v создаёт volume и mount. --network добавляет сеть. Переопределённый CMD фиксируй в events.\n'
      '6. solved=true только если задача ПОЛНОСТЬЮ выполнена. Ответ — ТОЛЬКО валидный JSON:\n'
      '{"output": "...", "state": {…полное состояние…}, "solved": false}\n\n'
      'Схема state:\n'
      '{"workdir":"/workspace","files":{"путь":"содержимое"},"images":{"repo:tag":{"id":"sha256:ab12","repo":"repo","tag":"tag","size_mb":52,"env":[],"entrypoint":"","cmd":"","layers":["FROM …"]}},"containers":{"имя":{"id":"ab12cd34","name":"имя","image":"repo:tag","status":"running","ports":"8080->80/tcp","mounts":["том:/путь"],"networks":["bridge"],"execs":[],"logs_viewed":false}},"volumes":{"имя":"local"},"networks":["bridge","host","none"],"events":[]}\n'
      'Возвращай state ВСЕГДА целиком.';

  Future<SimResult> runCommand(Course c, Task? task, SandboxState st, List<HistEntry> hist, String cmd) async {
    final taskDesc = task == null
        ? 'задач нет (свободный режим): solved всегда false.'
        : 'курс: ${c.title}\nтип: ${task.kind}\nцель: ${task.goal}\nкритерий: ${task.check}';
    final user = 'КУРС И ЗАДАЧА:\n$taskDesc\n\nНЕДАВНЯЯ ИСТОРИЯ ТЕРМИНАЛА:\n${formatHist(hist, 240)}\n\n'
        'СОСТОЯНИЕ ПЕСОЧНИЦЫ (до):\n${jsonEncode(st.toJson())}\n\nВВОД ПОЛЬЗОВАТЕЛЯ:\n$cmd\n\nВерни JSON output/state/solved.';
    final j = await chatJSON(_sysSimulator, user, 0.0);
    return SimResult(
      j['output'] as String? ?? '',
      SandboxState.normalized((j['state'] as Map?)?.cast<String, dynamic>() ?? {}),
      j['solved'] as bool? ?? false,
    );
  }

  // ---------- роль 2: проверяющий ----------

  static const _sysChecker =
      'Ты — строгий, но справедливый проверяющий в тренажёре (Docker/Linux/Git). Тебе дают задачу, критерий успеха, ИСТОРИЮ КОМАНД терминала студента и финальное состояние песочницы.\n'
      'Задача засчитывается, только если выполнены ОБА условия:\n'
      '- итоговое состояние удовлетворяет критерию;\n'
      '- студент пришёл к нему сам через терминал: в истории видны осмысленные шаги, соответствующие условию.\n'
      'Если состояние подходит, но история пуста или шаги не соответствуют условию — solved=false и объясни одной фразой, чего не хватает. Учитывай эквивалентные формы флагов.\n'
      'Также оцени объективную сложность 1-5.\n'
      'Ответ — только JSON: {"solved": true|false, "comment": "1-2 фразы по-русски", "difficulty": 3}';

  Future<CheckResult> verify(Course c, Task task, SandboxState st, List<HistEntry> hist,
      {String termTail = ''}) async {
    final histStr = formatHist(hist, 400);
    final user = 'Курс: ${c.title}\nЗадача: ${task.title}\nУсловие: ${task.goal}\nКритерий: ${task.check}\n\n'
        'ИСТОРИЯ ТЕРМИНАЛА СТУДЕНТА (команды и вывод в порядке ввода — главная улика того, что студент делал сам):\n$histStr'
        '${termTail.isEmpty ? '' : '\n\nСЫРОЙ ЛОГ ТЕРМИНАЛА (последние строки):\n$termTail'}'
        '\n\nФинальное состояние:\n${jsonEncode(st.toJson())}'
        '\n\nЕсли команды из условия видны в истории/логе — студент выполнял их сам: ставь solved=true при выполнении критерия. '
        'Пустая история — единственный повод считать, что студент ничего не делал.';
    final j = await chatJSON(_sysChecker, user, 0.0);
    var diff = (j['difficulty'] as num?)?.toInt() ?? task.difficulty;
    if (diff < 1 || diff > 5) diff = task.difficulty;
    return CheckResult(j['solved'] as bool? ?? false, j['comment'] as String? ?? '', diff);
  }

  // ---------- роль 3: ментор ----------

  static const _sysMentor =
      'Ты — ИИ-наставник в тренажёре (Docker/Linux/Git и смежное). Стиль: тепло, по-человечески, кратко.\n'
      '- Отвечай по-русски, обычно до 120 слов. Без эмодзи.\n'
      '- Видишь задачу, состояние песочницы и историю команд студента — отвечай в этом контексте.\n'
      '- Сначала подтолкни к решению: идея, наводящий вопрос. Полное решение — только по прямой просьбе («дай решение»). Просто «покажи решение» — тоже просьба показать решение.\n'
      '- Используй markdown умеренно: **жирный**, `код`, списки.\n'
      '- Не выдумывай несуществующие команды и флаги.';

  static const _sysInterviewer =
      'Ты — техлид, проводящий собеседование DevOps-инженера по материалу курса и смежным темам.\n'
      '- По одному вопросу за раз; после ответа студента — коротко оцени его и задай следующий, чуть сложнее.\n'
      '- В конце (после 6–8 вопросов) дай разбор: что отвечено хорошо, что подтянуть, и вердикт.\n'
      '- Отвечай по-русски, кратко, без markdown-заголовков.';

  Future<String> mentor(Course c, Task? task, SandboxState st, List<HistEntry> hist, List<String> chatLog, String question,
      {bool interview = false}) {
    final b = StringBuffer('Курс: ${c.title}\n');
    if (task != null) b.write('Текущая задача: ${task.title} — ${task.goal}\n');
    b.write(stateSummary(st));
    b.write('\nНедавние команды:\n${formatHist(hist, 160)}');
    if (chatLog.isNotEmpty) b.write('\nНедавний диалог:\n${chatLog.join('\n')}\n');
    b.write('\nВопрос студента: $question');
    return chatText(interview ? _sysInterviewer : _sysMentor, b.toString(), 0.7);
  }

  // ---------- роль 4: генератор задач ----------

  static const _sysTaskGen = 'Ты — генератор учебных задач для тренажёра (Docker/Linux/Git и смежные темы). Тебе дают курс, тему (префикс cmd: практика в терминале, quiz: вопрос-тест) и названия недавних задач — не повторяй их.\n'
      'Формат задачи: ТЕОРИЯ → ТЕСТ (2 вопроса по теории) → ПРАКТИКА.\n'
      'Теория: markdown, каждый элемент массива theory — один блок, 3-5 блоков, с примерами команд в `коде` и ```блоках```.\n'
      'Для kind=cmd добавь quiz — РОВНО 2 вопроса с 3 вариантами (correct — индекс с 0). Для kind=quiz массив quiz пуст.\n'
      'Сложность 1-5. Ответ — только JSON строго по схеме:\n'
      '{"id":"short-english-id","title":"Название по-русски","kind":"cmd","difficulty":3,'
      '"theory":["абзац markdown"],"quiz":[{"question":"вопрос","options":["в1","в2","в3"],"correct":0}],'
      '"goal":"что сделать","hints":["подсказка 1","подсказка 2"],'
      '"check":"критерий успеха по state",'
      '"start_state":{"workdir":"/workspace","files":{},"images":{},"containers":{},"volumes":{},"networks":["bridge","host","none"],"events":[]}}';

  Future<Task> generateTask(String courseTitle, String topic, List<String> recent, String style) async {
    final topicLine = topic.startsWith('повторение')
        ? 'Тема: свободная — повторение пройденного ТОЛЬКО по предмету курса (выбери сам, можно cmd или quiz).'
        : 'Тема задачи: $topic';
    var user = 'ПРЕДМЕТ КУРСА: $courseTitle — вся задача, теория, примеры и команды ТОЛЬКО про этот предмет. '
        'Запрещено использовать команды и темы других предметов.\n'
        'Курс: $courseTitle\n$topicLine\nНедавние задачи (не повторять): ${recent.join('; ')}\n';
    if (style.trim().isNotEmpty) user += '\nОБЯЗАТЕЛЬНОЕ УКАЗАНИЕ К СТИЛЮ:\n$style\n';
    user += '\nСгенерируй задачу по схеме. Ответ — только JSON.';
    final j = await chatJSON(_sysTaskGen, user, 0.6);
    final t = Task.fromJson(j);
    if (t.title.trim().isEmpty || t.goal.trim().isEmpty) throw Exception('модель вернула задачу без названия или условия');
    t.id = t.id.isEmpty ? 'ai-${DateTime.now().millisecondsSinceEpoch % 100000}' : t.id;
    t.difficulty = t.difficulty < 1 || t.difficulty > 5 ? 3 : t.difficulty;
    if (t.hints.isEmpty) t.hints = ['Перечитай условие и теорию.', 'Спроси ментора в чате.'];
    if (t.check.isEmpty) t.check = t.goal;
    return t;
  }

  /// generateTaskBatch — сразу много задач по курсу (по темам программы).
  Future<List<Task>> generateTaskBatch(Course course, int count) async {
    final syllabus = course.syllabus.isEmpty
        ? ['cmd: базовая практика по теме курса']
        : course.syllabus;
    final user = 'Курс: ' + course.title
        + '\nТемы программы (по одной на задачу, по порядку или группами):\n'
        + syllabus.take(count).join('\n')
        + '\n\nСгенерируй РОВНО ' + count.toString() + ' задач по этим темам. Если тем меньше — добавь задачи на углубление и повторение.'
        + '\nНедавние задачи курса (не повторять): ' + course.tasks.map((t) => t.title).take(10).join('; ')
        + '\n\nВАЖНО: все задачи строго по предмету курса «' + course.title + '» и только по перечисленным темам. Никаких других предметов (например, для курса Linux — только Linux, без Git/Docker).'
        + '\n\nОтвет — только JSON: {"tasks": [ {задача по схеме}, … ]}';
    final j = await chatJSON(_sysTaskGen, user, 0.55);
    // модель иногда шлёт одну задачу без обёртки — принимаем оба варианта
    final raw = j['tasks'];
    final List list;
    if (raw is List) {
      list = raw;
    } else if (j.containsKey('title') || j.containsKey('goal')) {
      list = [j];
    } else {
      list = [];
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tasks = <Task>[];
    for (var i = 0; i < list.length && i < count + 2; i++) {
      final t = Task.fromJson(list[i] as Map<String, dynamic>);
      if (t.title.trim().isEmpty || t.goal.trim().isEmpty) continue;
      t.id = t.id.isEmpty ? 'ai-${now % 100000}-$i' : t.id;
      t.kind = t.isQuiz ? 'quiz' : 'cmd';
      t.difficulty = t.difficulty < 1 || t.difficulty > 5 ? 3 : t.difficulty;
      if (t.hints.isEmpty) t.hints = ['Перечитай условие и теорию.', 'Спроси ментора в чате.'];
      if (t.check.isEmpty) t.check = t.goal;
      tasks.add(t);
    }
    if (tasks.isEmpty) throw Exception('модель не вернула ни одной задачи');
    return tasks;
  }

  // ---------- роль 5: генератор курсов ----------

  static const _sysCourseGen = 'Ты — методист, собирающий учебную программу для тренажёра (Docker/Linux/Git/сети/CI-CD). Пользователь описывает цель.\n'
      'Составь от 3 до 5 ПОСЛЕДОВАТЕЛЬНЫХ курсов от базы к цели. В каждом курсе syllabus — список тем (10-20): формат "cmd: ..." для практики или "quiz: ..." для теста.\n'
      'Ответ — только JSON: {"courses":[{"id":"linux-basics","title":"Название","desc":"одно предложение","syllabus":["cmd: ...","quiz: ..."]}]}';

  Future<List<Course>> generateCourses(String goal) async {
    final j = await chatJSON(_sysCourseGen, 'Цель студента: $goal\n\nСобери программу. Ответ — только JSON.', 0.5);
    final list = (j['courses'] as List?) ?? [];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final courses = list.map((c) => Course.fromJson(c as Map<String, dynamic>)).toList();
    for (var i = 0; i < courses.length; i++) {
      final c = courses[i];
      c.id = c.id.isEmpty ? 'ai-${now % 100000}-$i' : 'ai-${c.id}';
      if (c.title.isEmpty) c.title = 'Курс ${i + 1}';
      if (c.syllabus.isEmpty) c.syllabus = ['cmd: вводная практика по теме курса'];
    }
    if (courses.isEmpty) throw Exception('модель не вернула ни одного курса');
    return courses;
  }

  /// minimumCourseTasks — при создании курса проверяем, что задач не меньше 5;
  /// если модель сгенерировала меньше — добираем по одной на тему программы.
  Future<List<Task>> ensureCourseFilled(Course course) async {
    while (course.tasks.length < 5) {
      final i = course.tasks.length;
      final topic = course.syllabus.isEmpty
          ? 'практика по предмету курса, часть ' + (i + 1).toString()
          : course.syllabus[i % course.syllabus.length];
      final t = await generateTask(course.title, topic, course.tasks.map((x) => x.title).toList(), '');
      course.tasks.add(t);
    }
    return course.tasks;
  }
}

class SimResult {
  final String output;
  final SandboxState state;
  final bool solved;
  SimResult(this.output, this.state, this.solved);
}

class CheckResult {
  final bool solved;
  final String comment;
  final int difficulty;
  CheckResult(this.solved, this.comment, this.difficulty);
}
