// home.dart — главный экран «книжный шкаф»: деревянные полки, книги-курсы,
// выдвижение книги по тапу, drag-перестановка пальцем, меню по двойному тапу.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'lesson.dart';
import 'theme.dart';
import 'widgets.dart';

/// CourseGraphView — вертикальный скролл полок, на каждой 3 книги-курса.
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
        final shelves = (courses.length + 2) ~/ 3;
        return Column(
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Тап — открыть книгу · двойной тап — меню · удерживай и тащи — переставить',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted, fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
                itemCount: shelves,
                itemBuilder: (context, shelf) {
                  return _Shelf(
                    slots: List.generate(3, (k) => shelf * 3 + k),
                    isLast: shelf == shelves - 1,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// _Shelf — ряд из трёх слотов (книга или пусто) и деревянная полка под ними.
class _Shelf extends StatelessWidget {
  final List<int> slots;
  final bool isLast;
  const _Shelf({required this.slots, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final i in slots)
                Expanded(
                  child: i < controller.courses.length
                      ? _BookSlot(index: i)
                      : const _EmptySlot(),
                ),
            ],
          ),
        ),
        // деревянная полка
        Container(
          height: 12,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: const LinearGradient(
              colors: [Color(0xFF5C3F27), Color(0xFF7A5535), Color(0xFF5C3F27)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 4))],
          ),
          child: Container(
            margin: const EdgeInsets.only(top: 1.5, left: 6, right: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.white.withAlpha(22),
            ),
          ),
        ),
      ],
    );
  }
}

/// _BookSlot — курс-книга: тап (выдвижение + переход), двойной тап (меню), drag (перестановка).
class _BookSlot extends StatelessWidget {
  final int index;
  const _BookSlot({required this.index});

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAccept: (data) => data != null && data != index,
      onAccept: (data) => controller.moveCourse(data, index),
      builder: (context, candidate, _) {
        final highlighted = candidate.isNotEmpty;
        return Draggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: _Book(index: index, pulled: true, dragging: true),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: _Book(index: index, pulled: false)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: highlighted ? Border.all(color: C.accent, width: 2) : null,
            ),
            child: _Book(index: index, pulled: false),
          ),
        );
      },
    );
  }
}

/// _EmptySlot — пустое место на полке: тоже принимает книги (в конец списка).
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAccept: (data) => data != null,
      onAccept: (data) => controller.moveCourse(data, controller.courses.length),
      builder: (context, candidate, _) => Container(
        height: 168,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: candidate.isNotEmpty
              ? Border.all(color: C.accent, width: 2)
              : Border.all(color: C.border.withAlpha(90)),
        ),
        child: candidate.isNotEmpty
            ? Center(child: Icon(Icons.move_down, color: C.accent))
            : const SizedBox(),
      ),
    );
  }
}

/// _Book — книга-курс с корешком (название снизу вверх) и выдвижением по тапу.
class _Book extends StatefulWidget {
  final int index;
  final bool pulled;
  final bool dragging;
  const _Book({required this.index, required this.pulled, this.dragging = false});

  @override
  State<_Book> createState() => _BookState();
}

class _BookState extends State<_Book> {
  bool _animating = false;

  // приглушённые цвета корешков — книги выглядят как книги в любой теме
  static const _spines = <Color>[
    Color(0xFF8A5A44), Color(0xFF4E6E58), Color(0xFF54679A),
    Color(0xFF9A6B5A), Color(0xFF6B5E8A), Color(0xFF8A7D4E),
  ];

  void _open() {
    if (_animating) return;
    setState(() => _animating = true);
    Future.delayed(const Duration(milliseconds: 230), () {
      if (!mounted) return;
      Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: widget.index)));
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) setState(() => _animating = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = controller.courses[widget.index];
    final out = widget.pulled || _animating || widget.dragging;
    return GestureDetector(
      onTap: _open,
      onDoubleTap: () => _showCourseActions(context, widget.index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: out ? 172 : 156,
        width: out ? 96 : 88,
        margin: const EdgeInsets.all(4),
        transform: Matrix4.translationValues(0, out ? -16 : 0, 0),
        decoration: BoxDecoration(
          color: _spines[widget.index % _spines.length],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(5),
            topRight: Radius.circular(9),
            bottomRight: Radius.circular(9),
            bottomLeft: Radius.circular(3),
          ),
          border: Border.all(color: Colors.black.withAlpha(70)),
          boxShadow: [
            BoxShadow(
              color: out ? C.accent.withAlpha(90) : Colors.black54,
              blurRadius: out ? 22 : 8,
              offset: Offset(0, out ? 10 : 5),
            ),
          ],
        ),
        child: Column(children: [
          Container(height: 7, decoration: BoxDecoration(color: Colors.black.withAlpha(60), borderRadius: const BorderRadius.vertical(top: Radius.circular(5)))),
          Expanded(
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
          ),
          Container(height: 7, decoration: BoxDecoration(color: Colors.black.withAlpha(40), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)))),
        ]),
      ),
    );
  }
}

/// Двойной тап по книге: размытие фона + окно действий (открыть/переименовать/удалить).
void _showCourseActions(BuildContext context, int i) {
  final cid = controller.courses[i].id;
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
              return Container(
                width: 300,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: C.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
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
                            content: Text('«' + c.title + '» исчезнет с полки. Прогресс курса сохранится.'),
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
        controller.fillCourse();
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
                      : 'Задач пока нет.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted, height: 1.5),
            ),
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
