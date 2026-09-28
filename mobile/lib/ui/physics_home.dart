// physics_home.dart — игровой экран выбора курсов: кот Барсик, труба сверху,
// коробки-курсы падают и сталкиваются (кастомная физика кругов), drag-швыряние,
// гироскоп-гравитация, тряска, кнопка «Магнит» — упорядочивание в сетку.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../main.dart';
import '../store.dart';
import 'home.dart' show TaskListScreen;
import 'theme.dart';
import 'widgets.dart';

/// PhysicsCoursesView — экран с физикой коробок.
class PhysicsCoursesView extends StatefulWidget {
  const PhysicsCoursesView({super.key});
  @override
  State<PhysicsCoursesView> createState() => _PhysicsCoursesViewState();
}

class _PhysicsCoursesViewState extends State<PhysicsCoursesView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _boxes = <_Box>[];
  final _rand = math.Random();
  Size _size = Size.zero;
  double _gravX = 0, _gravY = 980;
  bool _magnet = false;
  int _dragIdx = -1;
  Offset? _dragPos;
  Offset _dragLast = Offset.zero;
  DateTime _downAt = DateTime.now();
  Offset _downPos = Offset.zero;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _shakeEnergy = 0;
  double _catWag = 0;

  static const _boxColors = <Color>[
    Color(0xFF8A5A44), Color(0xFF4E6E58), Color(0xFF54679A),
    Color(0xFF9A6B5A), Color(0xFF6B5E8A), Color(0xFF8A7D4E),
    Color(0xFF4E8A7A), Color(0xFF8A4E62),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_step);
    _ticker.start();
    _accelSub = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 40)).listen(_onAccel);
    // коробки сыплются из трубы одна за другой при входе на экран
    WidgetsBinding.instance.addPostFrameCallback((_) {
      var i = 0;
      for (final _ in controller.courses) {
        Future.delayed(Duration(milliseconds: 350 * i++), _spawnFromPipe);
      }
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onAccel(AccelerometerEvent e) {
    // наклон телефона → гравитация; резкие скачки → тряска
    _gravX = (e.x * 60).clamp(-1400.0, 1400.0).toDouble();
    _gravY = (980 + e.y * 40).clamp(300.0, 1800.0).toDouble();
    final mag = e.x * e.x + e.y * e.y + e.z * e.z;
    if (mag > 400) _shakeEnergy = (_shakeEnergy + mag / 800).clamp(0.0, 6.0);
  }

  void _spawnFromPipe() {
    if (!mounted || _size == Size.zero) return;
    final i = _boxes.length;
    if (i >= controller.courses.length) return;
    final c = controller.courses[i];
    _boxes.add(_Box(
      courseIdx: i,
      title: c.title,
      color: _boxColors[i % _boxColors.length],
      pos: Offset(_size.width / 2 + _rand.nextDouble() * 60 - 30, -60),
      vel: Offset(_rand.nextDouble() * 120 - 60, 80),
      angVel: _rand.nextDouble() * 3 - 1.5,
    ));
    if (mounted) setState(() {});
  }

  void _reDropAll() {
    for (var i = 0; i < _boxes.length; i++) {
      final b = _boxes[i];
      b.pos = Offset(_size.width / 2 + _rand.nextDouble() * 80 - 40, -60.0 - 90 * i);
      b.vel = Offset(_rand.nextDouble() * 200 - 100, 60);
      b.angVel = _rand.nextDouble() * 4 - 2;
    }
    setState(() {});
  }

  void _shake() {
    for (final b in _boxes) {
      b.vel += Offset(_rand.nextDouble() * 900 - 450, -_rand.nextDouble() * 700 - 200);
      b.angVel += _rand.nextDouble() * 8 - 4;
    }
  }

  void _toggleMagnet() {
    _magnet = !_magnet;
    if (_magnet) {
      // раскладка по алфавиту в сетку 4 в ряд
      final sorted = [..._boxes]..sort((a, b) => a.title.compareTo(b.title));
      const cols = 4;
      for (var k = 0; k < sorted.length; k++) {
        final row = k ~/ cols, col = k % cols;
        final cellW = _size.width / cols;
        sorted[k].target = Offset(cellW * (col + 0.5), 150.0 + row * 110);
      }
    } else {
      for (final b in _boxes) {
        b.target = null;
        b.vel = Offset(_rand.nextDouble() * 200 - 100, -150);
      }
    }
    setState(() {});
  }

  void _step(Duration _) {
    if (_size == Size.zero) return;
    final dt = 1 / 60;
    if (_shakeEnergy > 2.5) {
      _shakeEnergy = 0;
      _shake();
    } else {
      _shakeEnergy *= 0.94;
    }
    _catWag += dt * 2.4;

    if (_magnet) {
      for (final b in _boxes) {
        final t = b.target ?? b.pos;
        b.pos += (t - b.pos) * 0.16;
        b.vel = Offset.zero;
        b.ang *= 0.8;
        b.angVel = 0;
      }
    } else {
      for (var i = 0; i < _boxes.length; i++) {
        final b = _boxes[i];
        if (i == _dragIdx && _dragPos != null) {
          b.vel = (_dragPos! - b.pos) / math.max(dt, 0.016) * 0.35;
          b.pos += (_dragPos! - b.pos) * 0.55;
        } else {
          b.vel += Offset(_gravX, _gravY) * dt;
          b.pos += b.vel * dt;
          b.angVel *= 0.995;
        }
        b.ang += b.angVel * dt;
        // стены
        if (b.pos.dx < b.r) {
          b.pos = Offset(b.r, b.pos.dy);
          b.vel = Offset(b.vel.dx.abs() * 0.55, b.vel.dy);
          b.angVel += 2;
        } else if (b.pos.dx > _size.width - b.r) {
          b.pos = Offset(_size.width - b.r, b.pos.dy);
          b.vel = Offset(-b.vel.dx.abs() * 0.55, b.vel.dy);
          b.angVel -= 2;
        }
        // пол (над панелью кота)
        final floor = _size.height - 132 - b.r;
        if (b.pos.dy > floor) {
          b.pos = Offset(b.pos.dx, floor);
          if (b.vel.dy > 60) {
            b.vel = Offset(b.vel.dx * 0.9, -b.vel.dy * 0.42);
          } else {
            b.vel = Offset(b.vel.dx * 0.82, 0);
            b.angVel *= 0.85;
          }
        }
        if (b.pos.dy < b.r + 46) {
          b.pos = Offset(b.pos.dx, b.r + 46);
          b.vel = Offset(b.vel.dx, b.vel.dy.abs() * 0.4);
        }
      }
      // столкновения пар
      for (var i = 0; i < _boxes.length; i++) {
        for (var j = i + 1; j < _boxes.length; j++) {
          _collide(_boxes[i], _boxes[j]);
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _collide(_Box a, _Box b) {
    final d = b.pos - a.pos;
    final dist = d.distance;
    final minD = a.r + b.r;
    if (dist >= minD || dist == 0) return;
    final n = d / dist;
    final overlap = minD - dist;
    a.pos -= n * overlap * 0.5;
    b.pos += n * overlap * 0.5;
    final rel = dotV(b.vel - a.vel, n);
    if (rel > 0) return;
    const rest = 0.35;
    final imp = -(1 + rest) * rel / 2;
    a.vel -= n * imp;
    b.vel += n * imp;
    // tangential → вращение и «трение»
    final t = Offset(-n.dy, n.dx);
    final relT = dotV(b.vel - a.vel, t);
    a.angVel += relT * 0.004;
    b.angVel -= relT * 0.004;
    a.vel -= t * relT * 0.06;
    b.vel += t * relT * 0.06;
  }

  void _onPointerDown(Offset p) {
    _downAt = DateTime.now();
    _downPos = p;
    _dragLast = p;
    _dragIdx = -1;
    for (var i = _boxes.length - 1; i >= 0; i--) {
      if ((p - _boxes[i].pos).distance <= _boxes[i].r * 1.35) {
        _dragIdx = i;
        break;
      }
    }
    if (_dragIdx >= 0) {
      _dragPos = _boxes[_dragIdx].pos + const Offset(0, -4);
      _boxes[_dragIdx].angVel = 0;
    }
  }

  void _onPointerMove(Offset p) {
    _dragLast = p;
    if (_dragIdx >= 0) _dragPos = p;
  }

  void _onPointerUp(Offset p) {
    final quick = DateTime.now().difference(_downAt).inMilliseconds < 300;
    final still = (p - _downPos).distance < 14;
    if (_dragIdx >= 0 && quick && still) {
      // тап по коробке — открыть курс
      final idx = _boxes[_dragIdx].courseIdx;
      _dragIdx = -1;
      _dragPos = null;
      Navigator.of(context).push(pageRoute(TaskListScreen(courseIdx: idx)));
      return;
    }
    if (_dragIdx >= 0) {
      // швырок: скорость пальца
      _boxes[_dragIdx].vel = (_boxes[_dragIdx].vel).clampLength(0, 1600);
    }
    _dragIdx = -1;
    _dragPos = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _size = box.biggest;
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Тапни по коробке — открыть курс · тащи и швыряй · наклоняй телефон',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Listener(
              onPointerDown: (e) => _onPointerDown(e.localPosition),
              onPointerMove: (e) => _onPointerMove(e.localPosition),
              onPointerUp: (e) => _onPointerUp(e.localPosition),
              child: CustomPaint(
                painter: _WorldPainter(boxes: _boxes, magnet: _magnet, catWag: _catWag),
                size: Size.infinite,
              ),
            ),
          ),
          _BottomBar(
            onDrop: _reDropAll,
            onMagnet: _toggleMagnet,
            magnetOn: _magnet,
          ),
        ],
      );
    });
  }
}

