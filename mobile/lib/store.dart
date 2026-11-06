// store.dart — контроллер приложения: настройки, прогресс, песочница,
// поток команды (fast-path → ИИ), проверка задач, XP и достижения.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'ai.dart';
import 'app_action.dart';
import 'attachments.dart';
import 'diagnostics.dart';
import 'directions.dart';
import 'editor_verify.dart';
import 'generation_operation.dart';
import 'k8s_sandbox.dart';
import 'models.dart';
import 'navigation.dart';
import 'notifications.dart';
import 'sandbox.dart';
import 'secret_store.dart';
import 'shared_ai.dart';
import 'sync_service.dart';
import 'theme_refresh.dart';
import 'tts_service.dart';
import 'update_background.dart';
import 'update_service.dart';
import 'ui/theme.dart';

/// diagLog — глобальный журнал ошибок для экрана «Диагностика».
final StringBuffer diagLog = StringBuffer();

class UndoEntry {
  final String key;
  final SandboxState st;
  final String term;
  UndoEntry(this.key, this.st, this.term);
}

class CourseRebuildPlan {
  final Course course;
  final List<Task> tasks;
  final List<String> keptTitles;
  final List<String> addedTitles;
  final List<String> removedTitles;
  final List<String> preservedCompleted;
  const CourseRebuildPlan({
    required this.course,
    required this.tasks,
    required this.keptTitles,
    required this.addedTitles,
    required this.removedTitles,
    required this.preservedCompleted,
  });
}

class AppController extends ChangeNotifier {
  Config config = Config();
  Progress prog = Progress();
  AIClient? ai;

  /// Тема, из которой включили светлую: быстрый тумблер возвращает её.
  String _themeBeforeLight = 'dark';

  /// Исполнитель MCP-подобных действий, регистрируется в main().
  AppActionExecutor? actionExecutor;

  /// Структурированный исполнитель инструментов, регистрируется в main().
  AppToolExecutor? toolExecutor;

  final SyncService sync = SyncService.instance;

  List<Course> courses = [];

  /// allCourses — все курсы, включая архивные (для экрана архива).
  List<Course> allCourses = [];
  int courseIdx = 0;
  int viewIdx = 0;

  Map<String, SandboxState> states = {};
  Map<String, List<HistEntry>> history = {};
  Map<String, String> stateTask = {};

  /// Вывод терминала хранится отдельно для каждого терминала (курс + задача):
  /// переключение не теряет историю и не переносит её в соседний терминал.
  final Map<String, String> _termBuffers = {};
  final Map<String, List<String>> _cmdHistories = {};
  final Map<String, int> _cmdHistIndexes = {};

  /// Неотправленный ввод не должен переезжать в другой терминал.
  final Map<String, String> _termDrafts = {};

  /// termKey — идентификатор текущего терминала.
  String get termKey => stateKey;

  String get termText => _termBuffers[termKey] ?? '';

  set termText(String value) {
    if (value.isEmpty) {
      _termBuffers.remove(termKey);
    } else {
      _termBuffers[termKey] = value;
    }
  }

  /// Общее поле ввода терминала: ИИ может вставить туда команду действием.
  final TextEditingController termInput = TextEditingController();

  /// Запрос на переключение слайда урока из действия ИИ.
  int lessonSlideRequest = -1;
  int lessonSlideSeq = 0;

  /// История команд тоже принадлежит конкретному терминалу.
  List<String> get cmdHist =>
      _cmdHistories.putIfAbsent(termKey, () => <String>[]);

  int get cmdHistIdx => _cmdHistIndexes[termKey] ?? cmdHist.length;

  set cmdHistIdx(int value) => _cmdHistIndexes[termKey] = value;
  final Map<String, List<UndoEntry>> _undoBuffers = {};
  final Map<String, List<UndoEntry>> _redoBuffers = {};

  List<UndoEntry> get undoBuf =>
      _undoBuffers.putIfAbsent(termKey, () => <UndoEntry>[]);
  List<UndoEntry> get redoBuf =>
      _redoBuffers.putIfAbsent(termKey, () => <UndoEntry>[]);

  List<ChatMsg> chatMsgs = [];
  bool termBusy = false;
  bool mentorBusy = false;
  bool solutionLoad = false;
  bool generating = false;
  bool examBusy = false;
  int fillTotal = 0, fillDone = 0;
  String fillCurrent = '';
  bool ready = false;
  String lastFillError = '';

  /// Доступное обновление и состояние проверки GitHub Releases.
  UpdateInfo? availableUpdate;
  bool updateChecking = false;
  String updateError = '';

  /// Длительные ИИ-операции имеют собственное состояние и не используют
  /// глобальный busy терминала/чата. Благодаря этому создание одной задачи
  /// не зависит от того, закончена ли предыдущая задача или идёт чат.
  final GenerationOperations operations = GenerationOperations();

  GenerationOperation? get activeGeneration => operations.active;
  bool get generationBusy => operations.isBusy;
  bool get taskGenerationBusy => operations.isActive(GenerationKind.task);
  bool get courseGenerationBusy => operations.isActive(GenerationKind.courses);
  bool get canGenerateTask => ai != null && ai!.ready && courses.isNotEmpty;

  Future<void> cancelGeneration() async {
    final op = operations.active;
    if (op == null) return;
    op.requestCancel();
    notifyListeners();
  }

  // режимы
  bool interviewMode = false;
  String? reviewKey;

  String? lastAchievement; // для всплывашки
  final pendingAchievements = <String>[];
  Map<String, dynamic>? lastCompletion;
  // контекст только что решённой задачи — отдаётся ментору один раз
  String lastSolvedTitle = '';
  String lastSolvedHist = ''; // данные окна «Задача выполнена»
  /// Сообщение о том, что сработала резервная модель (показывается один раз).
  String lastAiFallback = '';

  // ---------- инициализация ----------

