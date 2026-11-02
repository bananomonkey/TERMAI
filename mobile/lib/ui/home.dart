// home.dart — главный экран в стиле Duolingo: вертикальная зигзаг-тропинка
// из кружков-курсов, толстые соединения (пройдено — ярко, впереди — серо),
// баннеры модулей каждые пять кружков. Скролл только сверху вниз.
import 'package:flutter/material.dart';

import '../main.dart';
import '../directions.dart';
import '../store.dart';
import 'app_background.dart';
import 'chat.dart';
import 'design_system.dart';
import 'dialogs.dart';
import 'direction_switcher.dart';
import 'generation_status.dart';
import 'lesson.dart';
import 'review.dart';
import 'theme.dart';
import 'update_banner.dart';
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
          return Column(
            children: [
              const DirectionSwitcher(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          controller.activeDirectionDef?.title ?? 'Направление',
                          style: AppText.title.copyWith(color: C.text),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Здесь пока нет курсов. Добавь направление через «+» или собери курс в «Ещё».',
                          textAlign: TextAlign.center,
                          style: AppText.caption.copyWith(color: C.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
        var totalTasks = 0;
        var solvedTasks = 0;
        for (final course in courses) {
          totalTasks += course.tasks.length;
          final done = controller.prog.completed[course.id] ?? {};
          solvedTasks += course.tasks.where((t) => done[t.id] ?? false).length;
        }
        final overall =
            totalTasks == 0 ? 0 : (solvedTasks / totalTasks * 100).round();
        final list = Column(
          children: [
            const DirectionSwitcher(),
            _HomeSummary(
              courses: courses.length,
              solved: solvedTasks,
              total: totalTasks,
              percent: overall,
            ),
            const GenerationStatusCard(),
            const UpdateBanner(),
            if (controller.generating && controller.fillTotal > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: appCard(
                  padding: const EdgeInsets.all(11),
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
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(3),
                          backgroundColor: C.card2,
                          color: C.accent,
                        ),
                      ]),
                ),
              ),
            Expanded(
              child: ReorderableListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  // Нижняя панель (Термай + навигация) не должна закрывать
                  // последний курс; SafeArea панели учитывает системный отступ.
                  104,
                ),
                buildDefaultDragHandles: false,
                itemCount: courses.length,
                onReorder: (oldIndex, newIndex) =>
                    controller.reorderCourses(oldIndex, newIndex),
                itemBuilder: (context, i) => _CourseTile(
                  key: ValueKey(courses[i].id),
                  index: i,
                  currentIdx: current,
                ),
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

/// _HomeSummary — короткий обзор вместо пустого пространства под списком.
/// Имя берётся из профиля; если его нет, обращение остаётся нейтральным.
class _HomeSummary extends StatelessWidget {
  final int courses, solved, total, percent;
  const _HomeSummary({
    required this.courses,
    required this.solved,
    required this.total,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final d = controller.activeDirectionDef;
    final title = d?.title ?? 'Твой маршрут';
    final category =
        d == null ? 'обучение' : directionCategoryTitle(d.category);
    return Padding(
      padding: const EdgeInsets.fromLTRB(17, 10, 17, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.screenTitle.copyWith(color: C.text),
                ),
              ),
              appStatusPill(
                '$percent%',
                color: percent >= 100 ? C.good : C.accent,
                icon: percent >= 100
                    ? Icons.check_circle_outline
                    : Icons.trending_up_rounded,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '$category · $courses ${_coursesWord(courses)} · $solved/${total} · '
            '${controller.prog.directionXp[controller.config.activeDirection] ?? 0} XP',
            style: AppText.mono.copyWith(fontSize: 10.5, color: C.muted),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : solved / total,
              minHeight: 3,
              backgroundColor: C.card2,
              color: percent >= 100 ? C.good : C.accent,
            ),
          ),
        ],
      ),
    );
  }

  String _coursesWord(int n) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return 'курсов';
    if (mod10 == 1) return 'курс';
    if (mod10 >= 2 && mod10 <= 4) return 'курса';
    return 'курсов';
  }
}

