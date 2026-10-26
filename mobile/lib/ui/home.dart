// home.dart — главный экран в стиле Duolingo: вертикальная зигзаг-тропинка
// из кружков-курсов, толстые соединения (пройдено — ярко, впереди — серо),
// баннеры модулей каждые пять кружков. Скролл только сверху вниз.
import 'package:flutter/material.dart';

import '../main.dart';
import '../store.dart';
import 'app_background.dart';
import 'chat.dart';
import 'lesson.dart';
import 'mentor_launcher.dart';
import 'review.dart';
import 'theme.dart';
import 'widgets.dart';

/// CourseGraphView — чистые плитки курсов: название, зелёный прогресс-бар,
/// процент выполнения. Плитки подстраиваются под цвета темы.
class CourseGraphView extends StatelessWidget {
  const CourseGraphView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final courses = controller.courses;
        if (courses.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Курсов пока нет — создай через «Ещё» → Курс от ИИ.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted)),
            ),
          );
        }
        // индекс активного курса считаем один раз, а не для каждой плитки
        var current = -1;
        for (var i = 0; i < courses.length; i++) {
          if (!controller.isCourseDone(i)) {
            current = i;
            break;
          }
        }
        if (current < 0) current = courses.length - 1;
        final list = Column(
          children: [
            if (controller.generating && controller.fillTotal > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: cardBox(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.auto_awesome, size: 15, color: C.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Наполняю курсы задачами: ${controller.fillDone}/${controller.fillTotal} · ${controller.fillCurrent}',
                              style: TextStyle(fontSize: 12, color: C.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: controller.fillDone / controller.fillTotal,
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(3),
                          backgroundColor: C.card2,
                          color: C.accent,
                        ),
                      ]),
                ),
              ),
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 196),
                itemCount: courses.length,
                itemBuilder: (context, i) =>
                    _CourseTile(index: i, currentIdx: current),
              ),
            ),
          ],
        );
        // фон (фото/туман + затемнение) рисует AppBackdrop вокруг всего тела
        return list;
      },
    );
  }
}

/// _CourseTile — стеклянная плитка курса: имя, число уроков, прогресс.
/// У активного курса под стеклом — зелёное свечение, видное сквозь размытие.
class _CourseTile extends StatelessWidget {
  final int index;
  final int currentIdx;
  const _CourseTile({required this.index, required this.currentIdx});

