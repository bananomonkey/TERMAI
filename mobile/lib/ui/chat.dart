// chat.dart — чат с ИИ-наставником: сохранённые беседы по задачам,
// пузыри сообщений, переименование/удаление и выбор истории.
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import 'app_background.dart';
import 'theme.dart';

class ChatScreen extends StatefulWidget {
  final String? autoQuestion;
  final bool interview;
  const ChatScreen({super.key, this.autoQuestion, this.interview = false});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _asked = false;
  int _lastMsgCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.interview) {
        controller.startInterview();
        controller.createInterviewChat();
      } else {
        controller.ensureChatForCurrentTask();
      }
      if (_asked) return;
      _asked = true;
      if (widget.interview) {
        controller.sendChat(
            '(Начни собеседование: коротко представься и задай первый вопрос по материалу курса)');
      } else if ((widget.autoQuestion ?? '').isNotEmpty) {
        controller.sendChat(widget.autoQuestion!);
      }
      _scrollDown();
    });
  }

  @override
  void dispose() {
    if (widget.interview) controller.stopInterview();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    _input.clear();
    controller.sendChat(q);
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _newChat() async {
    if (widget.interview) {
      controller.createInterviewChat();
    } else {
      controller.createChatForCurrentTask();
    }
    _scrollDown();
  }

  Future<void> _rename(MentorChat chat) async {
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
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    ctrl.dispose();
    if (title != null && title.isNotEmpty) {
      controller.renameChat(chat.id, title);
    }
  }

  Future<void> _delete(MentorChat chat) async {
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

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final chats = List<MentorChat>.from(controller.prog.mentorChats)
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 6),
                  child: Row(children: [
                    Icon(Icons.forum_outlined, size: 19, color: C.accent),
                    const SizedBox(width: 9),
                    Text('Чаты с ментором',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: C.text)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _newChat();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Новый'),
                    ),
                  ]),
                ),
                if (chats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                    child: Text('Пока нет сохранённых чатов.',
                        style: TextStyle(color: C.muted, fontSize: 13)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      itemCount: chats.length,
                      itemBuilder: (ctx, i) {
                        final c = chats[i];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          leading: CircleAvatar(
                            radius: 17,
                            backgroundColor: C.card,
                            child: Icon(Icons.chat_bubble_outline,
                                size: 17, color: C.secondary),
                          ),
                          title: Text(c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: C.text)),
                          subtitle: Text(_chatSubtitle(c),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: C.muted)),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Действия',
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Переименовать')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Удалить')),
                            ],
                            onSelected: (v) {
                              Navigator.pop(ctx);
                              if (v == 'rename') {
                                _rename(c);
                              } else if (v == 'delete') {
                                _delete(c);
                              }
                            },
                          ),
                          onTap: () {
                            controller.openChat(c.id);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }

  String _courseName(String id) {
    for (final c in controller.courses) {
      if (c.id == id) return c.title;
    }
    return '';
  }

  String _chatSubtitle(MentorChat c) {
    final parts = <String>[];
    if (c.taskId == '__interview__') {
      parts.add('Собеседование');
    } else {
      final course = _courseName(c.courseId);
      if (course.isNotEmpty) parts.add(course);
      if (c.taskTitle.isNotEmpty) parts.add(c.taskTitle);
    }
    parts.add('${c.messages.length} сообщ.');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final chat = controller.activeChat;
        final msgs = controller.chatMsgs;
        // прокручиваем вниз только когда пришло новое сообщение,
        // а не на каждой перерисовке (это подвешивало длинные чаты)
        if (msgs.length != _lastMsgCount) {
          _lastMsgCount = msgs.length;
          _scrollDown();
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    widget.interview
                        ? 'Собеседование'
                        : (chat?.title ?? 'Ментор'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: widget.interview ? C.warn : C.text)),
                if (!widget.interview && (chat?.taskTitle ?? '').isNotEmpty)
                  Text(chat!.taskTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: C.muted)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Чаты',
                icon: const Icon(Icons.forum_outlined),
                onPressed: _showHistory,
              ),
              PopupMenuButton<String>(
                tooltip: 'Действия',
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'new', child: Text('Новый чат')),
                  if (chat != null)
                    const PopupMenuItem(
                        value: 'rename', child: Text('Переименовать')),
                  if (chat != null)
                    const PopupMenuItem(
                        value: 'delete', child: Text('Удалить чат')),
                ],
                onSelected: (v) {
                  if (v == 'new') {
                    _newChat();
                  } else if (v == 'rename' && chat != null) {
                    _rename(chat);
                  } else if (v == 'delete' && chat != null) {
                    _delete(chat);
                  }
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: AppBackdrop(
            child: SafeArea(
            child: Column(children: [
              Expanded(
                child: msgs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                              'Спроси ментора о задаче, синтаксисе, ошибке…',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: C.muted)),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(14),
                        itemCount:
                            msgs.length + (controller.mentorBusy ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= msgs.length) {
                            return Padding(
                              padding: const EdgeInsets.all(14),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.4, color: C.accent))),
                            );
                          }
                          return _Bubble(msg: msgs[i]);
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onSubmitted: (_) => _send(),
                      decoration:
                          const InputDecoration(hintText: 'Спроси ментора…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: controller.mentorBusy ? null : _send,
                    icon: const Icon(Icons.send, size: 19),
                    style: IconButton.styleFrom(backgroundColor: C.accentDark),
                  ),
                ]),
              ),
            ]),
          ),
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMsg msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    switch (msg.role) {
      case 'system':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
              child: Text('· ${msg.text}',
                  style: TextStyle(color: C.muted, fontSize: 12.5))),
        );
      case 'user':
        return Align(
          alignment: Alignment.centerRight,
          child: _wrap(msg.text, C.accentDark, isUser: true),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CircleAvatar(
                  radius: 14,
                  backgroundImage: AssetImage('assets/icon/clawd.png'),
                  backgroundColor: C.card,
                ),
              ),
              Expanded(
                  child: _wrap(msg.text, C.secondary.withAlpha(28),
                      isUser: false)),
            ],
          ),
        );
    }
  }

  Widget _wrap(String text, Color bg, {required bool isUser}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: isUser
            ? null
            : Border(left: BorderSide(color: C.secondary, width: 3)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
      ),
      child: MarkdownBody(
        data: text,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(fontSize: 14, height: 1.4, color: C.text),
          code: TextStyle(
              fontSize: 12.5,
              color: C.accent,
              fontFamily: 'monospace',
              backgroundColor: C.bg),
          codeblockDecoration: BoxDecoration(
              color: C.bg, borderRadius: BorderRadius.circular(10)),
          codeblockPadding: const EdgeInsets.all(10),
        ),
      ),
    );
  }
}
