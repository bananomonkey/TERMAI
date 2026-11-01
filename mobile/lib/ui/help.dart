// help.dart — инструкция приложения: как учиться, что делают экраны,
// где лежат архив, чаты и расход токенов. Полностью вертикально скроллится.
import 'package:flutter/material.dart';

import 'app_background.dart';
import 'theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Инструкция',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'TERMAI — тренажёр навыков с ИИ-наставником. Направления, курсы, '
              'практика и проверка в одном приложении.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: C.muted),
            ),
            const SizedBox(height: 18),
            _Block(
              icon: Icons.route_outlined,
              title: '1. Выбери направление',
              text:
                  'На главной сверху — переключение между DevOps, английским и Go. '
                  'Каждое направление хранит свой маршрут, прогресс, XP и статистику. '
                  'Кнопка «+» добавляет ещё одно, долгое нажатие на чип убирает его без потери данных.',
            ),
            _Block(
              icon: Icons.menu_book_outlined,
              title: '2. Выбери курс',
              text:
                  'На главном экране — компактные строки курсов с прогрессом. '
                  'Тап открывает список уроков, меню строки — переименовать, убрать в архив или удалить.',
            ),
            _Block(
              icon: Icons.play_arrow_outlined,
              title: '3. Пройди урок',
              text: 'В уроке четыре вкладки: «Справка» (теория), «Задача», '
                  '«Терминал» (только в практических курсах) и «Решение». '
                  'Слайды листаются вправо-влево. В теоретических курсах терминала нет: '
                  'урок закрывается пройденным тестом.',
            ),
            _Block(
              icon: Icons.terminal,
              title: '4. Практика в терминале',
              text:
                  'Вводи команды внизу экрана. Базовые команды и kubectl выполняются локально, '
                  'сложные сценарии объясняет ИИ-симулятор. Kubernetes-задания проверяют '
                  'реальное состояние мини-кластера, а не факт нажатия кнопки.',
            ),
            _Block(
              icon: Icons.psychology_outlined,
              title: '5. Ментор',
              text:
                  'Кнопка чата открывает беседу по текущей задаче. Ментор подсказывает, '
                  'но не выдаёт решение без просьбы. Все беседы сохраняются.',
            ),
            _Block(
              icon: Icons.inventory_2_outlined,
              title: '6. Архив и порядок',
              text:
                  'Курсы можно убирать в архив. Прогресс сохраняется, курс возвращается '
                  'одним нажатием. Порядок курсов запоминается внутри направления.',
            ),
            _Block(
              icon: Icons.payments_outlined,
              title: '7. Расход токенов',
              text:
                  'Иконка расхода показывает, сколько токенов потрачено по каждой модели. '
                  'Счётчик сохраняется в облаке вместе с прогрессом.',
            ),
            _Block(
              icon: Icons.wallpaper_outlined,
              title: '8. Фон приложения',
              text:
                  '«Ещё» → «Фон приложения»: выбери своё фото и настрой размытие и затемнение. '
                  'Фон применяется на всех экранах.',
            ),
            _Block(
              icon: Icons.cloud_sync_outlined,
              title: '9. Синхронизация',
              text:
                  '«Ещё» → «Настройки» → «Облачная синхронизация»: войди через Google, '
                  'чтобы прогресс, чаты, настройки и ключи ИИ переносились на другое устройство. '
                  'Ключи можно не отправлять — тумблер в настройках.',
            ),
            _Block(
              icon: Icons.swap_horiz_outlined,
              title: '10. Резервные модели',
              text:
                  '«Ещё» → «Резервные модели»: добавь второе подключение. Если основное '
                  'откажет, TERMAI автоматически попробует резерв.',
            ),
            _Block(
              icon: Icons.emoji_events_outlined,
              title: '11. Прогресс',
              text:
                  'За уроки дают XP и достижения, серия растёт за ежедневные занятия. '
                  'В конце списка уроков есть повторение закладок и режим собеседования.',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: C.card, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(Icons.lightbulb_outline, size: 20, color: C.warn),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Совет: начни с одного курса и проходи по одному уроку в день — '
                    'серия и повторение закрепляют материал лучше, чем марафон.',
                    style:
                        TextStyle(fontSize: 12.5, height: 1.45, color: C.muted),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const _Block({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 24,
          child: Icon(icon, size: 18, color: C.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: C.text)),
            const SizedBox(height: 3),
            Text(text,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: C.muted)),
          ]),
        ),
      ]),
    );
  }
}
