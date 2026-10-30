// app_actions.dart — исполнитель MCP-подобных действий Термая.
// Навигация, курсы, уроки, терминал, тема, фон и настройки ИИ.
import 'package:flutter/material.dart';

import 'ai.dart';
import 'app_action.dart';
import 'models.dart';
import 'navigation.dart';
import 'store.dart';
import 'ui/ai_fallbacks.dart';
import 'ui/archive.dart';
import 'ui/background_settings.dart';
import 'ui/chat.dart';
import 'ui/chats.dart';
import 'ui/help.dart';
import 'ui/home.dart';
import 'ui/lesson.dart';
import 'ui/more.dart';
import 'ui/progress_map.dart';
import 'ui/review.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';
import 'ui/usage_screen.dart';
import 'ui/widgets.dart';

class AppActions {
  final AppController c;
  AppActions(this.c);

  NavigatorState? get _nav => rootNavigatorKey.currentState;
  BuildContext? get _ctx => rootNavigatorKey.currentContext;

  Future<String> execute(AppActionCall call) async {
    try {
      return await _run(call.name, call.args);
    } catch (e) {
      return _short(e);
    }
  }

  String _short(Object e) {
    var s = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return s.length > 220 ? '${s.substring(0, 220)}…' : s;
  }

  String _str(Map<String, dynamic> args, String key) =>
      (args[key] ?? '').toString().trim();

