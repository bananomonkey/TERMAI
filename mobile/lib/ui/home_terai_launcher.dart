// home_terai_launcher.dart — маленький Термай только на главном экране.
// Глобальной плавающей панели больше нет: остальные экраны не перекрываются.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models.dart';
import 'chat.dart';
import 'mentor_avatar.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeTeraiLauncher extends StatelessWidget {
  const HomeTeraiLauncher({super.key});

  void _openChat(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      pageRoute(const ChatScreen(scope: ChatScope.general)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.mentorBusy ||
            controller.termBusy ||
            controller.generating;
        return Semantics(
          button: true,
          label: 'Открыть чат с Термаем',
          child: Tooltip(
            message: 'Открыть чат с Термаем',
            child: Material(
              color: C.button.withAlpha(C.isLight ? 238 : 246),
              shape: CircleBorder(
                side: BorderSide(
                  color: C.buttonBorder.withAlpha(C.isLight ? 150 : 170),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _openChat(context),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: MentorAvatar(
                    size: 40,
                    speaking: busy,
                    glow: busy,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
