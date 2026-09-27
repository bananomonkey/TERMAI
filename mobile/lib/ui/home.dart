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
          return const Center(child: Text('Курсов пока нет — создай через «Ещё» → Курс от ИИ.', style: TextStyle(color: kMuted)));
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
                    style: TextStyle(color: kMuted.withAlpha(200), fontSize: 13),
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
  return 60.0 + rows * 148.0;
}

// позиции кружков: ряды по 3, шахматный сдвиг — «хаотичная сеть»
({Offset center, Offset topLeft}) _nodePos(int i, double w) {
  const d = 86.0;
  final col = i % 3;
  final row = i ~/ 3;
  final stagger = row % 2 == 1 ? 52.0 : 0.0;
  final usable = (w - 3 * d - 32).clamp(0.0, double.infinity);
  final stepX = 3 > 1 ? usable / 2 : 0.0;
  final x = 16.0 + col * (d + stepX) + (col == 2 ? -stagger : stagger / 2) + (row % 2 == 1 && col == 1 ? 24.0 : 0.0);
  final y = 36.0 + row * 148.0;
  return (center: Offset(x + d / 2, y + d / 2), topLeft: Offset(x, y));
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
        for (var i = 0; i < courses.length; i++) _buildNode(context, i),
      ],
    );
  }

  Widget _buildNode(BuildContext context, int i) {
    final c = courses[i];
    final pos = _nodePos(i, width);
    final active = i == controller.courseIdx;
    const d = 86.0;
    return Positioned(
      left: pos.topLeft.dx - 24,
      top: pos.topLeft.dy + d + 6,
      width: d + 48,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: i))),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: kCard,
                shape: BoxShape.circle,
                border: Border.all(color: active ? kAccent : kBorder, width: active ? 2.5 : 1.5),
                boxShadow: active
                    ? [BoxShadow(color: kAccent.withAlpha(60), blurRadius: 24, spreadRadius: 2)]
                    : const [],
              ),
              child: Center(
                child: Text(
                  String.fromCharCodes(c.title.runes.take(2)).toUpperCase(),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kText),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            c.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: active ? kAccent : kMuted, height: 1.15),
          ),
        ],
      ),
    );
  }
}

class _NetPainter extends CustomPainter {
  final List<Offset> centers;
  _NetPainter(this.centers);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = kBorder
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i + 1 < centers.length; i++) {
      canvas.drawLine(centers[i], centers[i + 1], line);
    }
    final faint = Paint()
      ..color = kBorder.withAlpha(110)
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
              textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
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
        accent: current ? kAccent : null,
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
                    Text(kind, style: const TextStyle(fontSize: 11, color: kMuted)),
                    const SizedBox(width: 10),
                    difficultyDots(difficulty),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: kMuted, size: 22),
          ],
        ),
      ),
    );
  }
}
