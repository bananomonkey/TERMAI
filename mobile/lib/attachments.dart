// attachments.dart — выбор фото/документа и копирование в папку приложения.
// В чат сохраняются метаданные; сам файл не уходит в Firestore.
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'ui/theme.dart';

String _mimeFor(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  if (p.endsWith('.gif')) return 'image/gif';
  if (p.endsWith('.pdf')) return 'application/pdf';
  if (p.endsWith('.json')) return 'application/json';
  if (p.endsWith('.csv')) return 'text/csv';
  if (p.endsWith('.txt') || p.endsWith('.md') || p.endsWith('.log')) {
    return 'text/plain';
  }
  if (p.endsWith('.doc')) return 'application/msword';
  if (p.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  return 'application/octet-stream';
}

String _baseName(String path) {
  final i = path.lastIndexOf(io.Platform.pathSeparator);
  return i >= 0 ? path.substring(i + 1) : path;
}

Future<ChatAttachment> _copyToApp(
  String sourcePath, {
  required String type,
  String mime = '',
  String name = '',
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final folder = io.Directory('${dir.path}/attachments');
  if (!await folder.exists()) await folder.create(recursive: true);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final base = name.isNotEmpty ? name : _baseName(sourcePath);
  final safe = base.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final target = io.File('${folder.path}/${stamp}_$safe');
  await io.File(sourcePath).copy(target.path);
  return ChatAttachment(
    type: type,
    path: target.path,
    name: base,
    mime: mime.isNotEmpty ? mime : _mimeFor(sourcePath),
    size: await target.length(),
  );
}

Future<ChatAttachment?> pickImageAttachment({bool camera = false}) async {
  final picker = ImagePicker();
  final x = await picker.pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1800,
    maxHeight: 1800,
    imageQuality: 82,
  );
  if (x == null) return null;
  return _copyToApp(x.path, type: 'image', mime: x.mimeType ?? '');
}

Future<ChatAttachment?> pickFileAttachment() async {
  final file = await FilePicker.pickFile();
  final path = file?.path;
  if (path == null || path.isEmpty) return null;
  return _copyToApp(path, type: 'file', name: file!.name);
}

/// showAttachmentSheet — нижний лист с выбором источника вложения.
Future<void> showAttachmentSheet(
    BuildContext context, void Function(ChatAttachment) onPicked) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(Icons.photo_library_outlined, color: C.accent),
          title: const Text('Фото из галереи'),
          onTap: () => Navigator.pop(ctx, 'gallery'),
        ),
        ListTile(
          leading: Icon(Icons.photo_camera_outlined, color: C.accent),
          title: const Text('Сделать фото'),
          onTap: () => Navigator.pop(ctx, 'camera'),
        ),
        ListTile(
          leading: Icon(Icons.attach_file, color: C.accent),
          title: const Text('Документ или файл'),
          onTap: () => Navigator.pop(ctx, 'file'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (action == null) return;
  try {
    ChatAttachment? a;
    if (action == 'gallery') a = await pickImageAttachment();
    if (action == 'camera') a = await pickImageAttachment(camera: true);
    if (action == 'file') a = await pickFileAttachment();
    if (a != null) onPicked(a);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось прикрепить: $e')));
    }
  }
}
