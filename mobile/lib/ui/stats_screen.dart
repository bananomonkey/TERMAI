// stats_screen.dart — честная статистика TERMAI: только реальные события.
// Периоды «неделя / месяц / всё время», общий и разрез по направлениям,
// графики активности/XP/времени, уроки, практика и достижения.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../directions.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'app_background.dart';
import 'design_system.dart';
import 'theme.dart';

enum _Period { week, month, all }

enum _Metric { solved, xp, minutes }

enum _Scope { overall, directions }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _Period _period = _Period.week;
  _Metric _metric = _Metric.solved;
  _Scope _scope = _Scope.overall;
  String? _detailDirection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Статистика', style: AppText.screenTitle),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final dirs = controller.selectedDirections;
            final detail = _detailDirectionFor(dirs);
            final directionId = _scope == _Scope.directions ? detail?.id : null;
            final now = DateTime.now();
            final start = _rangeStart(now);
            final snapshot = _Snapshot.from(
              controller: controller,
              directionId: directionId,
              start: start,
            );
            final points = _chartPoints(
              directionId: directionId,
              start: start,
              now: now,
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
              children: [
                _periodSelector(),
                const SizedBox(height: 10),
                _scopeSelector(dirs),
                if (_scope == _Scope.directions && dirs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _directionSelector(dirs, detail?.id),
                ],
                const SizedBox(height: 14),
                _heroCard(snapshot, detail),
                const SizedBox(height: 12),
                _summaryGrid(snapshot),
                const SizedBox(height: 18),
                _chartCard(points, snapshot),
                if (controller.prog.dailySolved.isEmpty) ...[
                  const SizedBox(height: 10),
                  appCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 17, color: C.muted),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'История по дням начнёт заполняться с первого '
                            'решённого урока в этой версии. Старые XP и '
                            'решённые задачи показаны в общей статистике, '
                            'но не приписаны к выдуманным датам.',
                            style: AppText.caption.copyWith(color: C.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _directionsSection(dirs, start),
                const SizedBox(height: 18),
                _achievementsSection(),
              ],
            );
          },
        ),
      ),
    );
  }

  DirectionDef? _detailDirectionFor(List<DirectionDef> dirs) {
    if (dirs.isEmpty) return null;
    final id = _detailDirection ?? controller.config.activeDirection;
    for (final d in dirs) {
      if (d.id == id) return d;
    }
    return dirs.first;
  }

  DateTime? _rangeStart(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _Period.week:
        return today.subtract(const Duration(days: 6));
      case _Period.month:
        return today.subtract(const Duration(days: 29));
      case _Period.all:
        return null;
    }
  }

  Widget _periodSelector() {
    const labels = {
      _Period.week: 'Неделя',
      _Period.month: 'Месяц',
      _Period.all: 'Всё время',
    };
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final p in _Period.values)
          ChoiceChip(
            label: Text(labels[p]!),
            selected: _period == p,
            onSelected: (_) => setState(() => _period = p),
          ),
      ],
    );
  }

  Widget _scopeSelector(List<DirectionDef> dirs) {
    return Row(
      children: [
        Expanded(
          child: _ScopeButton(
            label: 'Общая',
            icon: Icons.summarize_outlined,
            active: _scope == _Scope.overall,
            onTap: () => setState(() => _scope = _Scope.overall),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ScopeButton(
            label: 'По направлениям',
            icon: Icons.account_tree_outlined,
            active: _scope == _Scope.directions,
            onTap: dirs.isEmpty
                ? null
                : () => setState(() => _scope = _Scope.directions),
          ),
        ),
      ],
    );
  }

  Widget _directionSelector(List<DirectionDef> dirs, String? selected) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final d in dirs)
          ChoiceChip(
            label: Text(d.shortTitle),
            selected: d.id == selected,
            onSelected: (_) => setState(() => _detailDirection = d.id),
          ),
      ],
    );
  }

  Widget _heroCard(_Snapshot s, DirectionDef? detail) {
    final inLevel = controller.prog.xp % 100;
    final title = _scope == _Scope.directions && detail != null
        ? detail.title
        : 'Весь прогресс';
    final subtitle = _scope == _Scope.directions && detail != null
        ? directionCategoryTitle(detail.category)
        : 'Все выбранные направления';
    final periodLabel = switch (_period) {
      _Period.week => 'за 7 дней',
      _Period.month => 'за 30 дней',
      _Period.all => 'за всё время',
    };
    return appCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      accent: C.accent.withAlpha(C.isLight ? 80 : 105),
      glowAlpha: 24,
      glowColor: C.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title.copyWith(fontSize: 16)),
                    Text(subtitle,
                        style: AppText.caption.copyWith(color: C.muted)),
                  ],
                ),
              ),
              appStatusPill('ур. ${controller.prog.level}',
                  color: C.accent, icon: Icons.bolt_rounded),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${s.xp}',
                        style: TextStyle(
                            fontSize: 30,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: C.text)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('XP $periodLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(color: C.muted)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('серия ${controller.prog.streak} дн.',
                  maxLines: 1, style: AppText.caption.copyWith(color: C.warn)),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: inLevel / 100,
              minHeight: 5,
              backgroundColor: C.card2,
              color: C.accent,
            ),
          ),
          const SizedBox(height: 5),
          Text('до следующего уровня ${100 - inLevel} XP',
              style: AppText.caption.copyWith(color: C.muted)),
        ],
      ),
    );
  }

  Widget _summaryGrid(_Snapshot s) {
    final cards = [
      _SummaryCard(
          icon: Icons.check_circle_outline,
          label: 'Решено',
          value: '${s.solved}',
          color: C.good),
      _SummaryCard(
          icon: Icons.school_outlined,
          label: 'Уроки',
          value: '${s.lessons}',
          color: C.secondary),
      _SummaryCard(
          icon: Icons.terminal_outlined,
          label: 'Практика',
          value: '${s.practice}',
          color: C.accent),
      _SummaryCard(
          icon: Icons.timer_outlined,
          label: 'Время',
          value: _formatDuration(s.seconds),
          color: C.warn),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(130.0, (constraints.maxWidth - 9) / 2);
        return Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _chartCard(List<_ChartPoint> points, _Snapshot s) {
    final total = points.fold<int>(0, (a, p) => a + p.value);
    final metricLabel = switch (_metric) {
      _Metric.solved => 'решено',
      _Metric.xp => 'XP',
      _Metric.minutes => 'минут',
    };
    return appCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('График активности',
                        style: AppText.title.copyWith(fontSize: 14)),
                    Text(
                      '${points.length} ${_bucketWord(points.length)} · '
                      '$total $metricLabel',
                      style: AppText.caption.copyWith(color: C.muted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_Metric>(
                tooltip: 'Показатель графика',
                initialValue: _metric,
                onSelected: (m) => setState(() => _metric = m),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Metric.solved, child: Text('Решено')),
                  PopupMenuItem(value: _Metric.xp, child: Text('XP')),
                  PopupMenuItem(value: _Metric.minutes, child: Text('Минуты')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: C.card2,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    border: Border.all(color: C.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_metricTitle(_metric),
                        style: AppText.caption.copyWith(color: C.text)),
                    const SizedBox(width: 3),
                    Icon(Icons.expand_more, size: 15, color: C.muted),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 168,
            child: _ActivityChart(
              points: points,
              color: _metric == _Metric.xp
                  ? C.secondary
                  : (_metric == _Metric.minutes ? C.warn : C.accent),
              emptyText: total == 0 ? 'Нет данных за период' : null,
            ),
          ),
          if (_period == _Period.all && points.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('По месяцам · последние ${points.length}',
                  style: AppText.caption.copyWith(color: C.muted)),
            ),
        ],
      ),
    );
  }

  Widget _directionsSection(List<DirectionDef> dirs, DateTime? start) {
    if (dirs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        appSectionTitle('По направлениям'),
        for (final d in dirs) ...[
          _DirectionStatsRow(direction: d, start: start),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _achievementsSection() {
    final achieved = controller.prog.achieved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        appSectionTitle('Достижения',
            trailing: Text('${achieved.length}/${achievementList.length}',
                style: AppText.caption.copyWith(color: C.muted))),
        appCard(
          padding: const EdgeInsets.all(11),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in achievementList)
                _AchievementChip(
                    achievement: a, unlocked: achieved.containsKey(a.id)),
            ],
          ),
        ),
      ],
    );
  }

  List<_ChartPoint> _chartPoints({
    required String? directionId,
    required DateTime? start,
    required DateTime now,
  }) {
    if (_period == _Period.all) {
      return _monthPoints(directionId);
    }
    final from = start!;
    final days = now.difference(from).inDays + 1;
    final points = <_ChartPoint>[];
    for (var i = 0; i < days; i++) {
      final day = from.add(Duration(days: i));
      final key = Progress.dayKey(day);
      points.add(_ChartPoint(
        label: '${day.day}',
        fullLabel: _dayFull(day),
        value: _metricValue(controller.prog, directionId, key),
      ));
    }
    return points;
  }

  List<_ChartPoint> _monthPoints(String? directionId) {
    final all = <String>{
      ...controller.prog.dailySolved.keys,
      ...controller.prog.dailyXp.keys
    };
    DateTime first;
    if (all.isEmpty) {
      final now = DateTime.now();
      first = DateTime(now.year, now.month - 5);
    } else {
      final dates = all.map(DateTime.parse).toList()..sort();
      first = DateTime(dates.first.year, dates.first.month);
    }
    final now = DateTime.now();
    final months = <_ChartPoint>[];
    var cursor = DateTime(first.year, first.month);
    while (!cursor.isAfter(DateTime(now.year, now.month))) {
      final next = DateTime(cursor.year, cursor.month + 1);
      var value = 0;
      for (var d = cursor;
          d.isBefore(next);
          d = d.add(const Duration(days: 1))) {
        value += _metricValue(controller.prog, directionId, Progress.dayKey(d));
      }
      months.add(_ChartPoint(
        label: _monthShort(cursor.month),
        fullLabel: '${_monthTitle(cursor.month)} ${cursor.year}',
        value: value,
      ));
      cursor = next;
    }
    if (months.length > 24) return months.sublist(months.length - 24);
    return months;
  }

  int _metricValue(Progress p, String? directionId, String day) {
    switch (_metric) {
      case _Metric.solved:
        return directionId == null
            ? (p.dailySolved[day] ?? 0)
            : (p.dailyDirectionSolved[day]?[directionId] ?? 0);
      case _Metric.xp:
        return directionId == null
            ? (p.dailyXp[day] ?? 0)
            : (p.dailyDirectionXp[day]?[directionId] ?? 0);
      case _Metric.minutes:
        final seconds = directionId == null
            ? (p.dailySeconds[day] ?? 0)
            : (p.dailyDirectionSeconds[day]?[directionId] ?? 0);
        return (seconds / 60).round();
    }
  }
}

