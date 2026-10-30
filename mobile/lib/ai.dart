// ai.dart — клиент OpenAI-совместимого API и роли ИИ (порт ai.go):
// симулятор терминала, проверяющий, ментор, генератор задач и курсов.
import 'dart:convert';
import 'dart:io' as io;
import 'package:http/http.dart' as http;
import 'app_action.dart';
import 'models.dart';
import 'usage.dart';

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

/// rawError — техническая ошибка для буфера обмена, без префикса Exception.
String rawError(Object e) {
  var s = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  return s.trim();
}

/// friendlyAiError — короткое объяснение вместо сырого лога в чате.
String friendlyAiError(Object e) {
  final raw = rawError(e);
  final status = RegExp(r'\b([45]\d\d)\b').firstMatch(raw)?.group(1);
  switch (status) {
    case '401':
    case '403':
      return 'Неверный API-ключ или нет доступа к модели.';
    case '404':
      return 'Модель или адрес не найдены. Проверь модель и Base URL в настройках.';
    case '408':
    case '504':
      return 'Провайдер не ответил вовремя. Попробуй ещё раз.';
    case '429':
      return 'Слишком много запросов. Подожди немного и повтори.';
    case '500':
    case '502':
    case '503':
      return 'Провайдер временно недоступен. Попробуй ещё раз позже.';
  }
  if (raw.toLowerCase().contains('timeout') ||
      raw.toLowerCase().contains('timed out')) {
    return 'Превышено время ожидания ответа. Попробуй ещё раз.';
  }
  if (raw.toLowerCase().contains('все модели недоступны')) {
    return 'Все подключения к ИИ недоступны. Проверь ключ и сеть.';
  }
  if (raw.toLowerCase().contains('нет настроенных')) {
    return 'ИИ не настроен. Добавь API-ключ в настройках.';
  }
  return 'Не удалось получить ответ. Попробуй ещё раз.';
}

class AIClient {
  /// endpoints — основное подключение + резервные, по порядку перебора.
  final List<AiEndpoint> _endpoints;
  final List<String> _labels;
  AIClient._(this._endpoints, this._labels);

  factory AIClient(Config cfg) {
    final eps = <AiEndpoint>[];
    final labels = <String>[];

    void add(String provider, String apiKey, String model, String baseUrl) {
      final p = findProvider(provider);
      final b = baseUrl.trim().isNotEmpty ? baseUrl.trim() : p.baseUrl;
      var k = apiKey.trim();
      if (k.isEmpty && (p.id == 'ollama' || b.contains('localhost') || b.contains('127.0.0.1'))) {
        k = 'local';
      }
      final m = model.trim().isNotEmpty ? model.trim() : p.defaultModel;
      if (k.isEmpty || b.isEmpty || m.isEmpty) return;
      eps.add(AiEndpoint(provider: p.id, apiKey: k, model: m, baseUrl: b));
      labels.add(p.title);
    }

    add(cfg.provider, cfg.apiKey, cfg.model, cfg.baseUrl);
    if (eps.isNotEmpty) {
      final p = eps.first;
      p.failStreak = cfg.primaryFailStreak;
      p.lastErrorAt = cfg.primaryLastErrorAt;
      p.penaltyUntil = cfg.primaryPenaltyUntil;
      p.lastOkAt = cfg.primaryLastOkAt;
      p.lastError = cfg.primaryLastError;
    }
    for (final f in cfg.fallbacks) {
      final before = eps.length;
      add(f.provider, f.apiKey, f.model, f.baseUrl);
      if (eps.length > before) {
        final ep = eps.last;
        ep.failStreak = f.failStreak;
        ep.lastErrorAt = f.lastErrorAt;
        ep.penaltyUntil = f.penaltyUntil;
        ep.lastOkAt = f.lastOkAt;
        ep.lastError = f.lastError;
      }
    }
    return AIClient._(eps, labels);
  }

  bool get ready => _endpoints.isNotEmpty;

