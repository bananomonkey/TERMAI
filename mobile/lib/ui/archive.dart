// archive.dart — архив курсов: сюда курс убирают, отсюда возвращают.
// Прогресс и чаты курса не теряются, пока курс лежит в архиве.
import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'app_background.dart';
import 'theme.dart';
import 'widgets.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  Future<void> _rename(BuildContext context, Course c) async {
    final t = await askText(context, 'Переименовать курс', 'новое название', initial: c.title);
    if (t != null && t.isNotEmpty) controller.renameCourseById(c.id, t);
  }

  Future<void> _delete(BuildContext context, Course c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить навсегда?'),
        content: Text('«${c.title}» исчезнет вместе со своими задачами. Прогресс по нему останется в статистике.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: C.muted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.danger, minimumSize: const Size(64, 42)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) controller.deleteArchivedCourse(c.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Архив курсов', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final list = controller.archivedCourses;
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 42, color: C.muted),
                      const SizedBox(height: 14),
                      Text(
                        'Архив пуст.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.text),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Убери курс в архив двойным тапом по его плитке на главном экране — '
                        'он будет храниться здесь и в любой момент вернётся в список.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: C.muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  'Спрятанные курсы: ${list.length}. Прогресс сохранён — верни любой.',
                  style: TextStyle(fontSize: 12.5, color: C.muted),
                ),
                const SizedBox(height: 14),
                for (final c in list) ...[
                  _ArchiveTile(
                    course: c,
                    onRestore: () => controller.unarchiveCourse(c.id),
                    onDelete: () => _delete(context, c),
                    onRename: () => _rename(context, c),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  final Course course;
  final VoidCallback onRestore, onDelete, onRename;
  const _ArchiveTile({
    required this.course,
    required this.onRestore,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final completed = controller.prog.completed[course.id] ?? {};
    final solved = course.tasks.where((t) => completed[t.id] ?? false).length;
    final accent = course.isTheory ? C.secondary : C.accent;
    return glass(
      radius: 18,
      blur: 26,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(course.isTheory ? Icons.auto_stories_outlined : Icons.terminal, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(course.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.text)),
            ),
            IconButton(
              tooltip: 'Переименовать',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.edit_outlined, size: 18, color: C.muted),
              onPressed: onRename,
            ),
          ]),
          Text(
            '$solved/${course.tasks.length} уроков · ${course.isTheory ? 'теория' : 'терминал'}',
            style: TextStyle(fontSize: 11.5, color: C.muted),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onRestore,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                icon: const Icon(Icons.unarchive_outlined, size: 18),
                label: const Text('Вернуть в список'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(minimumSize: const Size(52, 44)),
              child: Icon(Icons.delete_outline, size: 18, color: C.danger),
            ),
          ]),
        ],
      ),
    );
  }
}
