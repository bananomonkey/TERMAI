// conveyor_home.dart — заводской конвейер выбора курсов:
// верхний ярус — робот-манипулятор на рельсе, средний — дощечка ожидания,
// нижний — стеклянные стаканы. Барсик в стеклянном куполе жмёт красную кнопку
// лапой, коробки ровно падают из трубы, робот распределяет их по стаканам.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../main.dart';
import '../store.dart';
import 'home.dart' show TaskListScreen;
import 'theme.dart';
import 'widgets.dart';

const _kBoxW = 62.0, _kBoxH = 48.0, _kCap = 4;

class ConveyorCoursesView extends StatefulWidget {
  const ConveyorCoursesView({super.key});
  @override
  State<ConveyorCoursesView> createState() => _ConveyorCoursesViewState();
}

class _Movable {
  Offset pos, target;
  double speed; // px/сек
  _Movable(this.pos, this.speed, {Offset? target}) : target = target ?? pos;
}

class _ConveyorCoursesViewState extends State<ConveyorCoursesView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Size _size = Size.zero;

  // сцена
  final belt = <int>[];          // курсы на дощечке (в порядке очереди)
  final chutes = <List<int>>[];  // стаканы: списки courseIdx снизу вверх
  final spawnQueue = <int>[];    // ещё не вылетевшие из трубы
  int? carried;                  // курс в клешне
  _Movable? carriedPos;
  _Movable? falling;             // коробка летит из трубы на дощечку (courseIdx в pos-кастом)
  int? fallingIdx;

  // робот
  late _Movable trolley;   // x на рельсе
  double clawY = 46;       // y кончика клешни
  double clawTarget = 46;
  bool robotBusy = false;

  // Барсик
  double pawAngle = -0.9;  // лапа поднята к кнопке
  bool buttonStruck = false;
  bool buttonPulse = false;
  double leverAngle = 0;
  double catWag = 0;
  Timer? _leverTimer;

  // интерактив
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  Offset? _lastTapPos;

  Offset _beltBoxPos(int slot) {
    final beltL = _size.width * 0.16, beltR = _size.width * 0.84;
    final step = (beltR - beltL - _kBoxW) / 3;
    return Offset(beltL + 10 + slot * step, _size.height * 0.40 - _kBoxH / 2 - 4);
  }

  double _railY() => 64;
  double _beltY() => _size.height * 0.40;
  double _chuteTop() => _size.height * 0.56;
  double _chuteFloor() => _size.height - 24;
  Offset _chuteCenter(int ch) {
    final n = math.max(1, _targetChuteCount());
    final cw = (_size.width - 24) / n;
    return Offset(12 + cw * (ch + 0.5), (_chuteTop() + _chuteFloor()) / 2);
  }

  int _targetChuteCount() => ((controller.courses.length + _kCap - 1) / _kCap).ceil().clamp(1, 4);

  Offset _stackPos(int ch, int level) {
    final c = _chuteCenter(ch);
    return Offset(c.dx, _chuteFloor() - _kBoxH / 2 - 2 - level * (_kBoxH + 3));
  }

  @override
  void initState() {
    super.initState();
    trolley = _Movable(const Offset(120, 64), 260);
    _ticker = createTicker(_tick);
    _ticker.start();
    // новые курсы (созданные в «Ещё») вылетают из трубы
    var known = -1;
    void checkNew() {
      if (controller.courses.length > known) {
        if (known >= 0) {
          for (var i = known; i < controller.courses.length; i++) {
            spawnQueue.add(i);
          }
          unawaited(_spawnPending());
        }
        known = controller.courses.length;
      }
    }
    controller.addListener(checkNew);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkNew());
  }

  @override
  void dispose() {
    _leverTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  // ---------- запуск шоу ----------

  Future<void> _startShow() async {
    if (buttonStruck || robotBusy) return;
    buttonStruck = true;
    // Барсик бьёт лапой по кнопке
    for (final a in [-0.2, -0.85, -0.25, -0.8]) {
      setState(() => pawAngle = a);
      await Future.delayed(const Duration(milliseconds: 90));
    }
    setState(() => pawAngle = -0.55);
    // рычаг качается, пока работает конвейер
    _leverTimer?.cancel();
    _leverTimer = Timer.periodic(const Duration(milliseconds: 90), (t) {
      if (mounted) setState(() => leverAngle = math.sin(t.tick * 0.012) * 0.35);
    });
    // коробки вылетают из трубы ровно друг за другом
    for (var i = 0; i < controller.courses.length; i++) {
      if (!mounted) return;
      spawnQueue.add(i);
      await _dropOneFromPipe();
      await Future.delayed(const Duration(milliseconds: 320));
    }
    // робот распределяет всё с дощечки
    await _runRobot();
    _leverTimer?.cancel();
    if (mounted) setState(() => leverAngle = 0);
  }

  Future<void> _spawnPending() async {
    while (spawnQueue.isNotEmpty && mounted) {
      await _dropOneFromPipe();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (belt.isNotEmpty && mounted) await _runRobot();
  }

  Future<void> _dropOneFromPipe() async {
    if (spawnQueue.isEmpty || _size == Size.zero) return;
    final idx = spawnQueue.removeAt(0);
    final start = Offset(_size.width / 2, 40);
    final box = _Movable(start, 520, target: _beltBoxPos(belt.length));
    setState(() => fallingIdx = idx);
    falling = box;
    await _awaitReach(box);
    setState(() {
      falling = null;
      fallingIdx = null;
      belt.add(idx);
    });
  }

  Future<void> _runRobot() async {
    if (robotBusy) return;
    robotBusy = true;
    while (belt.isNotEmpty && mounted) {
      final idx = belt.first;
      // 1) едем к коробке на дощечке
      final slot = belt.indexOf(idx);
      await _move(trolley, _beltBoxPos(slot), 260);
      // 2) клешня вниз
      await _moveClaw(_beltY() - _kBoxH / 2 - 6, 200);
      // 3) хватаем
      setState(() {
        carried = idx;
        carriedPos = _Movable(Offset(trolley.pos.dx, clawY), 320);
        belt.removeAt(0);
      });
      // 4) поднимаем
      await _moveClaw(_railY() + 34, 200);
      // 5) наименее заполненный стакан
      final ch = _leastFilledChute();
      while (ch >= chutes.length) chutes.add(<int>[]);
      await _move(trolley, Offset(_chuteCenter(ch).dx, _railY()), 420);
      // 6) опускаем к вершине стопки
      final target = _stackPos(ch, chutes[ch].length);
      await _moveClaw(target.dy - _kBoxH / 2 + 4, 240);
      // 7) отпускаем — коробка оседает в стопку
      setState(() {
        chutes[ch].add(idx);
        carried = null;
        carriedPos = null;
      });
      // 8) клешня вверх
      await _moveClaw(_railY() + 34, 200);
    }
    robotBusy = false;
    if (mounted) setState(() {});
  }

  int _leastFilledChute() {
    var best = 0;
    for (var i = 0; i < math.max(1, _targetChuteCount()); i++) {
      final cur = i < chutes.length ? chutes[i].length : 0;
      final bestCur = best < chutes.length ? chutes[best].length : 0;
      if (cur < bestCur) best = i;
    }
    return best;
  }

  // ---------- анимационные примитивы ----------

  final _waiters = <Completer<void>, _Movable>{};

  Future<void> _awaitReach(_Movable m) async {
    final c = Completer<void>();
    _waiters[c] = m;
    return c.future;
  }

  Future<void> _move(_Movable m, Offset to, int ms) async {
    m.target = to;
    m.speed = (m.pos - to).distance / (ms / 1000);
    await _awaitReach(m);
  }

  Future<void> _moveClaw(double y, int ms) async {
    clawTarget = y;
    final ms100 = ms;
    await Future.delayed(Duration(milliseconds: ms100));
  }

  void _tick(Duration elapsed) {
    if (_size == Size.zero) return;
    catWag = elapsed.inMilliseconds / 420.0;
    const k = 0.16;
    // тяга всех движущихся объектов к целям
    void pull(_Movable m) {
      final d = m.target - m.pos;
      final dist = d.distance;
      if (dist < 1.2) {
        m.pos = m.target;
      } else {
        final step = m.speed / 60;
        m.pos += d * (step / dist > 1 ? 1 : step / dist);
      }
    }

    if (falling != null) pull(falling!);
    if (carriedPos != null) {
      carriedPos!.target = Offset(trolley.pos.dx, clawY + 26);
      carriedPos!.speed = 400;
      pull(carriedPos!);
    }
    pull(trolley);
    // клешня
    clawY += (clawTarget - clawY) * k;
    leverAngle += 0;
    // завершение ожиданий
    _waiters.removeWhere((c, m) {
      if ((m.target - m.pos).distance < 1.5) {
        if (!c.isCompleted) c.complete();
        return true;
      }
      return false;
    });
    if (mounted) setState(() {});
  }

  // ---------- интерактив ----------

  void _onTapUp(Offset p) {
    // красная кнопка?
    if (_hitButton(p)) {
      _startShow();
      return;
    }
    final now = DateTime.now();
    final isDouble = now.difference(_lastTap).inMilliseconds < 350 &&
        (_lastTapPos! - p).distance < 40;
    _lastTap = now;
    _lastTapPos = p;
    // коробка в стакане?
    for (var ch = 0; ch < chutes.length; ch++) {
      for (var lvl = 0; lvl < chutes[ch].length; lvl++) {
        final c = _stackPos(ch, lvl);
        if ((p - c).distance <= _kBoxW / 2 + 6) {
          final courseIdx = chutes[ch][lvl];
          if (isDouble) {
            _showCourseActions(context, courseIdx);
          } else {
            Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: courseIdx)));
          }
          return;
        }
      }
    }
  }

  bool _hitButton(Offset p) {
    final b = _buttonPos();
    return (p - b).distance <= 26;
  }

  Offset _buttonPos() {
    // красная кнопка на подставке слева от купола
    return Offset(_size.width - 196, _chuteTop() + 8);
  }

  Offset _domeCenter() => Offset(_size.width - 84, _chuteTop() + 64);

  // ---------- меню курса ----------

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
                              content: Text('«' + c.title + '» исчезнет с конвейера. Прогресс сохранится.'),
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

  // ---------- отрисовка ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller]),
      builder: (context, _) {
        return LayoutBuilder(builder: (context, box) {
          _size = box.biggest;
          if (controller.courses.isEmpty) {
            return Center(
              child: Text('Курсов пока нет — создай через «Ещё» → Курс от ИИ.',
                  style: TextStyle(color: C.muted)),
            );
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onTapUp(d.localPosition),
            child: CustomPaint(
              size: Size.infinite,
              painter: _ConveyorPainter(
                state: this,
              ),
            ),
          );
        });
      },
    );
  }
}

