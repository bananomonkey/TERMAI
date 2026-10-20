// background_settings.dart — фон приложения: своё фото из галереи,
// уровень размытия и затемнение, чтобы текст оставался читаемым.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

class BackgroundSettingsScreen extends StatelessWidget {
  const BackgroundSettingsScreen({super.key});

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 3000,
        imageQuality: 90,
      );
      if (picked == null) return;
      final err = await controller.setBackgroundPhoto(picked.path);
      if (err.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть галерею')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Фон приложения', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final cfg = controller.config;
          final has = cfg.bgPhoto.isNotEmpty;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 200,
                  child: has
                      ? Stack(fit: StackFit.expand, children: [
                          Image.file(
                            File(cfg.bgPhoto),
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, __, ___) => ColoredBox(color: C.card),
                          ),
                          ColoredBox(color: C.bg.withAlpha((cfg.bgDim * 255).round().clamp(0, 255))),
                        ])
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [C.card, C.card2, C.bg],
                            ),
                          ),
                          child: Center(
                            child: Text('Фон темы',
                                style: TextStyle(color: C.muted, fontWeight: FontWeight.w700)),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _pick(context),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(has ? 'Заменить фото' : 'Выбрать из галереи',
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                ),
                if (has) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => controller.clearBackgroundPhoto(),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(52, 50)),
                    child: Icon(Icons.delete_outline, size: 18, color: C.danger),
                  ),
                ],
              ]),
              const SizedBox(height: 24),
              caption('Размытие', color: C.accent),
              Row(children: [
                Expanded(
                  child: Slider(
                    value: cfg.bgBlur,
                    min: 0,
                    max: 40,
                    divisions: 40,
                    label: cfg.bgBlur.round().toString(),
                    onChanged: has ? (v) => controller.setBackgroundTuning(blur: v) : null,
                    onChangeEnd: (v) => controller.setBackgroundTuning(blur: v, persist: true),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text('${cfg.bgBlur.round()}',
                      textAlign: TextAlign.right, style: TextStyle(color: C.muted, fontSize: 13)),
                ),
              ]),
              Text('0 — фото видно как есть, 40 — мягкое размытое пятно.',
                  style: TextStyle(fontSize: 11.5, color: C.muted)),
              const SizedBox(height: 18),
              caption('Затемнение', color: C.accent),
              Row(children: [
                Expanded(
                  child: Slider(
                    value: cfg.bgDim,
                    min: 0,
                    max: 0.9,
                    divisions: 18,
                    label: '${(cfg.bgDim * 100).round()}%',
                    onChanged: has ? (v) => controller.setBackgroundTuning(dim: v) : null,
                    onChangeEnd: (v) => controller.setBackgroundTuning(dim: v, persist: true),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text('${(cfg.bgDim * 100).round()}%',
                      textAlign: TextAlign.right, style: TextStyle(color: C.muted, fontSize: 13)),
                ),
              ]),
              Text('Затемнение поверх фото — чтобы карточки и текст читались.',
                  style: TextStyle(fontSize: 11.5, color: C.muted)),
              const SizedBox(height: 20),
              Text(
                'Фото копируется в папку приложения, поэтому работает и после удаления из галереи. '
                'Ничего никуда не отправляется.',
                style: TextStyle(fontSize: 11.5, color: C.muted, height: 1.45),
              ),
            ],
          );
        },
      ),
    );
  }
}
