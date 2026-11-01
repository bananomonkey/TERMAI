// local_ai.dart — локальная GGUF-модель и менеджер загрузок.
//
// Загрузка больше не живёт в State экрана: DownloadManager переживает
// переходы, сворачивание и перезапуск. Android использует системный
// DownloadManager, остальные платформы — HTTP Range-докачку.
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../download_manager.dart';
import '../local_ai.dart';
import '../main.dart';
import '../secret_store.dart';
import 'app_background.dart';
import 'design_system.dart';
import 'dialogs.dart';
import 'hugging_face.dart';
import 'theme.dart';
import 'widgets.dart';

class LocalAiScreen extends StatefulWidget {
  const LocalAiScreen({super.key});

  @override
  State<LocalAiScreen> createState() => _LocalAiScreenState();
}

class _LocalAiScreenState extends State<LocalAiScreen> {
  final LocalAiService _local = LocalAiService.instance;
  final DownloadManager _downloads = DownloadManager.instance;
  bool _busy = false;
  bool _selectingCompleted = false;
  int? _freeBytes;
  List<File> _installed = [];

  static const _presets = <_LocalPreset>[
    _LocalPreset(
      repo: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
      title: 'Qwen2.5 0.5B',
      size: '~491 МБ',
      note: 'Быстрый старт для слабых устройств',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      file: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      bytes: 491400032,
    ),
    _LocalPreset(
      repo: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
      title: 'Llama 3.2 1B',
      size: '~808 МБ',
      note: 'Баланс качества и скорости',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      file: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      bytes: 807694464,
    ),
    _LocalPreset(
      repo: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      title: 'Qwen2.5 1.5B',
      size: '~1.1 ГБ',
      note: 'Лучше держит контекст, нужно больше RAM',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      file: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      bytes: 1120000000,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _local.addListener(_refresh);
    _downloads.addListener(_refresh);
    _downloads.init().then((_) {
      if (mounted) {
        _refresh();
        _autoSelectCompleted();
      }
    });
    _loadInstalled();
    _loadFree();
  }

  Future<void> _loadFree() async {
    final free = await _downloads.freeBytes();
    if (mounted) setState(() => _freeBytes = free);
  }

  @override
  void dispose() {
    _local.removeListener(_refresh);
    _downloads.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _loadInstalled();
    _autoSelectCompleted();
  }

  Future<void> _loadInstalled() async {
    final files = await _local.installedModels();
    if (!mounted) return;
    setState(() => _installed = files);
  }

  /// Если пользователь скачал модель, но ушёл с экрана — при возвращении
  /// она уже выбрана. Это не трогает файлы и не запускает новую загрузку.
  Future<void> _autoSelectCompleted() async {
    if (_selectingCompleted) return;
    final path = controller.config.localModelPath;
    if (path.isNotEmpty && await File(path).exists()) return;
    final completed = _downloads.jobs
        .where((j) => j.status == DownloadStatus.completed)
        .where((j) => j.finalPath.isNotEmpty)
        .toList();
    if (completed.isEmpty) return;
    _selectingCompleted = true;
    try {
      final file = File(completed.first.finalPath);
      if (await file.exists()) {
        controller.config.localModelPath = file.path;
        await controller.saveConfig(autofill: false);
        if (mounted) setState(() {});
      }
    } finally {
      _selectingCompleted = false;
    }
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
      await _loadInstalled();
      if (!mounted) return;
      _snack('Модель добавлена. Загрузи её в память.');
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

  Future<void> _useFile(File file) async {
    if (!await file.exists()) {
      _snack('Файл модели не найден на устройстве.');
      return;
    }
    controller.config.localModelPath = file.path;
    await controller.saveConfig(autofill: false);
    if (!mounted) return;
    setState(() {});
    _snack('Модель выбрана. Загрузи её в память.');
  }

  Future<void> _deleteFile(File file) async {
    final active = controller.config.localModelPath == file.path;
    final loaded = _local.loadedPath == file.path;
    final ok = await showConfirmDialog(
      context,
      title: 'Удалить модель?',
      message: active || loaded
          ? 'Модель сейчас используется. Она будет выгружена и удалена '
              'с устройства.'
          : 'Файл модели будет удалён с устройства. Скачать его можно снова.',
    );
    if (!ok) return;
    await _local.deleteModel(file.path);
    if (active) {
      controller.config.localModelPath = '';
      await controller.saveConfig(autofill: false);
    }
    for (final job in _downloads.jobs) {
      if (job.finalPath == file.path) {
        await _downloads.removeRecord(job.id);
      }
    }
    await _loadInstalled();
    if (mounted) setState(() {});
  }

  Future<void> _download(_LocalPreset p) async {
    final token = await SecretStore.readHfToken();
    final existing = _downloads.jobFor(p.repo, p.file);
    if (existing != null && existing.status == DownloadStatus.failed) {
      await _downloads.retry(existing.id);
      return;
    }
    if (existing != null && existing.isActive) return;
    await _downloads.start(
      repoId: p.repo,
      fileName: p.file,
      url: p.url,
      token: token,
      expectedBytes: p.bytes,
    );
    await _loadFree();
  }

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';

  String _fileName(String path) => path.split(Platform.pathSeparator).last;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final path = controller.config.localModelPath;
    final hasPath = path.isNotEmpty;
    final loaded = _local.ready;
    final abi = Abi.current();
    final unsupported32 = abi == Abi.androidArm || abi == Abi.androidIA32;
    final jobs = _downloads.jobs;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Локальный ИИ', style: AppText.screenTitle),
      ),
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
          children: [
            appCard(
              padding: const EdgeInsets.all(AppSpace.x3),
              child: Row(
                children: [
                  Icon(
                    loaded ? Icons.memory : Icons.memory_outlined,
                    size: 22,
                    color: loaded ? C.good : C.accent,
                  ),
                  const SizedBox(width: AppSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loaded ? 'Модель в памяти' : _local.status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title.copyWith(color: C.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasPath ? _fileName(path) : 'Модель не выбрана',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: C.muted),
                        ),
                      ],
                    ),
                  ),
                  if (loaded)
                    appStatusPill('готово',
                        color: C.good, icon: Icons.check_circle_outline),
                ],
              ),
            ),
            if (unsupported32) ...[
              const SizedBox(height: 8),
              appCard(
                accent: C.warn.withAlpha(140),
                padding: const EdgeInsets.all(AppSpace.x3),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 19, color: C.warn),
                    const SizedBox(width: AppSpace.x2),
                    Expanded(
                      child: Text(
                        'На 32-битном Android локальный ИИ недоступен. Нужна arm64-сборка.',
                        style: AppText.caption.copyWith(color: C.warn),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_local.loading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _local.progress > 0 ? _local.progress : null,
                minHeight: 5,
                borderRadius: BorderRadius.circular(3),
                backgroundColor: C.card2,
                color: C.accent,
              ),
            ],
            if (_local.error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_local.error,
                  style: AppText.caption.copyWith(color: C.danger)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
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
                    onPressed:
                        _busy || _local.loading || !hasPath ? null : _load,
                    icon: _busy || _local.loading
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(loaded ? 'Перезагрузить' : 'Загрузить',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: loaded ? _local.unload : null,
                    icon: const Icon(Icons.power_settings_new, size: 16),
                    label:
                        const Text('Выгрузить', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasPath ? _makePrimary : null,
                    icon: const Icon(Icons.star_outline, size: 17),
                    label: const Text('Сделать основным',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            appSectionTitle('Установленные модели'),
            if (_installed.isEmpty)
              Text(
                'Пока нет ни одного GGUF-файла.',
                style: AppText.caption.copyWith(color: C.muted),
              )
            else
              for (final file in _installed) ...[
                _InstalledModelTile(
                  file: file,
                  active: file.path == path,
                  loaded: _local.loadedPath == file.path,
                  size: _fileSizeLabel(file),
                  onUse: () => _useFile(file),
                  onDelete: () => _deleteFile(file),
                ),
                const SizedBox(height: 6),
              ],
            const SizedBox(height: 12),
            appSectionTitle(
              'Загрузки',
              trailing: _freeBytes == null
                  ? null
                  : Text(
                      'свободно ${_mb(_freeBytes!)}',
                      style: AppText.caption.copyWith(color: C.muted),
                    ),
            ),
            if (jobs.isEmpty)
              Text(
                'Активных загрузок нет.',
                style: AppText.caption.copyWith(color: C.muted),
              )
            else
              for (final job in jobs) ...[
                _DownloadTile(
                  job: job,
                  progress: job.progress,
                  received: _mb(job.receivedBytes),
                  total: job.totalBytes > 0 ? _mb(job.totalBytes) : '',
                  onCancel: () => _downloads.cancel(job.id),
                  onRetry: () => _downloads.retry(job.id),
                  onRemoveRecord: () => _downloads.removeRecord(job.id),
                  onUse: job.status == DownloadStatus.completed
                      ? () => _useFile(File(job.finalPath))
                      : null,
                ),
                const SizedBox(height: 6),
              ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: appSectionTitle('Каталог Hugging Face'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push(pageRoute(const HuggingFaceScreen())),
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('Найти модель',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Text(
              'Поиск по метаданным Hugging Face, без загрузки всего каталога.',
              style: AppText.caption.copyWith(color: C.muted),
            ),
            const SizedBox(height: 10),
            appSectionTitle('Быстрый старт'),
            for (final p in _presets) ...[
              _PresetTile(
                preset: p,
                job: _downloads.jobFor(p.repo, p.file),
                onDownload: () => _download(p),
                onCancel: (job) => _downloads.cancel(job.id),
                onRetry: (job) => _downloads.retry(job.id),
                onUse: (job) => _useFile(File(job.finalPath)),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 10),
            appCard(
              padding: const EdgeInsets.all(AppSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Размер контекста',
                      style: AppText.title.copyWith(color: C.text)),
                  const SizedBox(height: 2),
                  Text(
                    'Больше контекста — больше памяти. 4096 подходит большинству.',
                    style: AppText.caption.copyWith(color: C.muted),
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

  String _fileSizeLabel(File file) {
    try {
      final size = file.lengthSync();
      return _mb(size);
    } catch (_) {
      return '';
    }
  }
}

class _LocalPreset {
  final String repo, title, size, note, url, file;
  final int bytes;
  const _LocalPreset({
    required this.repo,
    required this.title,
    required this.size,
    required this.note,
    required this.url,
    required this.file,
    required this.bytes,
  });
}

class _InstalledModelTile extends StatelessWidget {
  final File file;
  final bool active;
  final bool loaded;
  final String size;
  final VoidCallback onUse;
  final VoidCallback onDelete;
  const _InstalledModelTile({
    required this.file,
    required this.active,
    required this.loaded,
    required this.size,
    required this.onUse,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return appCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      accent: active ? C.accent.withAlpha(120) : null,
      child: Row(
        children: [
          Icon(Icons.widgets_outlined,
              size: 20, color: active ? C.accent : C.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.path.split(Platform.pathSeparator).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: C.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (active) 'Активная',
                    if (loaded) 'в памяти',
                    if (size.isNotEmpty) size,
                  ].join(' · '),
                  style: AppText.caption.copyWith(
                    color: active ? C.accent : C.muted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: active ? null : onUse,
            style: TextButton.styleFrom(
              minimumSize: const Size(56, 34),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(active ? 'Выбрана' : 'Выбрать',
                style: const TextStyle(fontSize: 11)),
          ),
          IconButton(
            tooltip: 'Удалить модель',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 18, color: C.danger),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadJob job;
  final double progress;
  final String received, total;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemoveRecord;
  final VoidCallback? onUse;

  const _DownloadTile({
    required this.job,
    required this.progress,
    required this.received,
    required this.total,
    required this.onCancel,
    required this.onRetry,
    required this.onRemoveRecord,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final active = job.isActive;
    final color = job.status == DownloadStatus.completed
        ? C.good
        : job.status == DownloadStatus.failed
            ? C.danger
            : C.accent;
    return appCard(
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: C.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              appStatusPill(job.status.label, color: color),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.totalBytes > 0 ? progress : null,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: C.card2,
              color: C.accent,
            ),
            const SizedBox(height: 3),
            Text(
              total.isEmpty ? received : '$received из $total',
              style: AppText.caption.copyWith(color: C.muted),
            ),
          ],
          if (job.error.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(job.error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: C.danger)),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (active)
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(minimumSize: const Size(72, 34)),
                  child:
                      const Text('Отменить', style: TextStyle(fontSize: 11.5)),
                )
              else if (job.status == DownloadStatus.failed)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(minimumSize: const Size(72, 34)),
                  child:
                      const Text('Повторить', style: TextStyle(fontSize: 11.5)),
                )
              else if (job.status == DownloadStatus.completed && onUse != null)
                TextButton(
                  onPressed: onUse,
                  style: TextButton.styleFrom(minimumSize: const Size(64, 34)),
                  child: const Text('Использовать',
                      style: TextStyle(fontSize: 11.5)),
                ),
              IconButton(
                tooltip: 'Убрать запись (файл останется)',
                onPressed: onRemoveRecord,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 17, color: C.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final _LocalPreset preset;
  final DownloadJob? job;
  final VoidCallback onDownload;
  final void Function(DownloadJob) onCancel;
  final void Function(DownloadJob) onRetry;
  final void Function(DownloadJob) onUse;

  const _PresetTile({
    required this.preset,
    required this.job,
    required this.onDownload,
    required this.onCancel,
    required this.onRetry,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final j = job;
    final active = j?.isActive ?? false;
    final completed = j?.status == DownloadStatus.completed;
    final failed = j?.status == DownloadStatus.failed;
    return appCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  preset.title,
                  style: AppText.title.copyWith(color: C.text),
                ),
              ),
              Text(preset.size,
                  style: AppText.caption.copyWith(color: C.muted)),
            ],
          ),
          const SizedBox(height: 2),
          Text(preset.note, style: AppText.caption.copyWith(color: C.muted)),
          if (active) ...[
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: (j?.totalBytes ?? 0) > 0 ? j!.progress : null,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: C.card2,
              color: C.accent,
            ),
            const SizedBox(height: 3),
            Text(
              (j?.totalBytes ?? 0) > 0
                  ? '${(j!.progress * 100).round()}% · ${(j.receivedBytes / (1024 * 1024)).toStringAsFixed(1)} МБ'
                  : 'Скачиваю…',
              style: AppText.caption.copyWith(color: C.muted),
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 4),
            Text(j!.error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: C.danger)),
          ],
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: active
                ? OutlinedButton(
                    onPressed: () => onCancel(j!),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(38),
                    ),
                    child: const Text('Отменить',
                        style: TextStyle(fontSize: 11.5)),
                  )
                : failed
                    ? OutlinedButton(
                        onPressed: () => onRetry(j!),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(38),
                        ),
                        child: const Text('Повторить',
                            style: TextStyle(fontSize: 11.5)),
                      )
                    : completed
                        ? OutlinedButton(
                            onPressed: () => onUse(j!),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(38),
                            ),
                            child: const Text('Использовать',
                                style: TextStyle(fontSize: 11.5)),
                          )
                        : FilledButton(
                            onPressed: onDownload,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(38),
                            ),
                            child: const Text('Скачать',
                                style: TextStyle(fontSize: 11.5)),
                          ),
          ),
        ],
      ),
    );
  }
}
