// main.dart — TERMAI mobile (Flutter). Сплэш → плашка ключа → карта курсов.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

import 'store.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'ui/home.dart';
import 'ui/physics_home.dart';
import 'ui/chat.dart';
import 'ui/more.dart';

final AppController controller = AppController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const TermaiApp());
}

/// мост для store.dart: грузим встроенные курсы из бандла
Future<String> _loadCoursesAsset() async => rootBundle.loadString('assets/courses.json');

class TermaiApp extends StatelessWidget {
  const TermaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // слушаем контроллер: смена темы в настройках перекрашивает всё приложение
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        key: ValueKey('theme-${C.p.id}'),
        title: 'TERMAI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const BootScreen(),
      ),
    );
  }
}

/// BootScreen — сплэш: логотип, инициализация, затем карта курсов.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});
  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200), value: 0)
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    loadCoursesAsset = _loadCoursesAsset;
    await controller.init();
    C.p = presetById(controller.config.theme);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(pageRoute(const HomeScreen()));
    if (controller.config.apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showOnboardingSheet(context);
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.04).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: C.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: C.accent, width: 2),
                ),
                child: Center(
                  child: Text('>_', style: TextStyle(color: C.accent, fontSize: 34, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text('TERMAI',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4, color: C.text)),
            const SizedBox(height: 8),
            Text('тренажёр с ИИ-наставником', style: TextStyle(color: C.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// showOnboardingSheet — закруглённая нижняя плашка с вводом ключа.
void showOnboardingSheet(BuildContext context) {
  final keyCtrl = TextEditingController();
  showModalBottomSheet(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 4, height: 18, decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text('ДОБРО ПОЖАЛОВАТЬ В TERMAI',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: C.accent)),
          ]),
          const SizedBox(height: 14),
          const Text('Вставь свой DeepSeek API-ключ — он нужен ИИ-симулятору и ментору.',
              style: TextStyle(fontSize: 15, height: 1.35)),
          const SizedBox(height: 16),
          TextField(
            controller: keyCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'sk-…'),
          ),
          const SizedBox(height: 8),
          Text('Ключ хранится только на этом устройстве.',
              style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () async {
              final k = keyCtrl.text.trim();
              if (k.isEmpty) return;
              controller.config.apiKey = k;
              await controller.saveConfig();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить и начать'),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Позже', style: TextStyle(color: C.muted)),
            ),
          ),
        ],
      ),
    ),
  );
}

/// HomeScreen — апбар (логотип, XP, «Ещё») + карта курсов.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text('TERMAI',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3, color: C.accent, fontSize: 19)),
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: C.border),
                  ),
                  child: Text('ур.${controller.prog.level} · ${controller.prog.xp} XP',
                      style: TextStyle(fontSize: 11, color: C.muted)),
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.more_horiz), onPressed: () => showMoreSheet(context)),
          const SizedBox(width: 4),
        ],
      ),
      body: const PhysicsCoursesView(),
    );
  }
}

/// вспомогательное: диалог однострочного ввода («Задача от ИИ», «Курс от ИИ»)
Future<String?> askText(BuildContext context, String title, String hint, {String? initial}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size(40, 42)),
          child: const Text('Создать'),
        ),
      ],
    ),
  );
}

/// маленькая утилита: документы-путь для настроек импорта/экспорта не нужен тут,
/// но файл прогресса нам пригодится для статистики
Future<String> dataDirPath() async {
  final base = await getApplicationDocumentsDirectory();
  return base.path;
}

String prettyJson(Object? o) => const JsonEncoder.withIndent('  ').convert(o);
