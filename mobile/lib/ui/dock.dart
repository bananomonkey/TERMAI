// dock.dart — плавающая круглая панель главного экрана: три круглые кнопки
// без подписей. Иконки — из того же монохромного набора Material, что и
// рядом с названиями курсов (никаких разноцветных эмодзи).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'archive.dart';
import 'progress_map.dart';
import 'theme.dart';
import 'usage_screen.dart';
import 'widgets.dart';

class GlassDock extends StatelessWidget {
  const GlassDock({super.key});

  @override
  Widget build(BuildContext context) {
    return glass(
      radius: 22,
      blur: 0,
      background: C.button,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DockButton(
            icon: Icons.route_outlined,
            label: 'Карта',
            tooltip: 'Карта прогресса',
            onTap: () => Navigator.of(context)
                .push(pageRoute(const ProgressMapScreen())),
          ),
          const SizedBox(width: 4),
          _DockButton(
            icon: Icons.inventory_2_outlined,
            label: 'Архив',
            tooltip: 'Архив курсов',
            onTap: () =>
                Navigator.of(context).push(pageRoute(const ArchiveScreen())),
          ),
          const SizedBox(width: 4),
          _DockButton(
            icon: Icons.payments_outlined,
            label: 'Расход',
            tooltip: 'Расход токенов',
            onTap: () =>
                Navigator.of(context).push(pageRoute(const UsageScreen())),
          ),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  const _DockButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: C.button2,
                  ),
                  child: Icon(icon, size: 20, color: C.text),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: C.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
