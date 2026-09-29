// home.dart — главный экран в стиле Duolingo: вертикальная зигзаг-тропинка
// из кружков-курсов, толстые соединения (пройдено — ярко, впереди — серо),
// баннеры модулей каждые пять кружков. Скролл только сверху вниз.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'ambient.dart';
import 'lesson.dart';
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
                  textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
            ),
          );
        }
        final ambient = controller.config.ambient;
        final list = Column(
          children: [
            if (controller.generating && controller.fillTotal > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: cardBox(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                itemCount: courses.length,
                itemBuilder: (context, i) => _CourseTile(index: i, ambient: ambient),
              ),
            ),
          ],
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            if (ambient) const Positioned.fill(child: AmbientBackground()),
            Positioned.fill(child: list),
          ],
        );
      },
    );
  }
}

/// _CourseTile — плитка курса: имя, зелёный прогресс-бар, процент.
class _CourseTile extends StatelessWidget {
  final int index;
  final bool ambient;
  const _CourseTile({required this.index, required this.ambient});

  @override
  Widget build(BuildContext context) {
    final c = controller.courses[index];
    final done = controller.isCourseDone(index);
    final total = c.tasks.length;
    final completedMap = controller.prog.completed[c.id] ?? {};
    final solved = total == 0 ? 0 : c.tasks.where((t) => completedMap[t.id] ?? false).length;
    final pct = total == 0 ? 0 : ((solved / total) * 100).round();
    final current = !done && index == _currentIdx();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: index))),
        onDoubleTap: () => _showCourseActions(context, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: ambient ? 14 : 0, sigmaY: ambient ? 14 : 0),
            child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: ambient ? C.surface.withAlpha(150) : C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: current ? C.accent : C.border, width: current ? 1.6 : 1),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: C.text)),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : solved / total,
                    minHeight: 7,
                    backgroundColor: C.card2,
                    color: C.good,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 14),
            Text('$pct%',
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w900, color: done ? C.good : C.muted)),
            const SizedBox(width: 6),
            if (done)
              Icon(Icons.check_circle_rounded, color: C.good, size: 22)
            else
              Icon(Icons.chevron_right, color: C.muted, size: 22),
          ]),
        ),
          ),
        ),
      ),
    );
  }

  int _currentIdx() {
    for (var i = 0; i < controller.courses.length; i++) {
      if (!controller.isCourseDone(i)) return i;
    }
    return controller.courses.length - 1;
  }
}

/// Двойной тап по плитке: размытие фона + окно (открыть/переименовать/удалить).
void _showCourseActions(BuildContext context, int courseIdx) {
  final cid = controller.courses[courseIdx].id;
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Действия с курсом',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, _) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: C.bg.withAlpha(110),
          alignment: Alignment.center,
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              final idx = controller.courses.indexWhere((x) => x.id == cid);
              if (idx < 0) return cardBox(child: const Text('Курс удалён'));
              final c = controller.courses[idx];
              return Container(
                width: 300,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(c.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: idx)));
                      },
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('Открыть'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final t = await askText(context, 'Переименовать курс', 'новое название', initial: c.title);
                        if (t != null && t.isNotEmpty) controller.renameCourse(idx, t);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Переименовать'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: ctx,
                          builder: (dctx) => AlertDialog(
                            backgroundColor: C.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Удалить курс?'),
                            content: Text('«' + c.title + '» исчезнет из списка. Прогресс сохранится.'),
                            actions: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(dctx),
                                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 42)),
                                child: const Text('Отмена'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: C.danger, minimumSize: const Size(64, 42)),
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
          appBar: AppBar(
            title: Text(c.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          body: const _TaskGroups(),
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
      groups.add(sectionHeader('${end - start} задач: $topic'));
      for (var i = start; i < end; i++) {
        final t = c.tasks[i];
        groups.add(_TaskRow(
          index: i,
          title: t.title,
          kind: t.isQuiz ? 'тест' : 'практика',
          difficulty: t.difficulty,
          done: controller.isDone(t),
          current: i == _frontier(),
          onTap: () {
            controller.selectTask(i);
            Navigator.of(context).push(pageRoute(const LessonScreen()));
          },
        ));
        groups.add(const SizedBox(height: 8));
      }
      groups.add(const SizedBox(height: 14));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: groups,
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
        accent: current ? C.accent : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: statusGlyph(done, current)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
                  const SizedBox(height: 5),
                  Row(children: [
                    Text(kind, style: TextStyle(fontSize: 11, color: C.muted)),
                    const SizedBox(width: 10),
                    difficultyDots(difficulty),
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: C.muted, size: 22),
          ],
        ),
      ),
    );
  }
}
