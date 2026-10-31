// hugging_face.dart — каталог моделей Hugging Face внутри TERMAI.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../download_manager.dart';
import '../hugging_face.dart';
import '../main.dart';
import '../secret_store.dart';
import 'app_background.dart';
import 'design_system.dart';
import 'theme.dart';

class HuggingFaceScreen extends StatefulWidget {
  const HuggingFaceScreen({super.key});

  @override
  State<HuggingFaceScreen> createState() => _HuggingFaceScreenState();
}

class _HuggingFaceScreenState extends State<HuggingFaceScreen> {
  final _search = TextEditingController();
  final _service = HuggingFaceService.instance;
  final _downloads = DownloadManager.instance;
  Timer? _debounce;
  String _token = '';
  String _error = '';
  String _next = '';
  bool _loading = false;
  bool _loadingMore = false;
  bool _onlyDownloaded = false;
  bool _noGated = false;
  String _typeFilter = 'all';
  int _generation = 0;
  List<HFModel> _models = const [];

  List<HFModel> get _shownModels {
    final jobs = DownloadManager.instance.jobs;
    return _models.where((m) {
      if (_noGated && m.gated) return false;
      if (_onlyDownloaded &&
          !jobs.any((j) =>
              j.repoId == m.id && j.status == DownloadStatus.completed)) {
        return false;
      }
      if (_typeFilter != 'all') {
        final tags = m.tags.map((t) => t.toLowerCase()).join(' ');
        final name = m.id.toLowerCase();
        final isVision = tags.contains('vision') ||
            tags.contains('image-text') ||
            name.contains('vision') ||
            name.contains('-vl');
        final isCode = tags.contains('code') ||
            name.contains('coder') ||
            name.contains('code');
        if (_typeFilter == 'vision' && !isVision) return false;
        if (_typeFilter == 'code' && !isCode) return false;
        if (_typeFilter == 'chat' && (isVision || isCode)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _downloads.addListener(_onDownloads);
    _loadToken();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _downloads.removeListener(_onDownloads);
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onDownloads() {
    if (mounted) setState(() {});
  }

  Future<void> _loadToken() async {
    final token = await SecretStore.readHfToken();
    if (mounted) setState(() => _token = token);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch({bool force = false}) async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = '';
      _models = const [];
      _next = '';
    });
    try {
      final page = await _service.search(
        _search.text,
        token: _token,
        force: force,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _models = page.items;
        _next = page.nextCursor;
      });
    } on HFException catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = 'Не удалось получить каталог: $e');
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _next.isEmpty) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.search(
        _search.text,
        cursor: _next,
        token: _token,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _models = [..._models, ...page.items];
        _next = page.nextCursor;
      });
    } on HFException catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e.message);
    } finally {
      if (mounted && gen == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _editToken() async {
    final ctrl = TextEditingController(text: _token);
    var obscure = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: C.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.panel)),
          title: const Text('Hugging Face token'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: 'hf_…',
                  labelText: 'Access token',
                  suffixIcon: IconButton(
                    onPressed: () => setDialog(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: C.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                'Нужен для gated-моделей. Хранится в защищённом хранилище устройства, не попадает в облако и логи.',
                style: AppText.caption.copyWith(color: C.muted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await SecretStore.clearHfToken();
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text('Удалить', style: TextStyle(color: C.danger)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: C.muted)),
            ),
            FilledButton(
              onPressed: () async {
                await SecretStore.writeHfToken(ctrl.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (saved == true) {
      await _loadToken();
      await _runSearch(force: true);
    }
  }

  Future<void> _openModel(HFModel model) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => _ModelSheet(model: model, token: _token),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shownModels;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Hugging Face', style: AppText.screenTitle),
        actions: [
          IconButton(
            tooltip: _token.isEmpty ? 'Добавить HF token' : 'HF token задан',
            onPressed: _editToken,
            icon: Icon(
              _token.isEmpty ? Icons.key_outlined : Icons.key,
              size: 20,
              color: _token.isEmpty ? C.muted : C.accent,
            ),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: () => _runSearch(force: true),
            icon: const Icon(Icons.refresh, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackdrop(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Найти GGUF-модель…',
                  prefixIcon: Icon(Icons.search, size: 20, color: C.muted),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          onPressed: () {
                            _search.clear();
                            _runSearch();
                          },
                          icon: Icon(Icons.close, size: 18, color: C.muted),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Только GGUF · по популярности',
                    style: AppText.caption.copyWith(color: C.muted),
                  ),
                  const Spacer(),
                  if (_token.isNotEmpty)
                    appStatusPill('token', color: C.accent, icon: Icons.key),
                ],
              ),
            ),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  _FilterChip(
                    label: 'Все',
                    selected:
                        !_onlyDownloaded && !_noGated && _typeFilter == 'all',
                    onTap: () => setState(() {
                      _onlyDownloaded = false;
                      _noGated = false;
                      _typeFilter = 'all';
                    }),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: 'Без gated',
                    selected: _noGated,
                    onTap: () => setState(() => _noGated = !_noGated),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: 'Скачанные',
                    selected: _onlyDownloaded,
                    onTap: () =>
                        setState(() => _onlyDownloaded = !_onlyDownloaded),
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    label: 'Чат',
                    selected: _typeFilter == 'chat',
                    onTap: () => setState(() =>
                        _typeFilter = _typeFilter == 'chat' ? 'all' : 'chat'),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: 'Код',
                    selected: _typeFilter == 'code',
                    onTap: () => setState(() =>
                        _typeFilter = _typeFilter == 'code' ? 'all' : 'code'),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: 'Vision',
                    selected: _typeFilter == 'vision',
                    onTap: () => setState(() => _typeFilter =
                        _typeFilter == 'vision' ? 'all' : 'vision'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _error.isNotEmpty
                  ? _ErrorState(
                      message: _error,
                      onRetry: () => _runSearch(force: true),
                    )
                  : _loading && _models.isEmpty
                      ? Center(
                          child: CircularProgressIndicator(
                              color: C.accent, strokeWidth: 2.4),
                        )
                      : shown.isEmpty
                          ? appEmptyState(
                              icon: Icons.search_off,
                              title: 'Ничего не найдено',
                              subtitle: _onlyDownloaded ||
                                      _noGated ||
                                      _typeFilter != 'all'
                                  ? 'Сбрось фильтры или измени запрос.'
                                  : 'Попробуй другое название: qwen, llama, mistral.',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                              itemCount:
                                  shown.length + (_next.isNotEmpty ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i >= shown.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: OutlinedButton(
                                      onPressed:
                                          _loadingMore ? null : _loadMore,
                                      child: _loadingMore
                                          ? const SizedBox(
                                              width: 17,
                                              height: 17,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : const Text('Показать ещё'),
                                    ),
                                  );
                                }
                                final model = shown[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 7),
                                  child: _ModelTile(
                                    model: model,
                                    onTap: () => _openModel(model),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: C.accent.withAlpha(C.isLight ? 35 : 48),
      backgroundColor: C.card,
      side: BorderSide(color: selected ? C.accent : C.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ModelTile extends StatelessWidget {
  final HFModel model;
  final VoidCallback onTap;
  const _ModelTile({required this.model, required this.onTap});

  String _num(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return appCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: C.accent.withAlpha(C.isLight ? 16 : 24),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(Icons.widgets_outlined, size: 19, color: C.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title.copyWith(color: C.text),
                ),
                const SizedBox(height: 2),
                Text(
                  '${model.author} · ↓ ${_num(model.downloads)} · ♥ ${_num(model.likes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: C.muted),
                ),
              ],
            ),
          ),
          if (model.gated)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: appStatusPill('gated', color: C.warn),
            ),
          Icon(Icons.chevron_right_rounded, size: 21, color: C.muted),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => appEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Hugging Face недоступен',
        subtitle: message,
        action: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 17),
          label: const Text('Повторить'),
        ),
      );
}

class _ModelSheet extends StatefulWidget {
  final HFModel model;
  final String token;
  const _ModelSheet({required this.model, required this.token});

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  final _service = HuggingFaceService.instance;
  final _downloads = DownloadManager.instance;
  List<HFFile> _files = const [];
  String _cursor = '';
  String _error = '';
  String _sizeFilter = 'all';
  bool _loading = true;
  bool _more = false;

  List<HFFile> get _shownFiles {
    if (_sizeFilter == 'all') return _files;
    return _files.where((f) {
      if (f.size <= 0) return false;
      const gb = 1024 * 1024 * 1024;
      if (_sizeFilter == 'small') return f.size < gb;
      if (_sizeFilter == 'medium') return f.size >= gb && f.size < 2 * gb;
      return f.size >= 2 * gb;
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool next = false}) async {
    setState(() {
      if (next) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = '';
    });
    try {
      final page = await _service.files(
        widget.model.id,
        cursor: next ? _cursor : '',
        token: widget.token,
      );
      if (!mounted) return;
      setState(() {
        _files = next ? [..._files, ...page.items] : page.items;
        _cursor = page.nextCursor;
      });
    } on HFException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось получить файлы: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  Future<void> _download(HFFile file) async {
    if (widget.model.gated && widget.token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Для gated-модели нужен Hugging Face token с доступом к репозиторию.'),
      ));
      return;
    }
    final job = _downloads.jobFor(widget.model.id, file.path);
    if (job != null && job.status == DownloadStatus.completed) {
      await _use(job);
      return;
    }
    if (job != null && job.status == DownloadStatus.failed) {
      await _downloads.retry(job.id);
      return;
    }
    await _downloads.start(
      repoId: widget.model.id,
      fileName: file.path,
      url: _service.downloadUrl(widget.model.id, file.path),
      token: widget.token,
      expectedBytes: file.size,
    );
  }

  Future<void> _use(DownloadJob job) async {
    if (!await File(job.finalPath).exists()) return;
    controller.config.localModelPath = job.finalPath;
    await controller.saveConfig(autofill: false);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Модель выбрана: ${job.fileName}')),
    );
  }

  String _bytes(int n) {
    if (n <= 0) return 'размер неизвестен';
    if (n >= 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    }
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  @override
  Widget build(BuildContext context) {
    final shownFiles = _shownFiles;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: Column(
          children: [
            const SizedBox(height: 10),
            appSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.model.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.screenTitle.copyWith(color: C.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.model.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: C.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'GGUF · llama.cpp · 64-битный Android',
                          style: AppText.caption.copyWith(
                            color: C.muted.withAlpha(190),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: 20, color: C.muted),
                  ),
                ],
              ),
            ),
            if (widget.model.gated)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                child: appCard(
                  color: C.warn.withAlpha(C.isLight ? 14 : 22),
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 17, color: C.warn),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Gated-модель. Нужен token с доступом к репозиторию и принятые условия на Hugging Face.',
                          style: AppText.caption.copyWith(color: C.warn),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  _FilterChip(
                    label: 'Любой размер',
                    selected: _sizeFilter == 'all',
                    onTap: () => setState(() => _sizeFilter = 'all'),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: '< 1 ГБ',
                    selected: _sizeFilter == 'small',
                    onTap: () => setState(() => _sizeFilter = 'small'),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: '1–2 ГБ',
                    selected: _sizeFilter == 'medium',
                    onTap: () => setState(() => _sizeFilter = 'medium'),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: '> 2 ГБ',
                    selected: _sizeFilter == 'large',
                    onTap: () => setState(() => _sizeFilter = 'large'),
                  ),
                ],
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_error,
                          style: AppText.caption.copyWith(color: C.danger)),
                    ),
                    TextButton(
                      onPressed: () => _load(),
                      child: const Text('Повторить',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: C.accent, strokeWidth: 2.4))
                  : shownFiles.isEmpty && _cursor.isEmpty
                      ? appEmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: _files.isEmpty
                              ? 'GGUF-файлы не найдены'
                              : 'Нет файлов с таким размером',
                          subtitle: _files.isEmpty
                              ? 'У этого репозитория нет файлов в формате GGUF.'
                              : 'Сбрось фильтр размера.',
                          action: _files.isEmpty
                              ? null
                              : OutlinedButton(
                                  onPressed: () =>
                                      setState(() => _sizeFilter = 'all'),
                                  child: const Text('Сбросить фильтр'),
                                ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                          itemCount: shownFiles.length +
                              ((_cursor.isNotEmpty || _files.isEmpty) ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= shownFiles.length) {
                              return OutlinedButton(
                                onPressed:
                                    _more ? null : () => _load(next: true),
                                child: _more
                                    ? const SizedBox(
                                        width: 17,
                                        height: 17,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Показать ещё файлы'),
                              );
                            }
                            final file = shownFiles[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: AnimatedBuilder(
                                animation: _downloads,
                                builder: (context, _) => _FileTile(
                                  model: widget.model,
                                  file: file,
                                  job: _downloads.jobFor(
                                      widget.model.id, file.path),
                                  size: _bytes(file.size),
                                  onDownload: () => _download(file),
                                  onCancel: (job) => _downloads.cancel(job.id),
                                  onRetry: (job) => _downloads.retry(job.id),
                                  onUse: _use,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final HFModel model;
  final HFFile file;
  final DownloadJob? job;
  final String size;
  final VoidCallback onDownload;
  final void Function(DownloadJob) onCancel;
  final void Function(DownloadJob) onRetry;
  final Future<void> Function(DownloadJob) onUse;

  const _FileTile({
    required this.model,
    required this.file,
    required this.job,
    required this.size,
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
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: C.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (file.quantization.isNotEmpty)
                appStatusPill(file.quantization, color: C.secondary),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${file.lfs ? 'LFS · ' : ''}$size',
            style: AppText.caption.copyWith(color: C.muted),
          ),
          if (active) ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: (j?.totalBytes ?? 0) > 0 ? j!.progress : null,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              backgroundColor: C.card2,
              color: C.accent,
            ),
            const SizedBox(height: 2),
            Text(
              '${(j!.receivedBytes / (1024 * 1024)).toStringAsFixed(1)} МБ'
              '${j.totalBytes > 0 ? ' из ${(j.totalBytes / (1024 * 1024)).toStringAsFixed(1)} МБ' : ''}',
              style: AppText.caption.copyWith(color: C.muted),
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 3),
            Text(j!.error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: C.danger)),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: active
                ? TextButton(
                    onPressed: () => onCancel(j!),
                    child: const Text('Отменить',
                        style: TextStyle(fontSize: 11.5)),
                  )
                : failed
                    ? TextButton(
                        onPressed: () => onRetry(j!),
                        child: const Text('Повторить',
                            style: TextStyle(fontSize: 11.5)),
                      )
                    : completed
                        ? TextButton(
                            onPressed: () => onUse(j!),
                            child: const Text('Использовать',
                                style: TextStyle(fontSize: 11.5)),
                          )
                        : TextButton.icon(
                            onPressed: onDownload,
                            icon: const Icon(Icons.download, size: 16),
                            label: const Text('Скачать',
                                style: TextStyle(fontSize: 11.5)),
                          ),
          ),
        ],
      ),
    );
  }
}
