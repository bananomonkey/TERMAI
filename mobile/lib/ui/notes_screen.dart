// notes_screen.dart — блокнот TERMAI: личные заметки с ИИ-помощью.
// Черновик письма на английском → «Проверить английский» → исправленный
// вариант с объяснениями. Плюс перевод, улучшение и продолжение текста.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai.dart';
import '../main.dart';
import '../models.dart';
import 'app_background.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Блокнот', style: AppText.screenTitle),
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => IconButton(
              tooltip: 'Экспорт заметок',
              onPressed: controller.notes.isEmpty
                  ? null
                  : () => _exportNotes(context),
              icon: const Icon(Icons.ios_share_outlined, size: 20),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.accent,
        foregroundColor: C.bg,
        onPressed: () => _open(context, null),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Новая заметка',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final notes = controller.notes;
            if (notes.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sticky_note_2_outlined,
                          size: 40, color: C.muted),
                      const SizedBox(height: 12),
                      Text('Пока пусто', style: AppText.title.copyWith(color: C.text)),
                      const SizedBox(height: 6),
                      Text(
                        'Черновики, конспекты, письмо на английском. '
                        'ИИ проверит, переведёт, улучшит и продолжит текст.',
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(color: C.muted),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: notes.length,
              itemBuilder: (context, i) {
                final n = notes[i];
                final preview = n.text.trim().isEmpty
                    ? '(пустая заметка)'
                    : n.text.trim().split('\n').first;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: appCard(
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              n.title.trim().isEmpty
                                  ? 'Без заголовка'
                                  : n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.title.copyWith(color: C.text),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: C.surface,
                                  title: Text('Удалить заметку?',
                                      style: TextStyle(
                                          color: C.text, fontSize: 16)),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text('Отмена',
                                            style:
                                                TextStyle(color: C.muted))),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text('Удалить',
                                            style:
                                                TextStyle(color: C.danger))),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await controller.deleteNote(n);
                              }
                            },
                            icon: Icon(Icons.delete_outline,
                                size: 19, color: C.muted),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: C.muted),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () => _open(context, n),
                            icon: Icon(Icons.edit_outlined,
                                size: 16, color: C.accent),
                            label: const Text('Открыть',
                                style: TextStyle(fontSize: 12.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// _exportNotes — плагин-free экспорт: весь блокнот одним текстом
  /// в диалоге с копированием (как экспорт прогресса).
  Future<void> _exportNotes(BuildContext context) async {
    final b = StringBuffer('Мои заметки TERMAI\n\n');
    for (final n in controller.notes) {
      b.write('=== ${n.title.isEmpty ? 'Без заголовка' : n.title} ===\n');
      b.write('${n.text.trim()}\n\n');
    }
    final text = b.toString().trim();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('Экспорт заметок (${controller.notes.length})',
            style: TextStyle(color: C.text, fontSize: 16)),
        content: SizedBox(
          width: 340,
          height: 320,
          child: SingleChildScrollView(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: C.text)),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Заметки скопированы')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Скопировать всё'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, Note? existing) async {
    final note = existing ??
        Note(id: DateTime.now().microsecondsSinceEpoch.toString());
    final isNew = existing == null;
    if (isNew) {
      controller.notes.add(note);
      await controller.saveNotes();
    }
    if (!context.mounted) return;
    await pushUnique(context, NoteScreen(noteId: note.id));
    // Возврат на список: перерисоваться + убрать пустую заметку.
    final n = controller.notes
        .where((x) => x.id == note.id)
        .toList();
    if (n.isNotEmpty && n.first.text.trim().isEmpty && n.first.title.isEmpty) {
      await controller.deleteNote(note);
    }
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    controller.notifyListeners();
  }
}

class NoteScreen extends StatefulWidget {
  final String noteId;
  const NoteScreen({super.key, required this.noteId});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final TextEditingController _title;
  late final TextEditingController _text;
  bool _busy = false;
  String _error = '';

  Note? get _note {
    for (final n in controller.notes) {
      if (n.id == widget.noteId) return n;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final n = _note;
    _title = TextEditingController(text: n?.title ?? '');
    _text = TextEditingController(text: n?.text ?? '');
  }

  @override
  void dispose() {
    _save();
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = _note;
    if (n == null) return;
    n.title = _title.text;
    n.text = _text.text;
    n.updatedAt = DateTime.now().toIso8601String();
    await controller.saveNotes();
  }

  Future<void> _run(String action) async {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Сначала напиши текст заметки.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final ai = controller.ai;
      if (ai == null || !ai.ready) {
        throw Exception('ИИ недоступен: настрой ключ в «Ещё» → Настройки.');
      }
      final result = await ai.noteAction(action, _title.text, _text.text);
      if (!mounted) return;
      await _showResult(result);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'ИИ не смог обработать текст: ${friendlyAiError(e)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResult(String result) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('Результат ИИ',
            style: TextStyle(color: C.text, fontSize: 16)),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Text(result,
                style: TextStyle(
                    fontSize: 13.5, height: 1.45, color: C.text)),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Скопировано')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Скопировать'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _text.text = _text.text.trim().isEmpty
                    ? result
                    : '${_text.text.trim()}\n\n$result';
              });
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.subdirectory_arrow_left, size: 16),
            label: const Text('Вставить ниже'),
          ),
          FilledButton.icon(
            onPressed: () {
              setState(() => _text.text = result);
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Заменить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Заметка', style: AppText.screenTitle),
      ),
      body: AppBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: 'Заголовок',
                  filled: true,
                  fillColor: C.card,
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: C.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: C.accent, width: 1.5)),
                ),
                onChanged: (_) => _save(),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: 'Пиши здесь…',
                    filled: true,
                    fillColor: C.card,
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: C.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: C.accent, width: 1.5)),
                  ),
                  onChanged: (_) => _save(),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_error,
                    style: TextStyle(fontSize: 12, color: C.danger)),
              ],
              const SizedBox(height: 10),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('ИИ работает…',
                        style: TextStyle(fontSize: 12.5)),
                  ]),
                )
              else
                // Одна ИИ-кнопка: блокнот — это блокнот. Остальные действия
                // доступны через ментора в чате.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _run('improve'),
                    icon: Icon(Icons.auto_fix_high, size: 18, color: C.accent),
                    label: const Text('Улучшить (ИИ)',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
