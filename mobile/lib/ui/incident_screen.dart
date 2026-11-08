// incident_screen.dart — инцидент-режим: выбери сломанный сервис и разбирайся.
// Сценарии детерминированные (без ИИ): состояние песочницы ломается заранее,
// проверка — штатными проверками песочницы.
import 'package:flutter/material.dart';

import '../incidents.dart';
import '../main.dart';
import '../store.dart';
import 'app_background.dart';
import 'design_system.dart';
import 'lesson.dart';
import 'theme.dart';
import 'widgets.dart';

class IncidentScreen extends StatelessWidget {
  const IncidentScreen({super.key});

  Future<void> _start(BuildContext context, IncidentScenario sc) async {
    final err = await controller.startIncident(sc);
    if (!context.mounted) return;
    if (err.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await pushUnique(context, const LessonScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Инциденты', style: AppText.screenTitle),
      ),
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Сломана «продукция». У тебя есть симптомы, логи и терминал — '
              'как в настоящем дежурстве. Диагностируй, почини, закрой инцидент.',
              style: AppText.caption.copyWith(color: C.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            for (final sc in incidentScenarios) ...[
              appCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.local_fire_department_rounded,
                          size: 20, color: C.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(sc.title,
                            style: AppText.title.copyWith(
                                color: C.text,
                                fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(sc.brief,
                        style: AppText.caption
                            .copyWith(color: C.muted, height: 1.4)),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => _start(context, sc),
                        icon: const Icon(Icons.play_arrow_rounded, size: 19),
                        label: const Text('Разбирать',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
