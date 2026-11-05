// local_tts_screen.dart — каталог офлайн-голосов Piper. Загрузка только по
// кнопке, с прогрессом, отменой, повтором, удалением и проверкой места.
import 'dart:async';

import 'package:flutter/material.dart';

import '../download_manager.dart';
import '../local_tts.dart';
import '../main.dart';
import 'app_background.dart';
import 'design_system.dart';
import 'dialogs.dart';
import 'theme.dart';

class LocalTtsScreen extends StatefulWidget {
  const LocalTtsScreen({super.key});

  @override
  State<LocalTtsScreen> createState() => _LocalTtsScreenState();
}

class _LocalTtsScreenState extends State<LocalTtsScreen> {
  Set<String> _installed = {};
  final Set<String> _testing = {};
  // Каталог показываем сразу; статусы установки догружаются в фоне.
  bool _loading = false;
  int? _free;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    DownloadManager.instance.addListener(_scheduleRefresh);
    LocalTtsService.instance.addListener(_scheduleRefresh);
    _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    DownloadManager.instance.removeListener(_scheduleRefresh);
    LocalTtsService.instance.removeListener(_scheduleRefresh);
    super.dispose();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 250), _refresh);
  }

  Future<void> _refresh() async {
    try {
      await LocalTtsService.instance.init();
      final ids = await LocalTtsService.instance.installedIds();
      final free = await DownloadManager.instance.freeBytes();
      if (!mounted) return;
      setState(() {
        _installed = ids.toSet();
        _free = free;
      });
    } catch (_) {
      // Каталог должен открываться даже без доступа к файловой системе.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(LocalTtsModel model) async {
    controller.config.ttsLocalModelId = model.id;
    controller.config.ttsUseLocal = true;
    controller.config.ttsEnabled = true;
    await controller.saveTtsConfig();
    if (!mounted) return;
    await _testVoice(model, selectedNow: true);
  }

  Future<void> _testVoice(LocalTtsModel model,
      {bool selectedNow = false}) async {
    if (_testing.contains(model.id)) return;
    setState(() => _testing.add(model.id));
    final ok = await LocalTtsService.instance.speak(
      'Привет! Голос ${model.title} установлен и готов к работе.',
      controller.config,
      modelId: model.id,
    );
    if (!mounted) return;
    setState(() => _testing.remove(model.id));
    final error = LocalTtsService.instance.lastError;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '${selectedNow ? 'Голос выбран. ' : ''}Тестовая озвучка выполнена.'
          : 'Голос не прошёл проверку: ${error.isEmpty ? 'движок не создал звук' : error}'),
    ));
  }

  Future<void> _delete(LocalTtsModel model) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить голос?',
      message: '«${model.title}» будет удалён с устройства. '
          'Скачать его можно снова.',
    );
    if (!ok) return;
    await LocalTtsService.instance.delete(model);
    if (controller.config.ttsLocalModelId == model.id) {
      controller.config.ttsUseLocal = false;
      controller.config.ttsLocalModelId = '';
      await controller.saveTtsConfig();
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Локальные голоса', style: AppText.screenTitle),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
          listenable: Listenable.merge([DownloadManager.instance, controller]),
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                appCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.offline_bolt_outlined,
                          size: 18, color: C.accent),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Работают без интернета после загрузки. Модели '
                          'большие, поэтому приложение никогда не скачивает '
                          'их само. Системный голос Android остаётся запасным.',
                          style: AppText.caption.copyWith(color: C.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_free != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Свободно на устройстве: '
                    '${(_free! / (1024 * 1024)).round()} МБ',
                    style: AppText.caption.copyWith(color: C.muted),
                  ),
                ],
                const SizedBox(height: 14),
                appSectionTitle('Каталог'),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  for (final model in localTtsCatalog) ...[
                    _modelCard(model),
                    const SizedBox(height: 9),
                  ],
                const SizedBox(height: 8),
                appCard(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Каталог намеренно небольшой: только русские голоса '
                    'Piper с понятной лицензией. Silero и голоса с '
                    'неясной лицензией не поставляются.',
                    style: AppText.caption.copyWith(color: C.muted),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _modelCard(LocalTtsModel model) {
    final installed = _installed.contains(model.id);
    final selected = controller.config.ttsLocalModelId == model.id;
    final job = LocalTtsService.instance.jobFor(model);
    final active = job?.isActive ?? false;
    final failed = job?.status == DownloadStatus.failed;
    final extractFailed = LocalTtsService.instance.extractionFailed(model.id);
    return appCard(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      accent: selected ? C.accent.withAlpha(100) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: C.accent.withAlpha(C.isLight ? 22 : 34),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.record_voice_over_outlined,
                    size: 19, color: C.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.title,
                        style: AppText.title.copyWith(fontSize: 14)),
                    Text(model.subtitle,
                        style: AppText.caption.copyWith(color: C.muted)),
                  ],
                ),
              ),
              if (selected)
                appStatusPill('выбран',
                    color: C.good, icon: Icons.check_rounded)
              else if (installed)
                appStatusPill('установлен',
                    color: C.accent, icon: Icons.download_done),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '${model.sizeLabel} архив · ~${(model.installedBytes / (1024 * 1024)).round()} МБ на диске · ${model.license}',
            style: AppText.caption.copyWith(color: C.muted),
          ),
          if (active) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job!.totalBytes <= 0 ? null : job.progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: C.card2,
              color: C.accent,
            ),
            const SizedBox(height: 4),
            Text(
              job.totalBytes > 0
                  ? '${(job.receivedBytes / (1024 * 1024)).toStringAsFixed(1)} '
                      'из ${(job.totalBytes / (1024 * 1024)).round()} МБ'
                  : 'Загрузка…',
              style: AppText.caption.copyWith(color: C.muted),
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 6),
            Text(
                job?.error.isNotEmpty == true
                    ? job!.error
                    : 'Загрузка не удалась',
                style: TextStyle(fontSize: 11.5, color: C.danger)),
          ],
          if (job?.status == DownloadStatus.completed &&
              !installed &&
              !extractFailed) ...[
            const SizedBox(height: 6),
            Text('Распаковываю голос…',
                style: AppText.caption.copyWith(color: C.accent)),
          ],
          if (extractFailed) ...[
            const SizedBox(height: 6),
            Text(
              LocalTtsService.instance.lastError.isEmpty
                  ? 'Не удалось распаковать голос.'
                  : LocalTtsService.instance.lastError,
              style: TextStyle(fontSize: 11.5, color: C.danger),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: installed
                    ? FilledButton.icon(
                        onPressed: selected ? null : () => _select(model),
                        icon: const Icon(Icons.check, size: 17),
                        label: Text(selected ? 'Выбран' : 'Использовать'),
                      )
                    : extractFailed
                        ? OutlinedButton.icon(
                            onPressed: () =>
                                LocalTtsService.instance.retryExtract(model),
                            icon: const Icon(Icons.refresh, size: 17),
                            label: const Text('Распаковать снова'),
                          )
                        : active
                            ? OutlinedButton.icon(
                                onPressed: () =>
                                    LocalTtsService.instance.cancel(model),
                                icon: const Icon(Icons.close, size: 17),
                                label: const Text('Отменить'),
                              )
                            : FilledButton.icon(
                                onPressed: failed
                                    ? () =>
                                        LocalTtsService.instance.retry(model)
                                    : () => LocalTtsService.instance
                                        .download(model),
                                icon: const Icon(Icons.download_outlined,
                                    size: 17),
                                label: Text(failed ? 'Повторить' : 'Скачать'),
                              ),
              ),
              if (installed) ...[
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: 'Проверить голос',
                  onPressed: _testing.contains(model.id)
                      ? null
                      : () => _testVoice(model),
                  icon: _testing.contains(model.id)
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.volume_up_outlined, size: 19),
                ),
              ],
              if (installed || job != null) ...[
                const SizedBox(width: 6),
                TextButton(
                  onPressed: active ||
                          (job?.status == DownloadStatus.completed &&
                              !installed &&
                              !extractFailed)
                      ? null
                      : () => _delete(model),
                  style: TextButton.styleFrom(
                    foregroundColor: C.danger,
                    minimumSize: const Size(64, 44),
                  ),
                  child: const Text('Удалить'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
