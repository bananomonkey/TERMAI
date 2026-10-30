// ai_fallbacks.dart — резервные ИИ-подключения: если основной провайдер
// ответил ошибкой (лимит, сбой, кончился баланс), TERMAI идёт по этому списку.
import 'package:flutter/material.dart';

import '../ai.dart';
import '../main.dart';
import '../models.dart';
import 'app_background.dart';
import 'theme.dart';
import 'widgets.dart';

class AiFallbacksScreen extends StatelessWidget {
  const AiFallbacksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Резервные модели', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
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
              const _PrimaryModelCard(),
              const SizedBox(height: 10),
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
                for (final entry in _sorted(list).asMap().entries) ...[
                  _FallbackTile(
                    key: ValueKey('${entry.value.key}-${entry.value.value.provider}-${entry.value.value.model}'),
                    index: entry.value.key,
                    rank: entry.key,
                    total: list.length,
                    ep: entry.value.value,
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
                'Ключи синхронизируются с Google-облаком, если включён тумблер '
                '«Синхронизировать ключи ИИ». Иначе остаются только на этом устройстве.',
                style: TextStyle(fontSize: 11.5, color: C.muted, height: 1.45),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  /// _sorted — показываем здоровые модели выше, пониженные — ниже.
  /// Индекс для редактирования остаётся исходным.
  static List<MapEntry<int, AiEndpoint>> _sorted(List<AiEndpoint> list) {
    final entries = list.asMap().entries.toList();
    entries.sort((a, b) {
      final pa = a.value.penalized ? 1 : 0;
      final pb = b.value.penalized ? 1 : 0;
      if (pa != pb) return pa.compareTo(pb);
      final fa = a.value.failStreak;
      final fb = b.value.failStreak;
      if (fa != fb) return fa.compareTo(fb);
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  static Future<void> _edit(BuildContext context, int? index) async {
    final cfg = controller.config;
    final existing = index == null ? null : cfg.fallbacks[index];
    final providerCtrl = TextEditingController(text: existing?.provider ?? 'openai');
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final modelCtrl = TextEditingController(text: existing?.model ?? '');
    final baseCtrl = TextEditingController(text: existing?.baseUrl ?? '');
    bool obscure = true;

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
                    isExpanded: true,
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
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API-ключ (sk-…)',
                      suffixIcon: IconButton(
                        tooltip: obscure ? 'Показать ключ' : 'Скрыть ключ',
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: C.muted,
                        ),
                        onPressed: () => setSheet(() => obscure = !obscure),
                      ),
                    ),
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

class _PrimaryModelCard extends StatefulWidget {
  const _PrimaryModelCard();

  @override
  State<_PrimaryModelCard> createState() => _PrimaryModelCardState();
}

class _PrimaryModelCardState extends State<_PrimaryModelCard> {
  bool _testing = false;
  bool? _ok;
  int _ms = 0;

  Future<void> _test() async {
    setState(() => _testing = true);
    final r = await controller.testEndpoint(-1);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = r.ok;
      _ms = r.latencyMs;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.ok
          ? 'Основная модель отвечает · ${r.latencyMs} мс'
          : 'Основная модель не ответила: ${r.error}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cfg = controller.config;
    final p = findProvider(cfg.provider);
    final model = cfg.model.trim().isEmpty ? p.defaultModel : cfg.model;
    final penalized = cfg.primaryPenaltyUntil >
        DateTime.now().millisecondsSinceEpoch;
    return cardBox(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: C.accent.withAlpha(40),
          child: Icon(Icons.star_rounded, size: 18, color: C.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.title} · основная',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: C.text)),
            const SizedBox(height: 2),
            Text(model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: C.muted)),
            if (penalized || cfg.primaryFailStreak > 0)
              Text(
                penalized
                    ? 'Временно понижена после ошибки'
                    : 'Ошибок подряд: ${cfg.primaryFailStreak}',
                style: TextStyle(fontSize: 10.5, color: C.warn),
              ),
            if (_ok != null)
              Text(
                _ok! ? 'Тест: отвечает · $_ms мс' : 'Тест: ошибка',
                style:
                    TextStyle(fontSize: 10.5, color: _ok! ? C.good : C.danger),
              ),
          ]),
        ),
        IconButton(
          tooltip: 'Тест основной модели',
          visualDensity: VisualDensity.compact,
          icon: _testing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: C.accent))
              : Icon(Icons.network_check,
                  size: 20,
                  color: _ok == null ? C.muted : (_ok! ? C.good : C.danger)),
          onPressed: _testing ? null : _test,
        ),
      ]),
    );
  }
}

class _FallbackTile extends StatefulWidget {
  final int index, rank, total;
  final AiEndpoint ep;
  const _FallbackTile(
      {super.key,
      required this.index,
      required this.rank,
      required this.total,
      required this.ep});

  @override
  State<_FallbackTile> createState() => _FallbackTileState();
}

class _FallbackTileState extends State<_FallbackTile> {
  bool _testing = false;
  bool? _ok;
  int _ms = 0;

  Future<void> _test() async {
    setState(() => _testing = true);
    final r = await controller.testEndpoint(widget.index);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = r.ok;
      _ms = r.latencyMs;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.ok
          ? 'Модель отвечает · ${r.latencyMs} мс'
          : 'Модель не ответила: ${r.error}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index, total = widget.total, ep = widget.ep;
    final p = findProvider(ep.provider);
    final model = ep.model.trim().isEmpty ? p.defaultModel : ep.model;
    return cardBox(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: C.card2,
          child: Text('${widget.rank + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.accent)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
            const SizedBox(height: 2),
            Text(model, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: C.muted)),
            if (ep.penalized || ep.failStreak > 0)
              Text(
                ep.penalized
                    ? 'Временно понижена после ошибки'
                    : 'Ошибок подряд: ${ep.failStreak}',
                style: TextStyle(fontSize: 10.5, color: C.warn),
              ),
            if (_ok != null)
              Text(
                _ok! ? 'Тест: отвечает · $_ms мс' : 'Тест: ошибка',
                style: TextStyle(
                    fontSize: 10.5,
                    color: _ok! ? C.good : C.danger),
              ),
          ]),
        ),
        IconButton(
          tooltip: 'Тест модели',
          visualDensity: VisualDensity.compact,
          icon: _testing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: C.accent))
              : Icon(
                  Icons.network_check,
                  size: 20,
                  color: _ok == null
                      ? C.muted
                      : (_ok! ? C.good : C.danger),
                ),
          onPressed: _testing ? null : _test,
        ),
        IconButton(
          tooltip: 'Сделать основной',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.swap_vert, size: 21, color: C.accent),
          onPressed: () async {
            final msg = await controller.swapPrimaryWithFallback(index);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(msg)));
            }
          },
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
