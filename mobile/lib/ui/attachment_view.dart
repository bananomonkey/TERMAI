// attachment_view.dart — компактные вложения и их просмотр.
//
// В пузыре показываем тип и порядковый номер, а не длинное имя файла.
// Исходное имя остаётся в модели ChatAttachment и доступно в tooltip.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:open_filex/open_filex.dart';

import '../models.dart';
import '../navigation.dart';
import 'design_system.dart';
import 'theme.dart';

String attachmentTypeLabel(ChatAttachment a) {
  final n = a.name.toLowerCase();
  final mime = a.mime.toLowerCase();
  if (a.isSvg || mime == 'image/svg+xml') return 'Иллюстрация';
  if (a.isImage || mime.startsWith('image/')) return 'Фото';
  if (mime == 'application/pdf' ||
      n.endsWith('.pdf') ||
      n.endsWith('.doc') ||
      n.endsWith('.docx') ||
      n.endsWith('.xls') ||
      n.endsWith('.xlsx') ||
      n.endsWith('.ppt') ||
      n.endsWith('.pptx')) {
    return 'Документ';
  }
  return 'Файл';
}

String attachmentSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} КБ';
  return '$bytes Б';
}

class AttachmentBadge extends StatelessWidget {
  final ChatAttachment attachment;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const AttachmentBadge({
    super.key,
    required this.attachment,
    required this.index,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final label = '${attachmentTypeLabel(attachment)} $index';
    final details = [
      attachment.name,
      if (attachmentSize(attachment.size).isNotEmpty)
        attachmentSize(attachment.size),
    ].join(' · ');
    final file = File(attachment.path);
    final thumb = attachment.isImage && file.existsSync()
        ? ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.file(
              file,
              width: 24,
              height: 24,
              cacheWidth: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                size: 16,
                color: C.muted,
              ),
            ),
          )
        : Icon(
            attachment.isSvg
                ? Icons.brush_outlined
                : attachment.isImage
                    ? Icons.image_outlined
                    : attachmentTypeLabel(attachment) == 'Документ'
                        ? Icons.description_outlined
                        : Icons.insert_drive_file_outlined,
            size: 16,
            color: C.accent,
          );
    return Tooltip(
      message: details,
      child: Material(
        color: C.card2,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                thumb,
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 118),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: C.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 2),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onRemove,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14, color: C.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Подписи с независимой нумерацией по типам внутри одного сообщения.
List<Widget> attachmentBadges(
  List<ChatAttachment> attachments, {
  bool compact = false,
}) {
  var images = 0;
  var docs = 0;
  var files = 0;
  final out = <Widget>[];
  for (final a in attachments) {
    final type = attachmentTypeLabel(a);
    final index = type == 'Фото'
        ? ++images
        : type == 'Документ'
            ? ++docs
            : ++files;
    out.add(AttachmentBadge(
      attachment: a,
      index: index,
      onTap: () => showAttachmentViewer(a),
    ));
  }
  return out;
}

/// SvgAttachmentPreview — картинка прямо в пузыре чата.
class SvgAttachmentPreview extends StatelessWidget {
  final ChatAttachment attachment;
  const SvgAttachmentPreview({super.key, required this.attachment});

