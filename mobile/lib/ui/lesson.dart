// lesson.dart — экран задачи: строка слайдов (Справка/Задача/Терминал/Решение),
// свайп пальцем, плавающий низ терминала над клавиатурой.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../editor_verify.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'app_background.dart';
import 'chat.dart';
import 'design_system.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  DateTime? _studySince;
  String _search = '';
  List<int> _answers = const [];
  String _answersFor = '';
  String _taskId = '';
  int _tabIdx = 0; // текущий слайд (для resize-логики терминала)
  int _lastSlideSeq = 0;
  Offset _swipeStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startStudy();
    if (diagAutoLesson) _tabIdx = 2;
    _lastSlideSeq = controller.lessonSlideSeq;
    if (controller.lessonSlideRequest >= 0) {
      _tabIdx = controller.lessonSlideRequest;
      controller.lessonSlideRequest = -1;
    }
    _taskId = controller.currentTask?.id ?? '';
    _syncAnswers();
    controller.addListener(_onController);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeCompletionDialog());
  }

  /// Слушаем контроллер только ради смены задачи и окна «выполнено».
  /// Раньше на каждый вывод терминала перестраивался весь урок вместе
  /// с markdown-слайдами — отсюда были фризы при работе в терминале.
  void _onController() {
    if (!mounted) return;
    final id = controller.currentTask?.id ?? '';
    if (id != _taskId) {
      _taskId = id;
      setState(_syncAnswers);
    }
    if (controller.lessonSlideSeq != _lastSlideSeq) {
      _lastSlideSeq = controller.lessonSlideSeq;
      final task = controller.currentTask;
      final last = task == null ? 2 : _slideNames(task).length - 1;
      final req = controller.lessonSlideRequest.clamp(0, last).toInt();
      controller.lessonSlideRequest = -1;
      if (mounted) setState(() => _tabIdx = req);
    }
    _maybeCompletionDialog();
  }

  void _syncAnswers() {
    final t = controller.currentTask;
    _answersFor = t?.id ?? '';
    _answers = List.filled(t?.quiz.length ?? 0, -1, growable: false);
  }

  List<String> _slideNames(Task t) {
    if (t.hasEditor) return const ['Справка', 'Задача', 'Редактор', 'Решение'];
    return (controller.cur.isTheory || t.isExam)
        ? const ['Справка', 'Задача', 'Решение']
        : const ['Справка', 'Задача', 'Терминал', 'Решение'];
  }

  void _startStudy() {
    if (controller.currentTask == null) return;
    _studySince ??= DateTime.now();
  }

  void _pauseStudy() {
    final start = _studySince;
    _studySince = null;
    if (start == null) return;
    final seconds = DateTime.now().difference(start).inSeconds;
    if (seconds > 0) unawaited(controller.addStudySeconds(seconds));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startStudy();
    } else {
      _pauseStudy();
    }
  }

  @override
  void dispose() {
    _pauseStudy();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onController);
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Окно «Задача выполнена»: анимация, XP, комментарий проверяющего,
  /// достижения. Закрытие — переход к списку задач курса.
  void _maybeCompletionDialog() {
    final lc = controller.lastCompletion;
    if (lc == null) return;
    controller.lastCompletion = null;
    final achievements = (lc['achievements'] as List).cast<String>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: C.good.withAlpha(120)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.elasticOut,
                  builder: (context, v, _) => Transform.scale(
                    scale: v,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: C.good,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: C.good.withAlpha(90),
                              blurRadius: 26,
                              spreadRadius: 3)
                        ],
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 42),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Задача выполнена!',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: C.text)),
                const SizedBox(height: 6),
                Text(lc['title'] as String,
                    style: TextStyle(fontSize: 13, color: C.muted)),
                const SizedBox(height: 10),
                if ((lc['xp'] as int) > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        color: C.good.withAlpha(40),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('+${lc['xp']} XP',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: C.good)),
                  ),
                if ((lc['peeked'] as bool)) ...[
                  const SizedBox(height: 8),
                  Text('Решение подсмотрено — XP не начисляются.',
                      style: TextStyle(fontSize: 12, color: C.muted)),
                ],
                if ((lc['comment'] as String).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                          left: BorderSide(color: C.secondary, width: 3)),
                    ),
                    child: Text(lc['comment'] as String,
                        style: TextStyle(
                            fontSize: 13, height: 1.4, color: C.text)),
                  ),
                ],
                if (achievements.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: caption('НОВЫЕ ДОСТИЖЕНИЯ', color: C.accent)),
                  const SizedBox(height: 6),
                  for (var i = 0; i < achievements.length; i++)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 350 + i * 150),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset((1 - v) * 24, 0),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Icon(Icons.workspace_premium,
                                  color: C.warn, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(achievements[i],
                                      style: TextStyle(
                                          fontSize: 13, color: C.text))),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx); // закрыть окно
                    Navigator.of(context).pop(); // урок → список задач курса
                  },
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: const Text('К списку задач'),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = controller.currentTask;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
      ),
      body: AppBackdrop(
        child: Builder(
          builder: (context) {
            if (t == null) {
              return Center(
                  child: Text('Задач нет — создай через «Ещё» → Задача от ИИ.',
                      style: TextStyle(color: C.muted)));
            }
            // после завершения задачи контроллер сразу открывает следующую —
            // ответы теста нужно пересоздать под её вопросы
            if (_answersFor != t.id) {
              _answersFor = t.id;
              _answers = List.filled(t.quiz.length, -1);
            }
            // своя строка слайдов: TabBar падал с null-check и рендерил серую заглушку.
            // В курсах-теориях терминал не нужен; задачи с editor получают
            // отдельный слайд «Редактор» вместо терминала.
            final theory = controller.cur.isTheory || t.isExam;
            final slideNames = _slideNames(t);
            final last = slideNames.length - 1;
            final current = _tabIdx.clamp(0, last);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Row(children: [
                    for (var i = 0; i < slideNames.length; i++)
                      Expanded(
                          child: _SlideTab(
                        title: slideNames[i],
                        active: current == i,
                        onTap: () => setState(() => _tabIdx = i),
                      )),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Listener(
                    onPointerDown: (e) => _swipeStart = e.position,
                    onPointerUp: (e) {
                      final dx = e.position.dx - _swipeStart.dx;
                      final dy = (e.position.dy - _swipeStart.dy).abs();
                      if (dx.abs() > 90 && dx.abs() > dy * 2) {
                        if (dx < 0 && current < last)
                          setState(() => _tabIdx = current + 1);
                        if (dx > 0 && current > 0)
                          setState(() => _tabIdx = current - 1);
                      }
                    },
                    child: RepaintBoundary(
                      child: IndexedStack(
                        index: current,
                        children: [
                          _HelpSlide(
                              t: t,
                              courseTasks: controller.cur.tasks,
                              onJump: (i) {
                                controller.selectTask(i);
                                setState(() => _search = '');
                              },
                              search: _search,
                              onSearch: (v) => setState(() => _search = v)),
                          _LiveSlide(
                            active: current == 1,
                            builder: () => _TaskSlide(
                              t: t,
                              answers: _answers,
                              onAnswer: (qi, oi) => setState(() {
                                if (qi >= _answers.length) {
                                  _answers = [
                                    ..._answers,
                                    ...List.filled(
                                        qi - _answers.length + 1, -1),
                                  ];
                                }
                                _answers[qi] = oi;
                              }),
                              onSnack: _snack,
                            ),
                          ),
                          if (t.hasEditor) ...[
                            _LiveSlide(
                              active: current == 2,
                              builder: () =>
                                  _EditorSlide(t: t, onSnack: _snack),
                            ),
                            _LiveSlide(
                              active: current == 3,
                              builder: () =>
                                  _SolutionSlide(t: t, onSnack: _snack),
                            ),
                          ] else if (theory)
                            _LiveSlide(
                              active: current == 2,
                              builder: () =>
                                  _SolutionSlide(t: t, onSnack: _snack),
                            )
                          else ...[
                            _LiveSlide(
                              active: current == 2,
                              builder: () => _TermSlide(onSnack: _snack),
                            ),
                            _LiveSlide(
                              active: current == 3,
                              builder: () =>
                                  _SolutionSlide(t: t, onSnack: _snack),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// _SlideTab — вкладка в строке слайдов урока.
class _SlideTab extends StatelessWidget {
  final String title;
  final bool active;
  final VoidCallback onTap;
  const _SlideTab(
      {required this.title, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                  color: active ? C.accent : C.muted)),
        ),
        Container(height: 3, color: active ? C.accent : Colors.transparent),
      ]),
    );
  }
}

// ---------- слайд 1: Справка ----------

class _HelpSlide extends StatelessWidget {
  final Task t;
  final List<Task> courseTasks;
  final void Function(int taskIndex) onJump;
  final String search;
  final ValueChanged<String> onSearch;
  const _HelpSlide({
    required this.t,
    required this.courseTasks,
    required this.onJump,
    required this.search,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final q = search.trim().toLowerCase();
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              onChanged: onSearch,
              decoration: InputDecoration(
                hintText: 'Поиск по справке всего курса…',
                prefixIcon: Icon(Icons.search, color: C.muted),
              ),
            ),
            const SizedBox(height: 14),
            if (q.isEmpty)
              ...t.theory.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: MarkdownBody(
                        data: p, selectable: true, styleSheet: mdStyle()),
                  ))
            else ...[
              // Поиск идёт по справке ВСЕГО курса: попадания из других задач
              // кликабельны и переносят в соответствующую задачу.
              ..._courseHits(q).map((hit) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: InkWell(
                      onTap: hit.key == _currentIdx ? null : () => onJump(hit.key),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: hit.key == _currentIdx
                              ? C.card
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: C.border.withAlpha(90)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hit.key == _currentIdx
                                  ? 'Текущая задача'
                                  : courseTasks[hit.key].title,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: C.accent),
                            ),
                            const SizedBox(height: 6),
                            MarkdownBody(
                                data: hit.value,
                                selectable: true,
                                styleSheet: mdStyle()),
                          ],
                        ),
                      ),
                    ),
                  )),
              if (_courseHits(q).isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: Text('Ничего не найдено.',
                          style: TextStyle(color: C.muted))),
                ),
            ],
          ],
        ),
        // TERMAI в левом нижнем углу справки: спроси ментора, он дополнит.
        Positioned(
          left: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'help-mentor',
            backgroundColor: C.accent,
            foregroundColor: C.bg,
            onPressed: () => Navigator.of(context)
                .push(pageRoute(const ChatScreen(scope: ChatScope.task))),
            icon: Icon(Icons.support_agent, size: 20),
            label: Text('TERMAI',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  int get _currentIdx => courseTasks.indexWhere((x) => x.id == t.id);

  List<MapEntry<int, String>> _courseHits(String q) {
    final hits = <MapEntry<int, String>>[];
    for (var i = 0; i < courseTasks.length; i++) {
      for (final p in courseTasks[i].theory) {
        if (p.toLowerCase().contains(q)) hits.add(MapEntry(i, p));
      }
    }
    return hits;
  }
}

MarkdownStyleSheet mdStyle() => MarkdownStyleSheet(
      p: TextStyle(fontSize: 14.5, height: 1.45, color: C.text),
      h1: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.text),
      h2: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.text),
      h3: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: C.text),
      code: TextStyle(
          fontSize: 13,
          color: C.accent,
          fontFamily: 'monospace',
          backgroundColor: C.card2),
      codeblockDecoration: BoxDecoration(
        color: C.termBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      listBullet: TextStyle(fontSize: 14.5, height: 1.4, color: C.text),
      blockquoteDecoration: BoxDecoration(
        border:
            Border(left: BorderSide(color: C.accent.withAlpha(120), width: 3)),
        color: C.card2.withAlpha(80),
      ),
      blockquotePadding: const EdgeInsets.all(10),
    );

