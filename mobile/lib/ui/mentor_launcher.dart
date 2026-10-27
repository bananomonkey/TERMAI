// mentor_launcher.dart — плавающая панель Термая на главном экране.
// Слева снизу: лицо, имя и статус. Аватар открывает быстрый вопрос рядом
// с панелью, а имя/статус — полноценный чат.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import 'chat.dart';
import 'mentor_avatar.dart';
import 'theme.dart';
import 'widgets.dart';

/// showMentorQuickAsk — компактный ввод рядом с аватаром, без перехода
/// в полноэкранный чат. После отправки вопрос открывается в обычном чате.
Future<void> showMentorQuickAsk(BuildContext context,
    {double anchorBottom = 146}) async {
  final question = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Быстрый вопрос',
    barrierColor: Colors.black.withAlpha(18),
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (_, __, ___) => _QuickAskDialog(anchorBottom: anchorBottom),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          alignment: Alignment.bottomLeft,
          child: child,
        ),
      );
    },
  );
  if (question == null || question.trim().isEmpty || !context.mounted) return;
  Navigator.of(context)
      .push(pageRoute(ChatScreen(autoQuestion: question.trim())));
}

class MentorLauncher extends StatelessWidget {
  const MentorLauncher({super.key});

  void _openChat(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(pageRoute(const ChatScreen()));
  }

  void _openQuickAsk(BuildContext context) {
    HapticFeedback.selectionClick();
    final box = context.findRenderObject() as RenderBox?;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final anchor = box == null
        ? 146.0
        : (screenHeight - box.localToGlobal(Offset.zero).dy + 8)
            .clamp(100.0, screenHeight * 0.7)
            .toDouble();
    showMentorQuickAsk(context, anchorBottom: anchor);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.mentorBusy ||
            controller.termBusy ||
            controller.generating;
        return Container(
          decoration: BoxDecoration(
            color: C.button.withAlpha(242),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: C.buttonBorder.withAlpha(C.isLight ? 120 : 150),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(C.isLight ? 24 : 64),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Быстрый вопрос',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _openQuickAsk(context),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: MentorAvatar(
                        size: 38,
                        speaking: busy,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Открыть чат',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openChat(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Термай',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: C.text)),
                          Text(busy ? 'печатает…' : 'на связи',
                              style: TextStyle(fontSize: 10.5, color: C.muted)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickAskDialog extends StatefulWidget {
  final double anchorBottom;
  const _QuickAskDialog({required this.anchorBottom});

  @override
  State<_QuickAskDialog> createState() => _QuickAskDialogState();
}

class _QuickAskDialogState extends State<_QuickAskDialog> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    Navigator.of(context).pop(q);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final bottom = keyboard > 0 ? keyboard + 16 : widget.anchorBottom;
    final available = media.size.width - 28;
    final width = available > 340 ? 340.0 : available;

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, bottom),
        child: SizedBox(
          width: width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: C.buttonBorder.withAlpha(180)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(C.isLight ? 28 : 80),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const MentorAvatar(size: 26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Быстрый вопрос',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: C.text)),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, size: 18, color: C.muted),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _input,
                    autofocus: true,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: TextStyle(fontSize: 14, color: C.text),
                    decoration: InputDecoration(
                      hintText: 'Спроси Термая…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      suffixIcon: IconButton(
                        tooltip: 'Спросить',
                        onPressed: _send,
                        icon: Icon(Icons.arrow_upward_rounded,
                            size: 19, color: C.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text('Ответ откроется в чате — история сохранится.',
                      style: TextStyle(fontSize: 10.5, color: C.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