  List<AiEndpoint> get endpoints => List<AiEndpoint>.unmodifiable(_endpoints);

  /// onUsage — расход токенов: модель, вход, выход. Ставит контроллер.
  void Function(String model, int prompt, int completion)? onUsage;
  /// onRetry — сюда пишем, какое резервное подключение сработало.
  void Function(String message)? onRetry;
  /// onEndpointResult — здоровье модели: успех/ошибка, задержка.
  void Function(AiEndpoint ep, bool ok, String error, int latencyMs)?
      onEndpointResult;

  String get model => _endpoints.isEmpty ? '' : _endpoints.first.model;

  Map<String, String> _headers(AiEndpoint ep) {
    final auth = findProvider(ep.provider).auth;
    return {
      'Content-Type': 'application/json',
      'Authorization': '${auth == 'apikey' ? 'Api-Key' : 'Bearer'} ${ep.apiKey}',
    };
  }

  String _messageText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .map((p) {
            if (p is Map) {
              return (p['text'] ?? p['file'] ?? p['image_url'] ?? '').toString();
            }
            return '';
          })
          .join('\n');
    }
    return '';
  }

  Future<Map<String, dynamic>> _chatOnce(
    AiEndpoint ep,
    List<Map<String, dynamic>> messages,
    double temp, {
    bool jsonMode = true,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final uri = Uri.parse('${ep.baseUrl}/chat/completions');
    Future<http.Response> post(bool strict) => http.post(uri,
        headers: _headers(ep),
        body: jsonEncode({
          'model': ep.model,
          'messages': messages,
          'temperature': temp,
          if (maxTokens != null) 'max_tokens': maxTokens,
          if (jsonMode && strict) 'response_format': {'type': 'json_object'},
        })).timeout(timeout);

    var resp = await post(true);
    if (resp.statusCode != 200) resp = await post(false);
    if (resp.statusCode != 200) {
      throw Exception('Ошибка ИИ ${resp.statusCode}: ${resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) throw Exception('пустой ответ модели');
    final msg = ((choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>).cast<String, dynamic>();

    // расход токенов: провайдер обычно отдаёт usage, иначе оцениваем по длине
    final usage = data['usage'] as Map?;
    var pt = (usage?['prompt_tokens'] as num?)?.toInt() ?? 0;
    var ct = (usage?['completion_tokens'] as num?)?.toInt() ?? 0;
    if (pt <= 0) {
      pt = estimateTokens(messages.map((m) => _messageText(m['content'])).join('\n'));
    }
    if (ct <= 0) ct = estimateTokens((msg['content'] as String?) ?? '');
    onUsage?.call(ep.model, pt, ct);
    return msg;
  }

  int _penaltyMs(Object e, int failStreak) {
    final raw = e.toString();
    final status = RegExp(r'\b([45]\d\d)\b').firstMatch(raw)?.group(1);
    final streak = failStreak.clamp(1, 6);
    if (status == '401' || status == '403' || status == '404') {
      return 30 * 60 * 1000;
    }
    if (status == '429') return streak * 2 * 60 * 1000;
    if (status != null && status.startsWith('5')) {
      return streak * 5 * 60 * 1000;
    }
    if (raw.toLowerCase().contains('timeout') ||
        raw.toLowerCase().contains('timed out')) {
      return streak * 5 * 60 * 1000;
    }
    return streak * 2 * 60 * 1000;
  }

  /// _chat — идём по подключениям с учётом здоровья: модели с ошибками
  /// временно уходят вниз, но всё равно пробуются, если остальные отказали.
  Future<Map<String, dynamic>> _chat(
    List<Map<String, dynamic>> messages,
    double temp, {
    bool jsonMode = true,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    if (_endpoints.isEmpty) throw Exception('нет настроенных ИИ-подключений');
    final now = DateTime.now().millisecondsSinceEpoch;
    final order = _endpoints.asMap().entries.toList()
      ..sort((a, b) {
        final pa = a.value.penaltyUntil > now ? 1 : 0;
        final pb = b.value.penaltyUntil > now ? 1 : 0;
        if (pa != pb) return pa.compareTo(pb);
        final fa = a.value.failStreak;
        final fb = b.value.failStreak;
        if (fa != fb) return fa.compareTo(fb);
        return a.key.compareTo(b.key);
      });
    final errors = <String>[];
    for (final entry in order) {
      final i = entry.key;
      final ep = entry.value;
      final sw = Stopwatch()..start();
      try {
        final msg = await _chatOnce(ep, messages, temp,
            jsonMode: jsonMode, maxTokens: maxTokens, timeout: timeout);
        ep.failStreak = 0;
        ep.penaltyUntil = 0;
        ep.lastOkAt = DateTime.now().millisecondsSinceEpoch;
        ep.lastError = '';
        onEndpointResult?.call(ep, true, '', sw.elapsedMilliseconds);
        if (i > 0) {
          onRetry?.call(
              'Основная модель недоступна — ответила резервная: ${_labels[i]}');
        }
        return msg;
      } catch (e) {
        final ms = DateTime.now().millisecondsSinceEpoch;
        ep.failStreak += 1;
        ep.lastErrorAt = ms;
        ep.lastError = _short(e);
        ep.penaltyUntil = ms + _penaltyMs(e, ep.failStreak);
        onEndpointResult?.call(
            ep, false, ep.lastError, sw.elapsedMilliseconds);
        errors.add('${_labels[i]}: ${_short(e)}');
      }
    }
    throw Exception('Все модели недоступны. ${errors.join(' · ')}');
  }

  /// testEndpoint — лёгкий тест конкретной модели, без перебора fallback.
  Future<TestResult> testEndpoint(AiEndpoint ep) async {
    final sw = Stopwatch()..start();
    try {
      final msg = await _chatOnce(
        ep,
        [
          {
            'role': 'user',
            'content': 'Ответь одним словом: ок',
          }
        ],
        0,
        jsonMode: false,
        maxTokens: 8,
        timeout: const Duration(seconds: 20),
      );
      return TestResult(
        true,
        sw.elapsedMilliseconds,
        (msg['content'] as String? ?? '').trim(),
        '',
      );
    } catch (e) {
      return TestResult(false, sw.elapsedMilliseconds, '', rawError(e));
    }
  }

  String _short(Object e) {
    var s = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    if (s.length > 120) s = '${s.substring(0, 120)}…';
    return s;
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

  /// chatTextWithAttachments — текст + фото/документы.
  /// Изображения уходят как image_url (data URL), документы — как file part.
  /// Провайдер, который не поддерживает формат, вернёт ошибку — это ожидаемо.
  Future<String> chatTextWithAttachments(
    String system,
    String user,
    List<ChatAttachment> attachments,
    double temp,
  ) async {
    final parts = <Map<String, dynamic>>[
      {'type': 'text', 'text': user},
    ];
    for (final a in attachments) {
      final f = io.File(a.path);
      if (!await f.exists()) {
        parts.add({
          'type': 'text',
          'text': '[Вложение ${a.name} недоступно на этом устройстве]',
        });
        continue;
      }
      final bytes = await f.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw Exception('Вложение «${a.name}» больше 8 МБ');
      }
      final mime = a.mime.isNotEmpty
          ? a.mime
          : (a.isImage ? 'image/jpeg' : 'application/octet-stream');
      final b64 = base64Encode(bytes);
      if (a.isImage) {
        parts.add({
          'type': 'image_url',
          'image_url': {'url': 'data:$mime;base64,$b64'},
        });
      } else {
        parts.add({
          'type': 'file',
          'file': {
            'filename': a.name,
            'file_data': 'data:$mime;base64,$b64',
          },
        });
      }
    }
    final msg = await _chat([
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': parts},
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

  static const _sysMentorTerminal =
      'Тебя зовут Термай. Ты — ИИ-наставник в тренажёре по терминалу и инфраструктуре (Docker/Linux/Git и смежное). Стиль: тепло, по-человечески, кратко.\n'
      '- Отвечай по-русски, обычно до 120 слов. Без эмодзи.\n'
      '- Если в состоянии приложения указано имя пользователя — обращайся по имени.\n'
      '- Видишь задачу, состояние песочницы и историю команд студента — отвечай в этом контексте.\n'
      '- Сначала подтолкни к решению: идея, наводящий вопрос. Полное решение — только по прямой просьбе («дай решение»). Просто «покажи решение» — тоже просьба показать решение.\n'
      '- Используй markdown умеренно: **жирный**, `код`, списки.\n'
      '- Не выдумывай несуществующие команды и флаги.';

  static const _sysMentorTheory =
      'Тебя зовут Термай. Ты — ИИ-наставник в учебном тренажёре по разным навыкам: языки, школьные и вузовские предметы, профессии, soft skills.\n'
      '- Отвечай по-русски, обычно до 120 слов, тепло и по делу. Без эмодзи.\n'
      '- Если в состоянии приложения указано имя пользователя — обращайся по имени.\n'
      '- Опирайся на материал курса и текущую задачу. Приводи примеры, аналогии и маленькие упражнения.\n'
      '- Сначала подтолкни к ответу: идея, наводящий вопрос. Готовый ответ — только по прямой просьбе.\n'
      '- Не говори про терминал, команды и песочницу, если студент сам не спросил.\n'
      '- Используй markdown умеренно: **жирный**, `код`, списки.';

  static const _sysInterviewer =
      'Тебя зовут Термай. Ты — интервьюер по материалу курса и смежным темам. Неважно, какой это навык: язык, профессия или технология.\n'
      '- Если в состоянии приложения указано имя пользователя — обращайся по имени.\n'
      '- По одному вопросу за раз; после ответа студента — коротко оцени его и задай следующий, чуть сложнее.\n'
      '- В конце (после 6–8 вопросов) дай разбор: что отвечено хорошо, что подтянуть, и вердикт.\n'
      '- Отвечай по-русски, кратко, без markdown-заголовков.';

  Future<String> mentor(Course c, Task? task, SandboxState st, List<HistEntry> hist, List<String> chatLog, String question,
      {bool interview = false, String solvedContext = '', String appContext = '', bool allowActions = true, List<ChatAttachment> attachments = const []}) {
    final b = StringBuffer('Курс: ${c.title}\n');
    b.write('Режим курса: ${c.isTheory ? 'теория, тесты и наставник (без терминала)' : 'практика в терминале'}\n');
    if (task != null) b.write('Текущая задача: ${task.title} — ${task.goal}\n');
    if (!c.isTheory) {
      b.write(stateSummary(st));
      b.write('\nНедавние команды:\n${formatHist(hist, 160)}');
    }
    if (appContext.isNotEmpty) b.write('\nСостояние приложения (для выбора действий):\n$appContext\n');
    if (solvedContext.isNotEmpty) b.write('\n' + solvedContext + '\n');
    if (chatLog.isNotEmpty) b.write('\nНедавний диалог:\n${chatLog.join('\n')}\n');
    b.write('\nВопрос студента: $question');
    final base = interview ? _sysInterviewer : (c.isTheory ? _sysMentorTheory : _sysMentorTerminal);
    final system = allowActions ? base + appActionsPrompt : base;
    if (attachments.isNotEmpty) {
      return chatTextWithAttachments(system, b.toString(), attachments, 0.7);
    }
    return chatText(system, b.toString(), 0.7);
  }

  static const _sysMentorGeneral =
      'Тебя зовут Термай. Ты — общий ИИ-наставник приложения TERMAI, не привязанный к конкретному курсу или задаче. '
      'Помогаешь учиться, разбираться в темах, составлять планы и отвечать на вопросы. '
      'Стиль: тепло, по-человечески, кратко, по-русски, обычно до 120 слов. Без эмодзи. '
      'Если в контексте есть имя пользователя — обращайся по имени. '
      'Не выдумывай факты и не давай опасных инструкций. '
      'Используй markdown умеренно.';

  /// generalMentor — ответ в общем чате без привязки к задаче.
  Future<String> generalMentor(
    String question, {
    List<String> chatLog = const [],
    String appContext = '',
    String userName = '',
    List<ChatAttachment> attachments = const [],
  }) {
    final b = StringBuffer();
    if (userName.trim().isNotEmpty) b.writeln('Имя пользователя: $userName');
    if (appContext.isNotEmpty) {
      b.writeln('Состояние приложения (для выбора действий):\n$appContext');
    }
    if (chatLog.isNotEmpty) {
      b.writeln('Недавний диалог:\n${chatLog.join('\n')}');
    }
    b.writeln('Вопрос студента: $question');
    final system = _sysMentorGeneral + appActionsPrompt;
    if (attachments.isNotEmpty) {
      return chatTextWithAttachments(system, b.toString(), attachments, 0.7);
    }
    return chatText(system, b.toString(), 0.7);
  }

  /// motivationalNotifications — короткие уникальные сообщения для push.
  Future<List<String>> motivationalNotifications({
    required String userName,
    required String appContext,
    int count = 3,
  }) async {
    const sys = 'Ты — Термай, ИИ-наставник TERMAI. '
        'Составь короткие мотивационные push-уведомления на русском. '
        'Правила: 1-2 предложения, без эмодзи, без давления и чувства вины, '
        'без обещаний и выдуманных фактов. Обращайся по имени, если оно есть. '
        'Учитывай прогресс, серию и текущую задачу. '
        'Верни только JSON: {"messages":["...","..."]}.';
    final user = 'Имя: $userName\n'
        'Данные пользователя: $appContext\n'
        'Сгенерируй ровно $count разных сообщений.';
    final j = await chatJSON(sys, user, 0.85);
    final list = (j['messages'] as List?) ?? const [];
    return list
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .take(count)
        .toList();
  }

  // ---------- роль 4: генератор задач ----------

  static const _sysTaskGenTerminal = 'Ты — генератор учебных задач для тренажёра по терминалу и инфраструктуре (Docker/Linux/Git и смежные темы). Тебе дают курс, тему (префикс cmd: практика в терминале, quiz: вопрос-тест) и названия недавних задач — не повторяй их.\n'
      'Формат задачи: ТЕОРИЯ → ТЕСТ (2 вопроса по теории) → ПРАКТИКА.\n'
      'Теория: markdown, каждый элемент массива theory — один блок, 3-5 блоков, с примерами команд в `коде` и ```блоках```.\n'
      'Для kind=cmd добавь quiz — РОВНО 2 вопроса с 3 вариантами (correct — индекс с 0). Для kind=quiz массив quiz пуст.\n'
      'Сложность 1-5. Ответ — только JSON строго по схеме:\n'
      '{"id":"short-english-id","title":"Название по-русски","kind":"cmd","difficulty":3,'
      '"theory":["абзац markdown"],"quiz":[{"question":"вопрос","options":["в1","в2","в3"],"correct":0}],'
      '"goal":"что сделать","hints":["подсказка 1","подсказка 2"],'
      '"check":"критерий успеха по state",'
      '"start_state":{"workdir":"/workspace","files":{},"images":{},"containers":{},"volumes":{},"networks":["bridge","host","none"],"events":[]}}';

  static const _sysTaskGenTheory = 'Ты — генератор учебных задач для тренажёра по разным навыкам: языки, школьные и вузовские предметы, профессии, soft skills, дизайн, музыка и т.п.\n'
      'Тебе дают курс, тему и названия недавних задач — не повторяй их.\n'
      'Формат задачи: ТЕОРИЯ (3-5 markdown-блоков с примерами, переводом или разбором) → ТЕСТ РОВНО из 2 вопросов по 3 варианта (correct — индекс с 0).\n'
      'НИКАКОГО терминала, команд, Docker и песочницы. kind всегда "quiz", start_state — пустое состояние.\n'
      'goal — что студент должен понять или уметь после урока. check — короткий критерий самопроверки.\n'
      'Сложность 1-5. Ответ — только JSON строго по схеме:\n'
      '{"id":"short-english-id","title":"Название по-русски","kind":"quiz","difficulty":3,'
      '"theory":["абзац markdown"],"quiz":[{"question":"вопрос","options":["в1","в2","в3"],"correct":0}],'
      '"goal":"чему научиться","hints":["подсказка 1","подсказка 2"],'
      '"check":"критерий самопроверки",'
      '"start_state":{"workdir":"/workspace","files":{},"images":{},"containers":{},"volumes":{},"networks":["bridge","host","none"],"events":[]}}';

  Future<Task> generateTask(String courseTitle, String topic, List<String> recent, String style,
      {String mode = 'terminal'}) async {
    final theory = mode == 'theory';
    final topicLine = topic.startsWith('повторение')
        ? 'Тема: свободная — повторение пройденного ТОЛЬКО по предмету курса.'
        : 'Тема задачи: $topic';
    var user = 'ПРЕДМЕТ КУРСА: $courseTitle — вся задача, теория и примеры ТОЛЬКО про этот предмет. '
        'Запрещено смешивать другие предметы.\n'
        'Курс: $courseTitle\n$topicLine\nНедавние задачи (не повторять): ${recent.join('; ')}\n';
    if (theory) {
      user += '\nРЕЖИМ КУРСА: теория и тесты (без терминала). kind="quiz", ровно 2 вопроса. '
          'Примеры — из языка/предмета курса, без команд и Docker.\n';
    } else {
      user += '\nРЕЖИМ КУРСА: практика в терминале. kind="cmd" или "quiz".\n';
    }
    if (style.trim().isNotEmpty) user += '\nОБЯЗАТЕЛЬНОЕ УКАЗАНИЕ К СТИЛЮ:\n$style\n';
    user += '\nСгенерируй задачу по схеме. Ответ — только JSON.';
    final j = await chatJSON(theory ? _sysTaskGenTheory : _sysTaskGenTerminal, user, 0.6);
    final t = Task.fromJson(j);
    if (t.title.trim().isEmpty || t.goal.trim().isEmpty) throw Exception('модель вернула задачу без названия или условия');
    t.id = t.id.isEmpty ? 'ai-${DateTime.now().millisecondsSinceEpoch % 100000}' : t.id;
    t.kind = theory ? 'quiz' : (t.isQuiz ? 'quiz' : 'cmd');
    t.difficulty = t.difficulty < 1 || t.difficulty > 5 ? 3 : t.difficulty;
    if (theory && t.quiz.isEmpty) throw Exception('модель вернула теорию без теста');
    if (t.hints.isEmpty) t.hints = ['Перечитай условие и теорию.', 'Спроси ментора в чате.'];
    if (t.check.isEmpty) t.check = t.goal;
    return t;
  }

  /// generateTaskBatch — сразу много задач по курсу (по темам программы).
  Future<List<Task>> generateTaskBatch(Course course, int count) async {
    final theory = course.isTheory;
    final syllabus = course.syllabus.isEmpty
        ? [theory ? 'quiz: вводный урок по теме курса' : 'cmd: базовая практика по теме курса']
        : course.syllabus;
    final user = 'Курс: ' + course.title
        + '\nРЕЖИМ: ' + (theory ? 'теория и тесты, без терминала' : 'практика в терминале')
        + '\nТемы программы (по одной на задачу, по порядку или группами):\n'
        + syllabus.take(count).join('\n')
        + '\n\nСгенерируй РОВНО ' + count.toString() + ' задач по этим темам. Если тем меньше — добавь задачи на углубление и повторение.'
        + '\nНедавние задачи курса (не повторять): ' + course.tasks.map((t) => t.title).take(10).join('; ')
        + '\n\nВАЖНО: все задачи строго по предмету курса «' + course.title + '» и только по перечисленным темам. Никаких других предметов.'
        + (theory ? '\nТолько теория и тесты. kind="quiz", ровно 2 вопроса. Никаких команд и Docker.' : '')
        + '\n\nОтвет — только JSON: {"tasks": [ {задача по схеме}, … ]}';
    final j = await chatJSON(theory ? _sysTaskGenTheory : _sysTaskGenTerminal, user, 0.55);
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
      t.kind = theory ? 'quiz' : (t.isQuiz ? 'quiz' : 'cmd');
      if (theory && t.quiz.isEmpty) continue;
      t.difficulty = t.difficulty < 1 || t.difficulty > 5 ? 3 : t.difficulty;
      if (t.hints.isEmpty) t.hints = ['Перечитай условие и теорию.', 'Спроси ментора в чате.'];
      if (t.check.isEmpty) t.check = t.goal;
      tasks.add(t);
    }
    if (tasks.isEmpty) throw Exception('модель не вернула ни одной задачи');
    return tasks;
  }

  /// generateContinuation — следующие задачи курса с учётом уже пройденного.
  Future<List<Task>> generateContinuation(
    Course course,
    int count, {
    List<String> completedTitles = const [],
  }) async {
    final start = course.tasks.length;
    final topics = <String>[];
    for (var i = 0; i < count; i++) {
      if (course.syllabus.isNotEmpty) {
        topics.add(course.syllabus[(start + i) % course.syllabus.length]);
      } else {
        topics.add('углубление и повторение по курсу, часть ${start + i + 1}');
      }
    }
    final temp = Course(
      id: course.id,
      title: course.title,
      desc: course.desc,
      mode: course.mode,
      syllabus: topics,
      tasks: List<Task>.from(course.tasks),
    );
    final tasks = await generateTaskBatch(temp, count);
    if (completedTitles.isNotEmpty) {
      // не повторяем уже пройденные названия
      tasks.removeWhere((t) => completedTitles
          .any((x) => x.trim().toLowerCase() == t.title.trim().toLowerCase()));
    }
    return tasks;
  }

  static const _sysExamGen = 'Ты — методист-экзаменатор TERMAI. Составь экзаменационную задачу по пройденным темам курса. '
      'Экзамен проверяет несколько тем сразу, без подсказок. '
      'Формат: kind="exam", 3-5 вопросов с 3 вариантами (correct — индекс с 0), '
      'theory — короткое вступление, goal — что проверить, check — критерий. '
      'Ответ — только JSON по схеме задачи: '
      '{"id":"exam-...","title":"Экзамен: ...","kind":"exam","difficulty":3,'
      '"theory":["..."],"quiz":[{"question":"...","options":["...","...","..."],"correct":0}],'
      '"goal":"...","hints":[],"check":"...",'
      '"start_state":{"workdir":"/workspace","files":{},"images":{},"containers":{},"volumes":{},"networks":["bridge","host","none"],"events":[]}}';

  Future<Task> generateExam(Course course, List<String> topics) async {
    final user = 'Курс: ${course.title}\n'
        'Пройденные темы: ${topics.join('; ')}\n'
        'Составь один экзамен по этим темам. Не повторяй названия задач: '
        '${course.tasks.map((t) => t.title).take(12).join('; ')}\n'
        'Ответ — только JSON.';
    final j = await chatJSON(_sysExamGen, user, 0.4);
    final t = Task.fromJson(j);
    t.kind = 'exam';
    t.id = t.id.isEmpty
        ? 'exam-${DateTime.now().millisecondsSinceEpoch % 100000}'
        : t.id;
    t.difficulty = t.difficulty < 1 || t.difficulty > 5 ? 3 : t.difficulty;
    if (t.title.trim().isEmpty) t.title = 'Экзамен по курсу';
    if (t.goal.trim().isEmpty) t.goal = 'Проверь себя по пройденным темам.';
    if (t.check.isEmpty) t.check = t.goal;
    if (t.quiz.isEmpty) {
      throw Exception('экзамен получился без вопросов');
    }
    return t;
  }

  static const _sysThemeGen = 'Ты — дизайнер тем для мобильного приложения TERMAI. '
      'Пользователь описывает настроение/цвета. Верни палитру в JSON. '
      'Нужны ключи: brightness ("dark" или "light"), bg, surface, card, card2, '
      'secondary, accent, accentDark, text, muted, good, warn, danger, border, '
      'termBg, termText. Все цвета — hex-строки #RRGGBB. '
      'Текст должен читаться на фоне (контраст не ниже 4.5), accent — заметный. '
      'Ответ — только JSON: {"title":"...","brightness":"dark","colors":{...}}.';

  Future<CustomThemeData> generateTheme(String prompt) async {
    final j = await chatJSON(
      _sysThemeGen,
      'Запрос пользователя: $prompt\nВерни палитру. Ответ — только JSON.',
      0.7,
    );
    final colors = ((j['colors'] as Map?) ?? {})
        .map((k, v) => MapEntry(k.toString(), v.toString()));
    final brightness = (j['brightness'] as String?)?.toLowerCase();
    if (brightness == 'light' || brightness == 'dark') {
      colors['brightness'] = brightness!;
    }
    return CustomThemeData(
      id: 'custom:${DateTime.now().millisecondsSinceEpoch % 1000000}',
      title: (j['title'] as String?)?.trim().isNotEmpty == true
          ? (j['title'] as String).trim()
          : 'Тема по запросу',
      colors: colors,
    );
  }

  // ---------- роль 5: генератор курсов ----------

  static const _sysCourseGen = 'Ты — методист, собирающий учебную программу для тренажёра по ЛЮБЫМ навыкам: языки, школьные и вузовские предметы, профессии, DevOps, дизайн, soft skills и т.п. Пользователь описывает цель.\n'
      'Составь от 3 до 5 ПОСЛЕДОВАТЕЛЬНЫХ курсов от базы к цели.\n'
      'Для каждого курса выбери mode:\n'
      '- "terminal" — если навык проверяется командами в терминале (Linux, Docker, Git, сети, CI/CD);\n'
      '- "theory" — если практика не в терминале (языки, теория, профессии, soft skills).\n'
      'syllabus — список тем (10-20). Для terminal: "cmd: ..." или "quiz: ...". Для theory: "quiz: ..." (тема урока).\n'
      'Ответ — только JSON: {"courses":[{"id":"english-a1","title":"Название","desc":"одно предложение","mode":"theory","syllabus":["quiz: ..."]}]}';

  Future<List<Course>> generateCourses(String goal) async {
    final j = await chatJSON(_sysCourseGen, 'Цель студента: $goal\n\nСобери программу. Ответ — только JSON.', 0.5);
    final list = (j['courses'] as List?) ?? [];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final courses = list.map((c) => Course.fromJson(c as Map<String, dynamic>)).toList();
    for (var i = 0; i < courses.length; i++) {
      final c = courses[i];
      c.id = c.id.isEmpty ? 'ai-${now % 100000}-$i' : 'ai-${c.id}';
      if (c.title.isEmpty) c.title = 'Курс ${i + 1}';
      // если модель не прислала mode, выводим его из префиксов тем
      if (!c.isTheory && c.syllabus.isNotEmpty && c.syllabus.every((t) => t.trimLeft().startsWith('quiz:'))) {
        c.mode = 'theory';
      }
      if (c.syllabus.isEmpty) {
        c.syllabus = [c.isTheory ? 'quiz: вводный урок по теме курса' : 'cmd: вводная практика по теме курса'];
      }
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
      final t = await generateTask(course.title, topic, course.tasks.map((x) => x.title).toList(), '',
          mode: course.mode);
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

class TestResult {
  final bool ok;
  final int latencyMs;
  final String reply;
  final String error;
  TestResult(this.ok, this.latencyMs, this.reply, this.error);
}
