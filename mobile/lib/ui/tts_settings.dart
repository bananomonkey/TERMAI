// tts_settings.dart — настройки системного озвучивания TERMAI.
// Голос Android ничего не скачивает; экран показывает реальные движки и
// русские голоса, которые сообщает система. Если их нет — честно говорит.
import 'package:flutter/material.dart';

import '../local_tts.dart';
import '../main.dart';
import '../tts_service.dart';
import 'app_background.dart';
import 'design_system.dart';
import 'local_tts_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class TtsSettingsScreen extends StatefulWidget {
  const TtsSettingsScreen({super.key});

  @override
  State<TtsSettingsScreen> createState() => _TtsSettingsScreenState();
}

class _TtsSettingsScreenState extends State<TtsSettingsScreen> {
  List<TtsEngineOption> _engines = const [];
  List<TtsVoiceOption> _voices = const [];
  bool _loading = true;
  bool _russianAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    await TtsService.instance.init();
    final engines = await TtsService.instance.engines();
    final voices = await TtsService.instance.russianVoices();
    final ru = await TtsService.instance.isRussianAvailable();
    if (!mounted) return;
    setState(() {
      _engines = engines;
      _voices = voices;
      _russianAvailable = ru;
      _loading = false;
    });
  }

  List<String> get _variants {
    final set = <String>{'ru-RU'};
    for (final v in _voices) {
      if (v.locale.isNotEmpty) set.add(v.locale);
    }
    return set.toList()..sort();
  }

  Future<void> _save() async {
    await controller.saveTtsConfig();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Озвучивание', style: AppText.screenTitle),
      ),
      body: AppBackdrop(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final c = controller.config;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                appSectionTitle('Системный голос'),
                appCard(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Озвучивать ответы',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: C.text)),
                          subtitle: Text(
                            'Android произносит только готовые ответы: без '
                            'кода, Markdown и служебных команд.',
                            style: TextStyle(fontSize: 11.5, color: C.muted),
                          ),
                          value: c.ttsEnabled,
                          activeThumbColor: C.accent,
                          onChanged: (v) async {
                            await controller.setTtsEnabled(v);
                            if (v) await _load();
                          },
                        ),
                      ),
                      if (c.ttsEnabled) ...[
                        if (_loading)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(children: [
                              SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: C.accent)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('Проверяю голоса Android…',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12, color: C.muted)),
                              ),
                            ]),
                          )
                        else if (!_russianAvailable)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: C.warn.withAlpha(24),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: C.warn.withAlpha(95)),
                            ),
                            child: Text(
                              'Русский голос не подтверждён системой. '
                              'Установи русский язык в настройках Android '
                              '(Настройки → Система → Языки → Синтез речи).',
                              style: TextStyle(
                                  fontSize: 11.5, height: 1.35, color: C.text),
                            ),
                          ),
                        const SizedBox(height: 8),
                        _label('Движок'),
                        DropdownButtonFormField<String>(
                          initialValue: _engineValue(c.ttsEngine),
                          isExpanded: true,
                          decoration: const InputDecoration(
                              hintText: 'Системный по умолчанию'),
                          items: [
                            const DropdownMenuItem(
                                value: '',
                                child: Text('Системный по умолчанию')),
                            for (final e in _engines)
                              DropdownMenuItem(
                                  value: e.name,
                                  child: Text(e.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) async {
                            c.ttsEngine = v ?? '';
                            await _save();
                          },
                        ),
                        const SizedBox(height: 12),
                        _label('Русский голос'),
                        if (_loading)
                          Text('Загружаю список голосов…',
                              style: TextStyle(fontSize: 11.5, color: C.muted))
                        else if (_voices.isEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Система не вернула ни одного русского голоса. '
                                'Это не ошибка приложения: установи голосовой '
                                'пакет Android.',
                                style:
                                    TextStyle(fontSize: 11.5, color: C.muted),
                              ),
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Проверить снова'),
                              ),
                            ],
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _voiceValue(c.ttsVoice),
                            isExpanded: true,
                            decoration: const InputDecoration(
                                hintText: 'Автоматически'),
                            items: [
                              const DropdownMenuItem(
                                  value: '', child: Text('Автоматически')),
                              for (final v in _voices)
                                DropdownMenuItem(
                                    value: v.name,
                                    child: Text(v.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (name) async {
                              c.ttsVoice = name ?? '';
                              final found = _voices
                                  .where((v) => v.name == c.ttsVoice)
                                  .toList();
                              if (found.isNotEmpty) {
                                c.ttsLocale = found.first.locale;
                                c.ttsVariant = found.first.locale;
                              }
                              await _save();
                            },
                          ),
                        const SizedBox(height: 12),
                        _label('Вариант произношения'),
                        DropdownButtonFormField<String>(
                          initialValue: _variantValue(c.ttsVariant),
                          isExpanded: true,
                          items: [
                            for (final v in _variants)
                              DropdownMenuItem(value: v, child: Text(v)),
                          ],
                          onChanged: (v) async {
                            c.ttsVariant = v ?? 'ru-RU';
                            c.ttsLocale = c.ttsVariant;
                            await _save();
                          },
                        ),
                        const SizedBox(height: 12),
                        Material(
                          color: Colors.transparent,
                          child: SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Озвучивать ответы Термая',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: C.text)),
                            value: c.ttsAutoChat,
                            activeThumbColor: C.accent,
                            onChanged: (v) async {
                              c.ttsAutoChat = v;
                              await _save();
                            },
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Озвучивать выполнение задачи',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: C.text)),
                            value: c.ttsAutoCompletion,
                            activeThumbColor: C.accent,
                            onChanged: (v) async {
                              c.ttsAutoCompletion = v;
                              await _save();
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        _label('Скорость · ${(c.ttsRate * 100).round()}%'),
                        Slider(
                          value: c.ttsRate,
                          min: 0.2,
                          max: 1.0,
                          divisions: 16,
                          label: '${(c.ttsRate * 100).round()}%',
                          onChanged: (v) => setState(() => c.ttsRate = v),
                          onChangeEnd: (_) => _save(),
                        ),
                        _label('Тон · ${(c.ttsPitch * 100).round()}%'),
                        Slider(
                          value: c.ttsPitch,
                          min: 0.5,
                          max: 1.5,
                          divisions: 20,
                          label: '${(c.ttsPitch * 100).round()}%',
                          onChanged: (v) => setState(() => c.ttsPitch = v),
                          onChangeEnd: (_) => _save(),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: () => TtsService.instance.sample(c),
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 19),
                              label: const Text('Прослушать'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => TtsService.instance.stop(),
                              child: const Text('Стоп'),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                appSectionTitle('Локальные голоса'),
                appCard(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Использовать Piper',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: C.text)),
                          subtitle: Text(
                            c.ttsLocalModelId.isEmpty
                                ? 'Сначала выбери и скачай голос в каталоге'
                                : '${localTtsModelById(c.ttsLocalModelId)?.title ?? c.ttsLocalModelId} · работает офлайн',
                            style: TextStyle(fontSize: 11.5, color: C.muted),
                          ),
                          value: c.ttsUseLocal,
                          activeThumbColor: C.accent,
                          onChanged: c.ttsLocalModelId.isEmpty
                              ? null
                              : (v) async {
                                  c.ttsUseLocal = v;
                                  await _save();
                                },
                        ),
                      ),
                      Divider(color: C.border, height: 1),
                      appRow(
                        icon: Icons.record_voice_over_outlined,
                        title: 'Каталог локальных голосов',
                        subtitle:
                            'Piper · загрузка только по кнопке · лицензии',
                        onTap: () async {
                          await Navigator.of(context)
                              .push(pageRoute(const LocalTtsScreen()));
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                appCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 17, color: C.muted),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Системный голос Android не занимает место и не '
                          'скачивается. Piper-голоса лежат локально, работают '
                          'офлайн и загружаются только вручную из каталога. '
                          'Silero с неясной лицензией в приложение не входит.',
                          style: AppText.caption.copyWith(color: C.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _engineValue(String v) => _engines.any((e) => e.name == v) ? v : '';

  String _voiceValue(String v) => _voices.any((e) => e.name == v) ? v : '';

  String _variantValue(String v) => _variants.contains(v) ? v : 'ru-RU';

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: AppText.caption.copyWith(color: C.muted)),
      );
}