// ---------- слайд 2: Задача ----------

class _TaskSlide extends StatelessWidget {
  final Task t;
  final List<int> answers;
  final void Function(int qi, int oi) onAnswer;
  final void Function(String) onSnack;
  const _TaskSlide(
      {required this.t,
      required this.answers,
      required this.onAnswer,
      required this.onSnack});

  @override
  Widget build(BuildContext context) {
    final needQuiz =
        t.quiz.isNotEmpty && !controller.quizDone(t) && !controller.isDone(t);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.title,
            style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w900, height: 1.2)),
        const SizedBox(height: 8),
        if (controller.reviewKey != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: C.secondary.withAlpha(28),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: C.secondary, width: 3)),
            ),
            child: Text('РЕЖИМ ПОВТОРЕНИЯ — освежи память и сдай снова',
                style: TextStyle(fontSize: 12.5, color: C.text)),
          ),
        Row(children: [
          Text(
              t.isExam
                  ? 'экзамен'
                  : (controller.cur.isTheory
                      ? 'урок'
                      : (t.isQuiz ? 'тест' : 'практика')),
              style: TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(width: 10),
          difficultyDots(t.difficulty),
          const SizedBox(width: 10),
          Text('+${t.xp} XP',
              style: TextStyle(
                  fontSize: 12, color: C.accent, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        cardBox(
          accent: C.accent.withAlpha(140),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            caption('Задача', color: C.accent),
            const SizedBox(height: 8),
            MarkdownBody(data: t.goal, styleSheet: mdStyle()),
          ]),
        ),
        if (t.check.isNotEmpty) ...[
          const SizedBox(height: 10),
          cardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                caption('Критерий проверки', color: C.secondary),
                const SizedBox(height: 5),
                Text(t.check,
                    style:
                        TextStyle(fontSize: 12.5, height: 1.4, color: C.text)),
                if (t.expected.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Ожидаемый результат: ${t.expected}',
                      style: AppText.caption.copyWith(color: C.muted)),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                final q = controller.cur.isTheory
                    ? 'Объясни тему «${t.title}»: главную идею, примеры и на что обратить внимание. Не давай сразу готовый ответ — сначала подсказку.'
                    : 'Объясни задачу «${t.title}»: что требуется, на что обратить внимание и в каком порядке действовать. Не давай сразу готовых команд — сначала идея.';
                Navigator.of(context).push(pageRoute(ChatScreen(
                  scope: ChatScope.task,
                  autoQuestion: q,
                )));
              },
              icon: Icon(Icons.emoji_objects_outlined, color: C.accent),
              label:
                  Text('Объяснить задание', style: TextStyle(color: C.accent)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: controller.toggleBookmark,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(52, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: Icon(
                controller.isBookmarked(t) ? Icons.star : Icons.star_border,
                size: 20,
                color: controller.isBookmarked(t) ? C.warn : C.muted),
          ),
        ]),
        const SizedBox(height: 18),
        if (needQuiz) ...[
          caption('Тест по теории', color: C.accent),
          const SizedBox(height: 10),
          _QuizBlock(
              t: t, answers: answers, onAnswer: onAnswer, onSnack: onSnack),
        ],
        if ((controller.cur.isTheory || t.isExam) &&
            controller.quizDone(t) &&
            !controller.isDone(t)) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => controller.completeTheoryTask(t),
              child: const Text('Завершить задачу'),
            ),
          ),
        ],
        if (t.hints.isNotEmpty) ...[
          caption('Подсказки'),
          const SizedBox(height: 8),
          for (var i = 0; i < t.hints.length && i < 2; i++)
            _HintTile(t: t, index: i),
        ],
        const SizedBox(height: 30),
      ],
    );
  }
}

