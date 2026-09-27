// lesson.dart — экран задачи со слайдами как в Coddy:
// Справка (поиск по теории) · Задача · Терминал · Решение (блюр + удержание).
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'chat.dart';
import 'theme.dart';
import 'widgets.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  String _search = '';
  List<int> _answers = const [];

  @override
  void initState() {
    super.initState();
    _syncAnswers();
  }

  void _syncAnswers() {
    final t = controller.currentTask;
    setState(() => _answers = List.filled(t?.quiz.length ?? 0, -1, growable: false));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final t = controller.currentTask;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const TabBar(
          isScrollable: false,
          labelColor: kAccent,
          unselectedLabelColor: kMuted,
          labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          unselectedLabelStyle: TextStyle(fontSize: 13),
          indicatorColor: kAccent,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: [
            Tab(text: 'Справка'),
            Tab(text: 'Задача'),
            Tab(text: 'Терминал'),
            Tab(text: 'Решение'),
          ],
        ),
        titleSpacing: 0,
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (t == null) {
            return const Center(child: Text('Задач нет — создай через «Ещё» → Задача от ИИ.', style: TextStyle(color: kMuted)));
          }
          return TabBarView(
            physics: const BouncingScrollPhysics(),
            children: [
              _HelpSlide(t: t, search: _search, onSearch: (v) => setState(() => _search = v)),
              _TaskSlide(
                t: t,
                answers: _answers,
                onAnswer: (qi, oi) => setState(() => _answers[qi] = oi),
                onSnack: _snack,
              ),
              _TermSlide(onSnack: _snack),
              _SolutionSlide(t: t, onSnack: _snack),
            ],
          );
        },
      ),
      ),
    );
  }
}

// ---------- слайд 1: Справка ----------

class _HelpSlide extends StatelessWidget {
  final Task t;
  final String search;
  final ValueChanged<String> onSearch;
  const _HelpSlide({required this.t, required this.search, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final q = search.trim().toLowerCase();
    final paras = q.isEmpty
        ? t.theory
        : t.theory.where((p) => p.toLowerCase().contains(q)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          onChanged: onSearch,
          decoration: const InputDecoration(
            hintText: 'Поиск справочных материалов…',
            prefixIcon: Icon(Icons.search, color: kMuted),
          ),
        ),
        const SizedBox(height: 14),
        if (paras.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('Ничего не найдено.', style: TextStyle(color: kMuted))),
          )
        else
          ...paras.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: cardBox(child: MarkdownBody(data: p, selectable: true, styleSheet: mdStyle())),
              )),
      ],
    );
  }
}

MarkdownStyleSheet mdStyle() => MarkdownStyleSheet(
      p: const TextStyle(fontSize: 14.5, height: 1.45, color: kText),
      h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kText),
      h2: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kText),
      h3: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: kText),
      code: const TextStyle(fontSize: 13, color: kAccent, fontFamily: 'monospace', backgroundColor: kCard2),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF101318),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      listBullet: const TextStyle(fontSize: 14.5, height: 1.4, color: kText),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: kAccent.withAlpha(120), width: 3)),
        color: kCard2.withAlpha(80),
      ),
      blockquotePadding: const EdgeInsets.all(10),
    );

// ---------- слайд 2: Задача ----------

class _TaskSlide extends StatelessWidget {
  final Task t;
  final List<int> answers;
  final void Function(int qi, int oi) onAnswer;
  final void Function(String) onSnack;
  const _TaskSlide({required this.t, required this.answers, required this.onAnswer, required this.onSnack});

