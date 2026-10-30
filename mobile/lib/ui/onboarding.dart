// onboarding.dart — первое знакомство: инструкция и подключение ИИ/аккаунта.
import 'package:flutter/material.dart';

import '../main.dart';
import 'help.dart';
import 'theme.dart';
import 'widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  final _key = TextEditingController(text: controller.config.apiKey);
  final _name = TextEditingController(text: controller.config.userName);
  int _idx = 0;
  bool _starting = false;

  @override
  void dispose() {
    _page.dispose();
    _key.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish({bool saveKey = true}) async {
    if (_starting) return;
    setState(() => _starting = true);
    if (saveKey) controller.config.apiKey = _key.text.trim();
    controller.config.userName = _name.text.trim();
    controller.config.onboarded = true;
    // даже если запись файла не удалась — пользователь не должен застрять
    try {
      await controller.saveConfig();
      await controller.scheduleNotifications();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(pageRoute(const HomeScreen()));
  }

  Future<void> _google() async {
    if (controller.sync.busy) return;
    final msg = await controller.signInSync();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg.isEmpty ? 'Вход через Google выполнен' : msg),
    ));
  }

  void _next() {
    _page.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Stack(children: [
          PageView(
            controller: _page,
            onPageChanged: (i) => setState(() => _idx = i),
            children: [_intro(), _nameStep(), _setup()],
          ),
          // Кнопки поверх PageView: раньше «Пропустить» лежала ПОД ним
          // и не получала нажатия.
          Positioned(
            top: 4,
            right: 6,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).push(pageRoute(const HelpScreen())),
                child: Text('Инструкция',
                    style: TextStyle(color: C.muted, fontSize: 12.5)),
              ),
              TextButton(
                onPressed: _starting ? null : () => _finish(saveKey: false),
                child: Text('Пропустить',
                    style: TextStyle(color: C.accent, fontSize: 12.5)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _idx == i ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: _idx == i ? C.accent : C.muted.withAlpha(70),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      );

  Widget _intro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 52, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/icon/termai.png',
                width: 108,
                height: 108,
                cacheWidth: 216,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'тренажёр навыков с ИИ-наставником',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: C.text,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text('Учись делать, а не смотреть',
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: 8),
          Text(
            'Короткие уроки, практика и наставник, который объясняет ошибки. '
            'Курсы можно собрать под любую цель: языки, Linux, Docker, профессию или школьный предмет.',
            style: TextStyle(fontSize: 14, height: 1.45, color: C.muted),
          ),
          const SizedBox(height: 22),
          _FeatureRow(
            icon: Icons.route_outlined,
            title: 'Курсы-тропинки',
            text: 'От базы к цели, с прогрессом и достижениями.',
          ),
          _FeatureRow(
            icon: Icons.psychology_outlined,
            title: 'ИИ-наставник',
            text: 'Разбирает ошибки, задаёт вопросы и подсказывает.',
          ),
          _FeatureRow(
            icon: Icons.terminal,
            title: 'Терминал или теория',
            text: 'Практика в песочнице — или тесты по любому предмету.',
          ),
          _FeatureRow(
            icon: Icons.cloud_sync_outlined,
            title: 'Прогресс с собой',
            text: 'Локально или в Google-аккаунте между устройствами.',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              child: const Text('Далее'),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: _dots()),
        ],
      ),
    );
  }

  Widget _nameStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 52, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          caption('Шаг 2 из 3', color: C.accent),
          const SizedBox(height: 10),
          Text('Как тебя зовут?',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900, color: C.text)),
          const SizedBox(height: 8),
          Text(
            'Термай будет обращаться по имени в чате и напоминаниях. '
            'Это необязательно — можно пропустить и изменить позже в настройках.',
            style: TextStyle(fontSize: 14, height: 1.45, color: C.muted),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'Например, Влад'),
            onSubmitted: (_) => _next(),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              child: const Text('Далее'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _next,
              child: Text('Пропустить', style: TextStyle(color: C.muted)),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: _dots()),
        ],
      ),
    );
  }

  Widget _setup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 52, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          caption('Шаг 3 из 3', color: C.accent),
          const SizedBox(height: 10),
          Text('Подключи ИИ',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900, color: C.text)),
          const SizedBox(height: 8),
          Text(
            'Вставь API-ключ провайдера — например, DeepSeek. Ключ нужен для ментора, '
            'проверки задач и генерации курсов. Он хранится только на этом устройстве.',
            style: TextStyle(fontSize: 14, height: 1.45, color: C.muted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _key,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'sk-…'),
          ),
          const SizedBox(height: 18),
          ListenableBuilder(
            listenable: controller.sync,
            builder: (context, _) {
              final s = controller.sync;
              if (s.signedIn) {
                return Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(Icons.check_circle_rounded, color: C.good, size: 20),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text('Google: ${s.email}',
                          style: TextStyle(fontSize: 13, color: C.text)),
                    ),
                  ]),
                );
              }
              if (s.configured && s.supported) {
                return SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: s.busy ? null : _google,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50)),
                    icon: s.busy
                        ? SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: C.accent))
                        : const Icon(Icons.login, size: 18),
                    label: const Text('Войти через Google'),
                  ),
                );
              }
              return Text(
                'Google-синхронизация не настроена — можно пропустить и включить позже в настройках.',
                style: TextStyle(fontSize: 12, height: 1.4, color: C.muted),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
              'Вход в Google необязателен: прогресс и чаты будут доступны на новом устройстве.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: C.muted)),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _starting ? null : () => _finish(),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              child: _starting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Начать'),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _starting ? null : () => _finish(saveKey: false),
              child: Text('Позже', style: TextStyle(color: C.muted)),
            ),
          ),
          const SizedBox(height: 4),
          Center(child: _dots()),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const _FeatureRow(
      {required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: C.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: C.text)),
                const SizedBox(height: 2),
                Text(text,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.35, color: C.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