class _QuizBlock extends StatelessWidget {
  final Task t;
  final List<int> answers;
  final void Function(int qi, int oi) onAnswer;
  final void Function(String) onSnack;
  const _QuizBlock(
      {required this.t,
      required this.answers,
      required this.onAnswer,
      required this.onSnack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var qi = 0; qi < t.quiz.length; qi++) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${qi + 1}. ${t.quiz[qi].question}',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3)),
          ),
          const SizedBox(height: 8),
          for (var oi = 0; oi < t.quiz[qi].options.length; oi++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => onAnswer(qi, oi),
                child: cardBox(
                  accent: answers[qi] == oi ? C.accent : null,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [
                    Icon(
                        answers[qi] == oi
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: answers[qi] == oi ? C.accent : C.muted),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(t.quiz[qi].options[oi],
                            style: const TextStyle(fontSize: 14, height: 1.3))),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
        FilledButton(
          onPressed: () async {
            final err = await controller.checkQuiz(t, answers);
            if (!context.mounted) return;
            onSnack(err.isEmpty
                ? ((controller.cur.isTheory || t.isExam)
                    ? '✓ Тест пройден — задача завершена'
                    : '✓ Тест пройден — практика открыта')
                : err);
          },
          child: const Text('Проверить тест'),
        ),
      ],
    );
  }
}

