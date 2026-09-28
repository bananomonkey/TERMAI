import 'dart:ui' show ImageFilter;
// home.dart — главный экран: карта курсов кружками, соединёнными линиями,
// и список задач курса, сгруппированный по темам («5 задач: …»).
import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'lesson.dart';
import 'theme.dart';
import 'widgets.dart';

class CourseGraphView extends StatelessWidget {
  const CourseGraphView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final courses = controller.courses;
        if (courses.isEmpty) {
          return Center(child: Text('Курсов пока нет — создай через «Ещё» → Курс от ИИ.', style: TextStyle(color: C.muted)));
        }
        return SingleChildScrollView(
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return Column(
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Выбери направление — тапни по кружку',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.muted.withAlpha(200), fontSize: 13),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: _graphHeight(courses.length),
                  width: w,
                  child: _Graph(courses: courses, width: w),
                ),
                const SizedBox(height: 24),
              ],
            );
          }),
        );
      },
    );
  }
}

double _graphHeight(int n) {
  final rows = (n + 2) ~/ 3;
  return 40.0 + rows * 172.0;
}

// позиции кружков: ряды по 3, шахматный сдвиг — «хаотичная сеть»
({Offset topLeft, Offset center}) _nodePos(int i, double w) {
  const d = 88.0;
  final col = i % 3;
  final row = i ~/ 3;
  final cell = (w - 48.0) / 3;
  final stagger = row % 2 == 1 ? cell * 0.16 : 0.0;
  final x = (24.0 + col * cell + (cell - d) / 2 + stagger).clamp(8.0, w - d - 8.0);
  final y = 26.0 + row * 172.0;
  return (topLeft: Offset(x, y), center: Offset(x + d / 2, y + d / 2));
}

class _Graph extends StatelessWidget {
  final List<Course> courses;
  final double width;
  const _Graph({required this.courses, required this.width});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // линии под кружками
        Positioned.fill(
          child: CustomPaint(
            painter: _NetPainter(
              List.generate(courses.length, (i) => _nodePos(i, width).center),
            ),
          ),
        ),
        // кружки с подписями
        for (var i = 0; i < courses.length; i++) ..._buildNode(context, i),
      ],
    );
  }

  List<Widget> _buildNode(BuildContext context, int i) {
    final c = courses[i];
    final pos = _nodePos(i, width);
    final active = i == controller.courseIdx;
    const d = 88.0;
    return [
      Positioned(
        left: pos.topLeft.dx,
        top: pos.topLeft.dy,
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: i))),
          onLongPress: () => _showCourseActions(context, i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: d,
            height: d,
            decoration: BoxDecoration(
              color: C.card,
              shape: BoxShape.circle,
              border: Border.all(color: active ? C.accent : C.border, width: active ? 2.5 : 1.5),
              boxShadow: active
                  ? [BoxShadow(color: C.accent.withAlpha(60), blurRadius: 24, spreadRadius: 2)]
                  : const [],
            ),
            child: Center(
              child: Text(
                String.fromCharCodes(c.title.runes.take(2)).toUpperCase(),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: C.text),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: pos.center.dx - 80,
        top: pos.topLeft.dy + d + 6,
        width: 160,
        child: Text(
          c.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: active ? C.accent : C.muted, height: 1.15),
        ),
      ),
    ];
  }

  /// Долгое нажатие на кружке: размытие фона + окно действий с курсом.
  void _showCourseActions(BuildContext context, int i) {
    final cid = courses[i].id;
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
                if (idx < 0) {
                  return cardBox(child: const Text('Курс удалён'));
                }
                final c = controller.courses[idx];
                return cardBox(
                  accent: C.accent.withAlpha(120),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(c.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: idx)));
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
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
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: idx == 0 ? null : () => controller.moveCourse(idx, -1),
                            child: const Text('◀ влево'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Переместить', style: TextStyle(fontSize: 12, color: C.muted)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: idx == controller.courses.length - 1
                                ? null
                                : () => controller.moveCourse(idx, 1),
                            child: const Text('вправо ▶'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: ctx,
                            builder: (dctx) => AlertDialog(
                              backgroundColor: C.surface,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: const Text('Удалить курс?'),
                              content: Text('«' + c.title + '» исчезнет с главного экрана. Прогресс курса сохранится.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dctx), child: Text('Отмена', style: TextStyle(color: C.muted))),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: C.danger),
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
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Закрыть', style: TextStyle(color: C.muted)),
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
}

class _NetPainter extends CustomPainter {
  final List<Offset> centers;
  _NetPainter(this.centers);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = C.border
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i + 1 < centers.length; i++) {
      canvas.drawLine(centers[i], centers[i + 1], line);
    }
    final faint = Paint()
      ..color = C.border.withAlpha(110)
      ..strokeWidth = 1;
    for (var i = 0; i + 2 < centers.length; i += 2) {
      canvas.drawLine(centers[i], centers[i + 2], faint);
    }
  }

  @override
  bool shouldRepaint(covariant _NetPainter old) => old.centers != centers;
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('ИИ пишет первые задачи курса «${c.title}»…',
              textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
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