class _Snapshot {
  final int solved, xp, lessons, practice, seconds;
  const _Snapshot({
    required this.solved,
    required this.xp,
    required this.lessons,
    required this.practice,
    required this.seconds,
  });

  factory _Snapshot.from({
    required AppController controller,
    required String? directionId,
    required DateTime? start,
  }) {
    final p = controller.prog;
    final startKey = start == null ? null : Progress.dayKey(start);
    bool inRange(String day) =>
        startKey == null || day.compareTo(startKey) >= 0;

    var solved = 0;
    var xp = 0;
    var seconds = 0;
    if (start == null) {
      // За всё время канонические счётчики Progress точнее суммы дневной
      // истории: они включают и задачи, решённые до появления истории.
      solved = directionId == null
          ? p.solvedTotal
          : (p.directionSolved[directionId] ?? 0);
      xp = directionId == null ? p.xp : (p.directionXp[directionId] ?? 0);
    } else {
      for (final e in p.dailySolved.entries) {
        if (!inRange(e.key)) continue;
        solved += directionId == null
            ? e.value
            : (p.dailyDirectionSolved[e.key]?[directionId] ?? 0);
      }
      for (final e in p.dailyXp.entries) {
        if (!inRange(e.key)) continue;
        xp += directionId == null
            ? e.value
            : (p.dailyDirectionXp[e.key]?[directionId] ?? 0);
      }
    }
    for (final e in p.dailySeconds.entries) {
      if (!inRange(e.key)) continue;
      seconds += directionId == null
          ? e.value
          : (p.dailyDirectionSeconds[e.key]?[directionId] ?? 0);
    }

    var lessons = 0;
    var practice = 0;
    if (start == null) {
      for (final c in controller.allCourses) {
        if (directionId != null && c.direction != directionId) continue;
        final done = p.completed[c.id] ?? const <String, bool>{};
        for (final t in c.tasks) {
          if (done[t.id] != true) continue;
          if (t.kind == 'cmd') {
            practice++;
          } else {
            lessons++;
          }
        }
      }
    } else {
      final refs = <String, _TaskRef>{};
      for (final c in controller.allCourses) {
        if (directionId != null && c.direction != directionId) continue;
        for (final t in c.tasks) {
          refs[Progress.taskKey(c.id, t.id)] = _TaskRef(c, t);
        }
      }
      final fromMs = start.millisecondsSinceEpoch ~/ 1000;
      for (final e in p.solvedAt.entries) {
        if (e.value < fromMs) continue;
        final ref = refs[e.key];
        if (ref == null) continue;
        if (ref.task.kind == 'cmd') {
          practice++;
        } else {
          lessons++;
        }
      }
    }

    return _Snapshot(
      solved: solved,
      xp: xp,
      lessons: lessons,
      practice: practice,
      seconds: seconds,
    );
  }
}

