// store.dart — контроллер приложения: настройки, прогресс, песочница,
// поток команды (fast-path → ИИ), проверка задач, XP и достижения.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'ai.dart';
import 'models.dart';
import 'sandbox.dart';
import 'sync_service.dart';
import 'ui/theme.dart';

/// diagLog — глобальный журнал ошибок для экрана «Диагностика».
final StringBuffer diagLog = StringBuffer();

class UndoEntry {
  final String key;
  final SandboxState st;
  final String term;
  UndoEntry(this.key, this.st, this.term);
}

class AppController extends ChangeNotifier {
  Config config = Config();
  Progress prog = Progress();
  AIClient? ai;
  final SyncService sync = SyncService.instance;

  List<Course> courses = [];

  /// allCourses — все курсы, включая архивные (для экрана архива).
  List<Course> allCourses = [];
  int courseIdx = 0;
  int viewIdx = 0;

  Map<String, SandboxState> states = {};
  Map<String, List<HistEntry>> history = {};
  Map<String, String> stateTask = {};

  String termText = '';
  List<String> cmdHist = [];
  int cmdHistIdx = 0;
  final List<UndoEntry> undoBuf = [];
  final List<UndoEntry> redoBuf = [];

  List<ChatMsg> chatMsgs = [];
  bool termBusy = false;
  bool mentorBusy = false;
  bool solutionLoad = false;
  bool generating = false;
  int fillTotal = 0, fillDone = 0;
  String fillCurrent = '';
  bool ready = false;
  String lastFillError = '';

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
    final progFile = io.File('$dir/termai-progress.json');
    if (await progFile.exists()) {
      try {
        prog = Progress.fromJson(
            jsonDecode(await progFile.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        prog = Progress();
      }
    }
    _migrateTheme();
    C.p = presetById(config.theme);
    _initAI();

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
    unawaited(() async {
      try {
        await _initSync();
      } catch (_) {}
      await autoFillAll();
    }());
  }

  /// _initSync — тихо поднимает Firebase и подтягивает облачный прогресс,
  /// если пользователь уже входил через Google. Ошибки не блокируют запуск.
  Future<void> _initSync() async {
    await sync.init();
    if (!sync.signedIn) return;
    final cloud = await sync.pull();
    if (cloud == null) {
      await sync.push(jsonEncode(prog.toJson()));
      return;
    }
    try {
      final remote = Progress.fromJson(
          jsonDecode(cloud['json'] as String) as Map<String, dynamic>);
      if (_cloudIsBetter(remote)) {
        await _applyProgress(remote);
      }
    } catch (_) {}
  }

  /// _cloudIsBetter — облако полезнее локальной копии (больше решено/чатов).
  bool _cloudIsBetter(Progress remote) =>
      remote.solvedTotal > prog.solvedTotal ||
      (remote.solvedTotal == prog.solvedTotal &&
          remote.mentorChats.length > prog.mentorChats.length);

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
      // задачи, сгенерированные ИИ, живут в прогрессе — подмешиваем без дублей
      for (final t2 in prog.generated[c.id] ?? <Task>[]) {
        if (!c.tasks.any((x) => x.id == t2.id)) c.tasks.add(t2);
      }
    }
    _applyCourseFilter();
  }

  /// _applyCourseFilter — видимый список: без удалённых и архивных курсов.
  void _applyCourseFilter() {
    courses = allCourses
        .where((c) =>
            !prog.hiddenCourses.contains(c.id) && !prog.archived.contains(c.id))
        .toList();
    if (prog.courseOrder.isNotEmpty) {
      courses.sort((a, b) {
        final ia = prog.courseOrder.indexOf(a.id),
            ib = prog.courseOrder.indexOf(b.id);
        return (ia < 0 ? 9999 : ia).compareTo(ib < 0 ? 9999 : ib);
      });
    }
    if (prog.lastCourse.isNotEmpty) {
      final i = courses.indexWhere((c) => c.id == prog.lastCourse);
      if (i >= 0) courseIdx = i;
    }
    if (courseIdx >= courses.length) courseIdx = 0;
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
    // удалённые палитры (какао, sage, emerald и т.п.) → Dark Modern
    if (!themePresets.any((p) => p.id == config.theme)) config.theme = 'dark';
    // авто-тему возвращаем на основную; осознанный выбор синей сохраняем
    if (config.themeAuto && config.theme != 'dark') config.theme = 'dark';
  }

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
    ai = client.ready ? client : null;
  }

  /// recordUsage — копим токены по моделям; экран «Расход» считает доллары.
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

  Future<void> saveConfig({bool autofill = true}) async {
    _migrateTheme();
    C.p = presetById(config.theme);
    final dir = await _dataDir();
    await io.File('$dir/termai.json')
        .writeAsString(jsonEncode(config.toJson()));
    _initAI();
    notifyListeners();
    if (autofill) autoFillAll();
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
          .writeAsString(jsonEncode(config.toJson()));
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
    chatMsgs = [];
    reviewKey = null;
    await saveProgress();
    resetCourseState();
    selectFirstUndone();
    notifyListeners();
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

  Future<String> signInSync() async {
    final err = await sync.signIn();
    if (err.isNotEmpty) return err;
    final cloud = await sync.pull();
    if (cloud != null) {
      try {
        final remote = Progress.fromJson(
            jsonDecode(cloud['json'] as String) as Map<String, dynamic>);
        if (_cloudIsBetter(remote)) {
          await _applyProgress(remote);
          return 'Загружено из облака: ${prog.solvedTotal} задач';
        }
      } catch (_) {}
    }
    final pushErr = await sync.push(jsonEncode(prog.toJson()));
    return pushErr.isEmpty
        ? 'Вход выполнен — прогресс сохранён в облако'
        : pushErr;
  }

  Future<String> syncNow() async {
    if (!sync.signedIn) return 'Сначала войди через Google.';
    final cloud = await sync.pull();
    if (cloud != null) {
      try {
        final remote = Progress.fromJson(
            jsonDecode(cloud['json'] as String) as Map<String, dynamic>);
        if (_cloudIsBetter(remote)) {
          await _applyProgress(remote);
          return 'Загружено из облака: ${prog.solvedTotal} задач';
        }
      } catch (_) {}
    }
    final err = await sync.push(jsonEncode(prog.toJson()));
    return err.isEmpty ? 'Прогресс сохранён в облако' : err;
  }

  Future<void> signOutSync() => sync.signOut();
}

