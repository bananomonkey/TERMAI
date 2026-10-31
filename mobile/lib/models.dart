// models.dart — модели данных TERMAI (порт структур из Go: main.go/tasks.go/local.go).
import 'dart:convert';

// ---------- песочница ----------

class ImageInfo {
  String id, repo, tag, entrypoint, cmd;
  double sizeMb;
  List<String> env, layers;
  ImageInfo({
    required this.id,
    required this.repo,
    required this.tag,
    this.sizeMb = 0,
    this.entrypoint = '',
    this.cmd = '',
    List<String>? env,
    List<String>? layers,
  })  : env = env ?? [],
        layers = layers ?? [];

  factory ImageInfo.fromJson(Map<String, dynamic> j) => ImageInfo(
        id: j['id'] as String? ?? '',
        repo: j['repo'] as String? ?? '',
        tag: j['tag'] as String? ?? '',
        sizeMb: (j['size_mb'] as num?)?.toDouble() ?? 0,
        entrypoint: j['entrypoint'] as String? ?? '',
        cmd: j['cmd'] as String? ?? '',
        env: (j['env'] as List?)?.cast<String>() ?? [],
        layers: (j['layers'] as List?)?.cast<String>() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'repo': repo,
        'tag': tag,
        'size_mb': sizeMb,
        'entrypoint': entrypoint,
        'cmd': cmd,
        'env': env,
        'layers': layers,
      };
}

class ContainerInfo {
  String id, name, image, status, ports;
  List<String> mounts, networks, execs;
  bool logsViewed;
  ContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    this.status = 'running',
    this.ports = '',
    List<String>? mounts,
    List<String>? networks,
    List<String>? execs,
    this.logsViewed = false,
  })  : mounts = mounts ?? [],
        networks = networks ?? ['bridge'],
        execs = execs ?? [];

  factory ContainerInfo.fromJson(Map<String, dynamic> j) => ContainerInfo(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        image: j['image'] as String? ?? '',
        status: j['status'] as String? ?? 'running',
        ports: j['ports'] as String? ?? '',
        mounts: (j['mounts'] as List?)?.cast<String>() ?? [],
        networks: (j['networks'] as List?)?.cast<String>() ?? ['bridge'],
        execs: (j['execs'] as List?)?.cast<String>() ?? [],
        logsViewed: j['logs_viewed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'image': image,
        'status': status,
        'ports': ports,
        'mounts': mounts,
        'networks': networks,
        'execs': execs,
        'logs_viewed': logsViewed,
      };
}

class SandboxState {
  String workdir;
  Map<String, String> files;
  Map<String, ImageInfo> images;
  Map<String, ContainerInfo> containers;
  Map<String, String> volumes;
  List<String> networks;
  List<String> events;

  SandboxState({
    this.workdir = '/workspace',
    Map<String, String>? files,
    Map<String, ImageInfo>? images,
    Map<String, ContainerInfo>? containers,
    Map<String, String>? volumes,
    List<String>? networks,
    List<String>? events,
  })  : files = files ?? {},
        images = images ?? {},
        containers = containers ?? {},
        volumes = volumes ?? {},
        networks = networks ?? ['bridge', 'host', 'none'],
        events = events ?? [];

  factory SandboxState.fromJson(Map<String, dynamic> j) => SandboxState(
        workdir: j['workdir'] as String? ?? '/workspace',
        files: (j['files'] as Map?)?.cast<String, String>() ?? {},
        images: ((j['images'] as Map?) ?? {}).map((k, v) => MapEntry(
            k as String, ImageInfo.fromJson(v as Map<String, dynamic>))),
        containers: ((j['containers'] as Map?) ?? {}).map((k, v) => MapEntry(
            k as String, ContainerInfo.fromJson(v as Map<String, dynamic>))),
        volumes: (j['volumes'] as Map?)?.cast<String, String>() ?? {},
        networks: (j['networks'] as List?)?.cast<String>() ??
            ['bridge', 'host', 'none'],
        events: (j['events'] as List?)?.cast<String>() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'workdir': workdir,
        'files': files,
        'images': images.map((k, v) => MapEntry(k, v.toJson())),
        'containers': containers.map((k, v) => MapEntry(k, v.toJson())),
        'volumes': volumes,
        'networks': networks,
        'events': events,
      };

