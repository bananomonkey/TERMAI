// dialogs.dart — единые подтверждения. Кнопки всегда занимают одинаковую
// ширину, «Отмена» нейтральная, опасное действие — красное.
import 'package:flutter/material.dart';

import 'design_system.dart';
import 'theme.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Отмена',
  String confirmLabel = 'Удалить',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      title: Text(title),
      content: Text(message, style: TextStyle(color: C.muted, height: 1.4)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: C.text,
                  side: BorderSide(color: C.border),
                ),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: destructive ? C.danger : C.accent,
                  foregroundColor: destructive ? Colors.white : C.bg,
                ),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return result == true;
}