  @override
  Widget build(BuildContext context) {
    final c = controller.courses[index];
    final done = controller.isCourseDone(index);
    final total = c.tasks.length;
    final completedMap = controller.prog.completed[c.id] ?? {};
    final solved = total == 0
        ? 0
        : c.tasks.where((t) => completedMap[t.id] ?? false).length;
    final pct = total == 0 ? 0 : ((solved / total) * 100).round();
    final current = !done && index == currentIdx;
    final accent = c.isTheory ? C.secondary : C.accent;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        // выделение текста при двойном тапе отключено: заголовок не должен
        // подсвечиваться и «краснеть» системным селектом
        child: SelectionContainer.disabled(
          child: GestureDetector(
            onTap: () => Navigator.of(context)
                .push(pageRoute(TaskListScreen(courseIdx: index))),
            onDoubleTap: () => _showCourseActions(context, index),
            child: glass(
              radius: 20,
              blur: 22,
              padding: const EdgeInsets.all(16),
              glow: current
                  ? C.glow(color: C.good, alpha: 70)
                  : C.glow(color: accent, alpha: 18),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                              c.isTheory
                                  ? Icons.auto_stories_outlined
                                  : Icons.terminal,
                              size: 15,
                              color: accent),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: C.text,
                                    decoration: TextDecoration.none)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            '$solved/$total уроков · ${c.isTheory ? 'теория' : 'терминал'}',
                            style: TextStyle(fontSize: 11, color: C.muted)),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: total == 0 ? 0 : solved / total,
                            minHeight: 6,
                            backgroundColor: Colors.white.withAlpha(14),
                            color: done ? C.good : (current ? C.good : accent),
                          ),
                        ),
                      ]),
                ),
                const SizedBox(width: 10),
                Text('$pct%',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: done ? C.good : C.muted)),
                const SizedBox(width: 2),
                if (done)
                  Icon(Icons.check_circle_rounded, color: C.good, size: 22)
                else ...[
                  chevron(
                      size: current ? 28 : 26,
                      color: current ? C.good : C.muted),
                  GestureDetector(
                    onTap: () => _showCourseActions(context, index),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(Icons.more_vert,
                          size: 18, color: C.muted.withAlpha(170)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Двойной тап по плитке: окно действий (открыть/переименовать/в архив/удалить).
void _showCourseActions(BuildContext context, int courseIdx) {
  final cid = controller.courses[courseIdx].id;
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Действия с курсом',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, _) {
      return Container(
        color: C.bg.withAlpha(175),
        alignment: Alignment.center,
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            final idx = controller.courses.indexWhere((x) => x.id == cid);
            if (idx < 0) return const SizedBox.shrink();
            final c = controller.courses[idx];
            return Container(
              width: 300,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: C.surface, borderRadius: BorderRadius.circular(20)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(c.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: C.text,
                          decoration: TextDecoration.none)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context)
                          .push(pageRoute(TaskListScreen(courseIdx: idx)));
                    },
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Открыть'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final t = await askText(
                          context, 'Переименовать курс', 'новое название',
                          initial: c.title);
                      if (t != null && t.isNotEmpty)
                        controller.renameCourse(idx, t);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Переименовать'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      controller.archiveCourse(c.id);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('«${c.title}» в архиве'),
                        action: SnackBarAction(
                          label: 'Вернуть',
                          onPressed: () => controller.unarchiveCourse(c.id),
                        ),
                      ));
                    },
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('В архив'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          backgroundColor: C.surface,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          title: const Text('Удалить курс?'),
                          content: Text('«' +
                              c.title +
                              '» исчезнет из списка. Прогресс сохранится.'),
                          actions: [
                            OutlinedButton(
                              onPressed: () => Navigator.pop(dctx),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(64, 42)),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: C.danger,
                                  minimumSize: const Size(64, 42)),
                              onPressed: () {
                                Navigator.pop(dctx);
                                controller.deleteCourse(idx);
                                Navigator.pop(ctx);
                              },
                              child: const Text('Удалить'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: Icon(Icons.delete_outline, size: 18, color: C.danger),
                    label: Text('Удалить', style: TextStyle(color: C.danger)),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

// ---------- список задач курса ----------

class TaskListScreen extends StatefulWidget {
  final int courseIdx;
  const TaskListScreen({super.key, required this.courseIdx});
  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  @override
  void initState() {
    super.initState();
    controller.switchCourseSilent(widget.courseIdx);
    // пустой курс — сразу просим ИИ наполнить его пакетом задач
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.cur.tasks.isEmpty && !controller.generating) {
        controller.fillCourse(controller.cur);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller.cur;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(c.title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          body: AppBackdrop(
            child: Stack(children: [
              const Positioned.fill(child: _TaskGroups()),
              Positioned(
                left: 14,
                bottom: 14,
                child: SafeArea(
                  top: false,
                  child: const MentorLauncher(),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _TaskGroups extends StatelessWidget {
  const _TaskGroups();

  @override
  Widget build(BuildContext context) {
    final c = controller.cur;
    if (c.tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.generating) ...[
              CircularProgressIndicator(color: C.accent),
              const SizedBox(height: 16),
            ],
            Text(
              controller.generating
                  ? 'ИИ пишет задачи курса «${c.title}»…\n(пакет из 8 — это занимает до минуты)'
                  : controller.ai == null
                      ? 'Нет API-ключа — курс нечем наполнить.\nНастрой ИИ в «Ещё» → Настройки.'
                      : (controller.lastFillError.isNotEmpty
                          ? 'Не получилось сгенерировать:\n${controller.lastFillError}\n\nПопробуй ещё раз.'
                          : 'Задач пока нет.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted, height: 1.5),
            ),
            if (!controller.generating && controller.ai != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => controller.fillCourse(controller.cur),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Наполнить задачами от ИИ'),
              ),
            ],
          ],
        ),
      );
    }
    final groups = <Widget>[];
    for (var start = 0; start < c.tasks.length; start += 5) {
      final end = (start + 5).clamp(0, c.tasks.length);
      var topic = c.title;
      if (c.syllabus.isNotEmpty) {
        topic = c.syllabus[(start ~/ 5).clamp(0, c.syllabus.length - 1)];
      }
      groups.add(sectionHeader('${end - start} уроков: $topic'));
      for (var i = start; i < end; i++) {
        final t = c.tasks[i];
        groups.add(_TaskRow(
          index: i,
          title: t.title,
          kind: c.isTheory ? 'урок' : (t.isQuiz ? 'тест' : 'практика'),
          difficulty: t.difficulty,
          done: controller.isDone(t),
          current: i == _frontier(),
          onTap: () async {
            controller.selectTask(i);
            await Navigator.of(context).push(pageRoute(const LessonScreen()));
            // возврат из урока: гарантируем перестройку списка (состояние могло
            // измениться, пока урок был поверх)
            if (context.mounted) controller.notifyListeners();
          },
        ));
        groups.add(const SizedBox(height: 8));
      }
      groups.add(const SizedBox(height: 14));
    }
    groups.add(_EndActions());
    // ленивая сборка строк: длинные курсы не строят все элементы сразу
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      itemCount: groups.length,
      itemBuilder: (context, i) => groups[i],
    );
  }

  int _frontier() {
    final tasks = controller.cur.tasks;
    final done = controller.prog.completed[controller.cur.id] ?? {};
    for (var i = 0; i < tasks.length; i++) {
      if (!(done[tasks[i].id] ?? false)) return i;
    }
    return tasks.length;
  }
}

class _TaskRow extends StatelessWidget {
  final int index;
  final String title, kind;
  final int difficulty;
  final bool done, current;
  final VoidCallback onTap;
  const _TaskRow({
    required this.index,
    required this.title,
    required this.kind,
    required this.difficulty,
    required this.done,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: cardBox(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: statusGlyph(done, current)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25)),
                  const SizedBox(height: 5),
                  Row(children: [
                    Text(kind, style: TextStyle(fontSize: 11, color: C.muted)),
                    const SizedBox(width: 10),
                    difficultyDots(difficulty),
                  ]),
                ],
              ),
            ),
            chevron(size: 24, color: current ? C.accent : C.muted),
          ],
        ),
      ),
    );
  }
}

