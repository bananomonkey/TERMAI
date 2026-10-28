// progress_map.dart — карта прогресса: маршрут по курсу, узлы задач,
// достижения и ключевые показатели. Открывается из нижнего дока.
import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'app_background.dart';
import 'lesson.dart';
import 'theme.dart';
import 'widgets.dart';

class ProgressMapScreen extends StatelessWidget {
  const ProgressMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Карта прогресса',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (controller.courses.isEmpty) {
              return Center(
                child: Text('Пока нет курсов — создай первый в «Ещё».',
                    style: TextStyle(color: C.muted)),
              );
            }
            final course = controller.cur;
            final tasks = course.tasks;
            final done = controller.prog.completed[course.id] ?? {};
            final completed =
                tasks.where((t) => done[t.id] ?? false).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _StatsCard(
                  level: controller.prog.level,
                  xp: controller.prog.xp,
                  streak: controller.prog.streak,
                  solved: controller.prog.solvedTotal,
                ),
                const SizedBox(height: 16),
                caption('Маршрут', color: C.accent),
                const SizedBox(height: 9),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: controller.courses.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (_, i) {
                      final c = controller.courses[i];
                      final selected = i == controller.courseIdx;
                      return ChoiceChip(
                        selected: selected,
                        label: Text(c.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onSelected: (_) => controller.switchCourseSilent(i),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: selected ? C.text : C.muted),
                        selectedColor: C.accent.withAlpha(C.isLight ? 40 : 55),
                        backgroundColor: C.card,
                        side: BorderSide(
                            color: selected ? C.accent : C.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                cardBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(course.title,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: C.text)),
                        ),
                        Text('$completed/${tasks.length}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: C.good)),
                      ]),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: tasks.isEmpty
                              ? 0
                              : completed / tasks.length,
                          minHeight: 6,
                          backgroundColor: C.card2,
                          color: C.good,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'В курсе пока нет задач. Открой курс и попроси ИИ наполнить его.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: C.muted, height: 1.4),
                    ),
                  )
                else
                  for (var i = 0; i < tasks.length; i++)
                    _RouteRow(
                      index: i,
                      total: tasks.length,
                      task: tasks[i],
                      done: done[tasks[i].id] ?? false,
                      current: i == _frontier(tasks, done),
                      onTap: () {
                        controller.selectTask(i);
                        Navigator.of(context)
                            .push(pageRoute(const LessonScreen()));
                      },
                    ),
                const SizedBox(height: 18),
                caption('Достижения', color: C.accent),
                const SizedBox(height: 9),
                _Achievements(achieved: controller.prog.achieved),
              ],
            );
          },
        ),
      ),
    );
  }

  int _frontier(List<Task> tasks, Map<String, bool> done) {
    for (var i = 0; i < tasks.length; i++) {
      if (!(done[tasks[i].id] ?? false)) return i;
    }
    return tasks.length;
  }
}

class _StatsCard extends StatelessWidget {
  final int level, xp, streak, solved;
  const _StatsCard({
    required this.level,
    required this.xp,
    required this.streak,
    required this.solved,
  });

  @override
  Widget build(BuildContext context) {
    final inLevel = xp % 100;
    return glass(
      radius: 20,
      blur: 26,
      padding: const EdgeInsets.all(17),
      glow: C.glow(color: C.accent, alpha: 45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.route_outlined, color: C.accent, size: 19),
            const SizedBox(width: 8),
            Text('Уровень $level',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: C.text)),
            const Spacer(),
            Text('$xp XP',
                style: TextStyle(fontSize: 12.5, color: C.muted)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: inLevel / 100,
              minHeight: 6,
              backgroundColor: C.card2,
              color: C.accent,
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _Stat(label: 'Серия', value: '$streak дн.', color: C.warn),
            const SizedBox(width: 22),
            _Stat(label: 'Решено', value: '$solved', color: C.good),
            const SizedBox(width: 22),
            _Stat(
                label: 'До уровня',
                value: '${100 - inLevel} XP',
                color: C.secondary),
          ]),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: C.muted)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      );
}

class _RouteRow extends StatelessWidget {
  final int index, total;
  final Task task;
  final bool done, current;
  final VoidCallback onTap;
  const _RouteRow({
    required this.index,
    required this.total,
    required this.task,
    required this.done,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 78,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 42,
              child: Column(children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: index == 0 ? Colors.transparent : C.border,
                  ),
                ),
                _MapNode(
                  done: done,
                  current: current,
                  number: index + 1,
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: index == total - 1
                        ? Colors.transparent
                        : C.border,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 7),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: current
                      ? C.accent.withAlpha(C.isLight ? 22 : 28)
                      : C.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: current ? C.accent.withAlpha(110) : C.border,
                  ),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: C.text)),
                        const SizedBox(height: 3),
                        Text(
                            '${task.isQuiz ? 'тест' : (task.kind == 'theory' ? 'урок' : 'практика')} · ${task.difficulty}/5',
                            style: TextStyle(
                                fontSize: 10.5, color: C.muted)),
                      ],
                    ),
                  ),
                  if (done)
                    Icon(Icons.check_circle_rounded,
                        size: 19, color: C.good)
                  else if (current)
                    Icon(Icons.play_circle_fill_rounded,
                        size: 21, color: C.accent)
                  else
                    Icon(Icons.lock_outline, size: 17, color: C.muted),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapNode extends StatefulWidget {
  final bool done, current;
  final int number;
  const _MapNode({
    required this.done,
    required this.current,
    required this.number,
  });

  @override
  State<_MapNode> createState() => _MapNodeState();
}

class _MapNodeState extends State<_MapNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.current) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _MapNode old) {
    super.didUpdateWidget(old);
    if (widget.current && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.current && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.done
        ? C.good
        : widget.current
            ? C.accent
            : C.muted;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final scale = widget.current ? 1 + _pulse.value * 0.08 : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(widget.done || widget.current ? 45 : 16),
              border: Border.all(
                  color: color.withAlpha(widget.current ? 230 : 130),
                  width: widget.current ? 2 : 1.4),
              boxShadow: widget.current
                  ? [
                      BoxShadow(
                        color: color.withAlpha(60),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: widget.done
                  ? Icon(Icons.check, size: 16, color: color)
                  : Text('${widget.number}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: color)),
            ),
          ),
        );
      },
    );
  }
}

class _Achievements extends StatelessWidget {
  final Map<String, String> achieved;
  const _Achievements({required this.achieved});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in achievementList)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: achieved.containsKey(a.id)
                  ? C.good.withAlpha(C.isLight ? 24 : 30)
                  : C.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: achieved.containsKey(a.id)
                      ? C.good.withAlpha(100)
                      : C.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                achieved.containsKey(a.id)
                    ? Icons.workspace_premium_outlined
                    : Icons.lock_outline,
                size: 15,
                color: achieved.containsKey(a.id) ? C.good : C.muted,
              ),
              const SizedBox(width: 6),
              Text(a.title,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: achieved.containsKey(a.id) ? C.text : C.muted)),
            ]),
          ),
      ],
    );
  }
}