class _HintTile extends StatelessWidget {
  final Task t;
  final int index;
  const _HintTile({required this.t, required this.index});

  @override
  Widget build(BuildContext context) {
    final used = (controller.prog.hints[controller.cur.id]?[t.id] ?? 0) > index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          collapsedBackgroundColor: C.card,
          backgroundColor: C.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: C.border)),
          collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: C.border)),
          title: Text('Подсказка ${index + 1}',
              style: TextStyle(fontSize: 14, color: C.text)),
          onExpansionChanged: (open) {
            if (open && !used) {
              final m = controller.prog.hints[controller.cur.id] ?? {};
              m[t.id] = index + 1;
              controller.prog.hints[controller.cur.id] = m;
              controller.saveProgress();
            }
          },
          children: [
            Align(
                alignment: Alignment.centerLeft,
                child:
                    MarkdownBody(data: t.hints[index], styleSheet: mdStyle()))
          ],
        ),
      ),
    );
  }
}

// ---------- слайд 3: Редактор YAML/кода ----------

class _EditorSlide extends StatefulWidget {
  final Task t;
  final void Function(String) onSnack;
  const _EditorSlide({required this.t, required this.onSnack});

  @override
  State<_EditorSlide> createState() => _EditorSlideState();
}

class _EditorSlideState extends State<_EditorSlide> {
  late _CodeController _text;
  Timer? _timer;
  EditorCheck? _check;
  bool _submitting = false;
  String _lastSaved = '';