/// _CourseTile — компактная плитка курса. В спокойном состоянии видны
/// только название, прогресс и меню; перетаскивание — долгим нажатием.
class _CourseTile extends StatelessWidget {
  final int index;
  final int currentIdx;
  const _CourseTile({super.key, required this.index, required this.currentIdx});

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
    final statusColor = done ? C.good : (current ? accent : C.muted);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        // выделение текста при длинном нажатии отключено: жест принадлежит
        // перетаскиванию карточки, а не системному селекту.
        child: SelectionContainer.disabled(
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: Material(
              color: C.card.withAlpha(C.isLight ? 246 : 238),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(
                  color: current
                      ? accent.withAlpha(C.isLight ? 90 : 120)
                      : (done ? C.good.withAlpha(70) : C.border.withAlpha(100)),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context)
                    .push(pageRoute(TaskListScreen(courseIdx: index))),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 3,
                        height: 40,
                        decoration: BoxDecoration(
                          color: statusColor
                              .withAlpha(done || current ? 230 : 110),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(
                                  c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.title.copyWith(
                                    fontSize: 15,
                                    color: C.text,
                                  ),
                                ),
                              ),
                              if (done) ...[
                                const SizedBox(width: 5),
                                Icon(Icons.check_rounded,
                                    color: C.good, size: 15),
                              ],
                            ]),
                            const SizedBox(height: 3),
                            Text(
                              '$solved/$total · ${c.isTheory ? 'теория' : 'практика'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.mono.copyWith(
                                fontSize: 10.5,
                                color: C.muted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: total == 0 ? 0 : solved / total,
                                minHeight: 3,
                                backgroundColor: C.isLight
                                    ? C.border.withAlpha(90)
                                    : Colors.white.withAlpha(14),
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: AppText.mono.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: done ? C.good : C.text,
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          tooltip: 'Действия с курсом',
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          onPressed: () => _showCourseActions(context, index),
                          icon: Icon(Icons.more_vert,
                              color: C.muted.withAlpha(190)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                      _rebuildCourse(context, c.id);
                    },
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Пересобрать программу'),
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
                    onPressed: () async {
                      final ok = await showConfirmDialog(
                        ctx,
                        title: 'Удалить курс?',
                        message: '«${c.title}» исчезнет из списка. '
                            'Прогресс сохранится.',
                      );
                      if (!ok || !ctx.mounted) return;
                      controller.deleteCourse(idx);
                      Navigator.pop(ctx);
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

/// _rebuildCourse — ИИ пересобирает программу, но сначала показывает diff.
/// Завершённые задачи и их id сохраняются даже при смене программы.
Future<void> _rebuildCourse(BuildContext context, String courseId) async {
  final idx = controller.courses.indexWhere((c) => c.id == courseId);
  if (idx < 0) return;
  final course = controller.courses[idx];
  if (controller.ai == null || !controller.ai!.ready) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Нет API-ключа — настрой ИИ в «Ещё» → Настройки.')));
    return;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel)),
      title: const Text('Пересобираю программу'),
      content: ListenableBuilder(
        listenable: controller,
        builder: (_, __) {
          final op = controller.operations.active;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(op?.stage ?? 'Подготовка',
                  style: AppText.title.copyWith(fontSize: 13.5)),
              const SizedBox(height: 4),
              Text(op?.detail ?? 'Собираю новый план курса…',
                  style: AppText.caption.copyWith(color: C.muted)),
              if (op != null && op.total > 0) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: op.current / op.total,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: C.card2,
                  color: C.accent,
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => op?.requestCancel(),
                  child: const Text('Отменить'),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  final plan = await controller.prepareCourseRebuild(course);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (plan == null) {
    final msg = controller.lastFillError.isEmpty
        ? 'Не удалось пересобрать курс.'
        : controller.lastFillError;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return;
  }
  final lines = <String>[
    'Сохранено прежних: ${plan.keptTitles.length}',
    'Новых: ${plan.addedTitles.length}',
    'Удалено незавершённых: ${plan.removedTitles.length}',
    if (plan.preservedCompleted.isNotEmpty)
      'Завершённые сохранены отдельно: ${plan.preservedCompleted.length}',
    if (plan.removedTitles.isNotEmpty)
      'Будут убраны: ${plan.removedTitles.take(4).join(', ')}'
          '${plan.removedTitles.length > 4 ? '…' : ''}',
    'Прогресс и XP уже выполненных задач не сбрасываются.',
  ];
  final ok = await showConfirmDialog(
    context,
    title: 'Пересобрать «${course.title}»?',
    message: lines.join('\n'),
    confirmLabel: 'Пересобрать',
    destructive: true,
  );
  if (!ok) return;
  await controller.applyCourseRebuild(plan);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Курс «${course.title}» пересобран')));
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
            title: Text(c.title, style: AppText.screenTitle),
          ),
          body: AppBackdrop(
            child: const _TaskGroups(),
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
          kind: t.isExam
              ? 'экзамен'
              : (c.isTheory ? 'урок' : (t.isQuiz ? 'тест' : 'практика')),
          difficulty: t.difficulty,
          done: controller.isDone(t),
          current: i == _frontier(),
          isExam: t.isExam,
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
    groups.insert(0, const GenerationStatusCard());
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
  final bool done, current, isExam;
  final VoidCallback onTap;
  const _TaskRow({
    required this.index,
    required this.title,
    required this.kind,
    required this.difficulty,
    required this.done,
    required this.current,
    required this.isExam,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = cardBox(
      accent: isExam
          ? C.warn.withAlpha(180)
          : (current ? C.accent.withAlpha(C.isLight ? 90 : 110) : null),
      duration: const Duration(milliseconds: 240),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          statusGlyph(done, current),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isExam) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: C.warn.withAlpha(35),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: C.warn.withAlpha(120)),
                    ),
                    child: Text('ЭКЗАМЕН',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: C.warn)),
                  ),
                  const SizedBox(height: 5),
                ],
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
    );
    return GestureDetector(
      onTap: onTap,
      child: card,
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
          onTap: () async {
            final err = await controller.continueCourse();
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
                Icon(Icons.play_arrow_rounded, color: C.accent, size: 21),
              const SizedBox(width: 8),
              Text(
                  controller.generating
                      ? 'ИИ продолжает курс…'
                      : 'Продолжить курс',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: C.accent)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final topic = await askText(context, 'Новая задача от ИИ',
                'тема: например «времена в английском» или «проброс портов»');
            if (topic == null || topic.trim().isEmpty) return;
            final err = await controller.generateTask(topic.trim());
            if (err.isNotEmpty && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(err)));
            }
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            side: BorderSide(color: C.accent.withAlpha(90)),
          ),
          icon: const Icon(Icons.add, size: 16),
          label:
              const Text('Создать одну задачу', style: TextStyle(fontSize: 12)),
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
