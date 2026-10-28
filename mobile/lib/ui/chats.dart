// chats.dart — все беседы с ментором в одном месте: открыть, переименовать,
// удалить; новый чат привязывается к текущей задаче.
import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'app_background.dart';
import 'chat.dart';
import 'mentor_avatar.dart';
import 'theme.dart';
import 'widgets.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  Future<void> _rename(BuildContext context, MentorChat chat) async {
    final ctrl = TextEditingController(text: chat.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Переименовать чат'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена', style: TextStyle(color: C.muted))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    ctrl.dispose();
    if (title != null && title.isNotEmpty) controller.renameChat(chat.id, title);
  }

  Future<void> _delete(BuildContext context, MentorChat chat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить чат?'),
        content: Text('«${chat.title}» будет удалён безвозвратно.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: C.muted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) controller.deleteChat(chat.id);
  }

  void _open(BuildContext context, MentorChat c) {
    controller.openChat(c.id);
    final interview = c.taskId == '__interview__';
    Navigator.of(context).push(pageRoute(
      interview
          ? const ChatScreen(interview: true, resume: true)
          : ChatScreen(
              scope: c.isGeneral ? ChatScope.general : ChatScope.task,
              resume: true,
            ),
      name: interview ? 'InterviewScreen' : 'ChatScreen',
    ));
  }

  void _new(BuildContext context) {
    controller.createGeneralChat();
    Navigator.of(context)
        .push(pageRoute(const ChatScreen(scope: ChatScope.general)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Чаты с Термаем', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Новый чат',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => _new(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final chats = List<MentorChat>.from(controller.prog.mentorChats)
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          if (chats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MentorAvatar(size: 76, glow: true),
                    const SizedBox(height: 14),
                    Text('Бесед пока нет.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.text)),
                    const SizedBox(height: 8),
                    Text(
                      'Задай вопрос Термаю о задаче, синтаксисе или ошибке — беседа сохранится здесь.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: C.muted, height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => _new(context),
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      label: const Text('Начать беседу'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
            itemCount: chats.length,
            itemBuilder: (context, i) {
              final c = chats[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: cardBox(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    const MentorAvatar(size: 36),
                    const SizedBox(width: 11),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _open(context, c),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: C.text)),
                            const SizedBox(height: 2),
                            Text(_subtitle(c),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: C.muted)),
                          ],
                        ),
                      ),
                    ),
                    chevron(size: 24, color: C.muted),
                    PopupMenuButton<String>(
                      tooltip: 'Действия',
                      icon: Icon(Icons.more_vert, size: 20, color: C.muted),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                      onSelected: (v) {
                        if (v == 'rename') _rename(context, c);
                        if (v == 'delete') _delete(context, c);
                      },
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
      ),
    );
  }

  String _courseName(String id) {
    for (final c in controller.allCourses) {
      if (c.id == id) return c.title;
    }
    return '';
  }

  String _subtitle(MentorChat c) {
    final parts = <String>[];
    if (c.taskId == '__interview__') {
      parts.add('Собеседование');
    } else if (c.isGeneral) {
      parts.add('Общий чат');
    } else {
      final course = _courseName(c.courseId);
      if (course.isNotEmpty) parts.add(course);
      if (c.taskTitle.isNotEmpty) parts.add(c.taskTitle);
    }
    parts.add('${c.messages.length} сообщ.');
    final last = c.messages.where((m) => m.role != 'system').toList();
    if (last.isNotEmpty) parts.add(last.last.text.replaceAll('\n', ' '));
    return parts.join(' · ');
  }
}
