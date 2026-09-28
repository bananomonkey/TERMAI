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
        'id': id, 'repo': repo, 'tag': tag, 'size_mb': sizeMb,
        'entrypoint': entrypoint, 'cmd': cmd, 'env': env, 'layers': layers,
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
        'id': id, 'name': name, 'image': image, 'status': status,
        'ports': ports, 'mounts': mounts, 'networks': networks,
        'execs': execs, 'logs_viewed': logsViewed,
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
        images: ((j['images'] as Map?) ?? {})
            .map((k, v) => MapEntry(k as String, ImageInfo.fromJson(v as Map<String, dynamic>))),
        containers: ((j['containers'] as Map?) ?? {})
            .map((k, v) => MapEntry(k as String, ContainerInfo.fromJson(v as Map<String, dynamic>))),
        volumes: (j['volumes'] as Map?)?.cast<String, String>() ?? {},
        networks: (j['networks'] as List?)?.cast<String>() ?? ['bridge', 'host', 'none'],
        events: (j['events'] as List?)?.cast<String>() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'workdir': workdir, 'files': files, 'images': images.map((k, v) => MapEntry(k, v.toJson())),
        'containers': containers.map((k, v) => MapEntry(k, v.toJson())),
        'volumes': volumes, 'networks': networks, 'events': events,
      };

  SandboxState clone() => SandboxState.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

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

  Map<String, dynamic> toJson() => {'question': question, 'options': options, 'correct': correct};
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

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        kind: (j['kind'] as String?) == 'quiz' ? 'quiz' : 'cmd',
        difficulty: (j['difficulty'] as num?)?.toInt() ?? 2,
        goal: j['goal'] as String? ?? '',
        check: j['check'] as String? ?? '',
        expected: j['expected_output'] as String? ?? '',
        solution: j['solution'] as String? ?? '',
        peeked: j['peeked'] as bool? ?? false,
        theory: (j['theory'] as List?)?.cast<String>() ?? [],
        hints: (j['hints'] as List?)?.cast<String>() ?? [],
        quiz: ((j['quiz'] as List?) ?? []).map((q) => QuizQ.fromJson(q as Map<String, dynamic>)).toList(),
        start: SandboxState.normalized((j['start_state'] as Map?)?.cast<String, dynamic>() ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'kind': kind, 'difficulty': difficulty,
        'theory': theory, 'quiz': quiz.map((q) => q.toJson()).toList(),
        'goal': goal, 'hints': hints, 'check': check,
        'expected_output': expected, 'solution': solution, 'peeked': peeked,
        'start_state': start.toJson(),
      };

  bool get isQuiz => kind == 'quiz';
  int get xp => 15 * difficulty + 15;
}

class Course {
  String id, title, desc;
  List<String> syllabus;
  List<Task> tasks;

  Course({
    required this.id,
    required this.title,
    this.desc = '',
    List<String>? syllabus,
    List<Task>? tasks,
  })  : syllabus = syllabus ?? [],
        tasks = tasks ?? [];

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        desc: j['desc'] as String? ?? '',
        syllabus: (j['syllabus'] as List?)?.cast<String>() ?? [],
        tasks: ((j['tasks'] as List?) ?? []).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'desc': desc, 'syllabus': syllabus,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };
}

class HistEntry {
  String cmd, out;
  HistEntry({required this.cmd, required this.out});
  Map<String, dynamic> toJson() => {'cmd': cmd, 'out': out};
  factory HistEntry.fromJson(Map<String, dynamic> j) =>
      HistEntry(cmd: j['cmd'] as String? ?? '', out: j['out'] as String? ?? '');
}

// ---------- настройки и прогресс ----------

class Config {
  String apiKey, provider, model, baseUrl, theme;
  Config({this.apiKey = '', this.provider = 'deepseek', this.model = '', this.baseUrl = '', this.theme = 'sage'});

  factory Config.fromJson(Map<String, dynamic> j) => Config(
        apiKey: j['api_key'] as String? ?? '',
        provider: j['provider'] as String? ?? 'deepseek',
        model: j['model'] as String? ?? '',
        baseUrl: j['base_url'] as String? ?? '',
        theme: j['theme'] as String? ?? 'sage',
      );

  Map<String, dynamic> toJson() => {'api_key': apiKey, 'provider': provider, 'model': model, 'base_url': baseUrl, 'theme': theme};
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
  Map<String, String> courseTitles = {};
  List<String> courseOrder = [];
  List<String> hiddenCourses = [];

  Progress();

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
    p.generated = ((j['generated'] as Map?) ?? {})
        .map((k, v) => MapEntry(k as String, ((v as List) as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList()));
    p.extraCourses = ((j['extra_courses'] as List?) ?? [])
        .map((c) => Course.fromJson(c as Map<String, dynamic>)).toList();
    p.achieved = (j['achievements'] as Map?)?.cast<String, String>() ?? {};
    p.courseTitles = (j['course_titles'] as Map?)?.cast<String, String>() ?? {};
    p.courseOrder = (j['course_order'] as List?)?.cast<String>() ?? [];
    p.hiddenCourses = (j['hidden_courses'] as List?)?.cast<String>() ?? [];
    return p;
  }

  Map<String, dynamic> toJson() => {
        'xp': xp, 'solved_total': solvedTotal, 'streak': streak,
        'last_course': lastCourse, 'last_day': lastDay,
        'completed': completed, 'quiz_done': quizDone, 'quiz_tries': quizTries,
        'hints': hints, 'generated': generated.map((k, v) => MapEntry(k, v.map((t) => t.toJson()).toList())),
        'extra_courses': extraCourses.map((c) => c.toJson()).toList(),
        'achievements': achieved,
        'course_titles': courseTitles, 'course_order': courseOrder, 'hidden_courses': hiddenCourses,
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
