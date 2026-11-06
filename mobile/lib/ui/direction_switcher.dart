// direction_switcher.dart — компактная строка направлений на главной.
// Wrap: все направления видны сразу, без горизонтальной прокрутки.
import 'package:flutter/material.dart';

import '../main.dart';
import 'design_system.dart';
import 'dialogs.dart';
import 'direction_picker.dart';
import 'theme.dart';

class DirectionSwitcher extends StatelessWidget {
  const DirectionSwitcher({super.key});

  Future<void> _add(BuildContext context) async {
    final selected = await showDirectionPicker(
      context,
      selected: controller.config.directions.toSet(),
    );
    if (selected == null || !context.mounted) return;
    await controller.setDirections(
      selected,
      active: controller.config.activeDirection,
    );
  }

  Future<void> _remove(BuildContext context, String id, String title) async {
    if (controller.config.directions.length <= 1) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Убрать «$title»?',
      message: 'Курсы и прогресс останутся в приложении. '
          'Направление можно вернуть через «+».',
      confirmLabel: 'Убрать',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    final next = controller.config.directions.where((x) => x != id).toSet();
    await controller.setDirections(next, protectStarted: false);
  }

  @override
  Widget build(BuildContext context) {
    final dirs = controller.selectedDirections;
    return Padding(
      padding: const EdgeInsets.fromLTRB(17, 0, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final d in dirs) _DirectionChip(d: d, onRemove: _remove),
          Tooltip(
            message: 'Добавить направление',
            child: InkWell(
              onTap: () => _add(context),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
                child: Icon(Icons.add, size: 19, color: C.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// _DirectionChip — именованная кнопка направления.
class _DirectionChip extends StatelessWidget {
  final dynamic d;
  final void Function(BuildContext, String, String) onRemove;
  const _DirectionChip({required this.d, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final active = d.id == controller.config.activeDirection;
    return Semantics(
      button: true,
      selected: active,
      label: 'Направление ${d.title}',
      child: Tooltip(
        message: d.title,
        child: InkWell(
          onTap: () => controller.switchDirection(d.id),
          onLongPress: () => onRemove(context, d.id, d.title),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: active ? C.card : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: active
                    ? C.accent.withAlpha(C.isLight ? 90 : 120)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? C.accent : C.muted.withAlpha(100),
                  ),
                ),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 116),
                  child: Text(
                    d.shortTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: active ? C.text : C.muted,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
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
