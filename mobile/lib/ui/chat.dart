// chat.dart — чат с ИИ-наставником: пузыри сообщений, авто-вопрос при открытии.
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../main.dart';
import '../store.dart';
import 'lesson.dart';
import 'theme.dart';
import 'widgets.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.interview) {
      controller.startInterview();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_asked) {
          _asked = true;
          controller.sendChat('(Начни собеседование: коротко представься и задай первый вопрос по материалу курса)');
        }
      });
    }
    if ((widget.autoQuestion ?? '').isNotEmpty && !_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.sendChat(widget.autoQuestion!);
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.interview ? 'Собеседование' : 'Ментор',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: widget.interview ? C.warn : C.text))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                _scrollDown();
                final msgs = controller.chatMsgs;
                if (msgs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Спроси ментора о задаче, синтаксисе, ошибке…',
                          textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: msgs.length + (controller.mentorBusy ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= msgs.length) {
                      return Padding(
                        padding: EdgeInsets.all(14),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: C.accent))),
                      );
                    }
                    return _Bubble(msg: msgs[i]);
                  },
                );
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
                  decoration: const InputDecoration(hintText: 'Спроси ментора…'),
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
          child: Center(child: Text('· ${msg.text}', style: TextStyle(color: C.muted, fontSize: 12.5))),
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
                padding: EdgeInsets.only(right: 6),
                child: CircleAvatar(
                  radius: 14,
                  backgroundImage: AssetImage('assets/icon/clawd.png'),
                  backgroundColor: C.card,
                ),
              ),
              Expanded(child: _wrap(msg.text, C.secondary.withAlpha(28), isUser: false)),
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
        border: isUser ? null : Border(left: BorderSide(color: C.secondary, width: 3)),
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
          code: TextStyle(fontSize: 12.5, color: C.accent, fontFamily: 'monospace', backgroundColor: C.bg),
          codeblockDecoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
          codeblockPadding: const EdgeInsets.all(10),
        ),
      ),
    );
  }
}
