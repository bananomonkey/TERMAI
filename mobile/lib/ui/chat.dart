// chat.dart — чат с ИИ-наставником: сохранённые беседы по задачам,
// пузыри сообщений, переименование/удаление и выбор истории.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../main.dart';
import '../models.dart';
import '../store.dart';
import '../theme_refresh.dart';
import 'app_background.dart';
import 'mentor_avatar.dart';
import 'theme.dart';

class ChatScreen extends StatefulWidget implements PreserveOnTheme {
  final String? autoQuestion;
  final bool interview;

  /// general — отдельный чат Термая, task — чат текущей задачи.
  final ChatScope scope;

  /// resume — открыть уже выбранную беседу, не привязываясь заново к задаче.
  final bool resume;
  const ChatScreen({
    super.key,
    this.autoQuestion,
    this.interview = false,
    this.scope = ChatScope.general,
    this.resume = false,
  });
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
        final active = controller.activeChat;
        if (active == null || active.taskId != '__interview__') {
          controller.createInterviewChat();
        }
      } else {
        controller.stopInterview();
        if (widget.resume && controller.activeChat != null) {
          // Открываем именно выбранную беседу.
        } else if (widget.scope == ChatScope.task) {
          controller.ensureChatForCurrentTask();
        } else {
          controller.ensureGeneralChat();
        }
      }
      if (_asked) return;
      _asked = true;
      if (widget.interview) {
        final active = controller.activeChat;
        if (active == null || active.messages.isEmpty) {
          controller.sendChat(
              '(Начни собеседование: коротко представься и задай первый вопрос по материалу курса)');
        }
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
      controller.createInterviewChat(force: true);
    } else if (widget.scope == ChatScope.task) {
      controller.createChatForCurrentTask();
    } else {
      controller.createGeneralChat();
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
    } else if (c.isGeneral) {
      parts.add('Общий чат');
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
            titleSpacing: 0,
            title: Row(children: [
              MentorAvatar(
                  size: 36, speaking: controller.mentorBusy, glow: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Термай',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: C.text)),
                    Text(
                        widget.interview
                            ? 'Собеседование · ИИ-интервьюер'
                            : (chat?.isGeneral ?? true)
                                ? 'Общий чат · ИИ-наставник'
                                : ((chat?.taskTitle ?? '').isNotEmpty
                                    ? chat!.taskTitle
                                    : (chat?.title ?? 'ИИ-наставник')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: widget.interview ? C.warn : C.muted)),
                  ],
                ),
              ),
            ]),
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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const MentorAvatar(size: 92, glow: true),
                              const SizedBox(height: 16),
                              Text('Термай',
                                  style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      color: C.text)),
                              const SizedBox(height: 5),
                              Text(
                                  widget.interview
                                      ? 'ИИ-интервьюер TERMAI'
                                      : (chat?.isGeneral ?? true)
                                          ? 'Общий чат · ${controller.userNameOrFriend}'
                                          : 'ИИ-наставник TERMAI',
                                  style: TextStyle(
                                      fontSize: 12,
                                      letterSpacing: 0.5,
                                      fontWeight: FontWeight.w700,
                                      color: C.accent)),
                              const SizedBox(height: 14),
                              Text(
                                  'Спроси о задаче, синтаксисе, ошибке…\n'
                                  'Или попроси открыть настройки, архив или вставить команду в терминал.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: C.muted, height: 1.45)),
                            ],
                          ),
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const MentorAvatar(
                                        size: 28, speaking: true),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: C.accent)),
                                    const SizedBox(width: 8),
                                    Text('Термай печатает…',
                                        style: TextStyle(
                                            fontSize: 12.5, color: C.muted)),
                                  ],
                                ),
                              ),
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
      case 'error':
        return _errorBubble(context);
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
              const Padding(
                padding: EdgeInsets.only(right: 7),
                child: MentorAvatar(size: 28),
              ),
              Expanded(
                  child: _wrap(msg.text, C.secondary.withAlpha(28),
                      isUser: false)),
            ],
          ),
        );
    }
  }

  Widget _errorBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: const BoxConstraints(maxWidth: 330),
        padding: const EdgeInsets.fromLTRB(13, 11, 11, 9),
        decoration: BoxDecoration(
          color: C.danger.withAlpha(C.isLight ? 22 : 30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.danger.withAlpha(100)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.error_outline, size: 18, color: C.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Ошибка',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: C.danger)),
              ),
              IconButton(
                tooltip: 'Скопировать ошибку',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () async {
                  final text = msg.details.isNotEmpty ? msg.details : msg.text;
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ошибка скопирована')),
                  );
                },
                icon: Icon(Icons.copy_rounded, size: 17, color: C.danger),
              ),
            ]),
            const SizedBox(height: 5),
            Text(msg.text,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: C.text)),
          ],
        ),
      ),
    );
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
