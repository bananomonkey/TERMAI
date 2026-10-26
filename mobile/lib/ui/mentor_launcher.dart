// mentor_launcher.dart — плавающая панель Термая на главном экране.
// Слева снизу: лицо, имя и статус. Нажатие открывает чат с наставником.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import 'chat.dart';
import 'mentor_avatar.dart';
import 'theme.dart';
import 'widgets.dart';

class MentorLauncher extends StatelessWidget {
  const MentorLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.mentorBusy ||
            controller.termBusy ||
            controller.generating;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(pageRoute(const ChatScreen()));
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(5, 5, 13, 5),
              decoration: BoxDecoration(
                color: C.card.withAlpha(242),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(110),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MentorAvatar(
                    size: 38,
                    speaking: busy,
                    glow: true,
                  ),
                  const SizedBox(width: 9),
                  Column(
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
