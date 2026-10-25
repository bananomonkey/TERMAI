// background_settings.dart — фон приложения: своё фото из галереи,
// уровень размытия и затемнение. Предпросмотр использует тот же
// кэшированный рендер, что и настоящий фон, поэтому размытие видно сразу.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import 'app_background.dart';
import 'theme.dart';
import 'widgets.dart';

class BackgroundSettingsScreen extends StatefulWidget {
  const BackgroundSettingsScreen({super.key});
  @override
  State<BackgroundSettingsScreen> createState() =>
      _BackgroundSettingsScreenState();
}

class _BackgroundSettingsScreenState extends State<BackgroundSettingsScreen> {
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 3200,
        imageQuality: 92,
      );
      if (picked == null) return;
      final err = await controller.setBackgroundPhoto(picked.path);
      if (err.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Фон применён')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть галерею')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Фон приложения',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final cfg = controller.config;
            final has = cfg.bgPhoto.isNotEmpty;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                // предпросмотр: фото (если есть) или фон темы
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 210,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (has)
                          BackdropImage(
                            path: cfg.bgPhoto,
                            blur: cfg.bgBlur,
                            maxWidth: 900,
                          )
                        else
                          ColoredBox(color: C.bg),
                        // затемнение — ровно как на реальном экране
                        ColoredBox(
                          color: C.bg.withAlpha(
                              (cfg.bgDim * 255).round().clamp(0, 242)),
                        ),
                        Center(
                          child: has
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(90),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Так фон выглядит на экранах',
                                    style: TextStyle(
                                        fontSize: 11.5, color: C.text),
                                  ),
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.wallpaper_outlined,
                                        size: 30, color: C.muted),
                                    const SizedBox(height: 8),
                                    Text('Фон темы',
                                        style: TextStyle(
                                            color: C.muted,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _picking ? null : _pick,
                      icon: _picking
                          ? SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: C.text))
                          : const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(has ? 'Заменить фото' : 'Выбрать из галереи',
                          style: const TextStyle(fontSize: 13.5)),
                    ),
                  ),
                  if (has) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => controller.clearBackgroundPhoto(),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(52, 50)),
                      child:
                          Icon(Icons.delete_outline, size: 18, color: C.danger),
                    ),
                  ],
                ]),
                const SizedBox(height: 24),
                caption('Размытие фона', color: C.accent),
                Row(children: [
                  Expanded(
                    child: Slider(
                      value: cfg.bgBlur,
                      min: 0,
                      max: 40,
                      divisions: 40,
                      label: cfg.bgBlur.round().toString(),
                      onChanged: has
                          ? (v) => controller.setBackgroundTuning(blur: v)
                          : null,
                      onChangeEnd: has
                          ? (v) => controller.setBackgroundTuning(
                              blur: v, persist: true)
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text('${cfg.bgBlur.round()}',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: C.muted, fontSize: 13)),
                  ),
                ]),
                Text(
                    has
                        ? 'Размытие применяется к фото фона и видно в предпросмотре сразу.'
                        : 'Фон сейчас ровный. Выбери фото, чтобы включить размытие.',
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
                      onChanged: has
                          ? (v) => controller.setBackgroundTuning(dim: v)
                          : null,
                      onChangeEnd: has
                          ? (v) => controller.setBackgroundTuning(
                              dim: v, persist: true)
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text('${(cfg.bgDim * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: C.muted, fontSize: 13)),
                  ),
                ]),
                Text(
                    has
                        ? 'Затемнение приглушает фото, чтобы карточки и текст читались.'
                        : 'Затемнение включится вместе с фото.',
                    style: TextStyle(fontSize: 11.5, color: C.muted)),
                const SizedBox(height: 20),
                Text(
                  'Фото копируется в папку приложения, поэтому работает и после удаления '
                  'из галереи. Ничего никуда не отправляется.',
                  style:
                      TextStyle(fontSize: 11.5, color: C.muted, height: 1.45),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