  @override
  void initState() {
    super.initState();
    _text = _CodeController(
      controller.editorDraft(widget.t),
      widget.t.editorLanguage,
    )..addListener(_changed);
    _lastSaved = _text.text;
    _validate();
  }

  @override
  void didUpdateWidget(covariant _EditorSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.t.id != widget.t.id) {
      _timer?.cancel();
      if (_text.text != _lastSaved) {
        controller.saveEditorDraft(oldWidget.t, _text.text);
      }
      _text
        ..removeListener(_changed)
        ..dispose();
      _text = _CodeController(
        controller.editorDraft(widget.t),
        widget.t.editorLanguage,
      )..addListener(_changed);
      _lastSaved = _text.text;
      _check = null;
      _validate();
    }
  }

  void _changed() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 380), () {
      controller.saveEditorDraft(widget.t, _text.text);
      _lastSaved = _text.text;
      _validate();
    });
  }

  void _validate() {
    final result = verifyEditorTask(widget.t, _text.text);
    if (mounted) setState(() => _check = result);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final err = await controller.submitEditorTask(widget.t, _text.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err.isNotEmpty) {
      widget.onSnack(err);
    } else {
      widget.onSnack('✓ Проверка пройдена');
    }
  }

  Future<void> _reset() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Сбросить редактор?',
      message: 'Черновик вернётся к исходному шаблону.',
      confirmLabel: 'Сбросить',
      destructive: false,
    );
    if (!ok) return;
    _text.text = widget.t.editorStarter;
    controller.saveEditorDraft(widget.t, _text.text);
    _lastSaved = _text.text;
    _validate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_text.text != _lastSaved) {
      controller.saveEditorDraft(widget.t, _text.text);
    }
    _text.removeListener(_changed);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.t.editorLanguage.toUpperCase();
    final check = _check;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 140),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.code, size: 17, color: C.accent),
              const SizedBox(width: 7),
              Text('$language-редактор',
                  style: AppText.section.copyWith(color: C.accent)),
              const Spacer(),
              if (check != null && check.ok)
                Icon(Icons.check_circle_outline, size: 17, color: C.good),
            ]),
            const SizedBox(height: 6),
            Text(
              'Проверяется структура, а не только слова. Ошибка покажет '
              'строку и позицию.',
              style: AppText.caption.copyWith(color: C.muted),
            ),
            if (check != null && !check.ok) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: C.warn.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: C.warn.withAlpha(90)),
                ),
                child: Text(check.message,
                    style:
                        TextStyle(fontSize: 11.5, height: 1.3, color: C.text)),
              ),
            ],
            if (check != null && check.ok) ...[
              const SizedBox(height: 6),
              Text('Структура в порядке. Можно проверять задачу.',
                  style: TextStyle(fontSize: 11.5, color: C.good)),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: C.termBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (check?.ok == false) ? C.warn : C.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: TextField(
                  key: const ValueKey('editor-field'),
                  controller: _text,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                    color: C.text,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                    hintText: '# введи конфигурацию…',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton(
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(92, 44),
                ),
                child: const Text('Сбросить'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting
                      ? 'Проверяю…'
                      : 'Проверить ${language.isEmpty ? 'код' : language}'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _CodeController extends TextEditingController {
  final String language;
  _CodeController(String text, this.language) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing || language != 'yaml' || text.isEmpty) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    final base = style ?? TextStyle(color: C.text);
    final spans = <TextSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#')) {
        spans.add(TextSpan(
            text: line,
            style: base.copyWith(color: C.muted, fontStyle: FontStyle.italic)));
      } else {
        final m = RegExp(r'^(\s*)(-\s+)?([^:#\n]+?)(:)(.*)$').firstMatch(line);
        if (m != null) {
          spans.add(TextSpan(text: m.group(1) ?? '', style: base));
          if ((m.group(2) ?? '').isNotEmpty) {
            spans.add(TextSpan(
                text: m.group(2), style: base.copyWith(color: C.accent)));
          }
          spans.add(TextSpan(
              text: m.group(3),
              style: base.copyWith(
                  color: C.secondary, fontWeight: FontWeight.w700)));
          spans.add(
              TextSpan(text: m.group(4), style: base.copyWith(color: C.muted)));
          final value = m.group(5) ?? '';
          spans.add(TextSpan(
              text: value,
              style: base.copyWith(
                color: value.trim().startsWith('#') ? C.muted : C.text,
                fontStyle: value.trim().startsWith('#')
                    ? FontStyle.italic
                    : FontStyle.normal,
              )));
        } else {
          spans.add(TextSpan(text: line, style: base));
        }
      }
      if (i < lines.length - 1) spans.add(TextSpan(text: '\n', style: base));
    }
    return TextSpan(style: base, children: spans);
  }
}