  double? _num(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  void _toast(String text) {
    final ctx = _ctx;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openNamed(String name, Widget Function() page) async {
    final nav = _nav;
    if (nav == null) throw 'навигация ещё не готова';
    if (ScreenObserver.has(name)) {
      nav.popUntil((r) => r.settings.name == name);
      return;
    }
    nav.push(pageRoute(page(), name: name));
    await Future<void>.delayed(const Duration(milliseconds: 180));
  }

  Course? _findCourse(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return c.courses.isEmpty ? null : c.cur;
    for (final course in c.allCourses) {
      if (course.id.toLowerCase() == q || course.title.toLowerCase() == q) {
        return course;
      }
    }
    for (final course in c.allCourses) {
      if (course.id.toLowerCase().contains(q) ||
          course.title.toLowerCase().contains(q)) {
        return course;
      }
    }
    return null;
  }

  Task? _findTask(Course course, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return c.currentTask;
    for (final task in course.tasks) {
      if (task.id.toLowerCase() == q || task.title.toLowerCase() == q) {
        return task;
      }
    }
    for (final task in course.tasks) {
      if (task.id.toLowerCase().contains(q) ||
          task.title.toLowerCase().contains(q)) {
        return task;
      }
    }
    return null;
  }

  int _visibleIndex(Course course) =>
      c.courses.indexWhere((x) => x.id == course.id);

  Future<String> _run(String name, Map<String, dynamic> args) async {
    // Синонимы: модели иногда называют действия по-своему.
    switch (name) {
      case 'open_settings':
        return _run('open_screen', {'screen': 'settings'});
      case 'open_archive':
        return _run('open_screen', {'screen': 'archive'});
      case 'open_chats':
        return _run('open_screen', {'screen': 'chats'});
      case 'open_usage':
        return _run('open_screen', {'screen': 'usage'});
      case 'open_help':
        return _run('open_screen', {'screen': 'help'});
      case 'open_background':
        return _run('open_screen', {'screen': 'background'});
      case 'open_fallbacks':
        return _run('open_screen', {'screen': 'fallbacks'});
      case 'open_review':
        return _run('open_screen', {'screen': 'review'});
      case 'open_progress':
        return _run('open_screen', {'screen': 'progress'});
      case 'open_home':
        return _run('open_screen', {'screen': 'home'});
      case 'write_terminal':
        return _run('fill_terminal', args);
      case 'solve_task':
        return _run('show_solution', args);
      case 'create_course':
        return _run('generate_course', args);
      case 'create_task':
        return _run('generate_task', args);
      case 'start_interview':
        return _run('open_interview', args);
      case 'open_task':
        return _run('open_lesson', args);
      case 'open_terminal':
        return _openTerminal();
    }

    switch (name) {
      case 'open_screen':
        return _openScreen(_str(args, 'screen').ifEmpty(_str(args, 'name')));
      case 'open_course':
        return _openCourse(
            _str(args, 'course').ifEmpty(_str(args, 'title')));
      case 'open_lesson':
        return _openLesson(
          course: _str(args, 'course'),
          task: _str(args, 'task'),
        );
      case 'open_chat':
        return _openChat(
            _str(args, 'chat').ifEmpty(_str(args, 'title')));
      case 'new_chat':
        if (ScreenObserver.current == 'InterviewScreen') {
          c.createInterviewChat(force: true);
          return '';
        }
        final active = c.activeChat;
        final taskContext = ScreenObserver.current == 'LessonScreen' ||
            (ScreenObserver.current == 'ChatScreen' &&
                active != null &&
                !active.isGeneral);
        if (taskContext) {
          c.createChatForCurrentTask();
        } else {
          c.createGeneralChat();
        }
        if (ScreenObserver.current != 'ChatScreen') {
          await _openNamed(
            'ChatScreen',
            () => ChatScreen(
              scope: taskContext ? ChatScope.task : ChatScope.general,
              resume: true,
            ),
          );
        }
        return '';
      case 'open_interview':
        return _openInterview();
      case 'select_course':
        return _selectCourse(_str(args, 'course'));
      case 'select_task':
        return _selectTask(_str(args, 'task'), _str(args, 'course'));
      case 'next_task':
        return _stepTask(1);
      case 'previous_task':
        return _stepTask(-1);
      case 'archive_course':
        return _archive(_str(args, 'course'));
      case 'unarchive_course':
        return _unarchive(_str(args, 'course'));
      case 'rename_course':
        return _renameCourse(_str(args, 'course'),
            _str(args, 'title').ifEmpty(_str(args, 'new_title')));
      case 'delete_course':
        return _deleteCourse(_str(args, 'course'));
      case 'generate_course':
        return _generateCourse(
            _str(args, 'goal').ifEmpty(_str(args, 'topic')));
      case 'generate_task':
        return _generateTask(
            _str(args, 'topic').ifEmpty(_str(args, 'goal')));
      case 'fill_course':
        return _fillCourse(_str(args, 'course'));
      case 'fill_terminal':
        return _fillTerminal(_str(args, 'text').ifEmpty(_str(args, 'command')));
      case 'run_terminal':
        return _runTerminal(_str(args, 'command').ifEmpty(_str(args, 'text')));
      case 'clear_terminal':
        c.termText = '';
        c.termInput.clear();
        c.termLine('  (вывод терминала очищен)');
        c.refreshTerminal();
        return '';
      case 'undo_terminal':
        c.undoCommand();
        return '';
      case 'submit_task':
        final err = await c.submitTask();
        if (err.isNotEmpty) _toast(err);
        return '';
      case 'show_solution':
        return _showSolution();
      case 'toggle_bookmark':
        final task = c.currentTask;
        if (task == null) return 'нет активной задачи';
        final key = c.cur.id + '|' + task.id;
        final had = c.prog.bookmarks.containsKey(key);
        c.toggleBookmark();
        _toast(had ? 'Закладка снята' : 'Задача в закладках');
        return '';
      case 'set_theme':
        return _setTheme(_str(args, 'theme'));
      case 'toggle_theme':
        await c.toggleLightTheme();
        return '';
      case 'set_background':
        return _setBackground(args);
      case 'set_button_brightness':
        final value = _num(args, 'value') ?? _num(args, 'brightness');
        if (value == null) return 'не указана яркость';
        await c.setButtonBrightness(value.clamp(0.6, 1.4).toDouble(),
            persist: true);
        _toast('Яркость кнопок: ${(c.config.buttonBrightness * 100).round()}%');
        return '';
      case 'set_ai':
        return _setAi(args);
      case 'reset_usage':
        c.resetUsage();
        _toast('Счётчик токенов обнулён');
        return '';
      case 'open_more':
        final ctx = _ctx;
        if (ctx == null) return 'меню недоступно';
        showMoreSheet(ctx);
        return '';
      default:
        return 'неизвестное действие «$name»';
    }
  }

  Future<String> _openScreen(String screen) async {
    final aliases = <String, String>{
      'главная': 'home',
      'домой': 'home',
      'настройки': 'settings',
      'архив': 'archive',
      'чаты': 'chats',
      'расход': 'usage',
      'токены': 'usage',
      'помощь': 'help',
      'фон': 'background',
      'резервные модели': 'fallbacks',
      'повторение': 'review',
      'карта': 'progress',
      'карта прогресса': 'progress',
      'маршрут': 'progress',
      'ещё': 'more',
      'еще': 'more',
      'чат': 'chat',
      'собеседование': 'interview',
      'задачи': 'tasks',
      'урок': 'lesson',
    };
    final key = screen.trim().toLowerCase();
    switch (aliases[key] ?? key) {
      case '':
        return 'не указан экран';
      case 'home':
        _nav?.popUntil((r) => r.isFirst);
        return '';
      case 'settings':
        await _openNamed('SettingsScreen', () => const SettingsScreen());
        return '';
      case 'archive':
        await _openNamed('ArchiveScreen', () => const ArchiveScreen());
        return '';
      case 'chats':
        await _openNamed('ChatsScreen', () => const ChatsScreen());
        return '';
      case 'usage':
        await _openNamed('UsageScreen', () => const UsageScreen());
        return '';
      case 'help':
        await _openNamed('HelpScreen', () => const HelpScreen());
        return '';
      case 'background':
        await _openNamed(
            'BackgroundSettingsScreen', () => const BackgroundSettingsScreen());
        return '';
      case 'fallbacks':
        await _openNamed('AiFallbacksScreen', () => const AiFallbacksScreen());
        return '';
      case 'review':
        await _openNamed('ReviewScreen', () => const ReviewScreen());
        return '';
      case 'progress':
        await _openNamed('ProgressMapScreen', () => const ProgressMapScreen());
        return '';
      case 'more':
        final ctx = _ctx;
        if (ctx == null) return 'меню недоступно';
        showMoreSheet(ctx);
        return '';
      case 'chat':
        c.ensureGeneralChat();
        await _openNamed(
          'ChatScreen',
          () => const ChatScreen(scope: ChatScope.general, resume: true),
        );
        return '';
      case 'interview':
        return _openInterview();
      case 'tasks':
        if (c.courses.isEmpty) return 'нет доступных курсов';
        await _openNamed(
            'TaskListScreen', () => TaskListScreen(courseIdx: c.courseIdx));
        return '';
      case 'lesson':
        return _openLesson();
      default:
        return 'неизвестный экран «$screen»';
    }
  }

  Future<String> _openInterview() async {
    if (c.courses.isEmpty) return 'нет доступных курсов';
    c.startInterview();
    if (!ScreenObserver.has('InterviewScreen')) {
      c.createInterviewChat(force: true);
    } else {
      // Возвращаемся на открытый экран собеседования: если активным стал
      // обычный чат, восстанавливаем последнюю беседу-собеседование.
      final active = c.activeChat;
      if (active == null || active.taskId != '__interview__') {
        final interviews = c.prog.mentorChats
            .where((x) => x.taskId == '__interview__')
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (interviews.isNotEmpty) {
          c.openChat(interviews.first.id);
        } else {
          c.createInterviewChat(force: true);
        }
      }
    }
    await _openNamed('InterviewScreen',
        () => const ChatScreen(interview: true, resume: true));
    return '';
  }

  Future<String> _openCourse(String query) async {
    final course = _findCourse(query);
    if (course == null) return 'курс не найден';
    final i = _visibleIndex(course);
    if (i < 0) return 'курс «${course.title}» в архиве — сначала верни его';
    c.switchCourseSilent(i);
    await _openNamed(
        'TaskListScreen', () => TaskListScreen(courseIdx: c.courseIdx));
    return '';
  }

  Future<String> _openLesson({String course = '', String task = ''}) async {
    if (c.courses.isEmpty) return 'нет доступных курсов';
    Course? target = course.trim().isEmpty ? c.cur : _findCourse(course);
    if (target == null) return 'курс не найден';
    final i = _visibleIndex(target);
    if (i < 0) return 'курс «${target.title}» в архиве';
    c.switchCourseSilent(i);
    if (task.trim().isNotEmpty) {
      final t = _findTask(target, task);
      if (t == null) return 'задача не найдена';
      final ti = target.tasks.indexOf(t);
      if (ti >= 0) c.selectTask(ti);
    } else if (c.currentTask == null && target.tasks.isNotEmpty) {
      c.selectTask(0);
    }
    await _openNamed('LessonScreen', () => const LessonScreen());
    return '';
  }

  Future<String> _openTerminal() async {
    if (c.courses.isEmpty) return 'нет доступных курсов';
    if (c.cur.isTheory) return 'в этом курсе нет терминала';
    if (c.currentTask == null) return 'нет активной задачи';
    await _openNamed('LessonScreen', () => const LessonScreen());
    await Future<void>.delayed(const Duration(milliseconds: 120));
    c.requestLessonSlide(2);
    return '';
  }

  Future<String> _openChat(String query) async {
    final q = query.trim().toLowerCase();
    MentorChat? found;
    if (q.isEmpty) {
      found = c.activeChat;
    } else {
      for (final chat in c.prog.mentorChats) {
        if (chat.id.toLowerCase() == q || chat.title.toLowerCase() == q) {
          found = chat;
          break;
        }
      }
      if (found == null) {
        for (final chat in c.prog.mentorChats) {
          if (chat.title.toLowerCase().contains(q)) {
            found = chat;
            break;
          }
        }
      }
    }
    if (found == null) {
      if (q.isNotEmpty) return 'чат не найден';
      c.ensureGeneralChat();
      await _openNamed(
        'ChatScreen',
        () => const ChatScreen(scope: ChatScope.general, resume: true),
      );
      return '';
    }
    if (found.taskId == '__interview__') {
      c.openChat(found.id);
      c.startInterview();
      await _openNamed('InterviewScreen',
          () => const ChatScreen(interview: true, resume: true));
    } else {
      if (!found.isGeneral &&
          !c.courses.any((x) => x.id == found!.courseId)) {
        return 'курс этого чата в архиве — сначала верни его';
      }
      c.openChat(found.id);
      await _openNamed(
        'ChatScreen',
        () => ChatScreen(
          scope: found!.isGeneral ? ChatScope.general : ChatScope.task,
          resume: true,
        ),
      );
    }
    return '';
  }

  Future<String> _selectCourse(String query) async {
    final course = _findCourse(query);
    if (course == null) return 'курс не найден';
    final i = _visibleIndex(course);
    if (i < 0) return 'курс в архиве';
    c.switchCourseSilent(i);
    return '';
  }

  Future<String> _selectTask(String query, String courseQuery) async {
    if (c.courses.isEmpty) return 'нет доступных курсов';
    final course =
        courseQuery.trim().isEmpty ? c.cur : _findCourse(courseQuery);
    if (course == null) return 'курс не найден';
    final i = _visibleIndex(course);
    if (i < 0) return 'курс в архиве';
    c.switchCourseSilent(i);
    final task = _findTask(course, query);
    if (task == null) return 'задача не найдена';
    final ti = course.tasks.indexOf(task);
    if (ti < 0) return 'задача не найдена';
    c.selectTask(ti);
    return '';
  }

  Future<String> _stepTask(int delta) async {
    if (c.courses.isEmpty) return 'нет доступных курсов';
    final tasks = c.cur.tasks;
    if (tasks.isEmpty) return 'в курсе нет задач';
    final next = (c.viewIdx + delta).clamp(0, tasks.length - 1).toInt();
    c.selectTask(next);
    return '';
  }

  Future<String> _archive(String query) async {
    final course = _findCourse(query);
    if (course == null) return 'курс не найден';
    c.archiveCourse(course.id);
    _toast('«${course.title}» в архиве');
    return '';
  }

  Future<String> _unarchive(String query) async {
    final course = _findCourse(query);
    if (course == null) return 'курс не найден';
    c.unarchiveCourse(course.id);
    _toast('«${course.title}» возвращён');
    return '';
  }

  Future<String> _renameCourse(String query, String title) async {
    if (title.trim().isEmpty) return 'пустое название';
    final course = _findCourse(query);
    if (course == null) return 'курс не найден';
    c.renameCourseById(course.id, title);
    _toast('Курс переименован');
    return '';
  }

  Future<String> _deleteCourse(String query) async {
    final course = _findCourse(query);
    if (course == null) return 'курс не найден';
    if (c.prog.archived.contains(course.id)) {
      c.deleteArchivedCourse(course.id);
      _toast('Курс удалён из архива');
      return '';
    }
    final i = _visibleIndex(course);
    if (i < 0) return 'курс не найден';
    if (c.courses.length <= 1) return 'нельзя удалить последний курс';
    c.deleteCourse(i);
    _toast('Курс удалён');
    return '';
  }

  Future<String> _generateCourse(String goal) async {
    if (goal.trim().isEmpty) return 'не указана цель курса';
    _toast('Термай собирает программу…');
    final err = await c.generateCourses(goal);
    if (err.isEmpty && c.courses.isNotEmpty) {
      // Показываем свежую программу, а не оставляем пользователя в чате.
      await _openNamed(
          'TaskListScreen', () => TaskListScreen(courseIdx: c.courseIdx));
    }
    return err;
  }

  Future<String> _generateTask(String topic) async {
    if (topic.trim().isEmpty) return 'не указана тема задачи';
    if (c.courses.isEmpty) return 'нет доступных курсов';
    _toast('Термай пишет задачу…');
    final err = await c.generateTask(topic);
    return err;
  }

  Future<String> _fillCourse(String query) async {
    if (c.courses.isEmpty) return 'нет доступных курсов';
    final course = query.trim().isEmpty ? c.cur : _findCourse(query);
    if (course == null) return 'курс не найден';
    _toast('Термай наполняет курс задачами…');
    return await c.fillCourse(course);
  }

  Future<String> _ensureTerminal() async {
    if (c.courses.isEmpty) return 'нет доступных курсов';
    if (c.cur.isTheory) return 'в этом курсе нет терминала';
    if (c.currentTask == null) return 'нет активной задачи';
    await _openNamed('LessonScreen', () => const LessonScreen());
    await Future<void>.delayed(const Duration(milliseconds: 120));
    c.requestLessonSlide(2);
    return '';
  }

  Future<String> _fillTerminal(String text) async {
    if (text.trim().isEmpty) return 'пустой текст команды';
    final err = await _ensureTerminal();
    if (err.isNotEmpty) return err;
    c.termInput.text = text;
    c.termInput.selection =
        TextSelection.collapsed(offset: c.termInput.text.length);
    _toast('Команда вставлена в терминал');
    return '';
  }

  Future<String> _runTerminal(String command) async {
    if (command.trim().isEmpty) return 'пустая команда';
    final err = await _ensureTerminal();
    if (err.isNotEmpty) return err;
    c.termInput.text = command;
    c.termInput.selection =
        TextSelection.collapsed(offset: c.termInput.text.length);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await c.runCommand(command);
    return '';
  }

  Future<String> _showSolution() async {
    final task = c.currentTask;
    if (task == null) return 'нет активной задачи';
    await _openNamed('LessonScreen', () => const LessonScreen());
    await Future<void>.delayed(const Duration(milliseconds: 120));
    c.requestLessonSlide(
        (c.cur.isTheory || (c.currentTask?.isExam ?? false)) ? 2 : 3);
    await c.loadSolution(task);
    return '';
  }

  Future<String> _setTheme(String raw) async {
    var id = raw.trim().toLowerCase();
    if (id.isEmpty) return 'не указана тема';
    if (id == 'black' ||
        id == 'dark modern' ||
        id == 'чёрная' ||
        id == 'черная' ||
        id == 'тёмная' ||
        id == 'темная') {
      id = 'dark';
    }
    if (id == 'blue' || id == 'синяя' || id == 'голубая') id = 'navy';
    if (id == 'light' ||
        id == 'day' ||
        id == 'светлая' ||
        id == 'дневная' ||
        id == 'белая') {
      id = 'light';
    }
    if (!themePresets.any((p) => p.id == id)) {
      return 'неизвестная тема «$raw» (доступны dark, light и navy)';
    }
    c.config.theme = id;
    c.config.themeAuto = false;
    await c.saveConfig(autofill: false);
    _toast('Тема: ${presetById(id).title}');
    return '';
  }

  Future<String> _setBackground(Map<String, dynamic> args) async {
    final blur = _num(args, 'blur');
    final dim = _num(args, 'dim');
    if (blur == null && dim == null) return 'не указаны blur или dim';
    if (blur != null) c.config.bgBlur = blur.clamp(0, 40).toDouble();
    if (dim != null) c.config.bgDim = dim.clamp(0, 0.9).toDouble();
    await c.saveConfig(autofill: false);
    _toast('Фон обновлён');
    return '';
  }

  Future<String> _setAi(Map<String, dynamic> args) async {
    final provider = _str(args, 'provider');
    final model = _str(args, 'model');
    final key = _str(args, 'api_key')
        .ifEmpty(_str(args, 'key'))
        .ifEmpty(_str(args, 'apiKey'));
    final base = _str(args, 'base_url').ifEmpty(_str(args, 'baseUrl'));
    if (provider.isEmpty && model.isEmpty && key.isEmpty && base.isEmpty) {
      return 'не указаны параметры ИИ';
    }
    if (provider.isNotEmpty) {
      final p = findProvider(provider);
      if (p.id != provider && p.title.toLowerCase() != provider.toLowerCase()) {
        return 'неизвестный провайдер «$provider»';
      }
      c.config.provider = p.id;
    }
    if (model.isNotEmpty) c.config.model = model;
    if (key.isNotEmpty) c.config.apiKey = key;
    if (base.isNotEmpty) c.config.baseUrl = base;
    await c.saveConfig(autofill: false);
    _toast('Настройки ИИ сохранены');
    return '';
  }
}

extension _EmptyX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
