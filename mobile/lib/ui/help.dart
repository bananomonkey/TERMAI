// help.dart — подробная справка по функциям TERMAI.
import 'package:flutter/material.dart';

import '../models.dart';
import 'app_background.dart';
import 'chat.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart';

class _HelpSection {
  final IconData icon;
  final String title;
  final String text;
  const _HelpSection(this.icon, this.title, this.text);
}

const _sections = <_HelpSection>[
  _HelpSection(
    Icons.rocket_launch_outlined,
    'Быстрый старт',
    '1. Выбери одно или несколько направлений обучения.\n'
        '2. Открой курс и первую незавершённую задачу.\n'
        '3. Прочитай справку урока, выполни практику или тест и нажми проверку.\n'
        '4. Если застрял — открой чат с Термаем: он видит текущий курс, задачу и последние команды.\n\n'
        'Прогресс, XP, серия, закладки и чаты сохраняются автоматически. Начать проще с одного курса и одного урока в день.',
  ),
  _HelpSection(
    Icons.route_outlined,
    'Направления, курсы и уроки',
    'На главной можно переключать направления, например DevOps, Go и английский. У каждого направления свой список курсов, порядок, XP и статистика. «+» добавляет направление; удаление направления из панели не стирает учебные данные.\n\n'
        'Тап по курсу открывает уроки. Меню курса позволяет переименовать, архивировать или удалить его. В уроке доступны теория, задача, терминал (для практических курсов) и решение. Слайды перелистываются, а последняя открытая задача запоминается.',
  ),
  _HelpSection(
    Icons.terminal,
    'Учебный терминал',
    'Команда редактируется в нижнем поле и одновременно видна после приглашения терминала. Она выполняется только после Enter или кнопки запуска. После отправки поле очищается.\n\n'
        'Каждая задача имеет собственную песочницу, вывод и историю команд: при переключении они не смешиваются. Поддерживаются учебные Linux-, Docker- и kubectl-команды. Быстрые команды выполняются локальным симулятором, сложные — ИИ. Кнопка отмены возвращает состояние до последней команды, очистка скрывает только вывод текущего терминала.',
  ),
  _HelpSection(
    Icons.psychology_outlined,
    'Термай и чаты',
    'Есть общий чат и отдельные беседы по задачам. В задаче Термай получает её условие, состояние песочницы и последние команды; в общем чате — контекст приложения. Чаты можно создавать, переименовывать, удалять и продолжать позже.\n\n'
        'Термай умеет объяснять материал, искать ошибку, создавать курс или задачу, открывать экраны и вставлять команду в терминал. Вложения добавляются кнопкой скрепки. Не отправляй пароли и другие секреты в текст запроса.',
  ),
  _HelpSection(
    Icons.hub_outlined,
    'ИИ-провайдеры и модели',
    'В «Настройки → ИИ-провайдер» выбираются DeepSeek, OpenAI, Gemini, Qwen, OpenRouter, Groq, Mistral, GigaChat, YandexGPT, Ollama или OpenAI-совместимый сервер. Для каждого провайдера отдельно запоминаются его ключ, модель и Base URL. Переключение провайдера не должно заменять настройки другого.\n\n'
        'Общий бесплатный доступ TERMAI работает только после входа через Google и явного согласия. Ключ Token Harbor находится только на серверном шлюзе и не входит в APK. После общей даты окончания приложение возвращается к личному подключению без автоматического платного переключения.',
  ),
  _HelpSection(
    Icons.swap_horiz_outlined,
    'Резервные модели',
    'Резерв — это личное подключение пользователя, которое пробуется, если основное недоступно. Порядок можно менять, подключение — тестировать или сделать основным. Ключи не показываются в карточках списка и никогда не берутся из серверного секрета TERMAI.\n\n'
        'Ошибка одной модели временно понижает её приоритет. Это не удаляет ключ и не меняет модель. Добавляй резерв только вручную и используй ключ своего аккаунта.',
  ),
  _HelpSection(
    Icons.fact_check_outlined,
    'Проверка, решение и прогресс',
    'Проверка практики анализирует реальное состояние учебной песочницы, а не только текст команды. Тестовые уроки завершаются после правильного ответа. Решение можно открыть отдельно; просмотр решения учитывается приложением.\n\n'
        'За завершение начисляются XP, растёт серия и открываются достижения. Закладки попадают в повторение. В конце курса доступны повторение материала и режим собеседования. Статистика показывает активность и прогресс по направлениям.',
  ),
  _HelpSection(
    Icons.record_voice_over_outlined,
    'Озвучивание и локальные голоса',
    'В «Настройки → Голос Термая» включается системная русская озвучка, скорость, тон и автоматическое чтение сообщений. Системный голос предоставляет Android.\n\n'
        'Piper-голоса скачиваются только по явному нажатию и после установки работают без сети. Установка считается успешной лишь после проверки модели, tokens.txt, данных espeak-ng и настоящей генерации тестового WAV. Модель можно выбрать, проверить фразой и удалить.',
  ),
  _HelpSection(
    Icons.image_outlined,
    'Файлы, фото и SVG-иллюстрации',
    'В чат можно прикрепить фото, документ или текстовый файл. Возможность понять изображение зависит от выбранной модели. Большие и неподдерживаемые вложения возвращают понятную ошибку провайдера.\n\n'
        'По просьбе нарисовать изображение TERMAI может запросить у текстовой модели безопасный SVG. SVG очищается от скриптов, внешних ссылок и встроенных ресурсов, затем показывается прямо в чате. Его можно увеличить и сохранить. Не каждая модель хорошо создаёт SVG — при отказе можно выбрать другую.',
  ),
  _HelpSection(
    Icons.cloud_sync_outlined,
    'Google-вход, синхронизация и ключи',
    'Google-вход нужен для облачного прогресса и общего ИИ. Синхронизация переносит прогресс, чаты и несекретные настройки между твоими устройствами. Локально API-ключи хранятся в защищённом хранилище, отдельно от termai.json.\n\n'
        'Передавать личные ключи в Firebase можно только отдельным тумблером. Если он выключен, облако не получает ключи. Серверный Token Harbor-ключ никогда не приходит в приложение, резервные модели не заполняются серверными ключами.',
  ),
  _HelpSection(
    Icons.tune_outlined,
    'Настройки и оформление',
    'В настройках меняются имя, направления, уведомления, голос, ИИ-провайдер, общий доступ, синхронизация, темы и яркость кнопок. Фон приложения выбирается в меню «Ещё»: можно настроить фото, размытие и затемнение.\n\n'
        'Напоминания работают отдельно от мотивационных сообщений Термая. Проверочная кнопка показывает, разрешены ли уведомления Android. Настройки применяются ко всему приложению и не должны сбрасывать прогресс.',
  ),
  _HelpSection(
    Icons.inventory_2_outlined,
    'Архив, импорт, диагностика и обновления',
    'Архив скрывает курс с главной, сохраняя задачи и прогресс; курс можно вернуть. Экспорт прогресса создаёт JSON-копию, импорт восстанавливает пользовательские учебные данные. Не публикуй экспорт, если он содержит личную переписку.\n\n'
        'Команда «/диагностика» в чате проверяет ИИ, общий доступ, загрузки, синхронизацию и уведомления без отправки секретов модели. Обновления проверяются через GitHub Releases; автоматическую проверку и уведомления можно отключить.',
  ),
];

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  void _ask(BuildContext context, _HelpSection section) {
    Navigator.of(context).push(pageRoute(ChatScreen(
      scope: ChatScope.general,
      initialDraft: 'Объясни подробнее или помоги мне с этим разделом.',
      contextHint: 'Раздел «${section.title}».\n${section.text}',
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Справка TERMAI', style: AppText.screenTitle),
      ),
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'Выбери раздел. Если ответа не хватает, открой чат кнопкой '
              '«Спросить Термая» — наставник получит контекст именно этого раздела.',
              style: AppText.body.copyWith(color: C.muted, height: 1.5),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _sections.length; i++) ...[
              _HelpBlock(
                section: _sections[i],
                expanded: i == 0,
                onAsk: () => _ask(context, _sections[i]),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _HelpBlock extends StatelessWidget {
  final _HelpSection section;
  final bool expanded;
  final VoidCallback onAsk;
  const _HelpBlock({
    required this.section,
    required this.expanded,
    required this.onAsk,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(section.icon, size: 20, color: C.accent),
          title: Text(section.title,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: C.text)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(section.text,
                  style: AppText.caption.copyWith(color: C.muted, height: 1.5)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAsk,
                icon: const Icon(Icons.chat_bubble_outline, size: 17),
                label: const Text('Спросить Термая'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
