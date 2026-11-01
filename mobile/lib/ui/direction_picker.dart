// direction_picker.dart — выбор нескольких учебных направлений.
// Один и тот же список используется в онбординге и в кнопке «+» на главной.
import 'package:flutter/material.dart';

import '../directions.dart';
import 'design_system.dart';
import 'theme.dart';

class DirectionOptionList extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool dense;

  const DirectionOptionList({
    super.key,
    required this.selected,
    required this.onToggle,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in directionCategories.keys) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(2, dense ? 14 : 18, 2, 6),
            child: Text(
              directionCategoryTitle(category).toUpperCase(),
              style: AppText.section.copyWith(color: C.muted),
            ),
          ),
          for (final d in directionsForCategory(category)) ...[
            _DirectionRow(
              d: d,
              checked: selected.contains(d.id),
              onTap: () => onToggle(d.id),
            ),
            if (d != directionsForCategory(category).last)
              Divider(color: C.border.withAlpha(110), height: 1),
          ],
        ],
      ],
    );
  }
}

class _DirectionRow extends StatelessWidget {
  final DirectionDef d;
  final bool checked;
  final VoidCallback onTap;
  const _DirectionRow({
    required this.d,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: AppDuration.fast,
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: checked ? C.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: checked ? C.accent : C.border,
                    width: 1.4,
                  ),
                ),
                child:
                    checked ? Icon(Icons.check, size: 14, color: C.bg) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      style: AppText.title.copyWith(color: C.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.desc,
                      style: AppText.caption.copyWith(color: C.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Set<String>?> showDirectionPicker(
  BuildContext context, {
  required Set<String> selected,
}) {
  final local = Set<String>.from(selected);
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Направления',
                          style: AppText.screenTitle.copyWith(color: C.text),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close, size: 20, color: C.muted),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      DirectionOptionList(
                        selected: local,
                        onToggle: (id) => setState(() {
                          if (local.contains(id)) {
                            local.remove(id);
                          } else {
                            local.add(id);
                          }
                        }),
                        dense: true,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Можно выбрать несколько. Прогресс сохраняется при снятии.',
                          style: AppText.caption.copyWith(color: C.muted),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: local.isEmpty
                            ? null
                            : () => Navigator.pop(ctx, local),
                        child: const Text('Готово'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