  SandboxState clone() => SandboxState.fromJson(
      jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  static SandboxState normalized(Map<String, dynamic> j) {
    final s = SandboxState.fromJson(j);
    if (s.workdir.isEmpty) s.workdir = '/workspace';
    if (s.networks.isEmpty) s.networks = ['bridge', 'host', 'none'];
    return s;
  }
}

// ---------- задачи и курсы ----------

class QuizQ {
  String question;
  List<String> options;
  int correct;
  QuizQ({required this.question, required this.options, this.correct = 0});

  factory QuizQ.fromJson(Map<String, dynamic> j) => QuizQ(
        question: j['question'] as String? ?? '',
        options: (j['options'] as List?)?.cast<String>() ?? [],
        correct: j['correct'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'question': question, 'options': options, 'correct': correct};
}

class Task {
  String id, title, kind, goal, check, expected, solution;
  int difficulty;
  List<String> theory, hints;
  List<QuizQ> quiz;
  bool peeked;
  SandboxState start;

  Task({
    required this.id,
    required this.title,
    this.kind = 'cmd',
    this.difficulty = 2,
    required this.goal,
    this.check = '',
    this.expected = '',
    this.solution = '',
    this.peeked = false,
    List<String>? theory,
    List<String>? hints,
    List<QuizQ>? quiz,
    SandboxState? start,
  })  : theory = theory ?? [],
        hints = hints ?? [],
        quiz = quiz ?? [],
        start = start ?? SandboxState();

  factory Task.fromJson(Map<String, dynamic> j) {
    final rawKind = (j['kind'] as String?)?.toLowerCase();
    final kind = rawKind == 'quiz'
        ? 'quiz'
        : (rawKind == 'exam' ? 'exam' : 'cmd');
    return Task(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        kind: kind,
        difficulty: (j['difficulty'] as num?)?.toInt() ?? 2,
        goal: j['goal'] as String? ?? '',
        check: j['check'] as String? ?? '',
        expected: j['expected_output'] as String? ?? '',
        solution: j['solution'] as String? ?? '',
        peeked: j['peeked'] as bool? ?? false,
        theory: (j['theory'] as List?)?.cast<String>() ?? [],
        hints: (j['hints'] as List?)?.cast<String>() ?? [],
        quiz: ((j['quiz'] as List?) ?? [])
            .map((q) => QuizQ.fromJson(q as Map<String, dynamic>))
            .toList(),
        start: SandboxState.normalized(
            (j['start_state'] as Map?)?.cast<String, dynamic>() ?? {}),
      );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'difficulty': difficulty,
        'theory': theory,
        'quiz': quiz.map((q) => q.toJson()).toList(),
        'goal': goal,
        'hints': hints,
        'check': check,
        'expected_output': expected,
        'solution': solution,
        'peeked': peeked,
        'start_state': start.toJson(),
      };

  bool get isQuiz => kind == 'quiz';
  bool get isExam => kind == 'exam';
  int get xp => 15 * difficulty + 15;
}

class Course {
  String id, title, desc;

  /// terminal — практика командами в песочнице; theory — теория, тесты и ментор.
  String mode;
  List<String> syllabus;
  List<Task> tasks;

  Course({
    required this.id,
    required this.title,
    this.desc = '',
    this.mode = 'terminal',
    List<String>? syllabus,
    List<Task>? tasks,
  })  : syllabus = syllabus ?? [],
        tasks = tasks ?? [];

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        desc: j['desc'] as String? ?? '',
        mode: (j['mode'] as String?)?.toLowerCase() == 'theory'
            ? 'theory'
            : 'terminal',
        syllabus: (j['syllabus'] as List?)?.cast<String>() ?? [],
        tasks: ((j['tasks'] as List?) ?? [])
            .map((t) => Task.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'desc': desc,
        'mode': mode,
        'syllabus': syllabus,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  bool get isTheory => mode == 'theory';
}

class HistEntry {
  String cmd, out;
  HistEntry({required this.cmd, required this.out});
  Map<String, dynamic> toJson() => {'cmd': cmd, 'out': out};
  factory HistEntry.fromJson(Map<String, dynamic> j) =>
      HistEntry(cmd: j['cmd'] as String? ?? '', out: j['out'] as String? ?? '');
}

// ---------- чат с ментором ----------

/// ChatAttachment — вложение в сообщении чата: фото или документ.
/// Сам файл лежит в папке приложения, в JSON хранится только путь и метаданные.
class ChatAttachment {
  String type; // image | file
  String path;
  String name;
  String mime;
  int size;

