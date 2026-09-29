// home.dart — главный экран в стиле Duolingo: вертикальная зигзаг-тропинка
// из кружков-курсов, толстые соединения (пройдено — ярко, впереди — серо),
// баннеры модулей каждые пять кружков. Скролл только сверху вниз.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'lesson.dart';
import 'theme.dart';
import 'widgets.dart';

/// CourseGraphView — тропинка курсов зигзагом (как в Duolingo).
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
        // геометрия тропинки: узлы-курсы + баннеры модулей каждые 5
        const nodeH = 168.0, bannerH = 88.0, topPad = 24.0, bottomPad = 36.0;
        const d = 96.0; // диаметр кружка
        final dxs = [-70.0, 0.0, 70.0, 0.0]; // зигзаг: влево, центр, вправо, центр

        final nodes = <_Node>[];
        var y = topPad;
        for (var i = 0; i < courses.length; i++) {
          nodes.add(_Node(
            type: _NodeType.course,
            y: y,
            dx: dxs[i % dxs.length],
            courseIdx: i,
          ));
          y += nodeH;
          if ((i + 1) % 5 == 0 && i != courses.length - 1) {
            nodes.add(_Node(type: _NodeType.module, y: y, moduleNum: (i + 1) ~/ 5));
            y += bannerH;
          }
        }
        final totalH = y - nodeH + d + 64 + bottomPad;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return SizedBox(
              height: totalH,
              width: w,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // соединительные линии под кружками
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TrailPainter(
                        nodes: nodes.where((n) => n.type == _NodeType.course).toList(),
                        center: w / 2,
                        d: d,
                      ),
                    ),
                  ),
                  // кружки-курсы
                  for (final n in nodes.where((n) => n.type == _NodeType.course))
                    _CourseCircle(node: n, d: d, centerX: w / 2),
                  // баннеры модулей
                  for (final n in nodes.where((n) => n.type == _NodeType.module))
                    Positioned(
                      left: 28,
                      right: 28,
                      top: n.y,
                      child: _ModuleBanner(number: n.moduleNum),
                    ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

enum _NodeType { course, module }

class _Node {
  final _NodeType type;
  final double y;
  final double dx;
  final int courseIdx;
  final int moduleNum;
  const _Node({
    required this.type,
    required this.y,
    this.dx = 0,
    this.courseIdx = -1,
    this.moduleNum = 0,
  });
}

/// _TrailPainter — толстые линии между кружками: пройденный путь яркий,
/// впереди — серый пунктир.
class _TrailPainter extends CustomPainter {
  final List<_Node> nodes;
  final double center, d;
  _TrailPainter({required this.nodes, required this.center, required this.d});

  @override
  void paint(Canvas canvas, Size size) {
    final dxs = [-70.0, 0.0, 70.0, 0.0];
    Offset nodeCenter(int i) {
      final n = nodes[i];
      return Offset(center + dxs[i % dxs.length], n.y + d / 2);
    }

    for (var i = 0; i + 1 < nodes.length; i++) {
      final a = nodeCenter(i), b = nodeCenter(i + 1);
      final done = controller.isCourseDone(nodes[i].courseIdx);
      final from = a + Offset(0, d / 2 - 6);
      final to = b - Offset(0, d / 2 - 6);
      if (done) {
        canvas.drawLine(from, to, Paint()
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..color = C.good);
        canvas.drawLine(from, to, Paint()
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withAlpha(70));
      } else {
        // серый пунктир
        const dash = 9.0, gap = 7.0;
        final dir = to - from;
        final len = dir.distance;
        if (len == 0) continue;
        final step = dir / len;
        for (var t = 0.0; t < len; t += dash + gap) {
          final segEnd = (t + dash) < len ? t + dash : len;
          canvas.drawLine(from + step * t, from + step * segEnd,
              Paint()..strokeWidth = 7 ..strokeCap = StrokeCap.round ..color = C.border);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) => old.nodes != nodes;
}

/// _CourseCircle — кружок курса: пройден (зелёный ✓), текущий (акцент, свечение),
/// впереди (серый). Под кружком — название.
class _CourseCircle extends StatelessWidget {
  final _Node node;
  final double d;
  final double centerX;
  const _CourseCircle({required this.node, required this.d, required this.centerX});

  @override
  Widget build(BuildContext context) {
    final i = node.courseIdx;
    final c = controller.courses[i];
    final done = controller.isCourseDone(i);
    final current = !done && i == _currentIdx();

    return Positioned(
      left: centerX + node.dx - 90,
      top: node.y,
      width: 180,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: i))),
            onDoubleTap: () => _showCourseActions(context, i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? C.good : current ? C.accent : C.card,
                border: Border.all(
                  color: done ? C.good : current ? C.accent : C.border,
                  width: current ? 3 : 2,
                ),
                boxShadow: current
                    ? [BoxShadow(color: C.accent.withAlpha(70), blurRadius: 22, spreadRadius: 2)]
                    : const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))],
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 42)
                    : Text(
                        String.fromCharCodes(c.title.runes.take(2)).toUpperCase(),
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: current ? Colors.white : C.muted),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: current ? C.accent : done ? C.text : C.muted),
          ),
        ],
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

/// _ModuleBanner — баннер между блоками тропинки.
class _ModuleBanner extends StatelessWidget {
  final int number;
  const _ModuleBanner({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [C.accentDark, C.accent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          SizedBox(
            width: 44,
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: Icon(Icons.emoji_events, color: Colors.white, size: 24),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text('Модуль пройден — впереди новые темы!',
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

/// Двойной тап по кружку: размытие фона + окно (открыть/переименовать/удалить).
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
                            content: Text('«' + c.title + '» исчезнет с тропинки. Прогресс сохранится.'),
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