class _TaskRef {
  final Course course;
  final Task task;
  const _TaskRef(this.course, this.task);
}

class _ChartPoint {
  final String label, fullLabel;
  final int value;
  const _ChartPoint({
    required this.label,
    required this.fullLabel,
    required this.value,
  });
}

class _ActivityChart extends StatelessWidget {
  final List<_ChartPoint> points;
  final Color color;
  final String? emptyText;
  const _ActivityChart({
    required this.points,
    required this.color,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
          child: Text('Нет данных', style: TextStyle(color: C.muted)));
    }
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _BarChartPainter(
              points: points,
              color: color,
              textColor: C.text,
              mutedColor: C.muted,
              gridColor: C.border.withAlpha(90),
            ),
          ),
        ),
        if (emptyText != null)
          Positioned.fill(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: C.surface.withAlpha(210),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(emptyText!,
                    style: AppText.caption.copyWith(color: C.muted)),
              ),
            ),
          ),
      ],
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final Color color, textColor, mutedColor, gridColor;
  _BarChartPainter({
    required this.points,
    required this.color,
    required this.textColor,
    required this.mutedColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 22.0;
    const top = 16.0;
    final chartHeight = size.height - bottom - top;
    final maxValue =
        points.fold<int>(0, (a, p) => math.max(a, p.value)).toDouble();
    final niceMax = maxValue <= 0 ? 1.0 : maxValue;
    final baseline = top + chartHeight;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), grid);
    canvas.drawLine(Offset(0, top), Offset(size.width, top),
        grid..color = gridColor.withAlpha(45));

    final slot = size.width / math.max(1, points.length);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = color;
    final fillPaint = Paint()..color = color.withAlpha(38);

    // координаты точек линейного графика
    final pts = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final v = points[i].value.toDouble();
      final y = v <= 0
          ? baseline
          : baseline - chartHeight * (v / niceMax);
      pts.add(Offset(slot * i + slot / 2, y));
    }

    // мягкая заливка под линией
    if (pts.isNotEmpty) {
      final fill = Path()
        ..moveTo(pts.first.dx, baseline);
      for (final p in pts) {
        fill.lineTo(p.dx, p.dy);
      }
      fill.lineTo(pts.last.dx, baseline);
      fill.close();
      canvas.drawPath(fill, fillPaint);
    }

    // сама линия
    for (var i = 0; i + 1 < pts.length; i++) {
      canvas.drawLine(pts[i], pts[i + 1], linePaint);
    }
    // точки
    for (var i = 0; i < pts.length; i++) {
      final r = i == pts.length - 1 ? 4.0 : 2.8;
      canvas.drawCircle(pts[i], r, dotPaint);
      if (points[i].value > 0 && points[i].value == maxValue.round()) {
        canvas.drawCircle(pts[i], r + 2.2,
            Paint()..style = PaintingStyle.stroke ..strokeWidth = 1.6 ..color = C.accent);
      }
      final showLabel = _showLabel(i, points.length);
      if (showLabel) {
        final tp = TextPainter(
          text: TextSpan(
            text: _periodLabel(points[i]),
            style: TextStyle(
              fontSize: 9,
              color: i == points.length - 1 ? textColor : mutedColor,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: slot * 2.2);
        tp.paint(canvas, Offset(pts[i].dx - tp.width / 2, baseline + 5));
      }
    }
    if (points.any((p) => p.value > 0)) {
      final maxText = TextPainter(
        text: TextSpan(
          text: 'макс ${points.fold<int>(0, (a, p) => math.max(a, p.value))}',
          style: TextStyle(fontSize: 9, color: mutedColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      maxText.paint(canvas, const Offset(0, 0));
    }
  }

  bool _showLabel(int index, int total) {
    if (total <= 8) return true;
    if (index == 0 || index == total - 1) return true;
    final step = (total / 6).ceil();
    return index % step == 0;
  }

  String _periodLabel(_ChartPoint p) => p.label;

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.points != points || old.color != color;
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return appCard(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withAlpha(C.isLight ? 24 : 34),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: C.text)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: C.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;
  const _ScopeButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? C.card : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        side: BorderSide(color: active ? C.accent.withAlpha(105) : C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? C.accent : C.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                        color: active ? C.text : C.muted,
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionStatsRow extends StatelessWidget {
  final DirectionDef direction;
  final DateTime? start;
  const _DirectionStatsRow({required this.direction, required this.start});

  @override
  Widget build(BuildContext context) {
    final all = controller.statsForDirection(direction.id);
    final startKey = start == null ? null : Progress.dayKey(start!);
    var periodSolved = 0;
    var periodXp = 0;
    var periodSeconds = 0;
    for (final e in controller.prog.dailyDirectionSolved.entries) {
      if (startKey != null && e.key.compareTo(startKey) < 0) continue;
      periodSolved += e.value[direction.id] ?? 0;
    }
    for (final e in controller.prog.dailyDirectionXp.entries) {
      if (startKey != null && e.key.compareTo(startKey) < 0) continue;
      periodXp += e.value[direction.id] ?? 0;
    }
    for (final e in controller.prog.dailyDirectionSeconds.entries) {
      if (startKey != null && e.key.compareTo(startKey) < 0) continue;
      periodSeconds += e.value[direction.id] ?? 0;
    }
    final showPeriod = start != null;
    return appCard(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(direction.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(fontSize: 13.5)),
              ),
              Text('${all.percent}%',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: all.percent >= 100 ? C.good : C.accent)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            showPeriod
                ? '$periodSolved решено · $periodXp XP · ${_formatDuration(periodSeconds)} за период'
                : '${all.solved}/${all.total} решено · ${all.xp} XP',
            style: AppText.caption.copyWith(color: C.muted),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: all.total == 0 ? 0 : all.solved / all.total,
              minHeight: 4,
              backgroundColor: C.card2,
              color: all.percent >= 100 ? C.good : C.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementChip extends StatelessWidget {
  final Achievement achievement;
  final bool unlocked;
  const _AchievementChip({required this.achievement, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: unlocked ? C.good.withAlpha(C.isLight ? 24 : 32) : C.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: unlocked ? C.good.withAlpha(100) : C.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          unlocked ? Icons.workspace_premium_outlined : Icons.lock_outline,
          size: 14,
          color: unlocked ? C.good : C.muted,
        ),
        const SizedBox(width: 5),
        Text(achievement.title,
            style: AppText.caption.copyWith(
                color: unlocked ? C.text : C.muted,
                fontWeight: unlocked ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }
}

String _metricTitle(_Metric m) => switch (m) {
      _Metric.solved => 'Решено',
      _Metric.xp => 'XP',
      _Metric.minutes => 'Минуты',
    };

String _formatDuration(int seconds) {
  if (seconds <= 0) return '0 мин';
  if (seconds < 60) return '$seconds с';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes мин';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h ч' : '$h ч $m мин';
}

String _monthShort(int month) => const [
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек'
    ][month - 1];

String _monthTitle(int month) => const [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь'
    ][month - 1];

String _dayFull(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

String _bucketWord(int n) {
  final mod100 = n % 100;
  final mod10 = n % 10;
  if (mod100 >= 11 && mod100 <= 14) return 'точек';
  if (mod10 == 1) return 'точка';
  if (mod10 >= 2 && mod10 <= 4) return 'точки';
  return 'точек';
}