  @override
  Widget build(BuildContext context) {
    final file = File(attachment.path);
    if (!file.existsSync()) {
      return Text('Иллюстрация не найдена на устройстве.',
          style: AppText.caption.copyWith(color: C.danger));
    }
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 5),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.accent.withAlpha(70)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAttachmentViewer(attachment),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Row(children: [
                Icon(Icons.brush_outlined, size: 15, color: C.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Иллюстрация Термая',
                      style: AppText.caption.copyWith(
                          color: C.text, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.zoom_in, size: 16, color: C.muted),
              ]),
            ),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: SvgPicture.file(
                  file,
                  fit: BoxFit.contain,
                  placeholderBuilder: (_) => const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAttachmentViewer(ChatAttachment attachment) async {
  final file = File(attachment.path);
  if (!await file.exists()) {
    _toast('Файл вложения не найден на устройстве.');
    return;
  }
  if (attachment.isSvg) {
    _showSvg(attachment, file);
    return;
  }
  if (attachment.isImage) {
    _showImage(attachment, file);
    return;
  }
  if (_isText(attachment)) {
    _showText(attachment, file);
    return;
  }
  _showFileInfo(attachment, file);
}

void _showSvg(ChatAttachment a, File file) {
  final ctx = _rootContext();
  if (ctx == null) return;
  showDialog<void>(
    context: ctx,
    barrierColor: Colors.black.withAlpha(220),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(10),
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.7,
              maxScale: 8,
              child: Center(
                child: SvgPicture.file(file, fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black.withAlpha(120),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Material(
              color: Colors.black.withAlpha(120),
              borderRadius: BorderRadius.circular(22),
              child: TextButton.icon(
                onPressed: () => _saveSvg(a, file),
                icon: const Icon(Icons.save_alt, color: Colors.white, size: 18),
                label: const Text('Сохранить',
                    style: TextStyle(color: Colors.white, fontSize: 12.5)),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: Text(
              '${a.name} · щипок для увеличения',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11.5, height: 1.3),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _saveSvg(ChatAttachment a, File file) async {
  try {
    final bytes = await file.readAsBytes();
    final uri = await FilePicker.saveFile(
      fileName: a.name.isEmpty ? 'illustration.svg' : a.name,
      bytes: bytes,
      mimeType: 'image/svg+xml',
      dialogTitle: 'Сохранить иллюстрацию',
    );
    if (uri == null) return;
    _toast('Иллюстрация сохранена');
  } catch (e) {
    _toast('Не удалось сохранить: $e');
  }
}

void _showImage(ChatAttachment a, File file) {
  final ctx = _rootContext();
  if (ctx == null) return;
  showDialog<void>(
    context: ctx,
    barrierColor: Colors.black.withAlpha(220),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(
                    'Не удалось открыть изображение',
                    style: TextStyle(color: C.text),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black.withAlpha(110),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 6,
            child: Text(
              a.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11.5, height: 1.3),
            ),
          ),
        ],
      ),
    ),
  );
}

void _showText(ChatAttachment a, File file) {
  final ctx = _rootContext();
  if (ctx == null) return;
  showDialog<void>(
    context: ctx,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel)),
      title: Text(a.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 380,
        height: 360,
        child: FutureBuilder<String>(
          future: _readText(file),
          builder: (context, snap) => snap.hasData
              ? SelectableText(
                  snap.data!,
                  style: AppText.mono.copyWith(color: C.text),
                )
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Закрыть', style: TextStyle(color: C.accent)),
        ),
        OutlinedButton.icon(
          onPressed: () => _openExternal(a.path),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Открыть'),
        ),
      ],
    ),
  );
}

void _showFileInfo(ChatAttachment a, File file) {
  final ctx = _rootContext();
  if (ctx == null) return;
  final size = attachmentSize(a.size);
  showDialog<void>(
    context: ctx,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel)),
      title: Text('Файл', style: TextStyle(fontSize: 16, color: C.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.name, style: AppText.body.copyWith(color: C.text)),
          const SizedBox(height: 4),
          Text(
            [
              if (size.isNotEmpty) size,
              a.mime.isEmpty ? 'тип неизвестен' : a.mime,
            ].join(' · '),
            style: AppText.caption.copyWith(color: C.muted),
          ),
          const SizedBox(height: 12),
          Text(
            'Встроенный просмотр для этого формата недоступен. Можно открыть системным приложением.',
            style: AppText.caption.copyWith(color: C.muted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Закрыть', style: TextStyle(color: C.muted)),
        ),
        FilledButton.icon(
          onPressed: () => _openExternal(a.path),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Открыть'),
        ),
      ],
    ),
  );
}

bool _isText(ChatAttachment a) {
  final n = a.name.toLowerCase();
  return a.mime.startsWith('text/') ||
      a.mime == 'application/json' ||
      a.mime == 'text/csv' ||
      const [
        '.txt',
        '.md',
        '.csv',
        '.json',
        '.log',
        '.yaml',
        '.yml',
        '.xml',
        '.dart',
        '.py',
        '.js',
        '.ts',
        '.java',
        '.kt',
        '.c',
        '.cpp',
        '.go',
        '.rs',
        '.sh',
        '.sql'
      ].any(n.endsWith);
}

Future<String> _readText(File f) async {
  try {
    final bytes = await f.readAsBytes();
    final text = String.fromCharCodes(
      bytes.length > 200000 ? bytes.take(200000) : bytes,
    );
    return bytes.length > 200000 ? '$text\n…' : text;
  } catch (e) {
    return 'Не удалось прочитать файл: $e';
  }
}

Future<void> _openExternal(String path) async {
  try {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _toast(
          result.message.isEmpty ? 'Не удалось открыть файл.' : result.message);
    }
  } catch (e) {
    _toast('Не удалось открыть файл: $e');
  }
}

void _toast(String text) {
  final ctx = _rootContext();
  if (ctx == null) return;
  ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text)));
}

BuildContext? _rootContext() {
  final nav = rootNavigatorKey.currentContext;
  if (nav != null) return nav;
  return FocusManager.instance.primaryFocus?.context;
}