// ---------- слайд 3: Терминал ----------

class _TermSlide extends StatefulWidget {
  final void Function(String) onSnack;
  const _TermSlide({required this.onSnack});
  @override
  State<_TermSlide> createState() => _TermSlideState();
}

class _TermSlideState extends State<_TermSlide> {
  // Общее поле ввода: ИИ вставляет команду прямо в него действием.
  TextEditingController get _input => controller.termInput;
  final _pageScroll = ScrollController();
  final _consoleScroll = ScrollController();
  String _lastTerm = '';

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
  }

  void _onInputChanged() => _scrollToConsoleEnd();

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _pageScroll.dispose();
    _consoleScroll.dispose();
    super.dispose();
  }

  void _run() {
    final cmd = _input.text;
    if (cmd.trim().isEmpty || controller.termBusy) return;
    // runCommand синхронно добавляет строку команды в историю до первого
    // await. Только после этого очищаем редактируемое поле.
    unawaited(controller.runCommand(cmd));
    _input.clear();
  }

  void _scrollToConsoleEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScroll.hasClients) {
        _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (controller.termText != _lastTerm) {
      _lastTerm = controller.termText;
      _scrollToConsoleEnd();
    }
    final t = controller.currentTask;
    // слайд скроллится ЦЕЛИКОМ: консоль фиксированной высоты не сжимается
    // ни клавиатурой, ни чем-либо ещё — страница просто прокручивается
    return SingleChildScrollView(
      controller: _pageScroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((t?.expected ?? '').isNotEmpty) ...[
            cardBox(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    caption('Ожидаемый вывод'),
                    const SizedBox(height: 6),
                    MarkdownBody(data: t!.expected, styleSheet: mdStyle()),
                  ]),
            ),
            const SizedBox(height: 12),
          ],
          // консоль: полэкрана, вывод прокручивается внутри
          Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.5,
            decoration: BoxDecoration(
              color: C.termBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.border),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
                child: Row(children: [
                  Text('Терминал',
                      style: TextStyle(fontSize: 11, color: C.muted)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Чат с ментором',
                    onPressed: () => Navigator.of(context).push(
                        pageRoute(const ChatScreen(scope: ChatScope.task))),
                    icon: Icon(Icons.chat_bubble_outline,
                        size: 17, color: C.secondary),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Отменить команду',
                    onPressed: controller.undoCommand,
                    icon: Icon(Icons.undo, size: 17, color: C.muted),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Очистить вывод',
                    onPressed: () {
                      controller.termText = '';
                      controller.termLine('  (вывод терминала очищен)');
                      controller.refreshTerminal();
                    },
                    icon: Icon(Icons.refresh, size: 17, color: C.muted),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _consoleScroll,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ListenableBuilder(
                      listenable: _input,
                      builder: (context, _) {
                        final draft = _input.text;
                        final live = draft.isEmpty
                            ? controller.termText
                            : '${controller.termText}${controller.prompt}$draft';
                        return Text(
                          live,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              height: 1.45,
                              color: C.termText),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // поле ввода + запуск
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
                onSubmitted: (_) => _run(),
                decoration: const InputDecoration(hintText: 'введите команду…'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: controller.termBusy ? null : _run,
              icon: controller.termBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow),
              style: IconButton.styleFrom(backgroundColor: C.accentDark),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: controller.busy
                  ? null
                  : () async {
                      final err = await controller.submitTask();
                      if (err.isNotEmpty && context.mounted)
                        widget.onSnack(err);
                    },
              icon: const Icon(Icons.send, size: 19),
              style: IconButton.styleFrom(backgroundColor: C.good),
            ),
          ]),
          const SizedBox(height: 10),
          // кнопки: ментор · файлы
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(pageRoute(const ChatScreen(scope: ChatScope.task))),
                icon: Icon(Icons.chat_bubble_outline,
                    size: 17, color: C.secondary),
                label: Text('Ментор',
                    style: TextStyle(fontSize: 12.5, color: C.secondary)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showFiles(context),
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Файлы'),
              ),
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showFiles(BuildContext context) {
    final st = controller.state;
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: st.files.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                    child: Text('Файлов в песочнице нет.',
                        style: TextStyle(color: C.muted))),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                children: [
                  caption('Файлы песочницы'),
                  const SizedBox(height: 10),
                  for (final e in st.files.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: cardBox(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: C.accent)),
                              const SizedBox(height: 6),
                              Text(e.value,
                                  maxLines: 6,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: C.muted)),
                            ]),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ---------- слайд 4: Решение ----------