  ChatAttachment({
    required this.type,
    required this.path,
    required this.name,
    this.mime = '',
    this.size = 0,
  });

  bool get isImage => type == 'image';

  factory ChatAttachment.fromJson(Map<String, dynamic> j) => ChatAttachment(
        type: j['type'] as String? ?? 'file',
        path: j['path'] as String? ?? '',
        name: j['name'] as String? ?? '',
        mime: j['mime'] as String? ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'path': path,
        'name': name,
        'mime': mime,
        'size': size,
      };
}

class ChatMsg {
  final String role; // user | mentor | system | error
  final String text;

  /// Технические детали ошибки. В чате не показываются — только в буфере
  /// обмена по кнопке «Скопировать».
  final String details;

  final List<ChatAttachment> attachments;

  ChatMsg(this.role, this.text,
      {this.details = '', List<ChatAttachment>? attachments})
      : attachments = attachments ?? [];

  bool get isError => role == 'error';

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        if (details.isNotEmpty) 'details': details,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };
  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
        j['role'] as String? ?? 'mentor',
        j['text'] as String? ?? '',
        details: j['details'] as String? ?? '',
        attachments: ((j['attachments'] as List?) ?? [])
            .map((a) => ChatAttachment.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}

/// ChatScope — к чему привязана беседа.
enum ChatScope { general, task, interview }

/// MentorChat — отдельная беседа с ментором.
/// taskId == '__interview__' — беседа в режиме собеседования.
/// Пустые courseId и taskId — общий чат Термая.
class MentorChat {
  String id, courseId, taskId, taskTitle, title, createdAt, updatedAt;
  List<ChatMsg> messages;

  MentorChat({
    required this.id,
    required this.courseId,
    required this.taskId,
    this.taskTitle = '',
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<ChatMsg>? messages,
  }) : messages = messages ?? [];

  bool get isGeneral => courseId.isEmpty && taskId.isEmpty;

  factory MentorChat.fromJson(Map<String, dynamic> j) => MentorChat(
        id: j['id'] as String? ?? '',
        courseId: j['course_id'] as String? ?? '',
        taskId: j['task_id'] as String? ?? '',
        taskTitle: j['task_title'] as String? ?? '',
        title: j['title'] as String? ?? 'Чат',
        createdAt: j['created_at'] as String? ?? '',
        updatedAt: j['updated_at'] as String? ?? '',
        messages: ((j['messages'] as List?) ?? [])
            .map((m) => ChatMsg.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'course_id': courseId,
        'task_id': taskId,
        'task_title': taskTitle,
        'title': title,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'messages': messages.map((m) => m.toJson()).toList(),
      };
}

// ---------- закладки ----------

class Bookmark {
  String taskId, courseId, due;
  int intervalDays;
  Bookmark(
      {required this.taskId,
      required this.courseId,
      this.intervalDays = 1,
      required this.due});

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        taskId: j['task_id'] as String? ?? '',
        courseId: j['course_id'] as String? ?? '',
        intervalDays: j['interval_days'] as int? ?? 1,
        due: j['due'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'course_id': courseId,
        'interval_days': intervalDays,
        'due': due
      };
}

// ---------- настройки и прогресс ----------

/// AiEndpoint — одно подключение к ИИ: провайдер, ключ, модель, base URL.
/// Основное подключение лежит в Config напрямую, резервные — списком
/// Config.fallbacks: если основной провайдер откажет, TERMAI идёт по списку.
class AiEndpoint {
  String provider, apiKey, model, baseUrl;

  /// Здоровье модели: сколько ошибок подряд, когда была последняя ошибка,
  /// до какого времени модель временно понижена, когда последний успех.
  int failStreak;
  int lastErrorAt;
  int penaltyUntil;
  int lastOkAt;
  String lastError;

  AiEndpoint({
    this.provider = 'deepseek',
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
    this.failStreak = 0,
    this.lastErrorAt = 0,
    this.penaltyUntil = 0,
    this.lastOkAt = 0,
    this.lastError = '',
  });

