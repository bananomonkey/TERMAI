import 'package:flutter/material.dart';
import '../main.dart';
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

  @override
  void initState() {
    super.initState();
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
        child: PageView(
          controller: _page,
          onPageChanged: (i) => setState(() => _idx = i),
          children: [_intro(), _directionsStep(), _nameStep(), _setup()],
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
        36.0,
        24.0,
        24.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 88.0,
            height: 88.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: C.accent.withValues(alpha: 0.18),
                  blurRadius: 28.0,
                  spreadRadius: 2.0,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/icon/termai.png',
                width: 88.0,
                height: 88.0,
                cacheWidth: 176,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 14.0),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: C.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Text(
              'TERMAI',
              style: AppText.mono.copyWith(
                color: C.accent,
                fontSize: 15.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
              ),
            ),
          ),
          const SizedBox(height: 10.0),
          Text(
            'Учись делать.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32.0,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: C.text,
            ),
          ),
          const SizedBox(height: 8.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              'Направления, уроки и проверяемая практика — в одном месте',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: C.muted,
                fontSize: 14.0,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 24.0),
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
          const SizedBox(height: 20.0),
          SizedBox(
            width: double.infinity,
            height: 52.0,
            child: FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Выбрать направление',
                    style:
                        TextStyle(fontSize: 15.0, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(width: 8.0),
                  Icon(Icons.arrow_forward_rounded, size: 18.0),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8.0),
          Center(
            child: TextButton(
              onPressed: _starting ? null : () => _finish(saveKey: false),
              style: TextButton.styleFrom(
                foregroundColor: C.muted,
              ),
              child: const Text(
                'Пропустить',
                style: TextStyle(fontSize: 14.0),
              ),
            ),
          ),
          const SizedBox(height: 10.0),
          _dots(),
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
            onCreate: (title) async {
              final err = await controller.addCustomDirection(title);
              if (err.isEmpty) {
                setState(
                    () => _selected.add(controller.config.activeDirection));
              }
            },
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

@NowaGenerated()
class _IntroPoint extends StatelessWidget {
  final String number;

  final String title;

  final String text;

  @NowaGenerated({'loader': 'auto-constructor'})
  const _IntroPoint(
      {required this.number, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: C.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34.0,
            height: 34.0,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: C.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Text(
              number,
              style: AppText.mono.copyWith(
                color: C.accent,
                fontSize: 13.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w700,
                    color: C.text,
                  ),
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 4.0),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 13.0,
                      height: 1.35,
                      color: C.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