class _SolutionSlide extends StatefulWidget {
  final Task t;
  final void Function(String) onSnack;
  const _SolutionSlide({required this.t, required this.onSnack});
  @override
  State<_SolutionSlide> createState() => _SolutionSlideState();
}

class _SolutionSlideState extends State<_SolutionSlide> {
  Timer? _timer;
  double _hold = 0;

  void _startHold() {
    if (_hold > 0 && _hold < 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      setState(() => _hold = (_hold + 0.01).clamp(0.0, 1.0));
      if (_hold >= 1) {
        t.cancel();
        _reveal();
      }
    });
  }

  void _stopHold() {
    _timer?.cancel();
    if (_hold < 1) setState(() => _hold = 0);
  }

  Future<void> _reveal() async {
    final t = widget.t;
    if (t.solution.isEmpty) {
      await controller.loadSolution(t);
    } else {
      t.peeked = true;
      controller.saveProgress();
    }
    if (mounted) setState(() => _hold = 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (t.solution.isEmpty) ...[
          cardBox(
            child: Column(children: [
              Icon(Icons.lock_outline, size: 40, color: C.muted),
              const SizedBox(height: 10),
              const Text('Решение скрыто',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  'Сначала попробуй сам — ментор подскажет в чате.\nРешение готовит ИИ после удержания кнопки.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 16),
              if (controller.solutionLoad)
                Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: C.accent),
                )
              else
                _HoldButton(
                    progress: _hold, onStart: _startHold, onStop: _stopHold),
            ]),
          ),
        ] else if (!t.peeked) ...[
          // заблюренное решение
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: cardBox(
                  accent: C.accent.withAlpha(60),
                  child: MarkdownBody(data: t.solution, styleSheet: mdStyle()),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: C.bg.withAlpha(200),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.accent),
                    ),
                    child: Text('удерживай кнопку, чтобы разблюрить',
                        style: TextStyle(fontSize: 12, color: C.text)),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _HoldButton(progress: _hold, onStart: _startHold, onStop: _stopHold),
        ] else ...[
          cardBox(
              child: MarkdownBody(
                  data: t.solution, selectable: true, styleSheet: mdStyle())),
          const SizedBox(height: 10),
          Text('За подсмотренное решение XP не начисляются.',
              style: TextStyle(color: C.muted, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        if (!t.peeked && t.solution.isNotEmpty)
          Text(
              'Если вы покажете решение, вы не получите XP при решении этой задачи.',
              style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 30),
      ],
    );
  }
}