/// _EndActions — действия в конце списка задач: создать задачу,
/// повторение закладок, собеседование.
class _EndActions extends StatelessWidget {
  const _EndActions();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(children: [
        GestureDetector(
          onTap: (controller.generating || controller.busy)
              ? null
              : () async {
                  final topic = await askText(context, 'Новая задача от ИИ',
                      'тема: например «времена в английском» или «проброс портов»');
                  if (topic == null || topic.isEmpty) return;
                  final err = await controller.generateTask(topic);
                  if (err.isNotEmpty && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(err)));
                  }
                },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.accent.withAlpha(90)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (controller.generating)
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: C.accent))
              else
                Icon(Icons.add, color: C.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                  controller.generating
                      ? 'ИИ пишет задачу…'
                      : 'Создать задачу от ИИ',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: C.accent)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).push(pageRoute(const ReviewScreen())),
              icon: Icon(Icons.refresh, size: 17, color: C.secondary),
              label: Text('Повторение',
                  style: TextStyle(fontSize: 12.5, color: C.secondary)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                controller.startInterview();
                controller.createInterviewChat(force: true);
                Navigator.of(context).push(pageRoute(
                    const ChatScreen(interview: true, resume: true),
                    name: 'InterviewScreen'));
              },
              icon: Icon(Icons.work_history_outlined, size: 17, color: C.warn),
              label: Text('Собеседование',
                  style: TextStyle(fontSize: 12.5, color: C.warn)),
            ),
          ),
        ]),
      ]),
    );
  }
}
