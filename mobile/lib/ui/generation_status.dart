// generation_status.dart — единая плашка реального прогресса ИИ-операций.
import 'package:flutter/material.dart';

import '../main.dart';
import 'design_system.dart';
import 'theme.dart';

class GenerationStatusCard extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final bool compact;

  const GenerationStatusCard({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 8),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final op = controller.activeGeneration;
        if (op == null) return const SizedBox.shrink();
        final hasSteps = op.total > 0;
        return Padding(
          padding: margin,
          child: appCard(
            padding: EdgeInsets.all(compact ? 9 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        op.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: compact ? 11.5 : 12.5,
                            fontWeight: FontWeight.w700,
                            color: C.text),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          op.canCancel ? controller.cancelGeneration : null,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Отменить',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
                Text(
                  op.stage,
                  style: TextStyle(fontSize: 11.5, color: C.accent),
                ),
                if (op.detail.isNotEmpty)
                  Text(
                    op.detail,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: C.muted),
                  ),
                if (hasSteps) ...[
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: (op.current / op.total).clamp(0.0, 1.0),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(3),
                    backgroundColor: C.card2,
                    color: C.accent,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