  bool get ready => apiKey.trim().isNotEmpty;

  bool get penalized =>
      penaltyUntil > DateTime.now().millisecondsSinceEpoch;

  factory AiEndpoint.fromJson(Map<String, dynamic> j) => AiEndpoint(
        provider: j['provider'] as String? ?? 'deepseek',
        apiKey: j['api_key'] as String? ?? '',
        model: j['model'] as String? ?? '',
        baseUrl: j['base_url'] as String? ?? '',
        failStreak: (j['fail_streak'] as num?)?.toInt() ?? 0,
        lastErrorAt: (j['last_error_at'] as num?)?.toInt() ?? 0,
        penaltyUntil: (j['penalty_until'] as num?)?.toInt() ?? 0,
        lastOkAt: (j['last_ok_at'] as num?)?.toInt() ?? 0,
        lastError: j['last_error'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'api_key': apiKey,
        'model': model,
        'base_url': baseUrl,
        if (failStreak > 0) 'fail_streak': failStreak,
        if (lastErrorAt > 0) 'last_error_at': lastErrorAt,
        if (penaltyUntil > 0) 'penalty_until': penaltyUntil,
        if (lastOkAt > 0) 'last_ok_at': lastOkAt,
        if (lastError.isNotEmpty) 'last_error': lastError,
      };
}

/// CustomThemeData — пользовательская палитра, сгенерированная ИИ.
/// Цвета хранятся в hex-строках, чтобы модель не зависела от Flutter.
class CustomThemeData {
  String id;
  String title;
  Map<String, String> colors;

  CustomThemeData({
    required this.id,
    required this.title,
    required this.colors,
  });

