// usage_screen.dart — расход токенов и оценка стоимости в долларах.
// Токены копятся по моделям, цены — из прайсов провайдеров (приблизительно).
import 'package:flutter/material.dart';

import '../main.dart';
import '../usage.dart';
import 'app_background.dart';
import 'theme.dart';
import 'widgets.dart';

class UsageScreen extends StatelessWidget {
  const UsageScreen({super.key});

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Обнулить счётчик?'),
        content: const Text('Статистика расхода токенов начнётся с нуля.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: C.muted))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Обнулить'),
          ),
        ],
      ),
    );
    if (ok == true) controller.resetUsage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Расход токенов', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Обнулить',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _reset(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final usage = controller.prog.aiUsage;
          final rows = usage.entries.toList()
            ..sort((a, b) => (b.value.fold(0, (x, y) => x + y))
                .compareTo(a.value.fold(0, (x, y) => x + y)));

          double total = 0;
          var known = true;
          for (final e in rows) {
            final p = e.value.isNotEmpty ? e.value[0] : 0;
            final c = e.value.length > 1 ? e.value[1] : 0;
            final cost = costFor(e.key, p, c);
            if (cost == null) {
              known = false;
            } else {
              total += cost;
            }
          }

          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.payments_outlined, size: 42, color: C.muted),
                    const SizedBox(height: 14),
                    Text('Пока ничего не потрачено.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.text)),
                    const SizedBox(height: 8),
                    Text(
                      'Токены начнут считаться, как только ИИ ответит на первый запрос.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: C.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              glass(
                radius: 20,
                blur: 30,
                padding: const EdgeInsets.all(18),
                glow: C.glow(color: C.accent, alpha: 55),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Всего токенов',
                        style: TextStyle(fontSize: 12, color: C.muted, letterSpacing: 0.6)),
                    const SizedBox(height: 6),
                    Text(prettyTokens(controller.prog.tokensTotal),
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: C.text)),
                    const SizedBox(height: 12),
                    Row(children: [
                      _stat('Вход', prettyTokens(controller.prog.tokensIn), C.secondary),
                      const SizedBox(width: 18),
                      _stat('Выход', prettyTokens(controller.prog.tokensOut), C.accent),
                    ]),
                    const SizedBox(height: 14),
                    Divider(color: C.border, height: 1),
                    const SizedBox(height: 14),
                    Row(children: [
                      Text('Оценка стоимости', style: TextStyle(fontSize: 12.5, color: C.muted)),
                      const Spacer(),
                      Text(money(total) + (known ? '' : ' и более'),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.good)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              caption('По моделям', color: C.accent),
              const SizedBox(height: 10),
              for (final e in rows) ...[
                _ModelRow(model: e.key, prompt: e.value.isNotEmpty ? e.value[0] : 0, completion: e.value.length > 1 ? e.value[1] : 0),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 10),
              Text(
                'Цены — публичные тарифы провайдеров на 1M токенов (USD): считаются приблизительно, '
                'без учёта кэша и скидок. Если модели нет в таблице, стоимость не показывается.',
                style: TextStyle(fontSize: 11.5, color: C.muted, height: 1.45),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: C.muted)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ],
      );
}

class _ModelRow extends StatelessWidget {
  final String model;
  final int prompt, completion;
  const _ModelRow({required this.model, required this.prompt, required this.completion});

  @override
  Widget build(BuildContext context) {
    final cost = costFor(model, prompt, completion);
    return cardBox(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.text)),
            const SizedBox(height: 3),
            Text('${prettyTokens(prompt)} вход · ${prettyTokens(completion)} выход',
                style: TextStyle(fontSize: 11.5, color: C.muted)),
          ]),
        ),
        Text(cost == null ? '—' : money(cost),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: cost == null ? C.muted : C.good)),
      ]),
    );
  }
}