  @override
  Widget build(BuildContext context) {
    final needQuiz = t.quiz.isNotEmpty && !controller.quizDone(t) && !controller.isDone(t);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, height: 1.2)),
        const SizedBox(height: 8),
        Row(children: [
          Text(t.isQuiz ? 'тест' : 'практика', style: const TextStyle(fontSize: 12, color: kMuted)),
          const SizedBox(width: 10),
          difficultyDots(t.difficulty),
          const SizedBox(width: 10),
          Text('+${t.xp} XP', style: const TextStyle(fontSize: 12, color: kAccent, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        cardBox(
          accent: kAccent.withAlpha(140),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            caption('Задача', color: kAccent),
            const SizedBox(height: 8),
            MarkdownBody(data: t.goal, styleSheet: mdStyle()),
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(pageRoute(ChatScreen(autoQuestion:
                'Объясни задачу «${t.title}»: что требуется, на что обратить внимание и в каком порядке действовать. Не давай сразу готовых команд — сначала идея.')));
          },
          icon: const Icon(Icons.emoji_objects_outlined, color: kAccent),
          label: const Text('Объяснить задание', style: TextStyle(color: kAccent)),
        ),
        const SizedBox(height: 18),
        if (needQuiz) ...[
          caption('Тест по теории', color: kAccent),
          const SizedBox(height: 10),
          _QuizBlock(t: t, answers: answers, onAnswer: onAnswer, onSnack: onSnack),
        ],
        if (!needQuiz && !t.isQuiz) ...[
          FilledButton(
            onPressed: controller.busy
                ? null
                : () async {
                    final err = await controller.submitTask();
                    if (err.isNotEmpty) onSnack(err);
                  },
            child: const Text('Отправить на проверку'),
          ),
          const SizedBox(height: 12),
        ],
        if (t.hints.isNotEmpty) ...[
          caption('Подсказки'),
          const SizedBox(height: 8),
          for (var i = 0; i < t.hints.length && i < 2; i++) _HintTile(t: t, index: i),
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
  const _QuizBlock({required this.t, required this.answers, required this.onAnswer, required this.onSnack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var qi = 0; qi < t.quiz.length; qi++) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${qi + 1}. ${t.quiz[qi].question}',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3)),
          ),
          const SizedBox(height: 8),
          for (var oi = 0; oi < t.quiz[qi].options.length; oi++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => onAnswer(qi, oi),
                child: cardBox(
                  accent: answers[qi] == oi ? kAccent : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [
                    Icon(answers[qi] == oi ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18, color: answers[qi] == oi ? kAccent : kMuted),
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
          onPressed: () {
            final err = controller.checkQuiz(t, answers);
            onSnack(err.isEmpty ? '✓ Тест пройден — практика открыта' : err);
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
          collapsedBackgroundColor: kCard,
          backgroundColor: kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder)),
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder)),
          title: Text('Подсказка ${index + 1}', style: const TextStyle(fontSize: 14, color: kText)),
          onExpansionChanged: (open) {
            if (open && !used) {
              final m = controller.prog.hints[controller.cur.id] ?? {};
              m[t.id] = index + 1;
              controller.prog.hints[controller.cur.id] = m;
              controller.saveProgress();
            }
          },
          children: [Align(alignment: Alignment.centerLeft, child: MarkdownBody(data: t.hints[index], styleSheet: mdStyle()))],
        ),
      ),
    );
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
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String _lastTerm = '';

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _run() {
    final cmd = _input.text;
    _input.clear();
    controller.runCommand(cmd);
  }

  @override
  Widget build(BuildContext context) {
    final t = controller.currentTask;
    if (controller.termText != _lastTerm) {
      _lastTerm = controller.termText;
      _autoScroll();
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((t?.expected ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: cardBox(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  caption('Ожидаемый вывод'),
                  const SizedBox(height: 6),
                  MarkdownBody(data: t!.expected, styleSheet: mdStyle()),
                ]),
              ),
            ),
          // вывод терминала
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0E1116),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                  child: Row(children: [
                    const Text('Терминал', style: TextStyle(fontSize: 11, color: kMuted)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: controller.undoCommand,
                      icon: const Icon(Icons.undo, size: 16, color: kMuted),
                      label: const Text('Отменить', style: TextStyle(fontSize: 12, color: kMuted)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        controller.termText = '';
                        controller.termLine('  (вывод терминала очищен)');
                        controller.refreshTerminal();
                      },
                      icon: const Icon(Icons.refresh, size: 16, color: kMuted),
                      label: const Text('Сбросить', style: TextStyle(fontSize: 12, color: kMuted)),
                    ),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        controller.termText,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45, color: Color(0xFFD7DBE0)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          // строка ввода
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
                onSubmitted: (_) => _run(),
                decoration: InputDecoration(
                  prefixText: '${controller.prompt} ',
                  prefixStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, color: kAccent),
                  hintText: 'введите команду…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: controller.termBusy ? null : _run,
              icon: controller.termBusy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow),
              style: IconButton.styleFrom(backgroundColor: kAccentDark),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _showFiles(context),
              icon: const Icon(Icons.folder_outlined, size: 18),
              label: const Text('Файлы'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.busy
                    ? null
                    : () async {
                        final err = await controller.submitTask();
                        if (err.isNotEmpty) widget.onSnack(err);
                      },
                icon: const Icon(Icons.send, size: 17),
                label: const Text('Отправить на проверку'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  void _showFiles(BuildContext context) {
    final st = controller.state;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: st.files.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('Файлов в песочнице нет.', style: TextStyle(color: kMuted))),
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
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kAccent)),
                          const SizedBox(height: 6),
                          Text(e.value, maxLines: 6, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: kMuted)),
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
              const Icon(Icons.lock_outline, size: 40, color: kMuted),
              const SizedBox(height: 10),
              const Text('Решение скрыто',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Сначала попробуй сам — ментор подскажет в чате.\nРешение готовит ИИ после удержания кнопки.',
                  textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 16),
              if (controller.solutionLoad)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: kAccent),
                )
              else
                _HoldButton(progress: _hold, onStart: _startHold, onStop: _stopHold),
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
                  accent: kAccent.withAlpha(60),
                  child: MarkdownBody(data: t.solution, styleSheet: mdStyle()),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: kBg.withAlpha(200),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kAccent),
                    ),
                    child: const Text('удерживай кнопку, чтобы разблюрить',
                        style: TextStyle(fontSize: 12, color: kText)),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _HoldButton(progress: _hold, onStart: _startHold, onStop: _stopHold),
        ] else ...[
          cardBox(child: MarkdownBody(data: t.solution, selectable: true, styleSheet: mdStyle())),
          const SizedBox(height: 10),
          const Text('За подсмотренное решение XP не начисляются.',
              style: TextStyle(color: kMuted, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        if (!t.peeked && t.solution.isNotEmpty)
          const Text('Если вы покажете решение, вы не получите XP при решении этой задачи.',
              style: TextStyle(color: kMuted, fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 30),
      ],
    );
  }
}

class _HoldButton extends StatelessWidget {
  final double progress;
  final VoidCallback onStart, onStop;
  const _HoldButton({required this.progress, required this.onStart, required this.onStop});

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
            color: progress > 0 ? kAccentDark.withAlpha(200) : kCard2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kAccent.withAlpha(120)),
          ),
          alignment: Alignment.center,
          child: Text(
            progress > 0 ? 'держи ещё… ${((1 - progress) * 5).toStringAsFixed(1)} с' : 'Удерживай 5 секунд — показать решение',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText),
          ),
        ),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: kCard2, color: kAccent),
      ),
    ]);
  }
}