// мост к корневому ассету объявлен в main.dart (rootBundle)// мост к корневому ассету объявлен в main.dart (rootBundle)
Future<String> Function() loadCoursesAsset = () async => '[]';

// ---------- курсы и задачи ----------

extension AppCourses on AppController {
  Course get cur => courses[courseIdx];

  String get stateKey => courses.isEmpty ? '__empty__' : cur.id;

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

  void selectTask(int i) {
    viewIdx = i;
    if (i >= 0 && i < cur.tasks.length) ensureStateForTask(cur.tasks[i]);
    bindChatForCurrentTask();
    notifyListeners();
  }

  void switchCourse(int i) {
    if (i < 0 || i >= courses.length) return;
    courseIdx = i;
    viewIdx = 0;
    prog.lastCourse = cur.id;
    saveProgress();
    resetCourseState();
    bindChatForCurrentTask();
    refreshTerminal();
    notifyListeners();
  }

  /// switchCourseSilent — смена курса без строк в терминале (из карты курсов).
  void switchCourseSilent(int i) {
    if (i < 0 || i >= courses.length || i == courseIdx) return;
    courseIdx = i;
    viewIdx = 0;
    prog.lastCourse = cur.id;
    saveProgress();
    resetCourseState();
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
          '  Локально и мгновенно: docker ps/ps -a/images/volume ls/network ls/rm/rmi/stop/start/restart, ls, cat, pwd, echo, cd, clear, help.');
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
    final tasks = cur.tasks;
    if (viewIdx < 0 || viewIdx >= tasks.length) return null;
    return tasks[viewIdx];
  }

  // ---------- тест ----------

  void _markQuizDone(Task t) {
    final m = prog.quizDone[cur.id] ?? {};
    m[t.id] = true;
    prog.quizDone[cur.id] = m;
    saveProgress();
  }

  /// completeTheoryTask — страховка, если тест уже пройден, а задача не закрыта.
  Future<void> completeTheoryTask(Task t) async {
    if (cur.isTheory && !isDone(t)) {
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
      // В курсах без терминала тест — это и есть завершение задачи.
      if (cur.isTheory && !isDone(t)) {
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
    if (ai == null || !ai!.ready)
      return 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
    if (task.isQuiz && !quizDone(task) && !isDone(task))
      return 'Сначала пройди тест по теории.';
    if (isDone(task)) return 'Эта задача уже решена.';
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
    _bumpStreak();
    _checkAchievements();
    await saveProgress();

    // результат — в окно, не в терминал
    // архив: чтобы ментор видел, ЧТО и КАК студент делал (история стирается
    // при переходе к следующей задаче — сохраняем снимок заранее)
    lastSolvedTitle = t.title;
    lastSolvedHist = (history[cur.id] ?? const <HistEntry>[])
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
    refreshTerminal();

    // следующая задача
    final next = cur.tasks.indexWhere((x) => !isDone(x));
    selectTask(next >= 0 ? next : 0);
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

  Future<String> sendChat(String question) async {
    if (mentorBusy) return '';
    final chat = this.activeChat ?? this.createChatForCurrentTask();
    final echo = question.trim().isEmpty ? '(вложение)' : question;
    chat.messages.add(ChatMsg('user', echo));
    chatMsgs = chat.messages;
    chat.updatedAt = DateTime.now().toIso8601String();
    await saveProgress();
    if (ai == null || !ai!.ready) {
      this.addChatMessage(
          'system', 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.');
      return '';
    }
    mentorBusy = true;
    notifyListeners();
    try {
      final solvedCtx = lastSolvedTitle.isNotEmpty
          ? 'ТОЛЬКО ЧТО ВЫПОЛНЕНО СТУДЕНТОМ: задача «' +
              lastSolvedTitle +
              '».\nИстория его терминала:\n' +
              lastSolvedHist +
              '\n'
          : '';
      final answer = await ai!.mentor(cur, currentTask, state, _lastHist(8),
          this.chatLogForAI, solvedCtx + question,
          interview: interviewMode);
      if (lastSolvedTitle.isNotEmpty) {
        lastSolvedTitle = '';
        lastSolvedHist = '';
      }
      this.addChatMessage('mentor', answer);
    } catch (e) {
      this.addChatMessage('system', 'Наставник недоступен: ${_errMsg(e)}');
    }
    mentorBusy = false;
    notifyListeners();
    return '';
  }

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
      final ask = cur.isTheory
          ? 'Дай разбор этой темы: главные идеи, примеры и типичные ошибки. Без команд терминала.'
          : 'Дай пошаговое решение этой задачи: команды по шагам и ожидаемый результат. Минимум теории, только шаги.';
      final ans =
          await ai!.mentor(cur, task, state, _lastHist(4), const [], ask);
      if (ans.trim().isNotEmpty) {
        task.solution = ans;
        task.peeked = true;
        await saveProgress();
      }
    } catch (e) {
      addChatMessage('system', 'Не удалось получить решение: ${_errMsg(e)}');
    }
    solutionLoad = false;
    notifyListeners();
  }

  // ---------- генерация от ИИ ----------

  Future<String> generateTask(String topic) async {
    if (busy) return '';
    if (ai == null || !ai!.ready) return 'Нет API-ключа.';
    termBusy = true;
    termLine('  …ИИ пишет задачу по теме: $topic');
    refreshTerminal();
    try {
      final t = await ai!.generateTask(cur.title, topic, _recentTitles(10), '',
          mode: cur.mode);
      cur.tasks.add(t);
      (prog.generated[cur.id] ??= []).add(t);
      await saveProgress();
      termLine('');
      termLine('  + новая задача добавлена: ${t.title}');
      refreshTerminal();
      selectTask(cur.tasks.length - 1);
      return '';
    } catch (e) {
      termLine('  ! не удалось сгенерировать: ${_errMsg(e)}');
      refreshTerminal();
      return _errMsg(e);
    } finally {
      termBusy = false;
      notifyListeners();
    }
  }

  Future<String> generateCourses(String goal) async {
    if (busy) return '';
    if (ai == null || !ai!.ready) return 'Нет API-ключа.';
    termBusy = true;
    notifyListeners();
    try {
      final news = await ai!.generateCourses(goal);
      for (final c in news) {
        await ai!.ensureCourseFilled(c); // минимум 5 задач в каждом новом курсе
      }
      courses.addAll(news);
      allCourses.addAll(news);
      prog.extraCourses.addAll(news);
      await saveProgress();
      grant('architect');
      addChatMessage('mentor',
          'Собрал программу: ${news.map((c) => c.title).join(' → ')}. Начинаем с первого.');
      switchCourse(courses.length - news.length);
      return '';
    } catch (e) {
      return _errMsg(e);
    } finally {
      termBusy = false;
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
    prog.courseOrder = courses.map((x) => x.id).toList();
    if (courseIdx == from) courseIdx = to;
    saveProgress();
    notifyListeners();
  }

  void deleteCourse(int i) {
    if (i < 0 || i >= courses.length || courses.length <= 1) return;
    final c = courses.removeAt(i);
    if (c.id.startsWith('ai-')) {
      prog.extraCourses.removeWhere((x) => x.id == c.id);
    } else {
      prog.hiddenCourses.add(c.id);
    }
    prog.courseOrder = courses.map((x) => x.id).toList();
    if (courseIdx >= courses.length) courseIdx = 0;
    if (viewIdx >= (courses.isEmpty ? 0 : cur.tasks.length)) viewIdx = 0;
    prog.lastCourse = courses.isEmpty ? '' : cur.id;
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
    prog.archived.add(id);
    prog.courseOrder.remove(id);
    _applyCourseFilter();
    if (courses.isNotEmpty) {
      if (viewIdx >= cur.tasks.length) viewIdx = 0;
      prog.lastCourse = cur.id;
    } else {
      prog.lastCourse = '';
    }
    saveProgress();
    notifyListeners();
  }

  /// unarchiveCourse — вернуть курс из архива в основной список.
  void unarchiveCourse(String id) {
    if (!prog.archived.contains(id)) return;
    prog.archived.remove(id);
    _applyCourseFilter();
    final i = courses.indexWhere((c) => c.id == id);
    if (i >= 0) {
      courseIdx = i;
      prog.lastCourse = id;
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
    prog.courseOrder.remove(id);
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

  void reviewFromBookmark(String key) {
    final b = prog.bookmarks[key];
    if (b == null) return;
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
    final out = prog.mentorChats
        .where((c) => c.courseId == courseId && c.taskId == taskId)
        .toList();
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// bindChatForCurrentTask — выбирает последний чат текущей задачи.
  /// create=false: новый чат не создаётся, активный просто очищается.
  void bindChatForCurrentTask({bool create = false, bool notify = false}) {
    final taskId = currentTask?.id ?? '';
    final found = chatsForTask(cur.id, taskId);
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
  MentorChat ensureChatForCurrentTask() {
    interviewMode = false;
    bindChatForCurrentTask();
    return activeChat ?? createChatForCurrentTask();
  }

  MentorChat createChatForCurrentTask({String? title}) {
    final now = DateTime.now().toIso8601String();
    final task = currentTask;
    final t = (title ?? '').trim();
    final c = MentorChat(
      id: 'chat-${DateTime.now().microsecondsSinceEpoch}',
      courseId: cur.id,
      taskId: task?.id ?? '',
      taskTitle: task?.title ?? '',
      title: t.isNotEmpty
          ? t
          : ((task?.title ?? '').isNotEmpty ? task!.title : 'Новый чат'),
      createdAt: now,
      updatedAt: now,
    );
    prog.mentorChats.add(c);
    _activateChat(c, save: true);
    return c;
  }

  /// createInterviewChat — новая беседа для собеседования.
  void createInterviewChat() {
    final a = activeChat;
    if (a != null && a.taskId == '__interview__' && a.messages.isEmpty) return;
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
      interviewMode = false;
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
    prog.mentorChats.removeWhere((c) => c.id == id);
    if (prog.activeChatId == id) {
      prog.activeChatId = '';
      chatMsgs = [];
      final left = chatsForTask(cur.id, currentTask?.id ?? '');
      if (left.isNotEmpty) {
        prog.activeChatId = left.first.id;
        chatMsgs = left.first.messages;
      }
    }
    saveProgress();
    notifyListeners();
  }

  /// addChatMessage — добавить сообщение в активную беседу (создав её при необходимости).
  void addChatMessage(String role, String text) {
    final c = activeChat ?? createChatForCurrentTask();
    c.messages.add(ChatMsg(role, text));
    chatMsgs = c.messages;
    c.updatedAt = DateTime.now().toIso8601String();
    saveProgress();
    notifyListeners();
  }

  /// chatLogForAI — последние реплики для контекста ментора.
  List<String> get chatLogForAI {
    final msgs = activeChat?.messages ?? chatMsgs;
    final tail = msgs.length <= 8 ? msgs : msgs.sublist(msgs.length - 8);
    return tail
        .where((m) => m.role != 'system')
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
