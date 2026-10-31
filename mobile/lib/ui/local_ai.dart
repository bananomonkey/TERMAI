// local_ai.dart — экран локальной GGUF-модели: выбор файла, загрузка
// готовых моделей, запуск в память и назначение основным провайдером.
import 'dart:ffi';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../local_ai.dart';
import '../main.dart';
import 'app_background.dart';
import 'theme.dart';
import 'widgets.dart';

class LocalAiScreen extends StatefulWidget {
  const LocalAiScreen({super.key});

  @override
  State<LocalAiScreen> createState() => _LocalAiScreenState();
}

class _LocalAiScreenState extends State<LocalAiScreen> {
  final LocalAiService _local = LocalAiService.instance;
  bool _busy = false;
  String _downloading = '';
  double _downloadProgress = 0;
  int _received = 0;
  int _total = 0;

  static const _presets = <_LocalPreset>[
    _LocalPreset(
      title: 'Qwen2.5 0.5B Instruct',
      size: '~491 МБ',
      note: 'Самая лёгкая: быстрый старт, базовые ответы',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      file: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    ),
    _LocalPreset(
      title: 'Llama 3.2 1B Instruct',
      size: '~808 МБ',
      note: 'Баланс качества и скорости',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      file: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    ),
    _LocalPreset(
      title: 'Qwen2.5 1.5B Instruct',
      size: '~1.1 ГБ',
      note: 'Лучше держит контекст, нужно больше RAM',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      file: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _local.addListener(_refresh);
  }

  @override
  void dispose() {
    _local.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final f = await FilePicker.pickFile(
        dialogTitle: 'Выбери GGUF-модель',
        type: FileType.custom,
        allowedExtensions: ['gguf'],
      );
      final path = f?.path;
      if (path == null || path.isEmpty) return;
      final copied = await _local.copyIntoModels(path);
      controller.config.localModelPath = copied;
      await controller.saveConfig(autofill: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Модель скопирована. Нажми «Загрузить в память».')));
    } catch (e) {
      _snack('Не удалось выбрать файл: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final path = controller.config.localModelPath;
    if (path.isEmpty) {
      _snack('Сначала выбери GGUF-файл или скачай модель.');
      return;
    }
    setState(() => _busy = true);
    final err = await _local.load(path,
        contextSize: controller.config.localContextSize);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(err.isEmpty
        ? 'Модель загружена и готова к работе'
        : 'Ошибка загрузки: $err');
  }

  Future<void> _makePrimary() async {
    final path = controller.config.localModelPath;
    if (path.isEmpty) {
      _snack('Сначала выбери локальную модель.');
      return;
    }
    controller.config.provider = 'local';
    controller.config.model = 'local';
    controller.config.apiKey = '';
    controller.config.baseUrl = '';
    await controller.saveConfig(autofill: false);
    if (!mounted) return;
    _snack('Локальная модель назначена основным ИИ');
  }

  Future<void> _download(_LocalPreset p) async {
    if (_downloading.isNotEmpty) return;
    setState(() {
      _downloading = p.file;
      _downloadProgress = 0;
      _received = 0;
      _total = 0;
    });
    try {
      final path = await _local.downloadModel(
        p.url,
        p.file,
        onProgress: (fraction, received, total) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = fraction;
            _received = received;
            _total = total;
          });
        },
      );
      controller.config.localModelPath = path;
      await controller.saveConfig(autofill: false);
      if (!mounted) return;
      _snack('Модель скачана: ${p.title}');
    } catch (e) {
      _snack('Не удалось скачать: $e');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = '';
          _downloadProgress = 0;
          _received = 0;
          _total = 0;
        });
      }
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final path = controller.config.localModelPath;
    final hasPath = path.isNotEmpty;
    final loaded = _local.ready;
    final abi = Abi.current();
    final unsupported32 =
        abi == Abi.androidArm || abi == Abi.androidIA32;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Локальный ИИ',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Text(
              'Модель работает прямо на телефоне и не отправляет запросы в сеть. '
              'Нужен GGUF-файл; для старта хватит Qwen2.5 0.5B или Llama 3.2 1B.',
              style: TextStyle(fontSize: 13, color: C.muted, height: 1.45),
            ),
            if (unsupported32) ...[
              const SizedBox(height: 10),
              cardBox(
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 19, color: C.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'На 32-битном Android локальный ИИ недоступен. '
                      'Нужна 64-битная сборка (arm64).',
                      style: TextStyle(fontSize: 11.5, color: C.warn),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            cardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(
                    loaded ? Icons.memory : Icons.memory_outlined,
                    size: 20,
                    color: loaded ? C.good : C.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loaded ? 'Модель в памяти' : _local.status,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: C.text),
                    ),
                  ),
                ]),
                if (_local.loading) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _local.progress > 0 ? _local.progress : null,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: C.card2,
                    color: C.accent,
                  ),
                  const SizedBox(height: 6),
                  Text('${(_local.progress * 100).round()}%',
                      style: TextStyle(fontSize: 11, color: C.muted)),
                ],
                if (hasPath) ...[
                  const SizedBox(height: 8),
                  Text(
                    path.split(Platform.pathSeparator).last,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: C.muted),
                  ),
                ],
                if (_local.error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_local.error,
                      style: TextStyle(fontSize: 11.5, color: C.danger)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.folder_open, size: 17),
                      label: const Text('Выбрать GGUF',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy || _local.loading || !hasPath
                          ? null
                          : _load,
                      icon: _busy || _local.loading
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(loaded ? 'Перезагрузить' : 'Загрузить',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: loaded ? _local.unload : null,
                      icon: const Icon(Icons.power_settings_new, size: 16),
                      label: const Text('Выгрузить',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasPath ? _makePrimary : null,
                      icon: const Icon(Icons.star_outline, size: 17),
                      label: const Text('Сделать основным',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ]),
                if (hasPath) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () async {
                      await _local.deleteModel(path);
                      controller.config.localModelPath = '';
                      await controller.saveConfig(autofill: false);
                      if (mounted) setState(() {});
                    },
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft),
                    icon: Icon(Icons.delete_outline,
                        size: 16, color: C.danger),
                    label: Text('Удалить файл модели',
                        style: TextStyle(fontSize: 11.5, color: C.danger)),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            caption('Скачать модель', color: C.accent),
            const SizedBox(height: 8),
            Text(
              'Скачивание идёт с Hugging Face. Лучше по Wi-Fi: файлы большие.',
              style: TextStyle(fontSize: 11.5, color: C.muted),
            ),
            const SizedBox(height: 8),
            for (final p in _presets) ...[
              _PresetTile(
                preset: p,
                downloading: _downloading == p.file,
                progress: _downloading == p.file ? _downloadProgress : 0,
                received: _downloading == p.file ? _received : 0,
                total: _downloading == p.file ? _total : 0,
                enabled: _downloading.isEmpty,
                onDownload: () => _download(p),
                onUse: () async {
                  final dir = await _local.modelsDir();
                  final file = File('${dir.path}/${p.file}');
                  if (!await file.exists()) {
                    _snack('Сначала скачай модель.');
                    return;
                  }
                  controller.config.localModelPath = file.path;
                  await controller.saveConfig(autofill: false);
                  if (mounted) setState(() {});
                  _snack('Модель выбрана. Нажми «Загрузить в память».');
                },
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            cardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Размер контекста',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: C.text)),
                  const SizedBox(height: 4),
                  Text(
                    'Больше контекста — больше памяти. 4096 подходит большинству.',
                    style: TextStyle(fontSize: 11, color: C.muted),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: controller.config.localContextSize,
                    items: const [
                      DropdownMenuItem(value: 2048, child: Text('2048')),
                      DropdownMenuItem(value: 4096, child: Text('4096')),
                      DropdownMenuItem(value: 8192, child: Text('8192')),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      controller.config.localContextSize = v;
                      await controller.saveConfig(autofill: false);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalPreset {
  final String title, size, note, url, file;
  const _LocalPreset({
    required this.title,
    required this.size,
    required this.note,
    required this.url,
    required this.file,
  });
}

class _PresetTile extends StatelessWidget {
  final _LocalPreset preset;
  final bool downloading, enabled;
  final double progress;
  final int received, total;
  final VoidCallback onDownload;
  final VoidCallback onUse;

  const _PresetTile({
    required this.preset,
    required this.downloading,
    required this.progress,
    required this.received,
    required this.total,
    required this.enabled,
    required this.onDownload,
    required this.onUse,
  });

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';

  @override
  Widget build(BuildContext context) {
    return cardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(preset.title,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: C.text)),
            ),
            Text(preset.size,
                style: TextStyle(fontSize: 11, color: C.muted)),
          ]),
          const SizedBox(height: 3),
          Text(preset.note,
              style: TextStyle(fontSize: 11, color: C.muted)),
          if (downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: C.card2,
              color: C.accent,
            ),
            const SizedBox(height: 4),
            Text(
              total > 0
                  ? '${_mb(received)} из ${_mb(total)}'
                  : '${(progress * 100).round()}%',
              style: TextStyle(fontSize: 10.5, color: C.muted),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: enabled ? onDownload : null,
                icon: const Icon(Icons.download, size: 16),
                label: Text(downloading ? 'Скачиваю…' : 'Скачать',
                    style: const TextStyle(fontSize: 11.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: enabled ? onUse : null,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Использовать',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
