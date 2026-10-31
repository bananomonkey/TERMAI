// progress_map.dart — интерактивная карта курса в виде графа.
//
// Один граф на курс: корень курса → модули (по 5 задач) → задачи/экзамены.
// Layout детерминированный, слоистый: без force-directed и пересчёта
// координат при зуме. Холст изолирован RepaintBoundary, ноды вне viewport
// не строятся (culling), сами ноды максимально лёгкие.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart' as gv;

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'app_background.dart';
import 'lesson.dart';
import 'theme.dart';
import 'widgets.dart';

class ProgressMapScreen extends StatefulWidget {
  const ProgressMapScreen({super.key});

  @override
  State<ProgressMapScreen> createState() => _ProgressMapScreenState();
}

class _ProgressMapScreenState extends State<ProgressMapScreen> {
  final TransformationController _tc = TransformationController();
  final Set<int> _collapsed = {};

  /// Ручные позиции узлов. Живут только в состоянии экрана: пользователь
  /// перетаскивает ветки и узлы, но после выхода раскладка сбрасывается.
  final Map<String, Offset> _manualPositions = {};
  String? _draggingId;
  Rect _visible = const Rect.fromLTWH(-300, -300, 1600, 1600);
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusRoot();
    });
  }

  /// _focusRoot — стартовый вид: корень по центру сверху, читаемый масштаб.
  /// Кнопка «fit» отдельно показывает всё дерево целиком.
  void _focusRoot() {
    if (controller.courses.isEmpty || _viewport == Size.zero) return;
    final graph = _buildGraph(controller.cur);
    final root = graph.nodes.firstWhere((n) => n.type == 'course',
        orElse: () => graph.nodes.first);
    const scale = 0.62;
    final tx = _viewport.width / 2 - (root.x + root.w / 2) * scale;
    final ty = 24 - root.y * scale;
    _tc.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
    setState(() {});
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransform);
    _tc.dispose();
    super.dispose();
  }

  void _onTransform() {
    if (_viewport == Size.zero) return;
    try {
      final inv = Matrix4.inverted(_tc.value);
      final rect = MatrixUtils.transformRect(
        inv,
        Offset.zero & _viewport,
      ).inflate(180);
      if (rect != _visible) setState(() => _visible = rect);
    } catch (_) {}
  }

  void _fit() {
    if (controller.courses.isEmpty) return;
    final size = _viewport;
    if (size == Size.zero) return;
    final graph = _buildGraph(controller.cur);
    final scaleX = size.width / (graph.width + 60);
    final scaleY = size.height / (graph.height + 60);
    final scale = scaleX < scaleY ? scaleX : scaleY;
    _tc.value = Matrix4.identity()
      ..translate(20.0, 20.0)
      ..scale(scale.clamp(0.08, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Карта прогресса',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Достижения',
            icon: const Icon(Icons.emoji_events_outlined, size: 21),
            onPressed: () => _showAchievements(context),
          ),
        ],
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
            final graph = _buildGraph(course);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _StatsCard(
                    level: controller.prog.level,
                    xp: controller.prog.xp,
                    streak: controller.prog.streak,
                    solved: controller.prog.solvedTotal,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: caption('Маршрут', color: C.accent),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        onSelected: (_) {
                          controller.switchCourseSilent(i);
                          _collapsed.clear();
                          _manualPositions.clear();
                          setState(() {});
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _focusRoot();
                          });
                        },
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
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'перетаскивай узлы · щипок — зум',
                      style: TextStyle(fontSize: 10.5, color: C.muted),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(builder: (context, box) {
                          _viewport = Size(box.maxWidth, box.maxHeight);
                          return ClipRect(
                            child: InteractiveViewer(
                              transformationController: _tc,
                              constrained: false,
                              minScale: 0.08,
                              maxScale: 2.6,
                              boundaryMargin:
                                  const EdgeInsets.symmetric(
                                      horizontal: 500, vertical: 500),
                              child: RepaintBoundary(
                                child: SizedBox(
                                  width: graph.width,
                                  height: graph.height,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _EdgePainter(
                                            nodes: graph.nodes,
                                            edges: graph.edges,
                                            visible: _draggingId != null
                                                ? const Rect.fromLTWH(
                                                    -99999, -99999, 199998, 199998)
                                                : _visible,
                                          ),
                                        ),
                                      ),
                                      for (final n in graph.nodes)
                                        if (_draggingId != null ||
                                            _visible.overlaps(n.rect))
                                          Positioned(
                                            key: ValueKey(n.id),
                                            left: n.x,
                                            top: n.y,
                                            width: n.w,
                                            height: n.h,
                                            child: RepaintBoundary(
                                              child: _GraphNodeView(
                                                node: n,
                                                dragging: _draggingId == n.id,
                                                onTap: () => _onNodeTap(n),
                                                onDragStart: () =>
                                                    _startDrag(n),
                                                onDrag: (d) => _dragNode(
                                                    n, d, graph.nodes),
                                                onDragEnd: _endDrag,
                                              ),
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      if (graph.nodes.length <= 1)
                        Center(
                          child: Text(
                            'В курсе пока нет задач. Открой курс и продолжи его.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: C.muted),
                          ),
                        ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ZoomButton(
                                icon: Icons.add,
                                onTap: () => _zoom(1.25)),
                            const SizedBox(height: 7),
                            _ZoomButton(
                                icon: Icons.remove,
                                onTap: () => _zoom(0.8)),
                            const SizedBox(height: 7),
                            _ZoomButton(
                                icon: Icons.fit_screen_outlined,
                                onTap: _fit),
                            const SizedBox(height: 7),
                            _ZoomButton(
                                icon: Icons.restart_alt,
                                onTap: () {
                                  setState(_manualPositions.clear);
                                  _fit();
                                }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _zoom(double factor) {
    final current = _tc.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.08, 2.6);
    final f = next / current;
    _tc.value = _tc.value.clone()..scale(f);
    setState(() {});
  }

  void _onNodeTap(_GNode n) {
    if (n.type == 'module') {
      setState(() {
        if (!_collapsed.remove(n.module)) _collapsed.add(n.module);
      });
      return;
    }
    if (n.taskIndex != null) {
      controller.selectTask(n.taskIndex!);
      Navigator.of(context).push(pageRoute(const LessonScreen()));
    }
  }

  void _startDrag(_GNode n) {
    setState(() => _draggingId = n.id);
  }

  void _endDrag() {
    if (_draggingId == null) return;
    setState(() => _draggingId = null);
  }

  /// _dragNode — перетаскивание узла. Корень тянет всё дерево,
  /// модуль — свою ветку с задачами, задача — только себя.
  void _dragNode(_GNode n, Offset delta, List<_GNode> all) {
    setState(() {
      Iterable<_GNode> targets;
      if (n.type == 'course') {
        targets = all;
      } else if (n.type == 'module') {
        targets = all.where(
            (x) => x.id == n.id || (x.type != 'module' && x.module == n.module));
      } else {
        targets = [n];
      }
      for (final t in targets) {
        final current = _manualPositions[t.id] ?? Offset(t.x, t.y);
        _manualPositions[t.id] = Offset(
          math.max(0.0, current.dx + delta.dx),
          math.max(0.0, current.dy + delta.dy),
        );
      }
    });
  }

  void _showAchievements(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Достижения',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: C.text)),
              const SizedBox(height: 12),
              _Achievements(achieved: controller.prog.achieved),
            ],
          ),
        ),
      ),
    );
  }

  /// _buildGraph — настоящее дерево: корень → модули → задачи.
  /// Координаты считает BuchheimWalkerAlgorithm (слоистый tree layout),
  /// а не ручная колонка. Поэтому модули и задачи одного уровня
  /// расходятся веером, а не выстраиваются в один список.
  _Graph _buildGraph(Course course) {
    final tasks = course.tasks;
    final done = controller.prog.completed[course.id] ?? {};
    var frontier = tasks.length;
    for (var i = 0; i < tasks.length; i++) {
      if (!(done[tasks[i].id] ?? false)) {
        frontier = i;
        break;
      }
    }

    final nodes = <_GNode>[];
    final graph = gv.Graph()..isTree = true;

    final rootMeta = _GNode(
      id: 'root',
      type: 'course',
      label: course.title,
      module: -1,
      x: 0,
      y: 0,
      w: 280,
      h: 58,
    );
    nodes.add(rootMeta);
    final root = gv.Node.Id('root')..size = Size(rootMeta.w, rootMeta.h);
    graph.addNode(root);

    for (var start = 0; start < tasks.length; start += 5) {
      final end = (start + 5).clamp(0, tasks.length);
      final count = end - start;
      final moduleIndex = start ~/ 5;
      var topic = course.title;
      if (course.syllabus.isNotEmpty) {
        topic = course.syllabus[
            (moduleIndex).clamp(0, course.syllabus.length - 1)];
      }
      final moduleDone = <Task>[
        for (var i = start; i < end; i++) tasks[i]
      ].every((t) => done[t.id] ?? false);
      final moduleId = 'm$moduleIndex';
      final moduleMeta = _GNode(
        id: moduleId,
        type: 'module',
        label: topic,
        module: moduleIndex,
        x: 0,
        y: 0,
        w: 210,
        h: 56,
        done: moduleDone,
        count: count,
        collapsed: _collapsed.contains(moduleIndex),
      );
      nodes.add(moduleMeta);
      final moduleNode = gv.Node.Id(moduleId)
        ..size = Size(moduleMeta.w, moduleMeta.h);
      graph.addNode(moduleNode);
      graph.addEdge(root, moduleNode);

      if (!_collapsed.contains(moduleIndex)) {
        for (var i = start; i < end; i++) {
          final t = tasks[i];
          final taskId = 't$i';
          final taskMeta = _GNode(
            id: taskId,
            type: t.isExam ? 'exam' : 'task',
            label: t.title,
            module: moduleIndex,
            taskIndex: i,
            x: 0,
            y: 0,
            w: 244,
            h: 54,
            done: done[t.id] ?? false,
            current: i == frontier,
            exam: t.isExam,
            subtitle: t.isExam
                ? 'экзамен'
                : (t.isQuiz ? 'тест' : 'практика'),
          );
          nodes.add(taskMeta);
          final taskNode = gv.Node.Id(taskId)
            ..size = Size(taskMeta.w, taskMeta.h);
          graph.addNode(taskNode);
          graph.addEdge(moduleNode, taskNode);
        }
      }
    }

    // Слоистый tree-layout: глубина → уровень, братья расходятся по ширине.
    final config = gv.BuchheimWalkerConfiguration()
      ..siblingSeparation = 26
      ..levelSeparation = 112
      ..subtreeSeparation = 46
      ..orientation = gv.BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM;
    final alg = gv.BuchheimWalkerAlgorithm(config, null);
    final graphSize = alg.run(graph, 40, 32);

    final byId = {for (final n in nodes) n.id: n};
    var maxX = graphSize.width + 80;
    var maxY = graphSize.height + 80;
    for (final gn in graph.nodes) {
      final id = gn.key?.value.toString() ?? '';
      final meta = byId[id];
      if (meta == null) continue;
      final manual = _manualPositions[id];
      meta.x = manual?.dx ?? gn.position.dx;
      meta.y = manual?.dy ?? gn.position.dy;
      maxX = math.max(maxX, meta.x + meta.w + 80);
      maxY = math.max(maxY, meta.y + meta.h + 80);
    }

    final edges = <_GEdge>[];
    for (final e in graph.edges) {
      final from = e.source.key?.value.toString() ?? '';
      final to = e.destination.key?.value.toString() ?? '';
      if (from.isEmpty || to.isEmpty) continue;
      edges.add(_GEdge(from, to));
    }

    return _Graph(
      nodes: nodes,
      edges: edges,
      width: maxX,
      height: math.max(maxY, 260.0),
    );
  }
}

class _Graph {
  final List<_GNode> nodes;
  final List<_GEdge> edges;
  final double width, height;
  _Graph({
    required this.nodes,
    required this.edges,
    required this.width,
    required this.height,
  });
}

class _GNode {
  final String id, type, label, subtitle;
  final int module;
  final int? taskIndex;
  double x, y;
  final double w, h;
  final bool done, current, exam, collapsed;
  final int count;
  _GNode({
    required this.id,
    required this.type,
    required this.label,
    required this.module,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.taskIndex,
    this.done = false,
    this.current = false,
    this.exam = false,
    this.collapsed = false,
    this.count = 0,
    this.subtitle = '',
  });

  Rect get rect => Rect.fromLTWH(x, y, w, h);
  Offset get right => Offset(x + w, y + h / 2);
  Offset get left => Offset(x, y + h / 2);
  Offset get bottom => Offset(x + w / 2, y + h);
  Offset get top => Offset(x + w / 2, y);
}

class _GEdge {
  final String from, to;
  _GEdge(this.from, this.to);
}

class _EdgePainter extends CustomPainter {
  final List<_GNode> nodes;
  final List<_GEdge> edges;
  final Rect visible;

  _EdgePainter({
    required this.nodes,
    required this.edges,
    required this.visible,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final n in nodes) n.id: n};
    for (final e in edges) {
      final a = byId[e.from], b = byId[e.to];
      if (a == null || b == null) continue;
      if (!visible.overlaps(a.rect.expandToInclude(b.rect).inflate(40))) {
        continue;
      }
      final color = b.done
          ? C.good.withAlpha(150)
          : b.current
              ? C.accent.withAlpha(200)
              : C.border;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.current ? 2.2 : 1.5
        ..strokeCap = StrokeCap.round;
      final path = Path();
      final p1 = a.bottom, p2 = b.top;
      final mid = (p1.dy + p2.dy) / 2;
      path.moveTo(p1.dx, p1.dy);
      path.cubicTo(p1.dx, mid, p2.dx, mid, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) => true;
}

class _GraphNodeView extends StatelessWidget {
  final _GNode node;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final bool dragging;
  const _GraphNodeView({
    required this.node,
    required this.onTap,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.dragging,
  });

  @override
  Widget build(BuildContext context) {
    final Color main = node.exam
        ? C.warn
        : node.done
            ? C.good
            : node.current
                ? C.accent
                : C.muted;
    final bool module = node.type == 'module';
    final bool root = node.type == 'course';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: (_) => onDragStart(),
      onPanUpdate: (d) => onDrag(d.delta),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      child: AnimatedScale(
        scale: dragging ? 1.04 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: module || root ? 12 : 10, vertical: 7),
          decoration: BoxDecoration(
            color: node.current
                ? main.withAlpha(C.isLight ? 26 : 34)
                : C.card,
            borderRadius: BorderRadius.circular(module || root ? 14 : 12),
            border: Border.all(
              color: dragging
                  ? main.withAlpha(230)
                  : node.current || node.exam
                      ? main.withAlpha(190)
                      : (node.done ? main.withAlpha(110) : C.border),
              width: dragging || node.current || node.exam ? 1.8 : 1,
            ),
            boxShadow: dragging
                ? [
                    BoxShadow(
                      color: main.withAlpha(70),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ]
                : node.current
                    ? [
                        BoxShadow(
                          color: main.withAlpha(45),
                          blurRadius: 10,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
          ),
          child: Row(children: [
            Icon(
              root
                  ? Icons.route_outlined
                  : module
                      ? (node.done
                          ? Icons.check_circle_outline
                          : Icons.folder_outlined)
                      : node.exam
                          ? Icons.assignment_late_outlined
                          : node.done
                              ? Icons.check_circle_rounded
                              : node.current
                                  ? Icons.play_circle_fill_rounded
                                  : Icons.circle_outlined,
              size: root || module ? 18 : 17,
              color: main,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.label,
                    maxLines: module || root ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: root ? 13.5 : (module ? 12.5 : 11.5),
                      height: 1.18,
                      fontWeight: FontWeight.w700,
                      color: node.done || node.current || node.exam
                          ? C.text
                          : C.muted,
                    ),
                  ),
                  if (module)
                    Text(
                      node.done
                          ? 'модуль пройден'
                          : '${node.count} уроков',
                      style: TextStyle(
                          fontSize: 9.5,
                          color: node.done ? C.good : C.muted),
                    )
                  else if (node.subtitle.isNotEmpty)
                    Text(node.subtitle,
                        style:
                            TextStyle(fontSize: 9.5, color: C.muted)),
                ],
              ),
            ),
            Icon(Icons.drag_indicator,
                size: 14, color: C.muted.withAlpha(dragging ? 200 : 110)),
            if (module)
              Icon(
                node.collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 16,
                color: C.muted,
              ),
          ]),
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.card.withAlpha(225),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 20, color: C.text),
        ),
      ),
    );
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
      radius: 18,
      blur: 20,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      glow: C.glow(color: C.accent, alpha: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.route_outlined, color: C.accent, size: 17),
            const SizedBox(width: 7),
            Text('Уровень $level',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: C.text)),
            const Spacer(),
            Text('$xp XP',
                style: TextStyle(fontSize: 11.5, color: C.muted)),
          ]),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: inLevel / 100,
              minHeight: 5,
              backgroundColor: C.card2,
              color: C.accent,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _Stat(label: 'Серия', value: '$streak дн.', color: C.warn),
            const SizedBox(width: 20),
            _Stat(label: 'Решено', value: '$solved', color: C.good),
            const SizedBox(width: 20),
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
          Text(label, style: TextStyle(fontSize: 10, color: C.muted)),
          const SizedBox(height: 1),
          Text(value,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      );
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