class _ConveyorPainter extends CustomPainter {
  final _ConveyorCoursesViewState state;
  _ConveyorPainter({required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // фон-цех
    canvas.drawRect(Offset.zero & size, Paint()..color = C.bg);

    // ---- верхний ярус: рельса ----
    canvas.drawLine(Offset(24, 64), Offset(w - 24, 64), Paint()..strokeWidth = 4 ..color = C.border);
    for (var x = 30.0; x < w - 30; x += 26) {
      canvas.drawLine(Offset(x, 64), Offset(x, 72), Paint()..strokeWidth = 2 ..color = C.border.withAlpha(120));
    }

    // труба (по центру над дощечкой)
    final pw = 88.0, px = w / 2 - pw / 2;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px, -6, pw, 44), const Radius.circular(9)),
        Paint()..color = C.card2);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px - 6, 26, pw + 12, 12), const Radius.circular(6)),
        Paint()..color = C.border);

    // ---- средний ярус: дощечка ----
    final beltY = state._beltY();
    final beltRect = Rect.fromLTWH(w * 0.14, beltY, w * 0.72, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(beltRect, const Radius.circular(5)),
      Paint()..shader = LinearGradient(colors: [const Color(0xFF5C3F27), const Color(0xFF7A5535), const Color(0xFF5C3F27)])
          .createShader(beltRect),
    );
    canvas.drawShadow(Path()..addRect(beltRect), Colors.black, 4, true);

    // ---- нижний ярус: стаканы ----
    final n = state._targetChuteCount();
    final cw = (w - 24) / n;
    for (var ch = 0; ch < n; ch++) {
      final left = 12.0 + ch * cw;
      final rect = Rect.fromLTRB(left + 4, state._chuteTop(), left + cw - 4, state._chuteFloor());
      // стекло
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()..color = Colors.white.withAlpha(14),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()..style = PaintingStyle.stroke ..strokeWidth = 1.6 ..color = C.border,
      );
      // блик
      canvas.drawLine(Offset(rect.left + 10, rect.top + 12), Offset(rect.left + 10, rect.bottom - 16),
          Paint()..strokeWidth = 2 ..color = Colors.white.withAlpha(26));
      // подпись стакана
      final tp = TextPainter(
        text: TextSpan(text: 'отсек ${ch + 1}', style: TextStyle(fontSize: 10, color: C.muted)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left + 8, rect.bottom - tp.height - 2));
    }

    // коробки в стаканах
    for (var ch = 0; ch < state.chutes.length && ch < n; ch++) {
      for (var lvl = 0; lvl < state.chutes[ch].length; lvl++) {
        _drawBox(canvas, state._stackPos(ch, lvl), state.chutes[ch][lvl], 0);
      }
    }

    // коробка на дощечке / падающая / несомая
    final st = state;
    if (st.falling != null && st.fallingIdx != null) {
      _drawBox(canvas, st.falling!.pos, st.fallingIdx!, 0);
    }
    for (var s = 0; s < st.belt.length; s++) {
      _drawBox(canvas, st._beltBoxPos(s), st.belt[s], 0);
    }

    // ---- робот на рельсе ----
    final tx = st.trolley.pos.dx;
    // тележка
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(tx, 64), width: 44, height: 22), const Radius.circular(6)),
      Paint()..color = C.accentDark,
    );
    // колесо-катушка
    canvas.drawCircle(Offset(tx, 64), 6, Paint()..color = C.accent);
    // тросы
    canvas.drawLine(Offset(tx - 10, 75), Offset(tx - 10, st.clawY - 10), Paint()..strokeWidth = 2 ..color = C.muted);
    canvas.drawLine(Offset(tx + 10, 75), Offset(tx + 10, st.clawY - 10), Paint()..strokeWidth = 2 ..color = C.muted);
    // клешня
    final grip = st.carried != null ? 0.0 : 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(tx, st.clawY), width: 30, height: 12), const Radius.circular(4)),
      Paint()..color = C.accent,
    );
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(
        Offset(tx + 8 * s, st.clawY + 6),
        Offset(tx + (8 + 7 * grip) * s, st.clawY + 18 + 4 * grip),
        Paint()..strokeWidth = 3.4 ..strokeCap = StrokeCap.round ..color = C.accent,
      );
    }

    // несомая коробка — на кончике клешни
    if (st.carried != null && st.carriedPos != null) {
      _drawBox(canvas, st.carriedPos!.pos, st.carried!, 0);
    }

    // ---- купол с Барсиком (справа) ----
    _drawDome(canvas, size, st);

    // красная кнопка
    final bp = st._buttonPos();
    final pressed = st.pawAngle > -0.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: bp + Offset(0, 14), width: 56, height: 18), const Radius.circular(4)),
      Paint()..color = C.card2,
    );
    canvas.drawCircle(
      bp,
      20,
      Paint()..color = pressed ? const Color(0xFFB3261E) : const Color(0xFFDC322A),
    );
    canvas.drawCircle(
      bp - Offset(0, 6),
      12,
      Paint()..color = Colors.white.withAlpha(pressed ? 40 : 70),
    );
    if (!st.buttonStruck) {
      final pulse = (st.buttonPulse ? 1.0 : 0.0);
      canvas.drawCircle(bp, 26 + pulse * 6, Paint()..style = PaintingStyle.stroke ..strokeWidth = 2 ..color = C.accent.withAlpha(140));
    }
  }

  void _drawBox(Canvas canvas, Offset c, int courseIdx, double ang) {
    if (courseIdx < 0 || courseIdx >= controller.courses.length) return;
    final title = controller.courses[courseIdx].title;
    const colors = [
      Color(0xFF8A5A44), Color(0xFF4E6E58), Color(0xFF54679A),
      Color(0xFF9A6B5A), Color(0xFF6B5E8A), Color(0xFF8A7D4E),
      Color(0xFF4E8A7A), Color(0xFF8A4E62),
    ];
    final color = colors[courseIdx % colors.length];
    final rect = Rect.fromCenter(center: c, width: _kBoxW, height: _kBoxH);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rrect, Paint()..color = color);
    canvas.drawRRect(rrect, Paint()..style = PaintingStyle.stroke ..strokeWidth = 1.6 ..color = Colors.black.withAlpha(80));
    // «скотч»
    canvas.drawLine(Offset(c.dx, rect.top), Offset(c.dx, rect.bottom), Paint()..strokeWidth = 4 ..color = Colors.white.withAlpha(34));
    // текст — строго по центру, без поворота
    final tp = TextPainter(
      text: TextSpan(
        text: _short(title),
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _kBoxW - 6);
    // до двух строк по вертикали
    final tp2 = TextPainter(
      text: TextSpan(text: title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white, height: 1.15)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _kBoxW - 8);
    if (tp2.height <= _kBoxH - 12) {
      tp2.paint(canvas, c - Offset(tp2.width / 2, tp2.height / 2));
    } else {
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  String _short(String s) {
    final r = s.runes.toList();
    return r.length <= 10 ? s : String.fromCharCodes(r.take(9)) + '…';
  }

  void _drawDome(Canvas canvas, Size size, _ConveyorCoursesViewState st) {
    final center = st._domeCenter();
    final r = 72.0;
    // подушка внутри
    canvas.drawOval(
      Rect.fromCenter(center: center + Offset(0, r * 0.52), width: r * 1.3, height: 22),
      Paint()..color = C.accentDark.withAlpha(120),
    );
    // Барсик (уменьшенный)
    _drawCat(canvas, center + Offset(0, r * 0.30), 0.66, st);
    // стеклянный купол
    final dome = Path()
      ..moveTo(center.dx - r, center.dy + 18)
      ..quadraticBezierTo(center.dx - r, center.dy - r * 1.05, center.dx, center.dy - r * 1.05)
      ..quadraticBezierTo(center.dx + r, center.dy - r * 1.05, center.dx + r, center.dy + 18)
      ..close();
    canvas.drawPath(dome, Paint()..color = Colors.white.withAlpha(16));
    canvas.drawPath(dome, Paint()..style = PaintingStyle.stroke ..strokeWidth = 2 ..color = Colors.white.withAlpha(60));
    // блик
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.86),
      -2.4, 0.8, false,
      Paint()..style = PaintingStyle.stroke ..strokeWidth = 3 ..color = Colors.white.withAlpha(70),
    );
    // основание купола
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: center + Offset(0, 22), width: r * 2.1, height: 10), const Radius.circular(5)),
      Paint()..color = C.card2,
    );
  }

  void _drawCat(Canvas canvas, Offset base, double scale, _ConveyorCoursesViewState st) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.scale(scale);
    final ginger = Paint()..color = const Color(0xFFD9843B);
    final dark = Paint()..color = const Color(0xFFB05E22);
    final white = Paint()..color = const Color(0xFFFFF3E2);
    final black = Paint()..color = const Color(0xFF201510);

    // рычаг-кнопка перед котом: лапа качает рычаг во время работы
    canvas.save();
    canvas.translate(-20, -6);
    canvas.rotate(st.leverAngle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -26, 8, 30), const Radius.circular(4)),
      dark,
    );
    canvas.drawCircle(const Offset(0, -26), 6, Paint()..color = C.accent);
    canvas.restore();

    // лапа на рычаге (поднята к кнопке до старта)
    canvas.save();
    canvas.translate(-18, -18);
    canvas.rotate(st.pawAngle * 0.4 - 0.4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-5, -16, 10, 20), const Radius.circular(5)),
      ginger,
    );
    canvas.restore();

    // хвост
    final tailSwing = math.sin(st.catWag) * 0.5;
    canvas.save();
    canvas.translate(-24, -4);
    canvas.rotate(-0.6 + tailSwing);
    final tail = Path()
      ..moveTo(0, 6)
      ..quadraticBezierTo(-26, 10, -30, -18)
      ..quadraticBezierTo(-31, -28, -22, -26)
      ..quadraticBezierTo(-14, -6, 4, -2)
      ..close();
    canvas.drawPath(tail, dark);
    canvas.restore();
    // тело
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -12), width: 56, height: 44), ginger);
    for (var i = 0; i < 3; i++) {
      final x = -12.0 + i * 12;
      canvas.drawArc(Rect.fromCenter(center: Offset(x, -24), width: 10, height: 12), math.pi, math.pi, true, dark);
    }
    // голова
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -44), width: 42, height: 36), ginger);
    canvas.drawPath(Path()..moveTo(-19, -56)..lineTo(-13, -69)..lineTo(-4, -58)..close(), ginger);
    canvas.drawPath(Path()..moveTo(19, -56)..lineTo(13, -69)..lineTo(4, -58)..close(), ginger);
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -36), width: 21, height: 13), white);
    canvas.drawCircle(const Offset(-9, -48), 3.2, black);
    canvas.drawCircle(const Offset(9, -48), 3.2, black);
    canvas.drawCircle(const Offset(0, -40), 2.0, dark);
    const whisker = Color(0xFFFFF3E2);
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(Offset(4 * s, -38), Offset(17 * s, -40), Paint()..strokeWidth = 1.1 ..color = whisker);
      canvas.drawLine(Offset(4 * s, -36), Offset(17 * s, -34), Paint()..strokeWidth = 1.1 ..color = whisker);
    }
    canvas.restore();

    // имя
    final tp = TextPainter(
      text: TextSpan(text: 'Барсик', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.accent)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, base - Offset(tp.width / 2 - 2, 12));
  }

  @override
  bool shouldRepaint(covariant _ConveyorPainter old) => true;
}