double dotV(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

extension _VelClamp on Offset {
  Offset clampLength(double minL, double maxL) {
    final l = distance;
    if (l <= 0) return this;
    final k = (l < minL ? minL : (l > maxL ? maxL : l)) / l;
    return this * k;
  }
}

class _Box {
  final int courseIdx;
  final String title;
  final Color color;
  Offset pos, vel;
  double ang, angVel;
  Offset? target;
  final double r = 36;
  _Box({
    required this.courseIdx,
    required this.title,
    required this.color,
    required this.pos,
    required this.vel,
    required this.angVel,
  }) : ang = 0;
}

/// _WorldPainter — труба, коробки, кот Барсик.
class _WorldPainter extends CustomPainter {
  final List<_Box> boxes;
  final bool magnet;
  final double catWag;
  _WorldPainter({required this.boxes, required this.magnet, required this.catWag});

  @override
  void paint(Canvas canvas, Size size) {
    // труба сверху по центру
    final pipe = Paint()..color = C.card2;
    final pw = 96.0;
    final px = size.width / 2 - pw / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(px, -8, pw, 52), const Radius.circular(10)),
      pipe,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(px - 8, 30, pw + 16, 16), const Radius.circular(8)),
      Paint()..color = C.border,
    );

    // коробки
    for (final b in boxes) {
      canvas.save();
      canvas.translate(b.pos.dx, b.pos.dy);
      canvas.rotate(b.ang);
      final w = b.r * 2.1, h = b.r * 1.8;
      final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(9));
      canvas.drawRRect(rrect, Paint()..color = b.color);
      canvas.drawRRect(rrect, Paint()..style = PaintingStyle.stroke ..strokeWidth = 2 ..color = Colors.black.withAlpha(80));
      // «скотч»
      canvas.drawLine(Offset(0, -h / 2), Offset(0, h / 2),
          Paint()..strokeWidth = 5 ..color = Colors.white.withAlpha(38));
      final tp = TextPainter(
        text: TextSpan(text: _short(b.title), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w - 8);
      canvas.rotate(-b.ang * 0.55); // текст читается, но «живёт» с коробкой
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    _drawCat(canvas, size);
    if (magnet) {
      final tp = TextPainter(
        text: TextSpan(text: 'упорядочено', style: TextStyle(fontSize: 11, color: C.accent)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 14, 60));
    }
  }

  String _short(String s) {
    final r = s.runes.toList();
    return r.length <= 12 ? s : '${String.fromCharCodes(r.take(11))}…';
  }

  void _drawCat(Canvas canvas, Size size) {
    // Барсик — рыжий кот сидит справа внизу; хвост качается
    final base = Offset(size.width - 92, size.height - 116);
    final ginger = Paint()..color = const Color(0xFFD9843B);
    final dark = Paint()..color = const Color(0xFFB05E22);
    final white = Paint()..color = const Color(0xFFFFF3E2);
    final black = Paint()..color = const Color(0xFF201510);

    canvas.save();
    canvas.translate(base.dx, base.dy);
    // хвост
    final tailSwing = math.sin(catWag) * 0.5;
    canvas.save();
    canvas.translate(-26, -8);
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
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -14), width: 58, height: 46), ginger);
    // полоски
    for (var i = 0; i < 3; i++) {
      final x = -12.0 + i * 12;
      canvas.drawArc(Rect.fromCenter(center: Offset(x, -26), width: 10, height: 12), math.pi, math.pi, true, dark);
    }
    // голова
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -48), width: 44, height: 38), ginger);
    // уши
    canvas.drawPath(
      Path()
        ..moveTo(-20, -60)
        ..lineTo(-14, -74)
        ..lineTo(-4, -62)
        ..close(),
      ginger,
    );
    canvas.drawPath(
      Path()
        ..moveTo(20, -60)
        ..lineTo(14, -74)
        ..lineTo(4, -62)
        ..close(),
      ginger,
    );
    // морда
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -40), width: 22, height: 14), white);
    // глаза
    canvas.drawCircle(const Offset(-9, -52), 3.4, black);
    canvas.drawCircle(const Offset(9, -52), 3.4, black);
    // нос и усы
    canvas.drawCircle(const Offset(0, -44), 2.2, dark);
    const whisker = Color(0xFFFFF3E2);
    for (final s in [-1.0, 1.0]) {
      canvas.drawLine(Offset(4 * s, -42), Offset(18 * s, -44), Paint()..strokeWidth = 1.2 ..color = whisker);
      canvas.drawLine(Offset(4 * s, -40), Offset(18 * s, -38), Paint()..strokeWidth = 1.2 ..color = whisker);
    }
    // лапы
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-18.0, -2.0, 16.0, 8.0), const Radius.circular(4)),
      white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(2.0, -2.0, 16.0, 8.0), const Radius.circular(4)),
      white,
    );
    canvas.restore();

    // имя
    final tp = TextPainter(
      text: const TextSpan(text: 'Барсик', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFD9843B))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, base - Offset(tp.width / 2 - 2, -6));
  }

  @override
  bool shouldRepaint(covariant _WorldPainter old) => true;
}

class _BottomBar extends StatelessWidget {
  final VoidCallback onDrop, onMagnet;
  final bool magnetOn;
  const _BottomBar({required this.onDrop, required this.onMagnet, required this.magnetOn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onDrop,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Сыпануть коробки'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onMagnet,
            icon: Icon(magnetOn ? Icons.close : Icons.grid_view_outlined, size: 18,
                color: magnetOn ? C.accent : C.text),
            label: Text(magnetOn ? 'В кучу' : 'Магнит', style: TextStyle(color: magnetOn ? C.accent : C.text)),
          ),
        ),
      ]),
    );
  }
}
