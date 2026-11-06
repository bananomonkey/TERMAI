// shared_ai_consent.dart — обязательное предупреждение перед общим ИИ.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared_ai.dart';
import 'design_system.dart';
import 'theme.dart';

/// askSharedAiConsent — показывает условия и возвращает true только при
/// явном согласии. Сам конфиг сохраняет вызывающий экран.
Future<bool> askSharedAiConsent(
  BuildContext context, {
  bool reConsent = false,
}) async {
  final service = SharedAiService.instance;
  final end = service.endsAt;
  final date = end == null
      ? 'до окончания акции'
      : '${end.day.toString().padLeft(2, '0')}.'
          '${end.month.toString().padLeft(2, '0')}.${end.year}';
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel)),
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: C.accent, size: 22),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              reConsent ? 'Обновлённые условия' : 'Бесплатный ИИ TERMAI',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сейчас доступ к ИИ оплачивает TERMAI. Все запросы идут через '
              'внешний серверный шлюз с моделью ${service.model}.',
              style: AppText.body.copyWith(color: C.text, height: 1.45),
            ),
            const SizedBox(height: 10),
            Text(
              'Что важно знать:\n'
              '• запросы отправляются на внешний серверный шлюз и обрабатываются '
              'по его правилам и правилам выбранной модели;\n'
              '• общий доступ работает только после входа через Google — так '
              'сервер отличает реальных пользователей от ботов;\n'
              '• личный API-ключ, модель и Base URL не перезаписываются;\n'
              '• после окончания акции приложение автоматически вернётся к '
              'твоему личному ИИ. Платных переключений без предупреждения нет;\n'
              '• акция действует для всех до $date. Остаток: ${service.remainingLabel}.',
              style: AppText.caption.copyWith(color: C.muted, height: 1.5),
            ),
            if (service.privacyUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(service.privacyUrl),
                  mode: LaunchMode.externalApplication,
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Условия и обработка данных',
                    style: TextStyle(color: C.accent, fontSize: 12.5)),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Без согласия запросы через общий шлюз не отправляются.',
              style: TextStyle(
                  fontSize: 11.5, color: C.warn, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Только мой ключ', style: TextStyle(color: C.muted)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Согласен, включить'),
        ),
      ],
    ),
  );
  return result == true;
}