  Future<void> init() async {
    final dir = await _dataDir();
    final cfgFile = io.File('$dir/termai.json');
    if (await cfgFile.exists()) {
      try {
        config = Config.fromJson(
            jsonDecode(await cfgFile.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
    }
    await _restoreAiSecrets();
    final progFile = io.File('$dir/termai-progress.json');
    if (await progFile.exists()) {
      try {
        prog = Progress.fromJson(
            jsonDecode(await progFile.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        prog = Progress();
      }
    }
    rebuildCustomThemePresets(config.customThemes);
    _migrateTheme();
    C.p = presetById(config.theme);
    C.buttonBrightness = config.buttonBrightness.clamp(0.6, 1.4);
    _initAI();
    SharedAiService.instance.addListener(_onSharedAiChanged);

    if (!prog.genCleaned) {
      // одноразовая чистка: задачи ранних версий могли смешивать предметы
      prog.generated.clear();
      prog.genCleaned = true;
      await saveProgress();
    }
    await _assembleCourses();
    _bumpStreak();
    resetCourseState();
    ready = true;
    notifyListeners();
    unawaited(refreshSharedAi());
    unawaited(SharedAiService.instance.bindAuth());
    unawaited(() async {
      try {
        await _initSync();
      } catch (_) {}
      await autoFillAll();
    }());
  }

  void _onSharedAiChanged() {
    _initAI();
    notifyListeners();
  }

  /// refreshSharedAi — обновляет публичные условия акции с серверного шлюза.
  /// Ключ и срок акции меняются на сервере без обновления приложения.
  Future<void> refreshSharedAi() async {
    await SharedAiService.instance.refresh();
    _initAI();
    notifyListeners();
  }

  /// _initSync — тихо поднимает Firebase и подтягивает облачный прогресс,
  /// если пользователь уже входил через Google. Ошибки не блокируют запуск.
  Future<void> _initSync() async {
    await sync.init();
    if (!sync.signedIn) return;
    final cloud = await sync.pull();
    if (cloud == null) {
      await sync.push(jsonEncode(prog.toJson()));
    } else {
      try {
        final remote = Progress.fromJson(
            jsonDecode(cloud['json'] as String) as Map<String, dynamic>);
        if (_cloudIsBetter(remote)) {
          await _applyProgress(remote);
        }
      } catch (_) {}
    }
    await _mergeCloudConfig();
  }

  /// _mergeCloudConfig — при старте подтягивает имя/тему/уведомления из
  /// облака, если там более свежая версия. Ключи — только при включённом
  /// тумблере и только если локально их нет.
  DateTime? _cloudConfigTime(Map<String, dynamic> cloud, Config remote) {
    final parsed = DateTime.tryParse(remote.updatedAt);
    if (parsed != null) return parsed;
    final ms = (cloud['updated_at'] as num?)?.toInt() ?? 0;
    return ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> _mergeCloudConfig() async {
    final cloud = await sync.pullConfig();
    if (cloud == null) {
      sync.scheduleConfigPush(jsonEncode(
        config.toCloudJson(includeKeys: config.syncKeysToCloud),
      ));
      return;
    }
    Config? remote;
    try {
      remote = Config.fromJson(
          jsonDecode(cloud['json'] as String) as Map<String, dynamic>);
    } catch (_) {
      return;
    }
    final remoteAt = _cloudConfigTime(cloud, remote);
    final localAt = DateTime.tryParse(config.updatedAt);
    final cloudNewer =
        remoteAt != null && (localAt == null || remoteAt.isAfter(localAt));
    if (!cloudNewer) {
      sync.scheduleConfigPush(jsonEncode(
        config.toCloudJson(includeKeys: config.syncKeysToCloud),
      ));
      return;
    }
    // Несекретные настройки: облако побеждает, если оно новее.
    config.userName = remote.userName;
    config.theme = remote.theme;
    config.themeAuto = remote.themeAuto;
    config.notificationsEnabled = remote.notificationsEnabled;
    config.dailyReminderEnabled = remote.dailyReminderEnabled;
    config.reminderHour = remote.reminderHour;
    config.reminderMinute = remote.reminderMinute;
    config.aiMotivationEnabled = remote.aiMotivationEnabled;
    config.mascotVisible = remote.mascotVisible;
    if (remote.directions.isNotEmpty) {
      config.directions = remote.directions;
      config.activeDirection = remote.activeDirection;
    }
    config.customThemes = remote.customThemes;
    config.buttonBrightness = remote.buttonBrightness;
    config.bgBlur = remote.bgBlur;
    config.bgDim = remote.bgDim;
    config.launcherX = remote.launcherX;
    config.launcherY = remote.launcherY;
    // Ключи: только если пользователь разрешил синхронизацию. Основной ключ
    // не затирается; резервные подключения объединяются, чтобы локальный
    // список не пропадал из интерфейса после входа.
    if (config.syncKeysToCloud) {
      if (config.apiKey.isEmpty) {
        config.apiKey = remote.apiKey;
        config.provider = remote.provider;
        config.model = remote.model;
        config.baseUrl = remote.baseUrl;
      }
      _mergeFallbacks(remote.fallbacks);
    }
    config.updatedAt = remote.updatedAt;
    _ensureDirections();
    _migrateDirectionData();
    _applyCourseFilter();
    // Это применение уже получено из облака: не перезаписываем документ
    // сразу же локальной копией (особенно секреты старого устройства).
    await saveConfig(autofill: false, syncCloud: false);
    await scheduleNotifications();
  }

  /// _cloudIsBetter — облако полезнее локальной копии (больше решено/чатов).
  bool _cloudIsBetter(Progress remote) {
    if (remote.solvedTotal != prog.solvedTotal) {
      return remote.solvedTotal > prog.solvedTotal;
    }
    if (remote.mentorChats.length != prog.mentorChats.length) {
      return remote.mentorChats.length > prog.mentorChats.length;
    }
    // При равном числе задач не теряем реальную историю активности/время.
    if (remote.dailySolved.length != prog.dailySolved.length) {
      return remote.dailySolved.length > prog.dailySolved.length;
    }
    final remoteSeconds =
        remote.dailySeconds.values.fold<int>(0, (a, b) => a + b);
    final localSeconds = prog.dailySeconds.values.fold<int>(0, (a, b) => a + b);
    return remoteSeconds > localSeconds;
  }

  /// _assembleCourses — собирает список курсов из актива + прогресса
  /// (используется при старте и после импорта).
  Future<void> _assembleCourses() async {
    final raw = await rootAssetCourses();
    allCourses = raw;
    final extra = List<Course>.from(prog.extraCourses);
    for (final c in extra) {
      if (!allCourses.any((x) => x.id == c.id)) allCourses.add(c);
    }
    for (final c in allCourses) {
      final t = prog.courseTitles[c.id];
      if (t != null && t.isNotEmpty) c.title = t;
      if (c.direction.isEmpty) c.direction = directionForCourse(c);
      if (c.category.isEmpty) c.category = categoryForDirection(c.direction);
      // задачи, сгенерированные ИИ, живут в прогрессе — подмешиваем без дублей
      for (final t2 in prog.generated[c.id] ?? <Task>[]) {
        if (!c.tasks.any((x) => x.id == t2.id)) c.tasks.add(t2);
      }
      final rebuilt = prog.rebuiltTasks[c.id];
      if (rebuilt != null) c.tasks = List<Task>.from(rebuilt);
    }
    _ensureDirections();
    _migrateDirectionData();
    _applyCourseFilter();
  }

  /// _ensureDirections — старые пользователи получают пространства по своим
  /// курсам. Новый пользователь выбирает их в онбординге.
  void _ensureDirections() {
    final valid = directionCatalog.map((d) => d.id).toSet();
    var selected =
        config.directions.where(valid.contains).toSet().toList(growable: true);
    if (selected.isEmpty) {
      // Существующий пользователь: DevOps открываем всегда (там появился
      // Kubernetes), остальные направления — если по ним уже есть прогресс.
      final ids = <String>{
        ...prog.completed.keys,
        ...prog.extraCourses.map((c) => c.id),
        if (prog.lastCourse.isNotEmpty) prog.lastCourse,
      };
      selected.add('devops');
      for (final d in directionCatalog) {
        if (d.id == 'devops') continue;
        if (d.courseIds.any(ids.contains)) selected.add(d.id);
      }
      for (final c in allCourses) {
        if (selected.contains(c.direction)) continue;
        if (prog.extraCourses.any((e) => e.id == c.id)) {
          selected.add(c.direction);
        }
      }
    }
    config.directions = selected;
    if (!selected.contains(config.activeDirection)) {
      config.activeDirection = selected.first;
    }
  }

  /// _migrateDirectionData — раскладывает старый общий порядок курсов по
  /// направлениям и считает базовую статистику для уже пройденных задач.
  void _migrateDirectionData() {
    if (prog.courseOrderByDirection.isEmpty && prog.courseOrder.isNotEmpty) {
      for (final id in prog.courseOrder) {
        final c = allCourses.where((x) => x.id == id).firstOrNull;
        if (c == null) continue;
        (prog.courseOrderByDirection[c.direction] ??= []).add(id);
      }
    }
    for (final d in config.directions) {
      if (prog.directionSolved.containsKey(d)) continue;
      var solved = 0;
      var xp = 0;
      for (final c in allCourses.where((x) => x.direction == d)) {
        final done = prog.completed[c.id] ?? const <String, bool>{};
        for (final t in c.tasks) {
          if (done[t.id] == true) {
            solved++;
            if (!t.peeked) xp += t.xp;
          }
        }
      }
      prog.directionSolved[d] = solved;
      prog.directionXp[d] = xp;
    }
  }

  /// _applyCourseFilter — видимый список активного направления: без
  /// удалённых и архивных курсов, в пользовательском или дорожном порядке.
  void _applyCourseFilter() {
    final dir = config.activeDirection;
    for (final c in allCourses) {
      if (c.direction.isEmpty) c.direction = directionForCourse(c);
      if (c.category.isEmpty) c.category = categoryForDirection(c.direction);
    }
    courses = allCourses
        .where((c) =>
            c.direction == dir &&
            !prog.hiddenCourses.contains(c.id) &&
            !prog.archived.contains(c.id))
        .toList();
    final order = prog.courseOrderByDirection[dir] ?? const <String>[];
    final roadmap = directionById(dir)?.courseIds ?? const <String>[];
    courses.sort((a, b) {
      final ia = order.indexOf(a.id);
      final ib = order.indexOf(b.id);
      if (ia != ib && (ia >= 0 || ib >= 0)) {
        return (ia < 0 ? 9999 : ia).compareTo(ib < 0 ? 9999 : ib);
      }
      final ra = roadmap.indexOf(a.id);
      final rb = roadmap.indexOf(b.id);
      return (ra < 0 ? 9999 : ra).compareTo(rb < 0 ? 9999 : rb);
    });
    final saved = prog.activeCourseByDirection[dir];
    if (saved != null && saved.isNotEmpty) {
      final i = courses.indexWhere((c) => c.id == saved);
      if (i >= 0) courseIdx = i;
    } else if (prog.lastCourse.isNotEmpty) {
      final i = courses.indexWhere((c) => c.id == prog.lastCourse);
      if (i >= 0) courseIdx = i;
    }
    if (courseIdx >= courses.length) courseIdx = 0;
    if (courses.isNotEmpty) prog.activeCourseByDirection[dir] = cur.id;
  }

  List<DirectionDef> get selectedDirections => [
        for (final d in directionCatalog)
          if (config.directions.contains(d.id)) d,
      ];

  DirectionDef? get activeDirectionDef => directionById(config.activeDirection);

  DirectionStats statsForDirection(String id) {
    final list = allCourses.where((c) => c.direction == id).toList();
    var solved = 0;
    var total = 0;
    for (final c in list) {
      total += c.tasks.length;
      final done = prog.completed[c.id] ?? const <String, bool>{};
      solved += c.tasks.where((t) => done[t.id] == true).length;
    }
    final xp = prog.directionXp[id] ?? 0;
    return DirectionStats(
      courses: list.length,
      solved: solved,
      total: total,
      xp: xp,
    );
  }

  DirectionStats get activeStats => statsForDirection(config.activeDirection);

  Future<void> setDirections(Iterable<String> ids,
      {String? active, bool protectStarted = true}) async {
    final valid = directionCatalog.map((d) => d.id).toSet();
    final next = ids.where(valid.contains).toSet().toList();
    if (next.isEmpty) next.add('devops');
    // Направления, по которым уже есть курсы или прогресс, не теряются при
    // частичном выборе (например, в онбординге): начатые предметы защищены.
    if (protectStarted) {
      for (final d in directionCatalog) {
        if (next.contains(d.id)) continue;
        final hasCourses = allCourses.any((c) => c.direction == d.id);
        final hasProgress = (prog.completed[d.id]?.isNotEmpty ?? false) ||
            prog.extraCourses.any((c) => c.direction == d.id);
        if (hasCourses || hasProgress) next.add(d.id);
      }
    }
    config.directions = next;
    config.activeDirection =
        active != null && next.contains(active) ? active : next.first;
    _migrateDirectionData();
    prog.activeCourseByDirection.putIfAbsent(config.activeDirection,
        () => directionById(config.activeDirection)?.defaultCourseId ?? '');
    _applyCourseFilter();
    resetCourseState();
    bindChatForCurrentTask();
    await saveConfig(autofill: false);
    await saveProgress();
    notifyListeners();
  }

  Future<void> switchDirection(String id) async {
    if (!config.directions.contains(id) || id == config.activeDirection) return;
    config.activeDirection = id;
    courseIdx = 0;
    viewIdx = 0;
    termInput.clear();
    _applyCourseFilter();
    resetCourseState();
    bindChatForCurrentTask();
    await saveConfig(autofill: false);
    await saveProgress();
    notifyListeners();
  }

  void _persistCourseOrder() {
    prog.courseOrderByDirection[config.activeDirection] =
        courses.map((c) => c.id).toList();
    prog.courseOrder = [
      for (final d in config.directions)
        ...(prog.courseOrderByDirection[d] ?? const <String>[]),
    ];
  }

  void _removeFromCourseOrder(String id) {
    prog.courseOrder.remove(id);
    for (final e in prog.courseOrderByDirection.entries) {
      e.value.remove(id);
    }
  }

  static Future<String> _dataDir() async {
    final base = await getApplicationDocumentsDirectory();
    return base.path;
  }

  Future<List<Course>> rootAssetCourses() async {
    final jsonStr = await loadCoursesAsset();
    final list = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
    return list.map((c) => Course.fromJson(c)).toList();
  }

  /// _migrateTheme — старые конфиги и авто-тема возвращаются на «какао».
  /// Если тему выбирали руками (themeAuto=false), не трогаем.
  void _migrateTheme() {
    // удалённые палитры → Dark Modern; кастомные темы не трогаем
    if (!themePresets.any((p) => p.id == config.theme) &&
        !customThemePresets.any((p) => p.id == config.theme)) {
      config.theme = 'dark';
    }
    // авто-тему возвращаем на основную; осознанный выбор синей сохраняем
    if (config.themeAuto &&
        config.theme != 'dark' &&
        !config.theme.startsWith('custom:')) {
      config.theme = 'dark';
    }
  }

  /// Секреты лежат в secure storage, а не в termai.json. При первом
  /// запуске после обновления переносим старые ключи из JSON в хранилище.
  Future<void> _restoreAiSecrets() async {
    final sec = await SecretStore.readAiSecrets();
    final main = (sec['main'] ?? '').toString();
    final mainProvider = (sec['main_provider'] ?? '').toString();
    // Старый формат не хранил провайдера. После первой записи он становится
    // привязанным к провайдеру и больше не может попасть в чужой профиль.
    if (main.isNotEmpty &&
        (mainProvider.isEmpty || mainProvider == config.provider)) {
      config.apiKey = main;
    }
    final rawFallbacks = sec['fallbacks'];
    if (rawFallbacks is List) {
      for (final f in config.fallbacks) {
        for (final item in rawFallbacks) {
          if (item is! Map) continue;
          if ((item['provider'] ?? '').toString() == f.provider &&
              (item['model'] ?? '').toString() == f.model &&
              (item['base_url'] ?? '').toString() == f.baseUrl) {
            final key = (item['api_key'] ?? '').toString();
            if (key.isNotEmpty) f.apiKey = key;
            break;
          }
        }
      }
    }
    final rawProfiles = sec['profiles'];
    if (rawProfiles is Map) {
      for (final entry in rawProfiles.entries) {
        final id = entry.key.toString();
        if (entry.value is! Map) continue;
        final saved =
            AiEndpoint.fromJson(Map<String, dynamic>.from(entry.value as Map));
        final duplicatedFallback = config.fallbacks.any((f) =>
            f.provider == saved.provider &&
            f.model == saved.model &&
            f.baseUrl == saved.baseUrl &&
            f.apiKey.isNotEmpty &&
            f.apiKey == saved.apiKey);
        // Версия 1 ошибочно копировала каждый резервный ключ в профиль
        // провайдера. Не подставляем такую копию в главное поле. Сам ключ
        // остаётся в резервном подключении и не удаляется.
        if (duplicatedFallback && id != config.provider) {
          saved.apiKey = '';
        }
        final existing = config.providerProfiles[id];
        if (existing == null) {
          config.providerProfiles[id] = saved;
        } else if (saved.apiKey.isNotEmpty) {
          existing.apiKey = saved.apiKey;
        }
      }
    }
    // Локальный GGUF больше не поддерживается. Если он был основным,
    // возвращаемся к первому живому резервному провайдеру (например,
    // OpenRouter), а иначе оставляем пустой DeepSeek для ручной настройки.
    if (config.provider == 'local' || config.provider == 'hf') {
      final alive = config.fallbacks
          .where((f) => f.provider != 'local' && f.provider != 'hf')
          .toList();
      if (alive.isNotEmpty) {
        final first = alive.removeAt(0);
        if (config.apiKey.trim().isEmpty) {
          config.provider = first.provider;
          config.apiKey = first.apiKey;
          config.model = first.model;
          config.baseUrl = first.baseUrl;
        }
        config.fallbacks = alive;
      } else {
        config.provider = 'deepseek';
        config.apiKey = '';
        config.model = '';
        config.baseUrl = '';
        config.fallbacks = [];
      }
    }
    config.fallbacks = config.fallbacks
        .where((f) => f.provider != 'local' && f.provider != 'hf')
        .toList();
    config.providerProfiles.remove('local');
    config.providerProfiles.remove('hf');

    // Миграция старых настроек: профиль создаём только для основного
    // провайдера. Резервные ключи остаются в резервных подключениях и не
    // копируются в видимое главное поле при переключении провайдера.
    void remember(String provider, String key, String model, String baseUrl) {
      if (provider.isEmpty) return;
      final existing = config.providerProfiles[provider];
      if (existing == null) {
        config.providerProfiles[provider] = AiEndpoint(
          provider: provider,
          apiKey: key,
          model: model,
          baseUrl: baseUrl,
        );
      } else if (existing.apiKey.isEmpty && key.isNotEmpty) {
        existing.apiKey = key;
      }
    }

    remember(config.provider, config.apiKey, config.model, config.baseUrl);
    // Также очищаем уже загруженные из старого termai.json копии. Ключ не
    // удаляется: исходник остаётся в соответствующем fallback.
    for (final entry in config.providerProfiles.entries) {
      if (entry.key == config.provider) continue;
      final profile = entry.value;
      final isFallbackCopy = config.fallbacks.any((f) =>
          f.provider == profile.provider &&
          f.model == profile.model &&
          f.baseUrl == profile.baseUrl &&
          f.apiKey.isNotEmpty &&
          f.apiKey == profile.apiKey);
      if (isFallbackCopy) profile.apiKey = '';
    }
    await _writeAiSecrets();
    // Убираем старые ключи из уже существующего termai.json.
    final dir = await _dataDir();
    await io.File('$dir/termai.json')
        .writeAsString(jsonEncode(config.toLocalJson()));
  }

  Future<void> _writeAiSecrets() => SecretStore.writeAiSecrets(
        mainProvider: config.provider,
        main: config.apiKey,
        fallbacks: config.fallbacks
            .map((f) => {
                  'provider': f.provider,
                  'model': f.model,
                  'base_url': f.baseUrl,
                  'api_key': f.apiKey,
                })
            .toList(growable: false),
        profiles:
            Map.fromEntries(config.providerProfiles.entries.where((entry) {
          if (entry.key == config.provider) return true;
          final v = entry.value;
          return !config.fallbacks.any((f) =>
              f.provider == v.provider &&
              f.model == v.model &&
              f.baseUrl == v.baseUrl &&
              f.apiKey.isNotEmpty &&
              f.apiKey == v.apiKey);
        }).map((entry) => MapEntry(entry.key, {
                  'provider': entry.value.provider,
                  'model': entry.value.model,
                  'base_url': entry.value.baseUrl,
                  'api_key': entry.value.apiKey,
                }))),
      );

  /// _initAI — собирает клиент из основного и резервных подключений.
  /// Если основной ключ пуст, но есть рабочий резервный — ИИ всё равно доступен.
  void _initAI() {
    final client = AIClient(config);
    client.onUsage = recordUsage;
    client.onRetry = (msg) {
      if (lastAiFallback == msg) return;
      lastAiFallback = msg;
      notifyListeners();
    };
    client.onEndpointResult = (ep, ok, err, latency) {
      // В общем режиме шлюз живёт по своим правилам: не переносим его ошибки
      // на личные настройки пользователя, чтобы после акции ничего не
      // выглядело «сломанным» без причины.
      if (SharedAiService.instance.isUsable(config)) return;
      final isPrimary =
          client.endpoints.isNotEmpty && identical(ep, client.endpoints.first);
      var changed = false;
      if (isPrimary) {
        changed = config.primaryFailStreak != ep.failStreak ||
            config.primaryPenaltyUntil != ep.penaltyUntil ||
            config.primaryLastError != ep.lastError;
        config.primaryFailStreak = ep.failStreak;
        config.primaryLastErrorAt = ep.lastErrorAt;
        config.primaryPenaltyUntil = ep.penaltyUntil;
        config.primaryLastOkAt = ep.lastOkAt;
        config.primaryLastError = ep.lastError;
      } else {
        for (final f in config.fallbacks) {
          if (f.provider == ep.provider &&
              f.model == ep.model &&
              f.baseUrl == ep.baseUrl) {
            changed = f.failStreak != ep.failStreak ||
                f.penaltyUntil != ep.penaltyUntil ||
                f.lastError != ep.lastError;
            f.failStreak = ep.failStreak;
            f.lastErrorAt = ep.lastErrorAt;
            f.penaltyUntil = ep.penaltyUntil;
            f.lastOkAt = ep.lastOkAt;
            f.lastError = ep.lastError;
            break;
          }
        }
      }
      notifyListeners();
      if (changed) unawaited(saveConfig(autofill: false));
    };
    ai = client.ready ? client : null;
  }

  /// recordUsage — копим фактические токены по моделям.
  void recordUsage(String model, int prompt, int completion) {
    if (model.trim().isEmpty || (prompt <= 0 && completion <= 0)) return;
    final cur0 = prog.aiUsage[model] ?? [0, 0];
    prog.aiUsage[model] = [cur0[0] + prompt, cur0[1] + completion];
    saveProgress();
    notifyListeners();
  }

  /// resetUsage — обнулить счётчик расхода.
  void resetUsage() {
    prog.aiUsage.clear();
    saveProgress();
    notifyListeners();
  }

  Future<void> saveConfig({bool autofill = true, bool syncCloud = true}) async {
    config.updatedAt = DateTime.now().toIso8601String();
    rebuildCustomThemePresets(config.customThemes);
    _migrateTheme();
    final oldTheme = C.p.id;
    C.p = presetById(config.theme);
    C.buttonBrightness = config.buttonBrightness.clamp(0.6, 1.4);
    if (oldTheme != C.p.id || config.theme.startsWith('custom:')) {
      themeRevision.value++;
    }
    final dir = await _dataDir();
    await _writeAiSecrets();
    final localJson = jsonEncode(config.toLocalJson());
    await io.File('$dir/termai.json').writeAsString(localJson);
    _initAI();
    notifyListeners();
    // Автосохранение в облако: имя, тема, уведомления и (по тумблеру) ключи.
    if (syncCloud) {
      sync.scheduleConfigPush(jsonEncode(
        config.toCloudJson(includeKeys: config.syncKeysToCloud),
      ));
    }
    if (autofill) autoFillAll();
  }

  /// toggleLightTheme — быстрый тумблер на главной: тёмная/синяя ↔ светлая.
  /// Запоминаем палитру, из которой пришли, чтобы вернуть её повторным нажатием.
  Future<void> toggleLightTheme() async {
    if (C.isLight) {
      config.theme = _themeBeforeLight == 'light' ? 'dark' : _themeBeforeLight;
    } else {
      _themeBeforeLight = C.p.id;
      config.theme = 'light';
    }
    config.themeAuto = false;
    await saveConfig(autofill: false);
  }

  /// setButtonBrightness — ползунок в настройках. Во время перетаскивания
  /// обновляем только цвета, а на отпускании сохраняем и пересобираем экраны.
  Future<void> setButtonBrightness(double value, {bool persist = false}) async {
    config.buttonBrightness = value.clamp(0.6, 1.4);
    C.buttonBrightness = config.buttonBrightness;
    if (persist) {
      themeRevision.value++;
      final dir = await _dataDir();
      await io.File('$dir/termai.json')
          .writeAsString(jsonEncode(config.toLocalJson()));
    }
    notifyListeners();
  }

  // ---------- профиль и уведомления ----------

  Future<void> setUserName(String value) async {
    config.userName = value.trim();
    await saveConfig(autofill: false);
    if (config.notificationsEnabled && config.aiMotivationEnabled) {
      unawaited(refreshMotivationNotifications(force: true));
    }
  }

  /// swapPrimaryWithFallback — мгновенно меняет основную и резервную модели.
  Future<String> swapPrimaryWithFallback(int index) async {
    if (index < 0 || index >= config.fallbacks.length) {
      return 'Резервная модель не найдена';
    }
    final f = config.fallbacks[index];
    final primary = AiEndpoint(
      provider: config.provider,
      apiKey: config.apiKey,
      model: config.model,
      baseUrl: config.baseUrl,
    );
    config.provider = f.provider;
    config.apiKey = f.apiKey;
    config.model = f.model;
    config.baseUrl = f.baseUrl;
    config.fallbacks[index] = primary;
    await saveConfig(autofill: false);
    return 'Модели поменялись местами';
  }

  /// reorderCourses — drag-and-drop курсов на главном экране.
  Future<void> reorderCourses(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= courses.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= courses.length) return;
    final activeId = courses.isEmpty ? '' : cur.id;
    final item = courses.removeAt(oldIndex);
    courses.insert(newIndex, item);
    _persistCourseOrder();
    final active = courses.indexWhere((c) => c.id == activeId);
    if (active >= 0) courseIdx = active;
    await saveProgress();
    notifyListeners();
  }

  /// testEndpoint — тест конкретной модели; не меняет основной выбор.
  Future<TestResult> testEndpoint(int index) async {
    final client = AIClient(config);
    AiEndpoint ep;
    if (index < 0) {
      final p = findProvider(config.provider);
      final model =
          config.model.trim().isEmpty ? p.defaultModel : config.model.trim();
      final base =
          config.baseUrl.trim().isEmpty ? p.baseUrl : config.baseUrl.trim();
      var key = config.apiKey.trim();
      if (key.isEmpty &&
          (p.id == 'ollama' ||
              base.contains('localhost') ||
              base.contains('127.0.0.1'))) {
        key = 'local';
      }
      ep = AiEndpoint(provider: p.id, apiKey: key, model: model, baseUrl: base);
    } else {
      if (index >= config.fallbacks.length) {
        return TestResult(false, 0, '', 'Модель не найдена');
      }
      final f = config.fallbacks[index];
      final p = findProvider(f.provider);
      final model = f.model.trim().isEmpty ? p.defaultModel : f.model.trim();
      final base = f.baseUrl.trim().isEmpty ? p.baseUrl : f.baseUrl.trim();
      var key = f.apiKey.trim();
      if (key.isEmpty &&
          (p.id == 'ollama' ||
              base.contains('localhost') ||
              base.contains('127.0.0.1'))) {
        key = 'local';
      }
      ep = AiEndpoint(provider: p.id, apiKey: key, model: model, baseUrl: base);
    }
    final r = await client.testEndpoint(ep);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (index < 0) {
      if (r.ok) {
        config.primaryFailStreak = 0;
        config.primaryPenaltyUntil = 0;
        config.primaryLastOkAt = now;
        config.primaryLastError = '';
      } else {
        config.primaryFailStreak += 1;
        config.primaryLastErrorAt = now;
        config.primaryLastError = r.error;
        config.primaryPenaltyUntil = now + 2 * 60 * 1000;
      }
    } else {
      final f = config.fallbacks[index];
      if (r.ok) {
        f.failStreak = 0;
        f.penaltyUntil = 0;
        f.lastOkAt = now;
        f.lastError = '';
      } else {
        f.failStreak += 1;
        f.lastErrorAt = now;
        f.lastError = r.error;
        f.penaltyUntil = now + 2 * 60 * 1000;
      }
    }
    await saveConfig(autofill: false);
    return r;
  }

  /// generateCustomTheme — ИИ собирает палитру по текстовому запросу.
  Future<String> generateCustomTheme(String prompt) async {
    if (ai == null || !ai!.ready) {
      return 'Нет API-ключа — настрой ИИ в разделе «ИИ-провайдер».';
    }
    try {
      final theme = await ai!.generateTheme(prompt);
      if (theme.colors.isEmpty) return 'ИИ вернул пустую палитру';
      config.customThemes.add(theme);
      config.theme = theme.id;
      config.themeAuto = false;
      await saveConfig(autofill: false);
      return '';
    } catch (e) {
      return _errMsg(e);
    }
  }

  Future<String> deleteCustomTheme(String id) async {
    config.customThemes.removeWhere((t) => t.id == id);
    if (config.theme == id) {
      config.theme = 'dark';
      config.themeAuto = false;
    }
    await saveConfig(autofill: false);
    return '';
  }

  Future<void> setNotificationsEnabled(bool value) async {
    config.notificationsEnabled = value;
    await saveConfig(autofill: false);
    if (!value) {
      await notificationService.cancelAll();
      return;
    }
    await notificationService.requestPermission();
    await scheduleNotifications();
  }

  Future<void> setDailyReminderEnabled(bool value) async {
    config.dailyReminderEnabled = value;
    await saveConfig(autofill: false);
    await scheduleNotifications();
  }

  Future<void> setAiMotivationEnabled(bool value) async {
    config.aiMotivationEnabled = value;
    await saveConfig(autofill: false);
    if (!value) {
      await notificationService.cancelAll();
      await scheduleNotifications();
    } else {
      await refreshMotivationNotifications(force: true);
    }
  }

  Future<void> setTtsEnabled(bool value) async {
    config.ttsEnabled = value;
    await saveConfig(autofill: false);
    if (!value) {
      await TtsService.instance.stop();
    } else {
      await TtsService.instance.init();
    }
    notifyListeners();
  }

  /// saveTtsConfig — сохранить движок/голос/скорость из экрана настроек.
  Future<void> saveTtsConfig() async {
    await saveConfig(autofill: false);
    notifyListeners();
  }

  // ---------- обновления ----------

  /// checkUpdates — ручная или тихая проверка GitHub Releases.
  /// Тихая не ходит в сеть чаще, чем раз в 6 часов.
  Future<UpdateInfo?> checkUpdates(
      {bool silent = false, bool force = false}) async {
    if (updateChecking) return availableUpdate;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force) {
      if (silent && !config.updatesAutoCheck) return availableUpdate;
      if (config.lastUpdateCheckAt > 0 &&
          now - config.lastUpdateCheckAt <
              UpdateService.checkInterval.inMilliseconds) {
        return availableUpdate;
      }
    }
    updateChecking = true;
    updateError = '';
    notifyListeners();
    try {
      final info = await UpdateService.check();
      availableUpdate = info;
      config.lastUpdateCheckAt = now;
      await saveConfig(autofill: false);
      return info;
    } catch (e) {
      updateError = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      updateChecking = false;
      notifyListeners();
    }
  }

  Future<bool> openAvailableUpdate() async {
    final info = availableUpdate;
    if (info == null) return false;
    final url = info.apkUrl.isNotEmpty ? info.apkUrl : info.releaseUrl;
    return UpdateService.open(url);
  }

  Future<void> dismissAvailableUpdate() async {
    final info = availableUpdate;
    if (info == null) return;
    config.ignoredUpdate = info.latest;
    await saveConfig(autofill: false);
    notifyListeners();
  }

  Future<void> setUpdatesAutoCheck(bool value) async {
    config.updatesAutoCheck = value;
    await saveConfig(autofill: false);
    if (value) {
      await initUpdateWorker();
    } else {
      await cancelUpdateWorker();
    }
    notifyListeners();
  }

  Future<void> setUpdatesNotifications(bool value) async {
    config.updatesNotifications = value;
    await saveConfig(autofill: false);
    notifyListeners();
  }

  Future<void> setReminderTime(int hour, int minute) async {
    config.reminderHour = hour.clamp(0, 23);
    config.reminderMinute = minute.clamp(0, 59);
    await saveConfig(autofill: false);
    await scheduleNotifications();
  }

  /// scheduleNotifications — пересобрать локальное расписание.
  Future<void> scheduleNotifications() async {
    if (!config.onboarded) return;
    await notificationService.apply(
      config,
      userName: userNameOrFriend,
      streak: prog.streak,
    );
    if (config.notificationsEnabled && config.aiMotivationEnabled) {
      unawaited(refreshMotivationNotifications());
    }
  }

  /// refreshMotivationNotifications — заранее подготовить уникальные
  /// сообщения. При ошибке остаётся старый кэш/готовые фразы.
  Future<void> refreshMotivationNotifications({bool force = false}) async {
    if (!config.notificationsEnabled || !config.aiMotivationEnabled) return;
    if (ai == null || !ai!.ready) return;
    final generated = DateTime.tryParse(config.motivationGeneratedAt);
    final fresh = generated != null &&
        DateTime.now().difference(generated).inDays < 7 &&
        config.motivationQueue.isNotEmpty;
    if (!force && fresh) return;
    try {
      final messages = await ai!.motivationalNotifications(
        userName: userNameOrFriend,
        appContext: appContextForAI,
        count: 3,
      );
      if (messages.isEmpty) return;
      config.motivationQueue = messages;
      config.motivationGeneratedAt = DateTime.now().toIso8601String();
      await saveConfig(autofill: false);
      await notificationService.apply(
        config,
        userName: userNameOrFriend,
        streak: prog.streak,
      );
    } catch (_) {
      // без сети/ключа остаются готовые фразы ежедневного напоминания
    }
  }

  // ---------- фоновое фото ----------

  /// setBackgroundPhoto — копирует выбранное изображение в папку приложения.
  /// Имя уникальное: так кэш картинок Flutter не покажет старое фото вместо
  /// нового, а старый файл мы аккуратно удаляем.
  Future<String> setBackgroundPhoto(String sourcePath) async {
    try {
      final dir = await _dataDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final target = io.File('$dir/termai-bg-$stamp.jpg');
      await io.File(sourcePath).copy(target.path);
      final old = config.bgPhoto;
      config.bgPhoto = target.path;
      await saveConfig(autofill: false);
      if (old.isNotEmpty && old != target.path) {
        try {
          final f = io.File(old);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      return '';
    } catch (e) {
      return _errMsg(e);
    }
  }

  /// clearBackgroundPhoto — вернуть фон темы.
  Future<void> clearBackgroundPhoto() async {
    final p = config.bgPhoto;
    config.bgPhoto = '';
    await saveConfig(autofill: false);
    if (p.isNotEmpty) {
      try {
        final f = io.File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// setBackgroundTuning — размытие и затемнение фона (сохраняем без перезапуска ИИ).
  Future<void> setBackgroundTuning(
      {double? blur, double? dim, bool persist = false}) async {
    if (blur != null) config.bgBlur = blur.clamp(0, 40);
    if (dim != null) config.bgDim = dim.clamp(0, 0.9);
    if (persist) {
      final dir = await _dataDir();
      await io.File('$dir/termai.json')
          .writeAsString(jsonEncode(config.toLocalJson()));
    }
    notifyListeners();
  }

  Timer? _progressSaveTimer;

  /// saveProgress — сохраняем прогресс с небольшой задержкой: во время
  /// работы в терминале уведомления идут очередями, и кодировать весь JSON
  /// (со всеми чатами и задачами) на каждую команду — заметный фриз.
  Future<void> saveProgress() async {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 160), () {
      _writeProgress();
    });
  }

  Future<void> _writeProgress() async {
    final json = jsonEncode(prog.toJson());
    final dir = await _dataDir();
    await io.File('$dir/termai-progress.json').writeAsString(json);
    sync.schedulePush(json);
  }
  // ---------- экспорт / импорт ----------
  // Файл пишем в доступную папку приложения (Android/data/…/files):
  // JSON не показываем, пользователь просто получает готовый файл.

  String exportProgress() {
    return const JsonEncoder.withIndent('  ').convert(prog.toJson());
  }

  /// exportProgressToFile — сохраняет прогресс в файл и возвращает путь.
  /// Пустая строка — сохранить не удалось.
  Future<String> exportProgressToFile() async {
    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-')
          .substring(0, 19);
      final json = const JsonEncoder.withIndent('  ').convert(prog.toJson());
      final f = io.File('${dir.path}/TERMAI-progress-$stamp.json');
      await f.writeAsString(json);
      // дублируем в буфер: так файл можно сразу вставить в «Импорт»
      try {
        await Clipboard.setData(ClipboardData(text: json));
      } catch (_) {}
      return f.path;
    } catch (_) {
      return '';
    }
  }

  /// _applyProgress — заменить прогресс (импорт или облако) и пересобрать состояние.
  Future<void> _applyProgress(Progress p) async {
    prog = p;
    await _assembleCourses();
    states.clear();
    history.clear();
    stateTask.clear();
    _termBuffers.clear();
    _cmdHistories.clear();
    _cmdHistIndexes.clear();
    _termDrafts.clear();
    _undoBuffers.clear();
    _redoBuffers.clear();
    chatMsgs = [];
    reviewKey = null;
    await saveProgress();
    resetCourseState();
    selectFirstUndone();
    notifyListeners();
  }

  /// _mergeFallbacks — объединяет облачные резервные подключения с локальными:
  /// локальные ключи не затираются, новые подключения добавляются.
  void _mergeFallbacks(List<AiEndpoint> remote) {
    final merged = List<AiEndpoint>.from(config.fallbacks);
    for (final rf in remote) {
      final i = merged.indexWhere((x) =>
          x.provider == rf.provider &&
          x.model == rf.model &&
          x.baseUrl == rf.baseUrl);
      if (i < 0) {
        merged.add(rf);
      } else if (merged[i].apiKey.isEmpty && rf.apiKey.isNotEmpty) {
        merged[i].apiKey = rf.apiKey;
      }
    }
    config.fallbacks = merged;
  }

  Future<String> importProgress(String json) async {
    try {
      final p = Progress.fromJson(jsonDecode(json) as Map<String, dynamic>);
      await _applyProgress(p);
      return '';
    } catch (e) {
      return _errMsg(e);
    }
  }

  // ---------- Google-синхронизация ----------

  /// syncConfig — синхронизирует настройки с Google-облаком.
  /// Несекретные поля уходят всегда; ключи и фолбэки — только при
  /// включённом syncKeysToCloud. Если локальных ключей нет, они
  /// подтягиваются из облака (например, на новом устройстве).
  Future<String> syncConfig({bool pullFirst = true}) async {
    if (!sync.signedIn) return 'Сначала войди через Google.';
    Map<String, dynamic>? remoteRaw;
    if (pullFirst) {
      final cloud = await sync.pullConfig();
      if (cloud != null) {
        try {
          remoteRaw =
              jsonDecode(cloud['json'] as String) as Map<String, dynamic>;
          final remoteCfg = Config.fromJson(remoteRaw);
          final remoteAt = _cloudConfigTime(cloud, remoteCfg);
          final localAt = DateTime.tryParse(config.updatedAt);
          final cloudNewer = remoteAt != null &&
              (localAt == null || remoteAt.isAfter(localAt));
          if (cloudNewer) {
            config.userName = remoteCfg.userName;
            config.theme = remoteCfg.theme;
            config.themeAuto = remoteCfg.themeAuto;
            config.notificationsEnabled = remoteCfg.notificationsEnabled;
            config.dailyReminderEnabled = remoteCfg.dailyReminderEnabled;
            config.reminderHour = remoteCfg.reminderHour;
            config.reminderMinute = remoteCfg.reminderMinute;
            config.aiMotivationEnabled = remoteCfg.aiMotivationEnabled;
            config.mascotVisible = remoteCfg.mascotVisible;
            config.customThemes = remoteCfg.customThemes;
            config.buttonBrightness = remoteCfg.buttonBrightness;
            config.bgBlur = remoteCfg.bgBlur;
            config.bgDim = remoteCfg.bgDim;
            config.launcherX = remoteCfg.launcherX;
            config.launcherY = remoteCfg.launcherY;
            if (config.syncKeysToCloud) {
              if (config.apiKey.isEmpty) {
                config.apiKey = remoteCfg.apiKey;
                config.provider = remoteCfg.provider;
                config.model = remoteCfg.model;
                config.baseUrl = remoteCfg.baseUrl;
              }
              // Фолбэки мержим по (provider+model+baseUrl): локальные ключи
              // не пропадают, облачные добавляются, пустые ключи из облака
              // не затирают локальные.
              final merged = List<AiEndpoint>.from(config.fallbacks);
              for (final rf in remoteCfg.fallbacks) {
                final i = merged.indexWhere((x) =>
                    x.provider == rf.provider &&
                    x.model == rf.model &&
                    x.baseUrl == rf.baseUrl);
                if (i < 0) {
                  merged.add(rf);
                } else if (merged[i].apiKey.isEmpty && rf.apiKey.isNotEmpty) {
                  merged[i].apiKey = rf.apiKey;
                }
              }
              config.fallbacks = merged;
            }
            config.updatedAt = remoteCfg.updatedAt;
            await saveConfig(autofill: false, syncCloud: false);
            notifyListeners();
          }
        } catch (_) {}
      }
    }
    config.updatedAt = DateTime.now().toIso8601String();
    final outgoing = config.toCloudJson(includeKeys: config.syncKeysToCloud);
    // Новая установка по умолчанию не читает облачные ключи. При обычном
    // входе при этом не стираем ранее сохранённые секреты: они останутся в
    // облаке до явного выключения тумблера (тот путь вызывает pullFirst=false).
    if (!config.syncKeysToCloud &&
        remoteRaw != null &&
        remoteRaw!['sync_keys_to_cloud'] == true) {
      for (final field in ['api_key', 'fallbacks', 'provider_profiles']) {
        if (remoteRaw!.containsKey(field)) outgoing[field] = remoteRaw![field];
      }
      outgoing['sync_keys_to_cloud'] = true;
    }
    return await sync.pushConfig(jsonEncode(outgoing));
  }

  Future<String> signInSync() async {
    final err = await sync.signIn();
    if (err.isNotEmpty) return err;
    final cloud = await sync.pull();
    var loaded = false;
    if (cloud != null) {
      try {
        final remote = Progress.fromJson(
            jsonDecode(cloud['json'] as String) as Map<String, dynamic>);
        if (_cloudIsBetter(remote)) {
          await _applyProgress(remote);
          loaded = true;
        }
      } catch (_) {}
    }
    final pushErr = loaded ? '' : await sync.push(jsonEncode(prog.toJson()));
    // Настройки уходят всегда; ключи — только если пользователь не выключил опцию.
    final cfgErr = await syncConfig(pullFirst: true);
    if (pushErr.isNotEmpty) return pushErr;
    if (cfgErr.isNotEmpty) return cfgErr;
    if (loaded) {
      return 'Загружено из облака: ${prog.solvedTotal} задач';
    }
    return config.syncKeysToCloud
        ? 'Вход выполнен — прогресс и ключи сохранены в облако'
        : 'Вход выполнен — прогресс сохранён, ключи не отправлялись';
  }

  Future<String> syncNow() async {
    if (!sync.signedIn) return 'Сначала войди через Google.';
    final cloud = await sync.pull();
    var loaded = false;
    if (cloud != null) {
      try {
        final remote = Progress.fromJson(
            jsonDecode(cloud['json'] as String) as Map<String, dynamic>);
        if (_cloudIsBetter(remote)) {
          await _applyProgress(remote);
          loaded = true;
        }
      } catch (_) {}
    }
    final err = loaded ? '' : await sync.push(jsonEncode(prog.toJson()));
    if (err.isNotEmpty) return err;
    final cfgErr = await syncConfig(pullFirst: true);
    if (cfgErr.isNotEmpty) return cfgErr;
    if (loaded) {
      return 'Загружено из облака: ${prog.solvedTotal} задач';
    }
    return config.syncKeysToCloud
        ? 'Прогресс и ключи сохранены в облако'
        : 'Прогресс сохранён; ключи не отправлялись';
  }

  Future<void> signOutSync() => sync.signOut();
}

// мост к корневому ассету объявлен в main.dart (rootBundle)// мост к корневому ассету объявлен в main.dart (rootBundle)
Future<String> Function() loadCoursesAsset = () async => '[]';

// ---------- курсы и задачи ----------

extension AppCourses on AppController {
  Course get cur => courses[courseIdx];

  /// Песочница принадлежит конкретной задаче, а не всему курсу. Раньше
  /// переход на соседнюю задачу перезаписывал состояние и историю курса.
  String get stateKey {
    if (courses.isEmpty) return '__empty__';
    final task = currentTask;
    return task == null ? '${cur.id}/__course__' : '${cur.id}/${task.id}';
  }

  void ensureStateForTask(Task t) {
    if (stateTask[stateKey] == t.id) return;
    states[stateKey] = t.start.clone();
    history[stateKey] = [];
    stateTask[stateKey] = t.id;
  }

  void resetCourseState() {
    if (courses.isEmpty) return;
    if (!states.containsKey(stateKey)) {
      states[stateKey] = viewIdx < cur.tasks.length
          ? cur.tasks[viewIdx].start.clone()
          : SandboxState();
      stateTask[stateKey] =
          viewIdx < cur.tasks.length ? cur.tasks[viewIdx].id : '';
    }
    history.putIfAbsent(stateKey, () => []);
  }

  bool isDone(Task t) => prog.completed[cur.id]?[t.id] ?? false;

  /// isCourseDone — курс пройден целиком (есть задачи и все решены).
  bool isCourseDone(int i) {
    if (i < 0 || i >= courses.length) return false;
    final tasks = courses[i].tasks;
    if (tasks.isEmpty) return false;
    final done = prog.completed[courses[i].id] ?? {};
    return tasks.every((t) => done[t.id] ?? false);
  }

  bool quizDone(Task t) => prog.quizDone[cur.id]?[t.id] ?? false;

  /// _swapTerminalDraft — сохраняет черновик старого терминала и
  /// восстанавливает черновик нового, не очищая ввод без отправки.
  void _swapTerminalDraft(String previousKey) {
    if (previousKey == termKey) return;
    _termDrafts[previousKey] = termInput.text;
    final draft = _termDrafts[termKey] ?? '';
    termInput.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  void selectTask(int i) {
    final oldTaskId = currentTask?.id ?? '';
    final oldKey = termKey;
    viewIdx = i;
    if (i >= 0 && i < cur.tasks.length) ensureStateForTask(cur.tasks[i]);
    if ((currentTask?.id ?? '') != oldTaskId) _swapTerminalDraft(oldKey);
    bindChatForCurrentTask();
    notifyListeners();
  }

  void switchCourse(int i) {
    if (i < 0 || i >= courses.length) return;
    final oldKey = termKey;
    courseIdx = i;
    viewIdx = 0;
    prog.lastCourse = cur.id;
    prog.activeCourseByDirection[config.activeDirection] = cur.id;
    saveProgress();
    resetCourseState();
    _swapTerminalDraft(oldKey);
    bindChatForCurrentTask();
    refreshTerminal();
    notifyListeners();
  }

  /// switchCourseSilent — смена курса без строк в терминале (из карты курсов).
  void switchCourseSilent(int i) {
    if (i < 0 || i >= courses.length || i == courseIdx) return;
    final oldKey = termKey;
    courseIdx = i;
    viewIdx = 0;
    prog.lastCourse = cur.id;
    prog.activeCourseByDirection[config.activeDirection] = cur.id;
    saveProgress();
    resetCourseState();
    _swapTerminalDraft(oldKey);
    bindChatForCurrentTask();
    notifyListeners();
  }

  /// selectFirstUndone — при старте открываем первую нерешённую задачу.
  void selectFirstUndone() {
    final i = cur.tasks.indexWhere((t) => !isDone(t));
    selectTask(i >= 0 ? i : 0);
  }

  // ---------- терминал ----------

  SandboxState get state => states[stateKey] ?? SandboxState();

  void termLine(String text) {
    termText += '$text\n';
    _capTerm();
  }

  /// _capTerm — не даём выводу терминала расти бесконечно (иначе кадры
  /// становятся тяжёлыми, а приложение «подвисает» на длинных сессиях).
  void _capTerm() {
    const max = 60000;
    if (termText.length > max) {
      termText = termText.substring(termText.length - max);
    }
  }

  void refreshTerminal() => notifyListeners();

  /// requestLessonSlide — попросить открытый урок перейти на нужный слайд.
  void requestLessonSlide(int index) {
    lessonSlideRequest = index;
    lessonSlideSeq++;
    notifyListeners();
  }

  String get prompt => termPrompt(state);

  Future<void> runCommand(String input) async {
    final cmd = input.trim();
    if (cmd.isEmpty || termBusy) return;
    termText += prompt + cmd + '\n';
    _capTerm();
    undoBuf.add(UndoEntry(stateKey, state.clone(), _termBefore(cmd)));
    if (undoBuf.length > 20) undoBuf.removeAt(0);
    redoBuf.clear();

    if (cmd.toLowerCase() == 'clear') {
      termText = '';
      refreshTerminal();
      return;
    }
    if (cmd.toLowerCase() == 'help') {
      termLine(
          '  Локально и мгновенно: kubectl get/apply/describe/scale/rollout/logs, docker ps/ps -a/images/volume ls/network ls/rm/rmi/stop/start/restart, ls, cat, pwd, echo, cd, clear, help.');
      termLine(
          '  Всё остальное исполняет ИИ-симулятор. Tab-подсказки и ↑/↓ — история.');
      refreshTerminal();
      return;
    }
    refreshTerminal();

    if (cmdHist.isEmpty || cmdHist.last != cmd) cmdHist.add(cmd);
    cmdHistIdx = cmdHist.length;

    // локальный fast-path
    final st = state;
    final local = tryLocalCommand(cmd, st);
    if (local != null && local.handled) {
      if (local.out.trim().isNotEmpty) st.lastOutput = local.out;
      if (local.out.trim().isNotEmpty) termLine(local.out);
      _pushHist(cmd, local.out);
      refreshTerminal();
      _autosave();
      return;
    }

    if (ai == null || !ai!.ready) {
      termLine('  ! Нет API-ключа — настрой ИИ в «Ещё» → Настройки.');
      refreshTerminal();
      return;
    }

    final task = currentTask;
    termBusy = true;
    refreshTerminal();
    try {
      final res = await ai!.runCommand(cur, task, state, _lastHist(6), cmd);
      states[stateKey] = res.state;
      final out = res.output.replaceAll(RegExp(r'\n+$'), '');
      if (out.trim().isNotEmpty) termLine(out);
      _pushHist(cmd, out);
      if (task != null && task.isQuiz && res.solved && !quizDone(task)) {
        _markQuizDone(task);
        termLine('  ✓ тест пройден — практика открыта');
      }
    } catch (e) {
      termLine('  ! ошибка симулятора: ${_errMsg(e)}');
    }
    termBusy = false;
    refreshTerminal();
    _autosave();
  }

  String _termBefore(String cmd) {
    // текст терминала ДО строки команды (для «Отменить»)
    final idx = termText.lastIndexOf(prompt + cmd + '\n');
    return idx > 0 ? termText.substring(0, idx) : '';
  }

  void undoCommand() {
    if (undoBuf.isEmpty) {
      termLine('  нечего отменять');
      refreshTerminal();
      return;
    }
    final u = undoBuf.removeLast();
    states[u.key] = u.st;
    termText = '${u.term}  ↩ отменено\n';
    refreshTerminal();
  }

  void _pushHist(String cmd, String out) {
    final key = stateKey;
    final list = history[key] ?? <HistEntry>[];
    list.add(HistEntry(cmd: cmd, out: out.trimRight()));
    if (list.length > 40) list.removeRange(0, list.length - 40);
    history[key] = list;
  }

  List<HistEntry> _lastHist(int n) {
    final l = history[stateKey] ?? const <HistEntry>[];
    return l.length <= n ? List.of(l) : l.sublist(l.length - n);
  }

  Task? get currentTask {
    if (courses.isEmpty) return null;
    final tasks = cur.tasks;
    if (viewIdx < 0 || viewIdx >= tasks.length) return null;
    return tasks[viewIdx];
  }

  // ---------- тест ----------

  String editorDraft(Task t) =>
      prog.drafts[Progress.taskKey(cur.id, t.id)] ?? t.editorStarter;

  /// saveEditorDraft — черновик переживает уход с экрана и перезапуск.
  void saveEditorDraft(Task t, String text) {
    prog.drafts[Progress.taskKey(cur.id, t.id)] = text;
    saveProgress();
  }

  /// submitEditorTask — детерминированная проверка YAML/кода из редактора.
  Future<String> submitEditorTask(Task t, String text) async {
    if (isDone(t)) return 'Эта задача уже решена.';
    final result = verifyEditorTask(t, text);
    if (!result.ok) return result.message;
    saveEditorDraft(t, text);
    await _completeTask(t, result.message, t.difficulty);
    return '';
  }

  void _markQuizDone(Task t) {
    final m = prog.quizDone[cur.id] ?? {};
    m[t.id] = true;
    prog.quizDone[cur.id] = m;
    saveProgress();
  }

  /// completeTheoryTask — страховка, если тест уже пройден, а задача не закрыта.
  Future<void> completeTheoryTask(Task t) async {
    if ((cur.isTheory || t.isExam) && !isDone(t)) {
      await _completeTask(t, 'Тест по теории пройден', t.difficulty);
    }
  }

  Future<String> checkQuiz(Task t, List<int> answers) async {
    if (answers.length != t.quiz.length) return 'Ответь на все вопросы.';
    for (var i = 0; i < answers.length; i++) {
      if (answers[i] == -1) return 'Ответь на все вопросы.';
    }
    var right = 0;
    for (var i = 0; i < t.quiz.length; i++) {
      if (answers[i] == t.quiz[i].correct) right++;
    }
    final tries = prog.quizTries[cur.id] ?? {};
    tries[t.id] = (tries[t.id] ?? 0) + 1;
    prog.quizTries[cur.id] = tries;
    if (right == t.quiz.length) {
      if (tries[t.id] == 1) grant('quiz-perfect');
      _markQuizDone(t);
      // В курсах без терминала и на экзаменах тест — это завершение задачи.
      if ((cur.isTheory || t.isExam) && !isDone(t)) {
        await _completeTask(t, 'Тест по теории пройден', t.difficulty);
        return '';
      }
      termLine('  ✓ тест пройден: ${t.title} — практика открыта');
      refreshTerminal();
      saveProgress();
      notifyListeners();
      return '';
    }
    saveProgress();
    notifyListeners();
    return 'Верных ответов: $right из ${t.quiz.length}. Перечитай теорию и попробуй снова.';
  }

  // ---------- завершение задачи ----------

  bool get busy => termBusy || mentorBusy;

  Future<String> submitTask() async {
    final task = currentTask;
    if (task == null) return 'Активной задачи нет.';
    if (busy) return '';
    if (task.isQuiz && !quizDone(task) && !isDone(task))
      return 'Сначала пройди тест по теории.';
    if (isDone(task)) return 'Эта задача уже решена.';
    final local = tryVerifyTask(task, state, history: _lastHist(40));
    if (local != null) {
      if (local.ok) {
        await _completeTask(task, local.message, task.difficulty);
        return '';
      }
      termLine('  ✗ пока не выполнено: ${local.message}');
      refreshTerminal();
      return local.message;
    }
    if (ai == null || !ai!.ready)
      return 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
    termBusy = true;
    refreshTerminal();
    try {
      final tail = termText.length > 1600
          ? termText.substring(termText.length - 1600)
          : termText;
      final res =
          await ai!.verify(cur, task, state, _lastHist(20), termTail: tail);
      termBusy = false;
      if (res.solved) {
        await _completeTask(task, res.comment, res.difficulty);
        return '';
      }
      termLine('  ✗ пока не выполнено: ${res.comment}');
      refreshTerminal();
      return res.comment;
    } catch (e) {
      termBusy = false;
      final m = 'Проверка не удалась: ${_errMsg(e)}';
      termLine('  ! $m');
      refreshTerminal();
      return m;
    }
  }

  Future<void> _completeTask(Task t, String note, int checkerDiff) async {
    var diff = t.difficulty.clamp(1, 5);
    if (checkerDiff >= 1 && checkerDiff <= 5) {
      diff = checkerDiff;
      t.difficulty = diff;
    }
    if (reviewKey != null) {
      final b = prog.bookmarks[reviewKey];
      if (b != null) {
        b.intervalDays = (b.intervalDays * 2).clamp(2, 30);
        b.due = DateTime.now()
            .add(Duration(days: b.intervalDays))
            .toIso8601String()
            .substring(0, 10);
        termLine('  ✓ повтор засчитан — следующее через ' +
            b.intervalDays.toString() +
            ' дн.');
      }
      grant('review1');
      reviewKey = null;
    }
    final xp = t.peeked ? 0 : t.xp;
    final m = prog.completed[cur.id] ?? {};
    m[t.id] = true;
    prog.completed[cur.id] = m;
    prog.xp += xp;
    prog.solvedTotal++;
    final dir = config.activeDirection;
    prog.directionXp[dir] = (prog.directionXp[dir] ?? 0) + xp;
    prog.directionSolved[dir] = (prog.directionSolved[dir] ?? 0) + 1;
    prog.recordSolved(
      courseId: cur.id,
      taskId: t.id,
      direction: dir,
      xp: xp,
    );
    _bumpStreak();
    _checkAchievements();
    await saveProgress();

    // результат — в окно, не в терминал
    // архив: чтобы ментор видел, ЧТО и КАК студент делал (история стирается
    // при переходе к следующей задаче — сохраняем снимок заранее)
    lastSolvedTitle = t.title;
    lastSolvedHist = (history[stateKey] ?? const <HistEntry>[])
        .map((h) =>
            '\$ ' +
            h.cmd +
            '\n' +
            (h.out.length > 200 ? h.out.substring(0, 200) + '…' : h.out))
        .join('\n');
    if (lastSolvedHist.length > 1600)
      lastSolvedHist = lastSolvedHist.substring(0, 1600);
    final achs = List<String>.from(pendingAchievements);
    pendingAchievements.clear();
    lastCompletion = {
      'title': t.title,
      'xp': xp,
      'peeked': t.peeked,
      'comment': note,
      'achievements': achs,
    };
    if (config.ttsEnabled && config.ttsAutoCompletion) {
      final phrase = note.trim().isEmpty
          ? '${t.title}. Задача выполнена.'
          : '${t.title}. $note';
      unawaited(TtsService.instance.speak(phrase, config));
    }
    refreshTerminal();

    // следующая задача
    final next = cur.tasks.indexWhere((x) => !isDone(x));
    selectTask(next >= 0 ? next : 0);
    unawaited(_maybeGenerateExam());
  }

  /// _maybeGenerateExam — раз в 5 пройденных задач добавляет экзамен.
  Future<void> _maybeGenerateExam() async {
    if (examBusy || generating || ai == null || !ai!.ready) return;
    final course = cur;
    final done = course.tasks
        .where((t) => prog.completed[course.id]?[t.id] ?? false)
        .map((t) => t.title)
        .toList();
    final examCount = course.tasks.where((t) => t.isExam).length;
    if (done.length < 5 || done.length ~/ 5 <= examCount) return;
    examBusy = true;
    try {
      final exam = await ai!.generateExam(course, done);
      if (course.tasks.any((x) => x.id == exam.id)) {
        exam.id = 'exam-${DateTime.now().millisecondsSinceEpoch % 100000}';
      }
      course.tasks.add(exam);
      (prog.generated[course.id] ??= []).add(exam);
      await saveProgress();
      notifyListeners();
    } catch (_) {
      // экзамен не критичен: добавится при следующем завершении
    } finally {
      examBusy = false;
    }
  }

  /// addStudySeconds — время, реально проведённое в уроке. Вызывается из
  /// LessonScreen при уходе с экрана/сворачивании приложения.
  Future<void> addStudySeconds(int seconds) async {
    if (seconds <= 0) return;
    prog.recordStudy(
      direction: config.activeDirection,
      seconds: seconds,
    );
    await saveProgress();
    notifyListeners();
  }

  void _bumpStreak() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prog.lastDay == today) return;
    final y = DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    prog.streak = prog.lastDay == y ? prog.streak + 1 : 1;
    prog.lastDay = today;
  }

  // ---------- достижения ----------

  void grant(String id) {
    if (prog.achieved.containsKey(id)) return;
    final a = achievementList.firstWhere((x) => x.id == id,
        orElse: () => const Achievement('', '', ''));
    if (a.id.isEmpty) return;
    prog.achieved[id] = DateTime.now().toIso8601String().substring(0, 10);
    lastAchievement = '${a.title}: ${a.desc}';
    saveProgress();
  }

  void _checkAchievements() {
    if (prog.solvedTotal >= 1) grant('first');
    if (prog.solvedTotal >= 10) grant('ten');
    if (prog.solvedTotal >= 50) grant('fifty');
    if (prog.streak >= 3) grant('streak3');
    if (prog.streak >= 7) grant('streak7');
  }

  // ---------- ментор ----------

  /// userNameOrFriend — имя для ИИ и уведомлений.
  String get userNameOrFriend {
    final n = config.userName.trim();
    return n.isEmpty ? 'Друг' : n;
  }

  /// appContextForAI — компактная карта приложения для решений Термая.
  String get appContextForAI {
    final visible = courses.take(14).map((c) => c.title).join('; ');
    final archived = archivedCourses.take(14).map((c) => c.title).join('; ');
    final task = currentTask;
    final screen = ScreenObserver.current;
    final screenLabel = switch (screen) {
      '' || 'HomeScreen' => 'главная',
      'ChatScreen' => 'чат',
      'InterviewScreen' => 'собеседование',
      'LessonScreen' => 'урок',
      'TaskListScreen' => 'список задач',
      'SettingsScreen' => 'настройки',
      'ArchiveScreen' => 'архив',
      'ChatsScreen' => 'чаты',
      'UsageScreen' => 'расход токенов',
      'HelpScreen' => 'справка',
      'BackgroundSettingsScreen' => 'фон',
      'AiFallbacksScreen' => 'резервные модели',
      'ReviewScreen' => 'повторение',
      'ProgressMapScreen' => 'карта прогресса',
      'StatsScreen' => 'статистика',
      'TtsSettingsScreen' => 'озвучивание',
      'LocalTtsScreen' => 'локальные голоса',
      _ => screen,
    };
    final chat = activeChat;
    final isInterview = chat?.taskId == '__interview__';
    final chatLabel =
        chat == null ? '—' : (chat.isGeneral ? 'общий чат' : chat.title);
    return 'Имя пользователя: ${userNameOrFriend}. '
        'Экран: $screenLabel. '
        'Чат: $chatLabel${isInterview ? ' (собеседование)' : ''}. '
        'Тема: ${C.p.title}. '
        'Курсы: ${visible.isEmpty ? '—' : visible}. '
        'Архив: ${archived.isEmpty ? '—' : archived}. '
        'Текущий курс: ${courses.isEmpty ? '—' : cur.title}. '
        'Текущая задача: ${task?.title ?? '—'}. '
        'XP: ${prog.xp}, серия: ${prog.streak}, решено: ${prog.solvedTotal}. '
        'Токены: ${prog.tokensTotal}. '
        'ИИ: ${ai == null ? 'не настроен' : (SharedAiService.instance.isUsable(config) ? 'TERMAI общий доступ' : config.provider)}/${ai?.model ?? '—'}.';
  }

  Future<String> sendChat(String question,
      {List<ChatAttachment> attachments = const [],
      String contextHint = ''}) async {
    if (mentorBusy) return '';
    final chat = activeChat ?? ensureGeneralChat();
    final general = chat.isGeneral;
    if (!general && courses.isEmpty) {
      chatMsgs = [
        ChatMsg('system', 'Нет доступных курсов — верни курс из архива.'),
      ];
      notifyListeners();
      return '';
    }
    final echo = question.trim().isEmpty ? '(вложение)' : question;
    chat.messages.add(ChatMsg('user', echo, attachments: attachments));
    chatMsgs = chat.messages;
    chat.updatedAt = DateTime.now().toIso8601String();
    await saveProgress();
    final command = question.trim().toLowerCase();
    if (command == '/диагностика' ||
        command == '/диагностика.' ||
        command == '/diagnostics' ||
        command == '/diagnostic') {
      mentorBusy = true;
      notifyListeners();
      try {
        final report = await runDiagnostics(this);
        addChatDiagnostic(report.summary, report.details);
      } catch (e) {
        addChatError('Диагностика не удалась', e);
      } finally {
        mentorBusy = false;
        notifyListeners();
      }
      return '';
    }
    if (ai == null || !ai!.ready) {
      final promo = SharedAiService.instance;
      final String hint;
      if (promo.promoActive && !promo.signedIn) {
        hint =
            'Общий бесплатный ИИ работает после входа через Google. Войди в настройках или добавь свой API-ключ.';
      } else if (promo.promoActive) {
        hint = 'Общий доступ ещё не включён: прими условия в настройках ИИ.';
      } else if (promo.endsAt != null) {
        hint =
            'Общий бесплатный доступ закончился. Добавь свой API-ключ в настройках ИИ.';
      } else {
        hint = 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
      }
      this.addChatMessage('system', hint);
      return '';
    }
    if (attachments.isEmpty && _looksLikeDrawingRequest(question)) {
      mentorBusy = true;
      notifyListeners();
      try {
        final svg = await ai!.generateSvg(question);
        final attachment = await saveSvgAttachment(svg);
        chat.messages.add(ChatMsg(
          'mentor',
          'Вот иллюстрация по твоему описанию. Нажми на неё, чтобы увеличить или сохранить.',
          attachments: [attachment],
        ));
        chatMsgs = chat.messages;
        chat.updatedAt = DateTime.now().toIso8601String();
        await saveProgress();
      } catch (e) {
        addChatError('Не удалось нарисовать иллюстрацию', e);
      } finally {
        mentorBusy = false;
        notifyListeners();
      }
      return '';
    }
    mentorBusy = true;
    notifyListeners();
    try {
      final helpCtx = contextHint.trim().isEmpty
          ? ''
          : 'КОНТЕКСТ ОТКРЫТОГО РАЗДЕЛА СПРАВКИ:\n${contextHint.trim()}\n'
              'Отвечай именно применительно к этому разделу TERMAI. Если пользователь '
              'просит дополнить справку, предложи конкретный недостающий текст.\n\n';
      final aiQuestion = helpCtx + question;
      final solvedCtx = lastSolvedTitle.isNotEmpty
          ? 'ТОЛЬКО ЧТО ВЫПОЛНЕНО СТУДЕНТОМ: задача «' +
              lastSolvedTitle +
              '».\nИстория его терминала:\n' +
              lastSolvedHist +
              '\n'
          : '';
      String answer;
      AssistantTurn? turn;
      final canUseNativeTools = toolExecutor != null && attachments.isEmpty;
      if (canUseNativeTools) {
        var navigationUsed = false;
        Future<AppActionResult> executeTool(AppActionCall call) async {
          if (isNavigationTool(call.name) && navigationUsed) {
            return const AppActionResult(
              ok: false,
              message: 'Пропущено конфликтующее навигационное действие.',
            );
          }
          final result = await toolExecutor!(call);
          if (isNavigationTool(call.name) && result.ok) {
            navigationUsed = true;
          }
          if (!result.ok && result.message.isNotEmpty) {
            addChatError('Не удалось выполнить ${call.name}', result.message);
          }
          return result;
        }

        turn = general
            ? await ai!.generalMentorWithTools(
                solvedCtx + aiQuestion,
                chatLog: this.chatLogForAI,
                appContext: appContextForAI,
                userName: userNameOrFriend,
                tools: appToolsJson(),
                execute: executeTool,
              )
            : await ai!.mentorWithTools(
                cur,
                currentTask,
                state,
                _lastHist(8),
                this.chatLogForAI,
                solvedCtx + aiQuestion,
                interview: chat.taskId == '__interview__',
                appContext: appContextForAI,
                tools: appToolsJson(),
                execute: executeTool,
              );
        answer = turn.text;
        if (answer.trim().isEmpty && turn.toolsUsed) answer = 'Готово.';
      } else {
        answer = general
            ? await ai!.generalMentor(
                solvedCtx + aiQuestion,
                chatLog: this.chatLogForAI,
                appContext: appContextForAI,
                userName: userNameOrFriend,
                attachments: attachments,
              )
            : await ai!.mentor(cur, currentTask, state, _lastHist(8),
                this.chatLogForAI, solvedCtx + aiQuestion,
                interview: chat.taskId == '__interview__',
                appContext: appContextForAI,
                attachments: attachments);
      }
      if (lastSolvedTitle.isNotEmpty) {
        lastSolvedTitle = '';
        lastSolvedHist = '';
      }

      // Ответ может содержать MCP-подобные вызовы приложения. Если native
      // tools уже выполнили действия, повторно маркеры не исполняем.
      final parsed = parseAppActions(answer);
      final markerActions =
          (turn?.toolsUsed ?? false) ? const <AppActionCall>[] : parsed.actions;
      final visible = parsed.text.trim();
      if (visible.isNotEmpty) {
        this.addChatMessage('mentor', visible);
      } else if (markerActions.isNotEmpty || (turn?.toolsUsed ?? false)) {
        this.addChatMessage('mentor', 'Готово.');
      }
      mentorBusy = false;
      notifyListeners();

      // Действия выполняем уже после снятия mentorBusy: генерация курса,
      // проверка задачи и терминал внутри проверяют флаг busy.
      final outcomes = await _executeAppActions(markerActions);
      final useful = outcomes
          .where((r) => r.ok && (r.data.isNotEmpty || r.message.isNotEmpty));
      if (useful.isNotEmpty) {
        final follow =
            await _answerWithToolResults(question, outcomes, general);
        final visibleFollow = parseAppActions(follow).text.trim();
        if (visibleFollow.isNotEmpty) {
          this.addChatMessage('mentor', visibleFollow);
        }
      }
    } catch (e) {
      addChatError('Наставник недоступен', e);
      mentorBusy = false;
      notifyListeners();
    }
    return '';
  }

  /// Возвращает результат инструментов модели и просит короткий ответ.
  /// Действия из этого ответа не исполняем: защита от циклов.
  Future<String> _answerWithToolResults(
    String question,
    List<AppActionResult> outcomes,
    bool general,
  ) async {
    if (ai == null || !ai!.ready) return '';
    final results = outcomes.map((r) => r.forModel).join('\n');
    final prompt = 'Вопрос пользователя: $question\n\n'
        'Результаты инструментов TERMAI (JSON, доверяй только им):\n$results\n\n'
        'Ответь пользователю по-русски кратко, используя эти данные. '
        'Не вызывай инструменты повторно и не выдумывай отсутствующие данные.';
    mentorBusy = true;
    notifyListeners();
    try {
      if (general) {
        return await ai!.generalMentor(
          prompt,
          chatLog: chatLogForAI,
          appContext: appContextForAI,
          userName: userNameOrFriend,
        );
      }
      return await ai!.mentor(
        cur,
        currentTask,
        state,
        _lastHist(8),
        chatLogForAI,
        prompt,
        interview: activeChat?.taskId == '__interview__',
        appContext: appContextForAI,
      );
    } catch (_) {
      return '';
    } finally {
      mentorBusy = false;
      notifyListeners();
    }
  }

  Future<List<AppActionResult>> _executeAppActions(
      List<AppActionCall> actions) async {
    if (actions.isEmpty) return const [];
    final tool = toolExecutor;
    final legacy = actionExecutor;
    if (tool == null && legacy == null) {
      addChatMessage('system', 'Действия приложения недоступны.');
      return const [];
    }
    final results = <AppActionResult>[];
    var navigationUsed = false;
    for (final action in actions) {
      final isNavigation = _navigationActionNames.contains(action.name);
      if (isNavigation && navigationUsed) {
        results.add(const AppActionResult(
          ok: false,
          message: 'Пропущено конфликтующее навигационное действие.',
        ));
        continue;
      }
      try {
        AppActionResult result;
        if (tool != null) {
          result = await tool(action);
        } else {
          final err = await legacy!(action);
          result = AppActionResult(ok: err.isEmpty, message: err);
        }
        if (isNavigation && result.ok) navigationUsed = true;
        if (!result.ok && result.message.isNotEmpty) {
          addChatError('Не удалось выполнить ${action.name}', result.message);
        }
        results.add(result);
      } catch (e) {
        final result = AppActionResult(ok: false, message: _errMsg(e));
        addChatError('Не удалось выполнить ${action.name}', result.message);
        results.add(result);
      }
    }
    return results;
  }

  static const _navigationActionNames = <String>{
    'open_screen',
    'open_course',
    'open_lesson',
    'open_task',
    'open_chat',
    'open_interview',
    'open_terminal',
    'open_mental_map',
    'open_progress',
    'open_settings',
    'open_archive',
    'open_chats',
    'open_usage',
    'open_help',
    'open_background',
    'open_fallbacks',
    'open_review',
    'open_home',
  };

  // ---------- решение ----------

  Future<void> loadSolution(Task task) async {
    if (solutionLoad) return;
    if (ai == null || !ai!.ready) {
      addChatMessage('system', 'Нет API-ключа — решение готовит ИИ.');
      return;
    }
    solutionLoad = true;
    notifyListeners();
    try {
      final ask = (cur.isTheory || task.isExam)
          ? 'Дай разбор этой темы: главные идеи, примеры и типичные ошибки. Без команд терминала.'
          : 'Дай пошаговое решение этой задачи: команды по шагам и ожидаемый результат. Минимум теории, только шаги.';
      final ans = await ai!.mentor(
          cur, task, state, _lastHist(4), const [], ask,
          allowActions: false);
      if (ans.trim().isNotEmpty) {
        task.solution = ans;
        task.peeked = true;
        await saveProgress();
      }
    } catch (e) {
      addChatError('Не удалось получить решение', e);
    }
    solutionLoad = false;
    notifyListeners();
  }

  // ---------- генерация от ИИ ----------

  String _uniqueTaskId(Course course, String raw) {
    var base = raw.trim();
    if (base.isEmpty) {
      base = 'ai-${DateTime.now().millisecondsSinceEpoch % 100000}';
    }
    if (!course.tasks.any((t) => t.id == base)) return base;
    var n = 2;
    while (course.tasks.any((t) => t.id == '$base-$n')) {
      n++;
    }
    return '$base-$n';
  }

  String _uniqueCourseId(String raw) {
    var base = raw.trim();
    if (base.isEmpty) {
      base = 'ai-${DateTime.now().millisecondsSinceEpoch % 100000}';
    }
    if (!allCourses.any((c) => c.id == base)) return base;
    var n = 2;
    while (allCourses.any((c) => c.id == '$base-$n')) {
      n++;
    }
    return '$base-$n';
  }

  String _normalizedTitle(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// prepareCourseRebuild — пересобрать программу курса, но сначала показать
  /// точный diff. Завершённые задачи сохраняются даже при смене программы.
  Future<CourseRebuildPlan?> prepareCourseRebuild(Course course) async {
    if (ai == null || !ai!.ready) {
      lastFillError = 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
      return null;
    }
    final GenerationOperation op;
    try {
      op = operations.begin(
          GenerationKind.fill, 'Пересборка курса «${course.title}»');
    } catch (e) {
      lastFillError = _errMsg(e);
      return null;
    }
    generating = true;
    lastFillError = '';
    notifyListeners();
    try {
      final old = List<Task>.from(course.tasks);
      final done = prog.completed[course.id] ?? const <String, bool>{};
      final target = old.isEmpty ? 5 : old.length.clamp(5, 12);
      op.update('Анализ курса',
          nextDetail:
              'Проверяю ${old.length} задач, сохраняю завершённые и id.',
          current: 0,
          total: target);
      notifyListeners();
      final generated = <Task>[];
      final knownTitles = <String>{...old.map((t) => t.title)};
      for (var i = 0; i < target; i++) {
        op.throwIfCanceled();
        final topic = course.syllabus.isEmpty
            ? 'тема ${i + 1} курса «${course.title}»'
            : course.syllabus[i % course.syllabus.length];
        op.update('Генерация задач',
            nextDetail: 'Задача ${i + 1} из $target: $topic',
            current: i,
            total: target);
        notifyListeners();
        final t = await ai!.generateTask(
            course.title, topic, knownTitles.toList(), '',
            mode: course.mode);
        op.throwIfCanceled();
        if (t.title.trim().isEmpty || t.goal.trim().isEmpty) {
          throw Exception('ИИ вернул задачу без названия или условия.');
        }
        if (course.isTheory && t.quiz.isEmpty && !t.hasEditor) {
          throw Exception('ИИ вернул урок без теста.');
        }
        if (t.id.isEmpty || generated.any((x) => x.id == t.id)) {
          t.id = 'rebuild-${DateTime.now().millisecondsSinceEpoch % 100000}-$i';
        }
        generated.add(t);
        knownTitles.add(t.title);
        op.advance('Задача ${i + 1} из $target готова');
      }

      op.update('Сверка изменений',
          nextDetail: 'Сопоставляю старые и новые задачи по названию');
      notifyListeners();
      final matchedOld = <Task>{};
      final kept = <String>[];
      final added = <String>[];
      for (final t in generated) {
        final key = _normalizedTitle(t.title);
        Task? oldTask;
        for (final o in old) {
          if (matchedOld.contains(o)) continue;
          if (_normalizedTitle(o.title) == key) {
            oldTask = o;
            break;
          }
        }
        if (oldTask != null) {
          t.id = oldTask.id;
          t.peeked = oldTask.peeked;
          matchedOld.add(oldTask);
          kept.add(t.title);
        } else {
          added.add(t.title);
        }
      }
      final preserved = <Task>[];
      final preservedTitles = <String>[];
      final oldIds = old.map((t) => t.id).toSet();
      for (final t in generated) {
        if (matchedOld.any((o) => o.id == t.id)) continue;
        if (oldIds.contains(t.id)) {
          t.id =
              'rebuild-${DateTime.now().millisecondsSinceEpoch % 100000}-${t.id}';
        }
      }
      for (final o in old) {
        if (matchedOld.contains(o)) continue;
        if (done[o.id] == true) {
          preserved.add(o);
          preservedTitles.add(o.title);
        }
      }
      final proposed = <Task>[...generated, ...preserved];
      final ids = <String>{};
      var seq = 0;
      for (final t in proposed) {
        if (ids.contains(t.id) || t.id.isEmpty) {
          t.id =
              'rebuild-${DateTime.now().millisecondsSinceEpoch % 100000}-${seq++}';
        }
        ids.add(t.id);
      }
      final removed = old
          .where((o) => !matchedOld.contains(o) && done[o.id] != true)
          .map((o) => o.title)
          .toList();
      op.finish();
      return CourseRebuildPlan(
        course: course,
        tasks: proposed,
        keptTitles: kept,
        addedTitles: added,
        removedTitles: removed,
        preservedCompleted: preservedTitles,
      );
    } catch (e) {
      final canceled = e is GenerationCanceled || op.cancelRequested;
      final message = canceled ? 'Пересборка отменена.' : _errMsg(e);
      lastFillError = message;
      op.finish(error: canceled ? null : message);
      return null;
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<void> applyCourseRebuild(CourseRebuildPlan plan) async {
    final course = plan.course;
    course.tasks = List<Task>.from(plan.tasks);
    prog.rebuiltTasks[course.id] = List<Task>.from(plan.tasks);
    viewIdx = 0;
    await saveProgress();
    notifyListeners();
  }

  Future<String> generateTask(String topic) async {
    final cleanTopic = topic.trim();
    if (cleanTopic.isEmpty) return 'Укажи тему новой задачи.';
    if (courses.isEmpty)
      return 'Нет доступных курсов — сначала создай или верни курс.';
    if (ai == null || !ai!.ready) {
      return 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
    }
    final GenerationOperation op;
    try {
      op = operations.begin(GenerationKind.task, 'Новая задача: $cleanTopic');
    } catch (e) {
      return _errMsg(e);
    }
    notifyListeners();
    try {
      op.update('Запрос к ИИ',
          nextDetail: 'Пишу задачу «$cleanTopic» для курса «${cur.title}»');
      notifyListeners();
      final t = await ai!.generateTask(
          cur.title, cleanTopic, _recentTitles(10), '',
          mode: cur.mode);
      op.throwIfCanceled();
      if (t.title.trim().isEmpty || t.goal.trim().isEmpty) {
        throw Exception('ИИ вернул задачу без названия или условия.');
      }
      if (cur.isTheory && t.quiz.isEmpty) {
        throw Exception('ИИ вернул урок без теста.');
      }
      t.id = _uniqueTaskId(cur, t.id);
      op.update('Сохранение',
          nextDetail: 'Добавляю задачу в курс «${cur.title}»');
      notifyListeners();
      cur.tasks.add(t);
      (prog.generated[cur.id] ??= []).add(t);
      await saveProgress();
      op.finish();
      selectTask(cur.tasks.length - 1);
      termLine('');
      termLine('  + новая задача добавлена: ${t.title}');
      refreshTerminal();
      return '';
    } catch (e) {
      final canceled = e is GenerationCanceled || op.cancelRequested;
      final message = canceled ? 'Операция отменена.' : _errMsg(e);
      op.finish(error: canceled ? null : message);
      if (!canceled) {
        termLine('  ! не удалось сгенерировать: $message');
        refreshTerminal();
      }
      return message;
    } finally {
      notifyListeners();
    }
  }

  Future<String> generateCourses(String goal) async {
    final cleanGoal = goal.trim();
    if (cleanGoal.isEmpty) return 'Опиши цель обучения.';
    if (ai == null || !ai!.ready) {
      return 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
    }
    final GenerationOperation op;
    try {
      op = operations.begin(
          GenerationKind.courses, 'Программа курсов: $cleanGoal');
    } catch (e) {
      return _errMsg(e);
    }
    notifyListeners();
    try {
      op.update('Анализ цели',
          nextDetail: 'ИИ строит последовательность курсов под цель.');
      notifyListeners();
      final news = await ai!.generateCourses(cleanGoal);
      op.throwIfCanceled();
      if (news.isEmpty) {
        throw Exception('ИИ не вернул ни одного курса.');
      }

      final prepared = <Course>[];
      for (final c in news) {
        if (c.title.trim().isEmpty) {
          throw Exception('ИИ вернул курс без названия.');
        }
        if (c.syllabus.isEmpty) {
          throw Exception('ИИ вернул курс «${c.title}» без программы.');
        }
        c.id = _uniqueCourseId(c.id);
        c.direction = config.activeDirection;
        c.category = categoryForDirection(c.direction);
        c.tasks.clear();
        prepared.add(c);
      }

      op.update('Наполнение курсов',
          nextDetail: '0 из ${prepared.length}',
          current: 0,
          total: prepared.length);
      notifyListeners();
      for (var i = 0; i < prepared.length; i++) {
        op.throwIfCanceled();
        final c = prepared[i];
        op.update('Наполнение курсов',
            nextDetail:
                'Курс ${i + 1} из ${prepared.length}: «${c.title}» — задачи');
        notifyListeners();
        await ai!.ensureCourseFilled(c, isCanceled: () => op.cancelRequested);
        op.throwIfCanceled();
        if (c.tasks.length < 5 || c.tasks.any((t) => t.title.trim().isEmpty)) {
          throw Exception(
              'Курс «${c.title}» получился неполным — задачи не сохранены.');
        }
        op.advance('Курс ${i + 1} из ${prepared.length} готов');
        notifyListeners();
      }

      op.update('Сохранение',
          nextDetail: 'Записываю ${prepared.length} курсов в прогресс');
      notifyListeners();
      courses.addAll(prepared);
      allCourses.addAll(prepared);
      prog.extraCourses.addAll(prepared);
      await saveProgress();
      op.finish();
      grant('architect');
      addChatMessage('mentor',
          'Собрал программу: ${prepared.map((c) => c.title).join(' → ')}. Начинаем с первого.');
      switchCourse(courses.length - prepared.length);
      return '';
    } catch (e) {
      final canceled = e is GenerationCanceled || op.cancelRequested;
      final message = canceled ? 'Операция отменена.' : _errMsg(e);
      op.finish(error: canceled ? null : message);
      return message;
    } finally {
      notifyListeners();
    }
  }

  /// fillCourse — наполняет курс задачами: один запрос на тему программы,
  /// чтобы задачи одного предмета не смешивались с другим.
  Future<String> fillCourse(Course course, {int count = 8}) async {
    if (generating) return '';
    if (ai == null || !ai!.ready)
      return 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
    if (course.tasks.isNotEmpty) return '';
    generating = true;
    lastFillError = '';
    if (fillTotal == 0) fillTotal = count;
    notifyListeners();
    var added = 0;
    try {
      final topics = course.syllabus.isEmpty
          ? List.generate(
              count,
              (i) =>
                  'повторение и углубление темы ' +
                  (i + 1).toString() +
                  ' курса «' +
                  course.title +
                  '»')
          : (course.syllabus.length >= count
              ? course.syllabus.take(count).toList()
              : course.syllabus.toList());
      for (var i = 0; i < topics.length; i++) {
        fillCurrent = course.title;
        try {
          final t = await ai!.generateTask(
              course.title, topics[i], _recentTitlesOf(course, 8), '',
              mode: course.mode);
          course.tasks.add(t);
          (prog.generated[course.id] ??= []).add(t);
          added++;
          fillDone++;
          notifyListeners();
        } catch (e) {
          // одна неудачная тема не рушит пакет
        }
      }
      if (added == 0) {
        lastFillError = 'ИИ не вернул ни одной задачи — попробуй ещё раз.';
        return lastFillError;
      }
      await saveProgress();
      return '';
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  /// continueCourse — «Продолжить курс»: ИИ смотрит на прогресс и добавляет
  /// следующие задачи. После каждого блока пройденных тем — экзамен.
  Future<String> continueCourse({int count = 4}) async {
    if (ai == null || !ai!.ready) {
      return 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
    }
    final GenerationOperation op;
    try {
      op = operations.begin(
          GenerationKind.continuation, 'Продолжение курса «${cur.title}»');
    } catch (e) {
      return _errMsg(e);
    }
    generating = true;
    fillCurrent = cur.title;
    lastFillError = '';
    notifyListeners();
    try {
      final course = cur;
      op.update('Анализ прогресса',
          nextDetail: 'Смотрю пройденные темы курса «${course.title}»');
      notifyListeners();
      final completed = course.tasks
          .where((t) => prog.completed[course.id]?[t.id] ?? false)
          .map((t) => t.title)
          .toList();
      op.update('Запрос к ИИ',
          nextDetail: 'Подбираю следующие $count задач с учётом прогресса');
      notifyListeners();
      final tasks = await ai!
          .generateContinuation(course, count, completedTitles: completed);
      op.throwIfCanceled();
      if (tasks.isEmpty) {
        throw Exception('ИИ не предложил новых задач — попробуй ещё раз.');
      }
      op.update('Проверка и сохранение',
          nextDetail: 'Проверяю ${tasks.length} новых задач');
      notifyListeners();
      var seq = 0;
      for (final t in tasks) {
        if (course.tasks.any((x) => x.id == t.id)) {
          t.id =
              'ai-${DateTime.now().millisecondsSinceEpoch % 100000}-${seq++}';
        }
        course.tasks.add(t);
        (prog.generated[course.id] ??= []).add(t);
      }
      // Периодический экзамен по пройденному материалу: один на каждые 5 тем.
      final doneCount = completed.length;
      final examCount = course.tasks.where((t) => t.isExam).length;
      if (doneCount >= 5 && doneCount ~/ 5 > examCount) {
        try {
          final exam = await ai!.generateExam(course, completed);
          if (course.tasks.any((x) => x.id == exam.id)) {
            exam.id = 'exam-${DateTime.now().millisecondsSinceEpoch % 100000}';
          }
          course.tasks.add(exam);
          (prog.generated[course.id] ??= []).add(exam);
        } catch (_) {}
      }
      await saveProgress();
      op.finish();
      if (tasks.isNotEmpty) {
        selectTask(course.tasks.length - tasks.length);
      }
      return '';
    } catch (e) {
      final canceled = e is GenerationCanceled || op.cancelRequested;
      final message = canceled ? 'Операция отменена.' : _errMsg(e);
      lastFillError = message;
      op.finish(error: canceled ? null : message);
      return message;
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  /// autoFillAll — заполняет задачами ВСЕ пустые курсы сразу (с прогрессом).
  Future<void> autoFillAll() async {
    if (generating || ai == null || !ai!.ready) return;
    final empty =
        courses.where((c) => c.tasks.isEmpty && c.syllabus.isNotEmpty).toList();
    if (empty.isEmpty) return;
    fillTotal = empty.length * 8;
    fillDone = 0;
    notifyListeners();
    for (final c in empty) {
      if (c.tasks.isNotEmpty && c.tasks.length >= 5) continue;
      await fillCourse(c);
    }
    fillTotal = 0;
    fillDone = 0;
    fillCurrent = '';
    notifyListeners();
  }

  List<String> _recentTitlesOf(Course c, int n) =>
      c.tasks.reversed.take(n).map((x) => x.title).toList();

  /// clearGeneratedTasks — убрать всю ИИ-генерацию из текущего курса
  /// (например, если старые задачи перепутали предметы).
  void clearGeneratedTasks() {
    final gen = prog.generated[cur.id];
    if (gen != null && gen.isNotEmpty) {
      final ids = gen.map((t) => t.id).toSet();
      cur.tasks.removeWhere((t) => ids.contains(t.id));
      prog.generated.remove(cur.id);
      viewIdx = viewIdx.clamp(0, cur.tasks.length - 1);
      saveProgress();
      notifyListeners();
    }
  }

  List<String> _recentTitles(int n) {
    final t = cur.tasks;
    return t.reversed.take(n).map((x) => x.title).toList();
  }

  // ---------- менеджмент курсов (долгое нажатие на кружке) ----------

  void renameCourse(int i, String title) {
    if (i < 0 || i >= courses.length || title.trim().isEmpty) return;
    courses[i].title = title.trim();
    prog.courseTitles[courses[i].id] = courses[i].title;
    final all = allCourses.where((c) => c.id == courses[i].id).firstOrNull;
    if (all != null) all.title = courses[i].title;
    saveProgress();
    notifyListeners();
  }

  /// renameCourseById — переименование с экрана архива.
  void renameCourseById(String id, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    prog.courseTitles[id] = t;
    for (final c in allCourses) {
      if (c.id == id) c.title = t;
    }
    for (final c in courses) {
      if (c.id == id) c.title = t;
    }
    saveProgress();
    notifyListeners();
  }

  void moveCourse(int from, int delta) {
    final to = from + delta;
    if (from < 0 || from >= courses.length || to < 0 || to >= courses.length)
      return;
    final c = courses.removeAt(from);
    courses.insert(to, c);
    _persistCourseOrder();
    if (courseIdx == from) courseIdx = to;
    saveProgress();
    notifyListeners();
  }

  void deleteCourse(int i) {
    if (i < 0 || i >= courses.length || courses.length <= 1) return;
    final currentId = cur.id;
    final wasCurrent = i == courseIdx;
    final c = courses.removeAt(i);
    if (c.id.startsWith('ai-')) {
      prog.extraCourses.removeWhere((x) => x.id == c.id);
    } else {
      prog.hiddenCourses.add(c.id);
    }
    _removeFromCourseOrder(c.id);
    _termBuffers.removeWhere((k, _) => k.startsWith('${c.id}/'));
    _cmdHistories.removeWhere((k, _) => k.startsWith('${c.id}/'));
    _cmdHistIndexes.removeWhere((k, _) => k.startsWith('${c.id}/'));
    if (wasCurrent) {
      courseIdx = courseIdx.clamp(0, courses.length - 1);
    } else if (i < courseIdx) {
      courseIdx--;
    }
    if (courseIdx >= courses.length) courseIdx = 0;
    final newCurrentId = courses.isEmpty ? '' : cur.id;
    if (newCurrentId != currentId) viewIdx = 0;
    if (viewIdx >= (courses.isEmpty ? 0 : cur.tasks.length)) viewIdx = 0;
    prog.lastCourse = courses.isEmpty ? '' : cur.id;
    if (courses.isNotEmpty) bindChatForCurrentTask();
    saveProgress();
    notifyListeners();
  }

  // ---------- архив курсов ----------

  /// archivedCourses — курсы, убранные в архив (в порядке «всех» курсов).
  List<Course> get archivedCourses =>
      allCourses.where((c) => prog.archived.contains(c.id)).toList();

  /// archiveCourse — убрать курс из основного списка в архив.
  /// Прогресс и чаты курса сохраняются: курс можно вернуть в любой момент.
  void archiveCourse(String id) {
    final c = allCourses.where((x) => x.id == id).firstOrNull;
    if (c == null || prog.archived.contains(id)) return;
    final currentId = courses.isEmpty ? '' : cur.id;
    final oldCourseIdx = courseIdx;
    prog.archived.add(id);
    _removeFromCourseOrder(id);
    _applyCourseFilter();
    if (courses.isNotEmpty) {
      // Если архивировали текущий курс, остаёмся на соседнем, а не
      // проваливаемся на первый. Если другой — сохраняем текущий.
      final idx = courses.indexWhere((x) => x.id == currentId);
      courseIdx = idx >= 0 ? idx : oldCourseIdx.clamp(0, courses.length - 1);
      if (cur.id != currentId) viewIdx = 0;
      if (viewIdx >= cur.tasks.length) viewIdx = 0;
      prog.lastCourse = cur.id;
      bindChatForCurrentTask();
    } else {
      courseIdx = 0;
      viewIdx = 0;
      prog.lastCourse = '';
    }
    saveProgress();
    notifyListeners();
  }

  /// unarchiveCourse — вернуть курс из архива в основной список.
  Future<void> unarchiveCourse(String id) async {
    if (!prog.archived.contains(id)) return;
    final course = allCourses.where((c) => c.id == id).firstOrNull;
    if (course != null &&
        course.direction != config.activeDirection &&
        config.directions.contains(course.direction)) {
      config.activeDirection = course.direction;
      await saveConfig(autofill: false);
    }
    prog.archived.remove(id);
    _applyCourseFilter();
    final i = courses.indexWhere((c) => c.id == id);
    if (i >= 0) {
      courseIdx = i;
      prog.lastCourse = id;
      prog.activeCourseByDirection[config.activeDirection] = id;
      bindChatForCurrentTask();
    }
    saveProgress();
    notifyListeners();
  }

  /// deleteArchivedCourse — стереть архивный курс навсегда.
  void deleteArchivedCourse(String id) {
    prog.archived.remove(id);
    prog.extraCourses.removeWhere((x) => x.id == id);
    allCourses.removeWhere((x) => x.id == id);
    if (!prog.hiddenCourses.contains(id)) prog.hiddenCourses.add(id);
    _removeFromCourseOrder(id);
    _applyCourseFilter();
    saveProgress();
    notifyListeners();
  }

  // ---------- закладки и повторение ----------

  bool isBookmarked(Task t) => prog.bookmarks.containsKey(cur.id + '|' + t.id);

  void toggleBookmark() {
    final t = currentTask;
    if (t == null) return;
    final key = cur.id + '|' + t.id;
    if (prog.bookmarks.containsKey(key)) {
      prog.bookmarks.remove(key);
      termLine('  ☆ закладка снята');
    } else {
      prog.bookmarks[key] = Bookmark(
        taskId: t.id,
        courseId: cur.id,
        intervalDays: 1,
        due: DateTime.now().toIso8601String().substring(0, 10),
      );
      termLine('  ★ в закладках — вернёмся через день для повторения');
    }
    saveProgress();
    notifyListeners();
  }

  List<MapEntry<String, Bookmark>> dueBookmarks() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final out = <MapEntry<String, Bookmark>>[];
    for (final e in prog.bookmarks.entries) {
      if (e.value.due.compareTo(today) <= 0) out.add(e);
    }
    out.sort((a, b) => a.value.due.compareTo(b.value.due));
    return out;
  }

  Future<void> reviewFromBookmark(String key) async {
    final b = prog.bookmarks[key];
    if (b == null) return;
    final course = allCourses.where((c) => c.id == b.courseId).firstOrNull;
    if (course == null) {
      prog.bookmarks.remove(key);
      saveProgress();
      return;
    }
    if (!config.directions.contains(course.direction)) {
      config.directions = [...config.directions, course.direction];
    }
    if (course.direction != config.activeDirection &&
        config.directions.contains(course.direction)) {
      await switchDirection(course.direction);
    }
    final ci = courses.indexWhere((c) => c.id == b.courseId);
    if (ci < 0) {
      prog.bookmarks.remove(key);
      saveProgress();
      return;
    }
    switchCourseSilent(ci);
    final ti = cur.tasks.indexWhere((t) => t.id == b.taskId);
    if (ti < 0) return;
    reviewKey = key;
    selectTask(ti);
  }

  // ---------- собеседование ----------

  void startInterview() {
    interviewMode = true;
  }

  void stopInterview() {
    interviewMode = false;
  }

  bool _looksLikeDrawingRequest(String text) {
    final q = text.toLowerCase();
    if (q.contains('не рисуй') || q.contains('не надо рисовать')) return false;
    return RegExp(
            r'(нарисуй|нарисовать|изобрази|иллюстрац|картинк|рисунок|\bsvg\b|\bdraw\b|illustrat)')
        .hasMatch(q);
  }

  String _errMsg(Object e) {
    var s = e.toString();
    s = s.replaceFirst(RegExp(r'^Exception:\s*'), '');
    return s.length > 200 ? s.substring(0, 200) : s;
  }

  void _autosave() {
    saveProgress();
  }
}

// ---------- чаты с ментором ----------

extension AppMentorChats on AppController {
  MentorChat? chatById(String id) {
    for (final c in prog.mentorChats) {
      if (c.id == id) return c;
    }
    return null;
  }

  MentorChat? get activeChat => chatById(prog.activeChatId);

  List<MentorChat> chatsForTask(String courseId, String taskId) {
    if (courseId.isEmpty || taskId.isEmpty) return const [];
    final out = prog.mentorChats
        .where(
            (c) => !c.isGeneral && c.courseId == courseId && c.taskId == taskId)
        .toList();
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  List<MentorChat> get generalChats {
    final out = prog.mentorChats.where((c) => c.isGeneral).toList();
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  MentorChat? get latestGeneralChat =>
      generalChats.isEmpty ? null : generalChats.first;

  /// bindChatForCurrentTask — выбирает последний чат текущей задачи.
  /// create=false: новый чат не создаётся, активный просто очищается.
  void bindChatForCurrentTask({bool create = false, bool notify = false}) {
    final task = currentTask;
    if (task == null) {
      prog.activeChatId = '';
      chatMsgs = [];
      if (notify) notifyListeners();
      return;
    }
    final found = chatsForTask(cur.id, task.id);
    if (found.isNotEmpty) {
      _activateChat(found.first, save: false, notify: notify);
    } else if (create) {
      createChatForCurrentTask();
    } else {
      prog.activeChatId = '';
      chatMsgs = [];
      if (notify) notifyListeners();
    }
  }

  /// ensureChatForCurrentTask — открыть существующий чат задачи или создать новый.
  /// Без активной задачи общий чат не подмешивается: это разные контексты.
  MentorChat ensureChatForCurrentTask() {
    interviewMode = false;
    if (currentTask == null || courses.isEmpty) {
      return ensureGeneralChat();
    }
    bindChatForCurrentTask(notify: true);
    return activeChat ?? createChatForCurrentTask();
  }

  /// ensureGeneralChat — открыть последний общий чат или создать его.
  MentorChat ensureGeneralChat() {
    interviewMode = false;
    final existing = latestGeneralChat;
    if (existing != null) {
      _activateChat(existing, save: false, notify: true);
      return existing;
    }
    return createGeneralChat();
  }

  /// createGeneralChat — отдельный чат Термая, не привязанный к курсу/задаче.
  MentorChat createGeneralChat({String? title}) {
    interviewMode = false;
    final now = DateTime.now().toIso8601String();
    final c = MentorChat(
      id: 'chat-${DateTime.now().microsecondsSinceEpoch}',
      courseId: '',
      taskId: '',
      taskTitle: '',
      title: (title ?? '').trim().isEmpty ? 'Термай' : title!.trim(),
      createdAt: now,
      updatedAt: now,
    );
    prog.mentorChats.add(c);
    _activateChat(c, save: true);
    return c;
  }

  /// createChatForCurrentTask — явный чат задачи. Если задачи нет,
  /// создаётся общий чат: «новый чат» не должен приписывать к задаче.
  MentorChat createChatForCurrentTask({String? title}) {
    interviewMode = false;
    final now = DateTime.now().toIso8601String();
    final task = currentTask;
    if (task == null || courses.isEmpty) {
      return createGeneralChat(title: title);
    }
    final t = (title ?? '').trim();
    final c = MentorChat(
      id: 'chat-${DateTime.now().microsecondsSinceEpoch}',
      courseId: cur.id,
      taskId: task.id,
      taskTitle: task.title,
      title: t.isNotEmpty ? t : task.title,
      createdAt: now,
      updatedAt: now,
    );
    prog.mentorChats.add(c);
    _activateChat(c, save: true);
    return c;
  }

  /// createInterviewChat — новая беседа для собеседования.
  /// force=true — начать новую, даже если уже открыто собеседование.
  void createInterviewChat({bool force = false}) {
    final a = activeChat;
    if (!force && a != null && a.taskId == '__interview__') return;
    final now = DateTime.now().toIso8601String();
    final c = MentorChat(
      id: 'chat-${DateTime.now().microsecondsSinceEpoch}',
      courseId: '',
      taskId: '__interview__',
      taskTitle: 'Собеседование',
      title: 'Собеседование',
      createdAt: now,
      updatedAt: now,
    );
    prog.mentorChats.add(c);
    _activateChat(c, save: true);
  }

  /// openChat — открыть беседу и перейти к её задаче (если она не про собеседование).
  void openChat(String id) {
    final c = chatById(id);
    if (c == null) return;
    if (c.taskId == '__interview__') {
      interviewMode = true;
    } else {
      interviewMode = false;
      if (!c.isGeneral) {
        final ci = courses.indexWhere((x) => x.id == c.courseId);
        if (ci >= 0) {
          if (ci != courseIdx) {
            courseIdx = ci;
            prog.lastCourse = cur.id;
          }
          final ti = cur.tasks.indexWhere((t) => t.id == c.taskId);
          if (ti >= 0) {
            viewIdx = ti;
            ensureStateForTask(cur.tasks[ti]);
          }
        }
      }
    }
    _activateChat(c);
    saveProgress();
  }

  void selectChat(String id) {
    final c = chatById(id);
    if (c == null) return;
    _activateChat(c);
  }

  void renameChat(String id, String title) {
    final c = chatById(id);
    final t = title.trim();
    if (c == null || t.isEmpty) return;
    c.title = t;
    c.updatedAt = DateTime.now().toIso8601String();
    saveProgress();
    notifyListeners();
  }

  void deleteChat(String id) {
    final deleted = chatById(id);
    prog.mentorChats.removeWhere((c) => c.id == id);
    if (prog.activeChatId == id) {
      prog.activeChatId = '';
      chatMsgs = [];
      final left = deleted != null && deleted.isGeneral
          ? generalChats
          : chatsForTask(cur.id, currentTask?.id ?? '');
      if (left.isNotEmpty) {
        prog.activeChatId = left.first.id;
        chatMsgs = left.first.messages;
      }
    }
    saveProgress();
    notifyListeners();
  }

  /// addChatMessage — добавить сообщение в активную беседу.
  void addChatMessage(String role, String text) {
    final c = activeChat ?? ensureGeneralChat();
    _appendChat(c, ChatMsg(role, text));
  }

  /// addChatDiagnostic — отчёт диагностики с раскрываемыми деталями.
  void addChatDiagnostic(String summary, String details) {
    final c = activeChat ?? ensureGeneralChat();
    _appendChat(c, ChatMsg('diagnostic', summary, details: details));
  }

  /// addChatError — человеческая ошибка без сырого лога в чате.
  void addChatError(String prefix, Object error) {
    final c = activeChat ?? ensureGeneralChat();
    final friendly = friendlyAiError(error);
    final text = prefix.trim().isEmpty ? friendly : '$prefix. $friendly';
    _appendChat(c, ChatMsg('error', text, details: rawError(error)));
  }

  void _appendChat(MentorChat c, ChatMsg message) {
    c.messages.add(message);
    chatMsgs = c.messages;
    c.updatedAt = DateTime.now().toIso8601String();
    saveProgress();
    notifyListeners();
    if (message.role == 'mentor' && config.ttsEnabled && config.ttsAutoChat) {
      unawaited(TtsService.instance.speak(message.text, config));
    }
  }

  /// chatLogForAI — последние реплики для контекста ментора.
  List<String> get chatLogForAI {
    final msgs = activeChat?.messages ?? chatMsgs;
    final tail = msgs.length <= 8 ? msgs : msgs.sublist(msgs.length - 8);
    return tail
        .where((m) =>
            m.role != 'system' && m.role != 'error' && m.role != 'diagnostic')
        .map((m) => (m.role == 'user' ? 'Студент: ' : 'Наставник: ') + m.text)
        .toList();
  }

  void _activateChat(MentorChat c, {bool save = true, bool notify = true}) {
    prog.activeChatId = c.id;
    chatMsgs = c.messages;
    if (save) saveProgress();
    if (notify) notifyListeners();
  }
}
