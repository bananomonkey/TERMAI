import 'package:flutter/material.dart';
import '../main.dart';
import '../shared_ai.dart';
import 'design_system.dart';
import 'direction_picker.dart';
import 'help.dart';
import 'theme.dart';
import 'widgets.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

@NowaGenerated()
class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();

  final _key = TextEditingController(text: controller.config.apiKey);

  final _name = TextEditingController(text: controller.config.userName);

  final _selected = <String>{'devops'};

  int _idx = 0;

  bool _starting = false;

  bool _showKey = false;

  bool _useShared = true;

  @override
  void initState() {
    super.initState();
    _useShared = controller.config.sharedAiEnabled;
  }

  @override
  void dispose() {
    _page.dispose();
    _key.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish({bool saveKey = true}) async {
    if (_starting) {
      return;
    }
    setState(() => _starting = true);
    if (saveKey) {
      controller.config.apiKey = _key.text.trim();
    }
    controller.config.userName = _name.text.trim();
    controller.config.onboarded = true;
    final shared = SharedAiService.instance;
    if (_useShared && controller.sync.signedIn) {
      controller.config.sharedAiEnabled = true;
      controller.config.sharedAiConsentVersion =
          shared.noticeVersion < 1 ? 1 : shared.noticeVersion;
    } else {
      controller.config.sharedAiEnabled = false;
      controller.config.sharedAiConsentVersion = -1;
    }
    if (_selected.isEmpty) {
      _selected.add('devops');
    }
    try {
      await controller.setDirections(_selected, active: _selected.first);
      await controller.scheduleNotifications();
    } catch (_) {
      try {
        await controller.saveConfig();
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(pageRoute(const HomeScreen()));
  }

  Future<void> _google() async {
    if (controller.sync.busy) {
      return;
    }
    final msg = await controller.signInSync();
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        msg.isEmpty ? 'Вход через Google выполнен' : msg,
      ),
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
        child: Stack(
          children: [
            PageView(
              controller: _page,
              onPageChanged: (i) => setState(() => _idx = i),
              children: [_intro(), _directionsStep(), _nameStep(), _setup()],
            ),
            Positioned(
              top: 4.0,
              right: 6.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .push(pageRoute(const HelpScreen())),
                    child: Text(
                      'Инструкция',
                      style: TextStyle(color: C.muted, fontSize: 12.5),
                    ),
                  ),
                  TextButton(
                    onPressed: _starting ? null : () => _finish(saveKey: false),
                    child: Text(
                      'Пропустить',
                      style: TextStyle(color: C.accent, fontSize: 12.5),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3.0),
            width: _idx == i ? 22.0 : 7.0,
            height: 7.0,
            decoration: BoxDecoration(
                color: _idx == i ? C.accent : C.muted.withAlpha(70),
                borderRadius: BorderRadius.circular(4.0)),
          )
      ],
    );
  }

  Widget _intro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        24.0,
        48.0,
        24.0,
        24.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ClipOval(
              child: Image.asset(
                'assets/icon/termai.png',
                width: 92.0,
                height: 92.0,
                cacheWidth: 184,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(
            height: 17.0,
          ),
          Center(
            child: Text(
              'TERMAI',
              textAlign: TextAlign.center,
              style: AppText.section.copyWith(
                color: C.accent,
                letterSpacing: 2.4,
                fontSize: 11.0,
              ),
            ),
          ),
          const SizedBox(
            height: 7.0,
          ),
          Center(
            child: Text(
              'Учись делать',
              style: TextStyle(
                fontSize: 31.0,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                color: C.text,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(
            height: 8.0,
          ),
          Text(
            'Направления, уроки и проверяемая практика — в одном месте.',
            style: AppText.body.copyWith(color: C.muted),
          ),
          const SizedBox(
            height: 28.0,
          ),
          const _IntroPoint(
            number: '01',
            title: 'Выбери направление',
            text:
                'DevOps, английский или Go. Позже можно добавить ещё — прогресс не смешается.',
          ),
          const _IntroPoint(
            number: '02',
            title: 'Иди по маршруту',
            text:
                'Короткие уроки, тесты, терминал и понятная следующая задача.',
          ),
          const _IntroPoint(
            number: '03',
            title: 'Спроси Термая',
            text:
                'Наставник разбирает ошибки, объясняет команды и возвращает к практике.',
          ),
          const SizedBox(
            height: 22.0,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _next,
              child: const Text(
                'Выбрать направление',
              ),
            ),
          ),
          const SizedBox(
            height: 10.0,
          ),
          Center(
            child: _dots(),
          )
        ],
      ),
    );
  }

  Widget _directionsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        24.0,
        48.0,
        24.0,
        24.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          caption('Шаг 1 из 3 · можно несколько', color: C.accent),
          const SizedBox(
            height: 10.0,
          ),
          Text(
            'Что учим?',
            style: TextStyle(
              fontSize: 26.0,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: C.text,
            ),
          ),
          const SizedBox(
            height: 7.0,
          ),
          Text(
            'У каждого направления свой маршрут, XP и статистика. DevOps + English + Go — нормальный выбор.',
            style: AppText.body.copyWith(color: C.muted),
          ),
          const SizedBox(
            height: 4.0,
          ),
          DirectionOptionList(
            selected: _selected,
            onToggle: (id) => setState(() {
              if (_selected.contains(id)) {
                _selected.remove(id);
              } else {
                _selected.add(id);
              }
            }),
            dense: true,
          ),
          const SizedBox(
            height: 20.0,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected.isEmpty ? null : _next,
              child: Text(
                _selected.isEmpty ? 'Выбери хотя бы одно' : 'Далее',
              ),
            ),
          ),
          const SizedBox(
            height: 10.0,
          ),
          Center(
            child: _dots(),
          )
        ],
      ),
    );
  }

  Widget _nameStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        24.0,
        52.0,
        24.0,
        24.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          caption('Шаг 2 из 3', color: C.accent),
          const SizedBox(
            height: 10.0,
          ),
          Text(
            'Как тебя зовут?',
            style: TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.w900,
              color: C.text,
            ),
          ),
          const SizedBox(
            height: 8.0,
          ),
          Text(
            'Термай будет обращаться по имени в чате и напоминаниях. Это необязательно — можно пропустить и изменить позже в настройках.',
            style: TextStyle(
              fontSize: 14.0,
              height: 1.45,
              color: C.muted,
            ),
          ),
          const SizedBox(
            height: 22.0,
          ),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'Например, Влад'),
            onSubmitted: (_) => _next(),
          ),
          const SizedBox(
            height: 26.0,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(minimumSize: const Size(0.0, 52.0)),
              child: const Text(
                'Далее',
              ),
            ),
          ),
          const SizedBox(
            height: 8.0,
          ),
          Center(
            child: TextButton(
              onPressed: _next,
              child: Text(
                'Пропустить',
                style: TextStyle(color: C.muted),
              ),
            ),
          ),
          const SizedBox(
            height: 10.0,
          ),
          Center(
            child: _dots(),
          )
        ],
      ),
    );
  }

  Widget _setup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        24.0,
        52.0,
        24.0,
        24.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          caption('Шаг 3 из 3', color: C.accent),
          const SizedBox(
            height: 10.0,
          ),
          Text(
            'Подключи ИИ',
            style: TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.w900,
              color: C.text,
            ),
          ),
          const SizedBox(
            height: 8.0,
          ),
          Text(
            'Вставь API-ключ провайдера — например, DeepSeek. Ключ нужен для ментора, проверки задач и генерации курсов. Он хранится на устройстве и, если включена синхронизация, в твоём Google-облаке.',
            style: TextStyle(
              fontSize: 14.0,
              height: 1.45,
              color: C.muted,
            ),
          ),
          TextField(
            controller: _key,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
                hintText: 'sk-…',
                suffixIcon: IconButton(
                  tooltip: _showKey ? 'Скрыть ключ' : 'Показать ключ',
                  icon: Icon(
                    _showKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20.0,
                    color: C.muted,
                  ),
                  onPressed: () => setState(() => _showKey = !_showKey),
                )),
          ),
          const SizedBox(
            height: 18.0,
          ),
          ListenableBuilder(
            listenable: controller.sync,
            builder: (context, _) {
              final s = controller.sync;
              if (s.signedIn) {
                return Container(
                  padding: const EdgeInsets.all(13.0),
                  decoration: BoxDecoration(
                      color: C.card, borderRadius: BorderRadius.circular(14.0)),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: C.good,
                        size: 20.0,
                      ),
                      const SizedBox(
                        width: 9.0,
                      ),
                      Expanded(
                        child: Text(
                          'Google: ${s.email}',
                          style: TextStyle(fontSize: 13.0, color: C.text),
                        ),
                      )
                    ],
                  ),
                );
              }
              if (s.configured && s.supported) {
                return SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: s.busy ? null : _google,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0.0, 50.0)),
                    icon: s.busy
                        ? SizedBox(
                            width: 17.0,
                            height: 17.0,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              color: C.accent,
                            ),
                          )
                        : const Icon(
                            Icons.login,
                            size: 18.0,
                          ),
                    label: const Text(
                      'Войти через Google',
                    ),
                  ),
                );
              }
              return Text(
                'Google-синхронизация не настроена — можно пропустить и включить позже в настройках.',
                style: TextStyle(
                  fontSize: 12.0,
                  height: 1.4,
                  color: C.muted,
                ),
              );
            },
          ),
          const SizedBox(
            height: 8.0,
          ),
          Text(
            'Вход в Google необязателен: прогресс и чаты будут доступны на новом устройстве.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: C.muted,
            ),
          ),
          const SizedBox(
            height: 28.0,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _starting ? null : () => _finish(),
              style: FilledButton.styleFrom(minimumSize: const Size(0.0, 52.0)),
              child: _starting
                  ? const SizedBox(
                      width: 20.0,
                      height: 20.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                      ),
                    )
                  : const Text(
                      'Начать',
                    ),
            ),
          ),
          const SizedBox(
            height: 6.0,
          ),
          Center(
            child: TextButton(
              onPressed: _starting ? null : () => _finish(saveKey: false),
              child: Text(
                'Позже',
                style: TextStyle(color: C.muted),
              ),
            ),
          ),
          const SizedBox(
            height: 4.0,
          ),
          Center(
            child: _dots(),
          )
        ],
      ),
    );
  }
}

class _IntroPoint extends StatelessWidget {
  final String number, title, text;
  const _IntroPoint({
    required this.number,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              number,
              style: AppText.mono.copyWith(
                color: C.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.title.copyWith(color: C.text),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: AppText.caption.copyWith(color: C.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