  factory CustomThemeData.fromJson(Map<String, dynamic> j) => CustomThemeData(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? 'Своя тема',
        colors: ((j['colors'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'colors': colors,
      };
}

class Config {
  String apiKey, provider, model, baseUrl, theme;
  bool ambient;
  bool onboarded;

  /// Как обращаться к пользователю. Пусто — «Друг».
  String userName;

  /// Уведомления: общий выключатель, ежедневное напоминание и мотивация.
  bool notificationsEnabled;
  bool dailyReminderEnabled;
  int reminderHour;
  int reminderMinute;
  bool aiMotivationEnabled;

  /// Кэш сгенерированных мотивационных сообщений и дата генерации.
  List<String> motivationQueue;
  String motivationGeneratedAt;

  /// Позиция плавающей панели Термая: 0..1 от свободной области экрана.
  /// -1 — позиция по умолчанию (слева внизу).
  double launcherX;
  double launcherY;

  /// true — тему ещё не выбирали вручную; такую тему можно безопасно
  /// вернуть на «какао» при обновлении.
  bool themeAuto;

  /// Резервные ИИ-подключения: перебираются по порядку, если основной откажет.
  List<AiEndpoint> fallbacks;

  /// Фоновое фото главного экрана: путь к файлу (пусто — фон темы).
  String bgPhoto;

  /// Размытие фонового фото, 0–40.
  double bgBlur;

  /// Вуаль фонового фото, 0–0.9: затемнение в тёмных темах,
  /// осветление в светлой (чтобы текст читался).
  double bgDim;

  /// Яркость кнопок: 1.0 — обычная, 0.6–1.4 — темнее/светлее.
  double buttonBrightness;

  /// Отправлять ли ключи ИИ (apiKey + фолбэки) в Google-облако.
  /// По умолчанию включено; пользователь может выключить в настройках.
  bool syncKeysToCloud;

  /// Показывать ли плавающего Термая на экране.
  bool mascotVisible;

  /// Пользовательские темы, сгенерированные ИИ.
  List<CustomThemeData> customThemes;

  /// Локальная GGUF-модель: путь к файлу на этом устройстве.
  /// Не синхронизируется в облако — на другом устройстве путь недействителен.
  String localModelPath;

  /// Размер контекста локальной модели в токенах.
  int localContextSize;

  /// Время последнего изменения конфига (ISO). Нужно для merge с облаком.
  String updatedAt;

  /// Здоровье основной модели (для авторанжирования).
  int primaryFailStreak;
  int primaryLastErrorAt;
  int primaryPenaltyUntil;
  int primaryLastOkAt;
  String primaryLastError;

  Config({
    this.apiKey = '',
    this.provider = 'deepseek',
    this.model = '',
    this.baseUrl = '',
    this.theme = 'dark',
    this.ambient = true,
    this.onboarded = false,
    this.userName = '',
    this.notificationsEnabled = true,
    this.dailyReminderEnabled = true,
    this.reminderHour = 12,
    this.reminderMinute = 0,
    this.aiMotivationEnabled = true,
    List<String>? motivationQueue,
    this.motivationGeneratedAt = '',
    this.launcherX = -1,
    this.launcherY = -1,
    this.themeAuto = true,
    List<AiEndpoint>? fallbacks,
    this.bgPhoto = '',
    this.bgBlur = 24,
    this.bgDim = 0.55,
    this.buttonBrightness = 1.0,
    this.syncKeysToCloud = true,
    this.mascotVisible = true,
    List<CustomThemeData>? customThemes,
    this.localModelPath = '',
    this.localContextSize = 4096,
    this.updatedAt = '',
    this.primaryFailStreak = 0,
    this.primaryLastErrorAt = 0,
    this.primaryPenaltyUntil = 0,
    this.primaryLastOkAt = 0,
    this.primaryLastError = '',
  }) : motivationQueue = motivationQueue ?? [],
       fallbacks = fallbacks ?? [],
       customThemes = customThemes ?? [];

  factory Config.fromJson(Map<String, dynamic> j) => Config(
        apiKey: j['api_key'] as String? ?? '',
        provider: j['provider'] as String? ?? 'deepseek',
        model: j['model'] as String? ?? '',
        baseUrl: j['base_url'] as String? ?? '',
        theme: j['theme'] as String? ?? 'dark',
        ambient: j['ambient'] as bool? ?? true,
        onboarded: j['onboarded'] as bool? ?? false,
        userName: j['user_name'] as String? ?? '',
        notificationsEnabled: j['notifications_enabled'] as bool? ?? true,
        dailyReminderEnabled: j['daily_reminder_enabled'] as bool? ?? true,
        reminderHour: ((j['reminder_hour'] as num?)?.toInt() ?? 12)
            .clamp(0, 23)
            .toInt(),
        reminderMinute: ((j['reminder_minute'] as num?)?.toInt() ?? 0)
            .clamp(0, 59)
            .toInt(),
        aiMotivationEnabled: j['ai_motivation_enabled'] as bool? ?? true,
        motivationQueue:
            (j['motivation_queue'] as List?)?.cast<String>() ?? [],
        motivationGeneratedAt:
            j['motivation_generated_at'] as String? ?? '',
        launcherX: (j['launcher_x'] as num?)?.toDouble() ?? -1,
        launcherY: (j['launcher_y'] as num?)?.toDouble() ?? -1,
        themeAuto: j['theme_auto'] as bool? ?? true,
        fallbacks: ((j['fallbacks'] as List?) ?? [])
            .map((e) => AiEndpoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        bgPhoto: j['bg_photo'] as String? ?? '',
        bgBlur: (j['bg_blur'] as num?)?.toDouble() ?? 24,
        bgDim: (j['bg_dim'] as num?)?.toDouble() ?? 0.55,
        buttonBrightness: ((j['button_brightness'] as num?)?.toDouble() ?? 1.0)
            .clamp(0.6, 1.4)
            .toDouble(),
        syncKeysToCloud: j['sync_keys_to_cloud'] as bool? ?? true,
        mascotVisible: j['mascot_visible'] as bool? ?? true,
        customThemes: ((j['custom_themes'] as List?) ?? [])
            .map((e) => CustomThemeData.fromJson(e as Map<String, dynamic>))
            .toList(),
        localModelPath: j['local_model_path'] as String? ?? '',
        localContextSize:
            ((j['local_context_size'] as num?)?.toInt() ?? 4096)
                .clamp(512, 32768)
                .toInt(),
        updatedAt: j['updated_at'] as String? ?? '',
        primaryFailStreak: (j['primary_fail_streak'] as num?)?.toInt() ?? 0,
        primaryLastErrorAt:
            (j['primary_last_error_at'] as num?)?.toInt() ?? 0,
        primaryPenaltyUntil:
            (j['primary_penalty_until'] as num?)?.toInt() ?? 0,
        primaryLastOkAt: (j['primary_last_ok_at'] as num?)?.toInt() ?? 0,
        primaryLastError: j['primary_last_error'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'api_key': apiKey,
        'provider': provider,
        'model': model,
        'base_url': baseUrl,
        'theme': theme,
        'ambient': ambient,
        'onboarded': onboarded,
        'user_name': userName,
        'notifications_enabled': notificationsEnabled,
        'daily_reminder_enabled': dailyReminderEnabled,
        'reminder_hour': reminderHour,
        'reminder_minute': reminderMinute,
        'ai_motivation_enabled': aiMotivationEnabled,
        'motivation_queue': motivationQueue,
        'motivation_generated_at': motivationGeneratedAt,
        'launcher_x': launcherX,
        'launcher_y': launcherY,
        'theme_auto': themeAuto,
        'fallbacks': fallbacks.map((e) => e.toJson()).toList(),
        'bg_photo': bgPhoto,
        'bg_blur': bgBlur,
        'bg_dim': bgDim,
        'button_brightness': buttonBrightness,
        'sync_keys_to_cloud': syncKeysToCloud,
        'mascot_visible': mascotVisible,
        'local_model_path': localModelPath,
        'local_context_size': localContextSize,
        'custom_themes': customThemes.map((e) => e.toJson()).toList(),
        if (updatedAt.isNotEmpty) 'updated_at': updatedAt,
        if (primaryFailStreak > 0) 'primary_fail_streak': primaryFailStreak,
        if (primaryLastErrorAt > 0)
          'primary_last_error_at': primaryLastErrorAt,
        if (primaryPenaltyUntil > 0)
          'primary_penalty_until': primaryPenaltyUntil,
        if (primaryLastOkAt > 0) 'primary_last_ok_at': primaryLastOkAt,
        if (primaryLastError.isNotEmpty) 'primary_last_error': primaryLastError,
      };

  /// toCloudJson — конфиг для Firestore. Ключи попадают в облако только
  /// при includeKeys=true; остальные настройки синхронизируются всегда.
  Map<String, dynamic> toCloudJson({required bool includeKeys}) {
    final j = Map<String, dynamic>.from(toJson());
    // локальные пути не имеют смысла на другом устройстве
    j.remove('bg_photo');
    j.remove('local_model_path');
    if (!includeKeys) {
      j.remove('api_key');
      final fbs = (j['fallbacks'] as List?) ?? const [];
      j['fallbacks'] = fbs
          .map((e) => Map<String, dynamic>.from(e as Map)
            ..remove('api_key'))
          .toList();
    }
    return j;
  }
}

class Progress {
  int xp = 0, solvedTotal = 0, streak = 0;
  String lastCourse = '', lastDay = '';
  Map<String, Map<String, bool>> completed = {};
  Map<String, Map<String, bool>> quizDone = {};
  Map<String, Map<String, int>> quizTries = {};
  Map<String, Map<String, int>> hints = {};
  Map<String, List<Task>> generated = {};
  List<Course> extraCourses = [];
  Map<String, String> achieved = {};
  Map<String, Bookmark> bookmarks = {};
  List<MentorChat> mentorChats = [];
  String activeChatId = '';
  bool genCleaned = false;
  Map<String, String> courseTitles = {};
  List<String> courseOrder = [];
  List<String> hiddenCourses = [];

  /// Курсы, убранные в архив (в основном списке не показываются).
  List<String> archived = [];

  /// Расход токенов по моделям: модель → [вход, выход].
  Map<String, List<int>> aiUsage = {};

  Progress();

  /// tokensIn / tokensOut / totalTokens — сводка расхода.
  int get tokensIn =>
      aiUsage.values.fold(0, (a, v) => a + (v.isNotEmpty ? v[0] : 0));
  int get tokensOut =>
      aiUsage.values.fold(0, (a, v) => a + (v.length > 1 ? v[1] : 0));
  int get tokensTotal => tokensIn + tokensOut;

  factory Progress.fromJson(Map<String, dynamic> j) {
    final p = Progress();
    p.xp = j['xp'] as int? ?? 0;
    p.solvedTotal = j['solved_total'] as int? ?? 0;
    p.streak = j['streak'] as int? ?? 0;
    p.lastCourse = j['last_course'] as String? ?? '';
    p.lastDay = j['last_day'] as String? ?? '';
    p.completed = ((j['completed'] as Map?) ?? {})
        .map((k, v) => MapEntry(k as String, (v as Map).cast<String, bool>()));
    p.quizDone = ((j['quiz_done'] as Map?) ?? {})
        .map((k, v) => MapEntry(k as String, (v as Map).cast<String, bool>()));
    p.quizTries = ((j['quiz_tries'] as Map?) ?? {})
        .map((k, v) => MapEntry(k as String, (v as Map).cast<String, int>()));
    p.hints = ((j['hints'] as Map?) ?? {})
        .map((k, v) => MapEntry(k as String, (v as Map).cast<String, int>()));
    p.generated = ((j['generated'] as Map?) ?? {}).map((k, v) => MapEntry(
        k as String,
        (v as List)
            .map((t) => Task.fromJson(t as Map<String, dynamic>))
            .toList()));
    p.extraCourses = ((j['extra_courses'] as List?) ?? [])
        .map((c) => Course.fromJson(c as Map<String, dynamic>))
        .toList();
    p.achieved = (j['achievements'] as Map?)?.cast<String, String>() ?? {};
    p.bookmarks = ((j['bookmarks'] as Map?) ?? {}).map((k, v) =>
        MapEntry(k as String, Bookmark.fromJson(v as Map<String, dynamic>)));
    p.mentorChats = ((j['mentor_chats'] as List?) ?? [])
        .map((c) => MentorChat.fromJson(c as Map<String, dynamic>))
        .toList();
    p.activeChatId = j['active_chat'] as String? ?? '';
    p.courseTitles = (j['course_titles'] as Map?)?.cast<String, String>() ?? {};
    p.genCleaned = j['gen_cleaned'] as bool? ?? false;
    p.courseOrder = (j['course_order'] as List?)?.cast<String>() ?? [];
    p.hiddenCourses = (j['hidden_courses'] as List?)?.cast<String>() ?? [];
    p.archived = (j['archived'] as List?)?.cast<String>() ?? [];
    p.aiUsage = ((j['ai_usage'] as Map?) ?? {}).map((k, v) => MapEntry(
        k as String,
        ((v as List?) ?? []).map((e) => (e as num).toInt()).toList()));
    return p;
  }

  Map<String, dynamic> toJson() => {
        'xp': xp,
        'solved_total': solvedTotal,
        'streak': streak,
        'last_course': lastCourse,
        'last_day': lastDay,
        'completed': completed,
        'quiz_done': quizDone,
        'quiz_tries': quizTries,
        'hints': hints,
        'generated': generated
            .map((k, v) => MapEntry(k, v.map((t) => t.toJson()).toList())),
        'extra_courses': extraCourses.map((c) => c.toJson()).toList(),
        'achievements': achieved,
        'bookmarks': bookmarks.map((k, v) => MapEntry(k, v.toJson())),
        'mentor_chats': mentorChats.map((c) => c.toJson()).toList(),
        'active_chat': activeChatId,
        'gen_cleaned': genCleaned,
        'course_titles': courseTitles,
        'course_order': courseOrder,
        'hidden_courses': hiddenCourses,
        'archived': archived,
        'ai_usage': aiUsage,
      };

  int get level => xp ~/ 100 + 1;
}

// ---------- достижения ----------

class Achievement {
  final String id, title, desc;
  const Achievement(this.id, this.title, this.desc);
}

const achievementList = <Achievement>[
  Achievement('first', 'Первый шаг', 'Решена первая задача'),
  Achievement('ten', 'Десятка', '10 решённых задач'),
  Achievement('fifty', 'Полсотни', '50 решённых задач'),
  Achievement('quiz-perfect', 'Перфекционист', 'Тест пройден с первой попытки'),
  Achievement('author', 'Сценарист', 'Создана своя задача через ИИ'),
  Achievement('architect', 'Архитектор', 'Собран свой курс через ИИ'),
  Achievement('streak3', 'Серия 3', '3 дня подряд'),
  Achievement('streak7', 'Неделя огня', '7 дней подряд'),
];
