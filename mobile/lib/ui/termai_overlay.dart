// termai_overlay.dart — плавающая панель Термая поверх экранов.
// Позиция запоминается, панель можно перетаскивать; на клавиатуре и
// служебных диалогах она временно прячется, чтобы не мешать вводу.
import 'package:flutter/material.dart';

import '../main.dart';
import '../navigation.dart';
import 'mentor_launcher.dart';

/// TermaiHost — постоянный слой поверх навигатора. Держит Overlay для
/// Tooltip-ов панели и не пересоздаёт его при каждой перерисовке приложения.
class TermaiHost extends StatefulWidget {
  final Widget child;
  const TermaiHost({super.key, required this.child});

  @override
  State<TermaiHost> createState() => _TermaiHostState();
}

class _TermaiHostState extends State<TermaiHost> {
  late final OverlayEntry _entry =
      OverlayEntry(builder: (_) => const TermaiOverlay());

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Overlay(initialEntries: [_entry]),
        ),
      ],
    );
  }
}

class TermaiOverlay extends StatefulWidget {
  const TermaiOverlay({super.key});

  @override
  State<TermaiOverlay> createState() => _TermaiOverlayState();
}

class _TermaiOverlayState extends State<TermaiOverlay> {
  static const _screens = <String>{
    'HomeScreen',
    'TaskListScreen',
    'LessonScreen',
    'SettingsScreen',
    'ChatScreen',
    'InterviewScreen',
    'ArchiveScreen',
    'UsageScreen',
    'ChatsScreen',
    'HelpScreen',
    'BackgroundSettingsScreen',
    'AiFallbacksScreen',
    'ReviewScreen',
    'ProgressMapScreen',
  };

  final GlobalKey _panelKey = GlobalKey();
  Offset? _pos;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListenableBuilder(
        listenable: screenObserver,
        builder: (context, __) {
          if (!controller.config.onboarded ||
              !_screens.contains(ScreenObserver.current)) {
            return const SizedBox.shrink();
          }
          if (MediaQuery.viewInsetsOf(context).bottom > 0) {
            return const SizedBox.shrink();
          }
          return Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final media = MediaQuery.of(context);
                final panel = _panelKey.currentContext?.size ??
                    const Size(154, 58);
                final minLeft = media.padding.left + 8;
                final minTop = media.padding.top + 8;
                final maxLeft = (constraints.maxWidth -
                        panel.width -
                        media.padding.right -
                        8)
                    .clamp(minLeft, double.infinity);
                final maxTop = (constraints.maxHeight -
                        panel.height -
                        media.padding.bottom -
                        8)
                    .clamp(minTop, double.infinity);
                final pos = _resolvePosition(
                  minLeft: minLeft,
                  minTop: minTop,
                  maxLeft: maxLeft,
                  maxTop: maxTop,
                );
                return Stack(
                  children: [
                    Positioned(
                      left: pos.dx,
                      top: pos.dy,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) => setState(() => _dragging = true),
                        onPanUpdate: (d) {
                          setState(() {
                            _pos = Offset(
                              (_pos!.dx + d.delta.dx)
                                  .clamp(minLeft, maxLeft)
                                  .toDouble(),
                              (_pos!.dy + d.delta.dy)
                                  .clamp(minTop, maxTop)
                                  .toDouble(),
                            );
                          });
                        },
                        onPanEnd: (_) {
                          setState(() => _dragging = false);
                          final p = _pos!;
                          final nx = maxLeft <= minLeft
                              ? 0.0
                              : (p.dx - minLeft) / (maxLeft - minLeft);
                          final ny = maxTop <= minTop
                              ? 0.0
                              : (p.dy - minTop) / (maxTop - minTop);
                          controller.setLauncherPosition(nx, ny);
                        },
                        child: AnimatedScale(
                          scale: _dragging ? 1.03 : 1,
                          duration: const Duration(milliseconds: 120),
                          child: KeyedSubtree(
                            key: _panelKey,
                            child: const MentorLauncher(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Offset _resolvePosition({
    required double minLeft,
    required double minTop,
    required double maxLeft,
    required double maxTop,
  }) {
    final current = _pos;
    if (current == null) {
      final cfg = controller.config;
      if (cfg.launcherX >= 0 && cfg.launcherY >= 0) {
        _pos = Offset(
          minLeft + cfg.launcherX.clamp(0.0, 1.0) * (maxLeft - minLeft),
          minTop + cfg.launcherY.clamp(0.0, 1.0) * (maxTop - minTop),
        );
      } else {
        // По умолчанию — слева внизу, над доком/полем ввода.
        _pos = Offset(minLeft + 6, (maxTop - 86).clamp(minTop, maxTop));
      }
    } else {
      _pos = Offset(
        current.dx.clamp(minLeft, maxLeft).toDouble(),
        current.dy.clamp(minTop, maxTop).toDouble(),
      );
    }
    return _pos!;
  }
}
