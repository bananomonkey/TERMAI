// ai_fallbacks.dart — резервные ИИ-подключения: если основной провайдер
// ответил ошибкой (лимит, сбой, кончился баланс), TERMAI идёт по этому списку.
import 'package:flutter/material.dart';

import '../ai.dart';
import '../main.dart';
import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

class AiFallbacksScreen extends StatelessWidget {
  const AiFallbacksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Резервные модели', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final list = controller.config.fallbacks;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Text(
                'Если основное подключение вернёт ошибку, TERMAI по очереди попробует эти — '
                'и подскажет, какая модель ответила. Первым в списке идёт тот, кого пробуем раньше.',
                style: TextStyle(fontSize: 12.5, color: C.muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                cardBox(
                  child: Column(children: [
                    Text('Резервных подключений нет.',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.text)),
                    const SizedBox(height: 6),
                    Text('Добавь вторую модель или другого провайдера — приложение продолжит работать, '
                        'даже если основная недоступна.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: C.muted, height: 1.4)),
                  ]),
                )
              else
                for (var i = 0; i < list.length; i++) ...[
                  _FallbackTile(
                    index: i,
                    total: list.length,
                    ep: list[i],
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: () => _edit(context, null),
                icon: const Icon(Icons.add, size: 19),
                label: const Text('Добавить резервную модель'),
              ),
              const SizedBox(height: 14),
              Text(
                'Ключи хранятся только на устройстве и в облачной копии прогресса — как и основной ключ.',
                style: TextStyle(fontSize: 11.5, color: C.muted, height: 1.45),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _edit(BuildContext context, int? index) async {
    final cfg = controller.config;
    final existing = index == null ? null : cfg.fallbacks[index];
    final providerCtrl = TextEditingController(text: existing?.provider ?? 'openai');
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final modelCtrl = TextEditingController(text: existing?.model ?? '');
    final baseCtrl = TextEditingController(text: existing?.baseUrl ?? '');

    await showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(index == null ? 'Новая резервная модель' : 'Резервная модель',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: findProvider(providerCtrl.text).id,
                    decoration: const InputDecoration(labelText: 'Провайдер'),
                    items: providers
                        .map((p) => DropdownMenuItem(value: p.id, child: Text(p.title)))
                        .toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      final p = findProvider(id);
                      setSheet(() {
                        providerCtrl.text = p.id;
                        baseCtrl.text = p.baseUrl;
                        modelCtrl.text = p.defaultModel;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'API-ключ (sk-…)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtrl,
                    decoration: const InputDecoration(labelText: 'Модель'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: baseCtrl,
                    decoration: const InputDecoration(labelText: 'Base URL (пусто — из пресета)'),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () async {
                      final key = keyCtrl.text.trim();
                      if (key.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Без ключа подключение не работает')));
                        return;
                      }
                      final ep = AiEndpoint(
                        provider: providerCtrl.text,
                        apiKey: key,
                        model: modelCtrl.text.trim(),
                        baseUrl: baseCtrl.text.trim(),
                      );
                      if (index == null) {
                        cfg.fallbacks.add(ep);
                      } else {
                        cfg.fallbacks[index] = ep;
                      }
                      await controller.saveConfig(autofill: false);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    providerCtrl.dispose();
    keyCtrl.dispose();
    modelCtrl.dispose();
    baseCtrl.dispose();
  }

  static void _move(int from, int delta) {
    final list = controller.config.fallbacks;
    final to = from + delta;
    if (to < 0 || to >= list.length) return;
    final ep = list.removeAt(from);
    list.insert(to, ep);
    controller.saveConfig(autofill: false);
  }

  static Future<void> _remove(BuildContext context, int i) async {
    final list = controller.config.fallbacks;
    final removed = list.removeAt(i);
    await controller.saveConfig(autofill: false);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Удалено: ${findProvider(removed.provider).title}'),
      action: SnackBarAction(
        label: 'Вернуть',
        onPressed: () {
          list.insert(i.clamp(0, list.length), removed);
          controller.saveConfig(autofill: false);
        },
      ),
    ));
  }
}

class _FallbackTile extends StatelessWidget {
  final int index, total;
  final AiEndpoint ep;
  const _FallbackTile({required this.index, required this.total, required this.ep});

  @override
  Widget build(BuildContext context) {
    final p = findProvider(ep.provider);
    final model = ep.model.trim().isEmpty ? p.defaultModel : ep.model;
    return cardBox(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: C.card2,
          child: Text('${index + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.accent)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
            const SizedBox(height: 2),
            Text(model, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: C.muted)),
          ]),
        ),
        IconButton(
          tooltip: 'Выше',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.keyboard_arrow_up_rounded, size: 22, color: index == 0 ? C.border : C.muted),
          onPressed: index == 0 ? null : () => AiFallbacksScreen._move(index, -1),
        ),
        IconButton(
          tooltip: 'Ниже',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: index == total - 1 ? C.border : C.muted),
          onPressed: index == total - 1 ? null : () => AiFallbacksScreen._move(index, 1),
        ),
        PopupMenuButton<String>(
          tooltip: 'Действия',
          icon: Icon(Icons.more_vert, size: 20, color: C.muted),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Изменить')),
            PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
          onSelected: (v) {
            if (v == 'edit') AiFallbacksScreen._edit(context, index);
            if (v == 'delete') AiFallbacksScreen._remove(context, index);
          },
        ),
      ]),
    );
  }
}