class _HoldButton extends StatelessWidget {
  final double progress;
  final VoidCallback onStart, onStop;
  const _HoldButton(
      {required this.progress, required this.onStart, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onLongPressStart: (_) => onStart(),
        onLongPressEnd: (_) => onStop(),
        onLongPressCancel: onStop,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: progress > 0 ? C.accentDark.withAlpha(200) : C.card2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.accent.withAlpha(120)),
          ),
          alignment: Alignment.center,
          child: Text(
            progress > 0
                ? 'держи ещё… ${((1 - progress) * 5).toStringAsFixed(1)} с'
                : 'Удерживай 5 секунд — показать решение',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 14, color: C.text),
          ),
        ),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: C.card2,
            color: C.accent),
      ),
    ]);
  }
}

/// _LiveSlide — перестраивает слайд по уведомлениям контроллера только когда
/// он активен: скрытые слайды не тратят кадры на терминал и markdown.
class _LiveSlide extends StatefulWidget {
  final bool active;
  final Widget Function() builder;
  const _LiveSlide({required this.active, required this.builder});

  @override
  State<_LiveSlide> createState() => _LiveSlideState();
}

class _LiveSlideState extends State<_LiveSlide> {
  Widget? _cache;

  @override
  void initState() {
    super.initState();
    if (widget.active) controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(_LiveSlide old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (widget.active) {
        controller.addListener(_onChange);
      } else {
        controller.removeListener(_onChange);
      }
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // неактивный слайд не пересобираем: возвращаем последний готовый вид
    if (!widget.active && _cache != null) return _cache!;
    return _cache = widget.builder();
  }
}
