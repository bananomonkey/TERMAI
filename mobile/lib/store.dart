// store.dart — контроллер приложения: настройки, прогресс, песочница,
// поток команды (fast-path → ИИ), проверка задач, XP и достижения.
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'ai.dart';
import 'models.dart';
import 'sandbox.dart';
import 'ui/theme.dart';

/// diagLog — глобальный журнал ошибок для экрана «Диагностика».
final StringBuffer diagLog = StringBuffer();

class ChatMsg {
  final String role; // user | mentor | system
  final String text;
  ChatMsg(this.role, this.text);
}

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

  List<Course> courses = [];
  int courseIdx = 0;
  int viewIdx = 0;

  Map<String, SandboxState> states = {};
  Map<String, List<HistEntry>> history = {};
  Map<String, String> stateTask = {};

  String termText = '';
  List<String> cmdHist = [];
  int cmdHistIdx = 0;
  final List<UndoEntry> undoBuf = [];

  List<ChatMsg> chatMsgs = [];
  List<String> chatLog = [];
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
  Map<String, dynamic>? lastCompletion; // данные окна «Задача выполнена»

  // ---------- инициализация ----------

  Future<void> init() async {
    final dir = await _dataDir();
    final cfgFile = io.File('$dir/termai.json');
    if (await cfgFile.exists()) {
      try {
        config = Config.fromJson(jsonDecode(await cfgFile.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
    }
    final progFile = io.File('$dir/termai-progress.json');
    if (await progFile.exists()) {
      try {
        prog = Progress.fromJson(jsonDecode(await progFile.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        prog = Progress();
      }
    }
    if (config.theme == 'sage') config.theme = 'cocoa';
    C.p = presetById(config.theme);
    ai = config.apiKey.isEmpty ? null : AIClient(config);

    if (!prog.genCleaned) {
      // одноразовая чистка: задачи ранних версий могли смешивать предметы
      prog.generated.clear();
      prog.genCleaned = true;
      await saveProgress();
    }
    await _assembleCourses();
    for (final c in courses) {
      c.tasks.addAll(prog.generated[c.id] ?? []);
    }
    if (prog.lastCourse.isNotEmpty) {
      final i = courses.indexWhere((c) => c.id == prog.lastCourse);
      if (i >= 0) courseIdx = i;
    }
    _bumpStreak();
    resetCourseState();
    ready = true;
    notifyListeners();
    autoFillAll();
  }

  /// _assembleCourses — собирает список курсов из актива + прогресса
  /// (используется при старте и после импорта).
  Future<void> _assembleCourses() async {
    final raw = await rootAssetCourses();
    courses = raw.where((c) => !prog.hiddenCourses.contains(c.id)).toList();
    courses.addAll(prog.extraCourses.where((c) => !prog.hiddenCourses.contains(c.id)));
    for (final c in courses) {
      final t = prog.courseTitles[c.id];
      if (t != null && t.isNotEmpty) c.title = t;
    }
    if (prog.courseOrder.isNotEmpty) {
      courses.sort((a, b) {
        final ia = prog.courseOrder.indexOf(a.id), ib = prog.courseOrder.indexOf(b.id);
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

  Future<void> saveConfig() async {
    if (config.theme == 'sage') config.theme = 'cocoa';
    C.p = presetById(config.theme);
    final dir = await _dataDir();
    await io.File('$dir/termai.json').writeAsString(jsonEncode(config.toJson()));
    ai = config.apiKey.isEmpty ? null : AIClient(config);
    notifyListeners();
    autoFillAll();
  }


  Future<void> saveProgress() async {
    final dir = await _dataDir();
    await io.File('$dir/termai-progress.json').writeAsString(jsonEncode(prog.toJson()));
  }
  // ---------- экспорт / импорт ----------

  Future<String> exportProgress() async {
    final dir = await _dataDir();
    final f = io.File(dir + '/termai-progress-export.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(prog.toJson()));
    return f.path;
  }

  Future<String> importProgress() async {
    final dir = await _dataDir();
    final f = io.File(dir + '/termai-progress-export.json');
    if (!await f.exists()) {
      return 'Файл не найден: ' + f.path + ' — сначала сделай экспорт.';
    }
    try {
      final p = Progress.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      prog = p;
      if (!prog.genCleaned) {
      // одноразовая чистка: задачи ранних версий могли смешивать предметы
      prog.generated.clear();
      prog.genCleaned = true;
      await saveProgress();
    }
    await _assembleCourses();
    states.clear();
      history.clear();
      stateTask.clear();
      reviewKey = null;
      await saveProgress();
      resetCourseState();
      selectFirstUndone();
      termLine('  ✓ прогресс импортирован: ' + prog.xp.toString() + ' XP, серия ' + prog.streak.toString() + ' дн.');
      refreshTerminal();
      return '';
    } catch (e) {
      return _errMsg(e);
    }
  }
}

// мост к корневому ассету объявлен в main.dart (rootBundle)
Future<String> Function() loadCoursesAsset = () async => '[]';

// ---------- курсы и задачи ----------

extension AppCourses on AppController {
  Course get cur => courses[courseIdx];

  String get stateKey => cur.id;

  void ensureStateForTask(Task t) {
    if (stateTask[stateKey] == t.id) return;
    states[stateKey] = t.start.clone();
    history[stateKey] = [];
    stateTask[stateKey] = t.id;
  }

  void resetCourseState() {
    if (!states.containsKey(stateKey)) {
      states[stateKey] =
          viewIdx < cur.tasks.length ? cur.tasks[viewIdx].start.clone() : SandboxState();
      stateTask[stateKey] = viewIdx < cur.tasks.length ? cur.tasks[viewIdx].id : '';
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
    notifyListeners();
  }

  void switchCourse(int i) {
    courseIdx = i;
    viewIdx = 0;
    prog.lastCourse = cur.id;
    saveProgress();
    resetCourseState();
    termLine('');
    termLine('── Курс: ${cur.title} ──');
    refreshTerminal();
    notifyListeners();
  }

  /// switchCourseSilent — смена курса без строк в терминале (из карты курсов).
  void switchCourseSilent(int i) {
    if (i == courseIdx) return;
    courseIdx = i;
    viewIdx = 0;
    prog.lastCourse = cur.id;
    saveProgress();
    resetCourseState();
    notifyListeners();
  }

  /// selectFirstUndone — при старте открываем первую нерешённую задачу.
  void selectFirstUndone() {
    final i = cur.tasks.indexWhere((t) => !isDone(t));
    selectTask(i >= 0 ? i : 0);
  }

  // ---------- терминал ----------

  SandboxState get state => states[stateKey] ?? SandboxState();

  void termLine(String text) => termText += '$text\n';

  void refreshTerminal() => notifyListeners();

  String get prompt => termPrompt(state);

  Future<void> runCommand(String input) async {
    final cmd = input.trim();
    if (cmd.isEmpty || termBusy) return;
    termText += prompt + cmd + '\n';
    undoBuf.add(UndoEntry(stateKey, state.clone(), _termBefore(cmd)));
    if (undoBuf.length > 20) undoBuf.removeAt(0);

    if (cmd.toLowerCase() == 'clear') {
      termText = '';
      refreshTerminal();
      return;
    }
    if (cmd.toLowerCase() == 'help') {
      termLine('  Локально и мгновенно: docker ps/ps -a/images/volume ls/network ls/rm/rmi/stop/start/restart, ls, cat, pwd, echo, cd, clear, help.');
      termLine('  Всё остальное исполняет ИИ-симулятор. Tab-подсказки и ↑/↓ — история.');
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

  String checkQuiz(Task t, List<int> answers) {
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
    if (ai == null || !ai!.ready) return 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
    if (task.isQuiz && !quizDone(task) && !isDone(task)) return 'Сначала пройди тест по теории.';
    if (isDone(task)) return 'Эта задача уже решена.';
    termBusy = true;
    termLine('  …проверяю выполнение по истории терминала');
    refreshTerminal();
    try {
      final tail = termText.length > 1600 ? termText.substring(termText.length - 1600) : termText;
      final res = await ai!.verify(cur, task, state, _lastHist(20), termTail: tail);
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
        b.due = DateTime.now().add(Duration(days: b.intervalDays)).toIso8601String().substring(0, 10);
        termLine('  ✓ повтор засчитан — следующее через ' + b.intervalDays.toString() + ' дн.');
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
    final y = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    prog.streak = prog.lastDay == y ? prog.streak + 1 : 1;
    prog.lastDay = today;
  }

  // ---------- достижения ----------

  void grant(String id) {
    if (prog.achieved.containsKey(id)) return;
    final a = achievementList.firstWhere((x) => x.id == id, orElse: () => const Achievement('', '', ''));
    if (a.id.isEmpty) return;
    prog.achieved[id] = DateTime.now().toIso8601String().substring(0, 10);
    termLine('  ★ достижение: «${a.title}» — ${a.desc}');
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
    final echo = question.trim().isEmpty ? '(вложение)' : question;
    chatMsgs.add(ChatMsg('user', echo));
    chatLog = _trim(chatLog, 'Студент: $echo', 8);
    if (ai == null || !ai!.ready) {
      chatMsgs.add(ChatMsg('system', 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.'));
      notifyListeners();
      return '';
    }
    mentorBusy = true;
    notifyListeners();
    try {
      final answer = await ai!.mentor(cur, currentTask, state, _lastHist(8), chatLog, question,
          interview: interviewMode);
      chatMsgs.add(ChatMsg('mentor', answer));
      chatLog = _trim(chatLog, 'Наставник: $answer', 8);
    } catch (e) {
      chatMsgs.add(ChatMsg('system', 'Наставник недоступен: ${_errMsg(e)}'));
    }
    mentorBusy = false;
    notifyListeners();
    return '';
  }

  List<String> _trim(List<String> list, String item, int n) {
    final l = [...list, item];
    return l.length <= n ? l : l.sublist(l.length - n);
  }

  // ---------- решение ----------

  Future<void> loadSolution(Task task) async {
    if (solutionLoad) return;
    if (ai == null || !ai!.ready) {
      chatMsgs.add(ChatMsg('system', 'Нет API-ключа — решение готовит ИИ.'));
      notifyListeners();
      return;
    }
    solutionLoad = true;
    notifyListeners();
    try {
      final ans = await ai!.mentor(cur, task, state, _lastHist(4), const [],
          'Дай пошаговое решение этой задачи: команды по шагам и ожидаемый результат. Минимум теории, только шаги.');
      if (ans.trim().isNotEmpty) {
        task.solution = ans;
        task.peeked = true;
        await saveProgress();
      }
    } catch (e) {
      chatMsgs.add(ChatMsg('system', 'Не удалось получить решение: ${_errMsg(e)}'));
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
      final t = await ai!.generateTask(cur.title, topic, _recentTitles(10), '');
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
      prog.extraCourses.addAll(news);
      await saveProgress();
      grant('architect');
      chatMsgs.add(ChatMsg('mentor', 'Собрал программу: ${news.map((c) => c.title).join(' → ')}. Начинаем с первого.'));
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
    if (ai == null || !ai!.ready) return 'Нет API-ключа — настрой ИИ в «Ещё» → Настройки.';
    if (course.tasks.isNotEmpty) return '';
    generating = true;
    lastFillError = '';
    if (fillTotal == 0) fillTotal = count;
    notifyListeners();
    var added = 0;
    try {
      final topics = course.syllabus.isEmpty
          ? List.generate(count, (i) => 'повторение и углубление темы ' + (i + 1).toString() + ' курса «' + course.title + '»')
          : (course.syllabus.length >= count ? course.syllabus.take(count).toList() : course.syllabus.toList());
      for (var i = 0; i < topics.length; i++) {
        fillCurrent = course.title;
        try {
          final t = await ai!.generateTask(course.title, topics[i], _recentTitlesOf(course, 8), '');
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
    final empty = courses.where((c) => c.tasks.isEmpty && c.syllabus.isNotEmpty).toList();
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
    saveProgress();
    notifyListeners();
  }

  void moveCourse(int from, int delta) {
    final to = from + delta;
    if (from < 0 || from >= courses.length || to < 0 || to >= courses.length) return;
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
        taskId: t.id, courseId: cur.id, intervalDays: 1,
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
