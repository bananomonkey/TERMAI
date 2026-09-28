// review.dart — интервальное повторение: список закладок, пора повторять.
import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'lesson.dart';
import 'theme.dart';
import 'widgets.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Повторение', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final due = controller.dueBookmarks();
          if (due.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'К повторению пока ничего нет.\nЗакладывай задачи ☆ в панели задачи —\nони будут возвращаться по расписанию.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted, height: 1.5),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Пора повторить: ${due.length}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.accent)),
              const SizedBox(height: 10),
              for (final e in due) ...[
                _ReviewRow(key: ValueKey(e.key), entry: e),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final MapEntry<String, Bookmark> entry;
  const _ReviewRow({required super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final b = entry.value;
    final course = controller.courses.where((c) => c.id == b.courseId).firstOrNull;
    final taskTitle = course?.tasks.where((t) => t.id == b.taskId).firstOrNull?.title ?? b.taskId;
    return GestureDetector(
      onTap: () {
        controller.reviewFromBookmark(entry.key);
        Navigator.of(context).push(pageRoute(const LessonScreen()));
      },
      child: cardBox(
        accent: C.secondary.withAlpha(120),
        child: Row(children: [
          Padding(padding: EdgeInsets.only(top: 2), child: Text('↻', style: TextStyle(color: C.secondary, fontSize: 16, fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(course?.title ?? b.courseId, style: TextStyle(fontSize: 11, color: C.muted)),
              const SizedBox(height: 3),
              Text(taskTitle, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25)),
            ]),
          ),
          Icon(Icons.chevron_right, color: C.muted, size: 22),
        ]),
      ),
    );
  }
}
