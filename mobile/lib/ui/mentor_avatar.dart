// mentor_avatar.dart — лицо Термая: круглый зелёный CRT-экран.
// Пока ИИ отвечает, рот быстро меняется с закрытого на открытый — эффект речи.
import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

class MentorAvatar extends StatefulWidget {
  final double size;
  final bool speaking;
  final bool glow;
  const MentorAvatar({
    super.key,
    this.size = 36,
    this.speaking = false,
    this.glow = false,
  });

  @override
  State<MentorAvatar> createState() => _MentorAvatarState();
}

class _MentorAvatarState extends State<MentorAvatar> {
  static const _closed = 'assets/icon/termai_closed.png';
  static const _open = 'assets/icon/termai_open.png';

  Timer? _timer;
  bool _mouthOpen = false;

  @override
  void initState() {
    super.initState();
    _syncSpeech();
  }

  @override
  void didUpdateWidget(covariant MentorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speaking != widget.speaking) _syncSpeech();
  }

  void _syncSpeech() {
    _timer?.cancel();
    _timer = null;
    if (!widget.speaking) {
      _mouthOpen = false;
      return;
    }
    _mouthOpen = true;
    _timer = Timer.periodic(const Duration(milliseconds: 140), (_) {
      if (!mounted) return;
      setState(() => _mouthOpen = !_mouthOpen);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return RepaintBoundary(
      child: Semantics(
        label: 'Термай',
        image: true,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: C.card,
            // Свечение — только там, где его явно просят (чат/пустой экран).
            // В плавающей панели и индикаторе набора оно выглядело грязным
            // пятном под аватаром, особенно на своём фото.
            boxShadow: widget.glow
                ? [
                    BoxShadow(
                      color: C.good.withAlpha(widget.speaking ? 95 : 55),
                      blurRadius: size * 0.38,
                      spreadRadius: -1,
                    ),
                  ]
                : null,
          ),
          child: ClipOval(
            child: Image.asset(
              _mouthOpen ? _open : _closed,
              width: size,
              height: size,
              cacheWidth: (size * 3).round(),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
