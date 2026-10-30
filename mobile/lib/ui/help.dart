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
              'TERMAI — тренажёр навыков с ИИ-наставником. Короткие уроки, практика '
              'и проверка: приложение подходит для языков, Linux, Docker, профессий '
              'и школьных предметов.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: C.muted),
            ),
            const SizedBox(height: 18),
            _Block(
              icon: Icons.route_outlined,
              title: '1. Выбери курс',
              text:
                  'На главном экране — плитки курсов с прогрессом «N/M уроков». '
                  'Тап открывает список уроков. Двойной тап (или меню плитки) — '
                  'переименовать, убрать в архив или удалить курс.',
            ),
            _Block(
              icon: Icons.menu_book_outlined,
              title: '2. Пройди урок',
              text: 'В уроке четыре вкладки: «Справка» (теория), «Задача», '
                  '«Терминал» (только в практических курсах) и «Решение». '
                  'Слайды листаются вправо-влево. В теоретических курсах терминала нет: '
                  'урок закрывается пройденным тестом.',
            ),
            _Block(
              icon: Icons.terminal,
              title: '3. Практика в терминале',
              text:
                  'Вводи команды внизу экрана. Быстрые команды (docker ps, ls, cd, cat…) '
                  'выполняются мгновенно, остальные объясняет ИИ-симулятор. '
                  'Кнопка проверки отправляет задачу наставнику.',
            ),
            _Block(
              icon: Icons.psychology_outlined,
              title: '4. Ментор',
              text:
                  'Кнопка чата открывает беседу по текущей задаче. Ментор подсказывает, '
                  'но не выдаёт решение без просьбы. Все беседы сохраняются: '
                  'иконка чатов на главном экране открывает их список.',
            ),
            _Block(
              icon: Icons.inventory_2_outlined,
              title: '5. Архив и порядок',
              text:
                  'Курсы можно убирать в архив (иконка архива на главном экране). '
                  'Прогресс сохраняется, курс возвращается одним нажатием. '
                  'Там же можно удалить курс навсегда.',
            ),
            _Block(
              icon: Icons.payments_outlined,
              title: '6. Расход токенов',
              text:
                  'Иконка расхода показывает, сколько токенов потрачено по каждой модели. '
                  'Счётчик сохраняется в облаке вместе с прогрессом.',
            ),
            _Block(
              icon: Icons.wallpaper_outlined,
              title: '7. Фон приложения',
              text:
                  '«Ещё» → «Фон приложения»: выбери своё фото из галереи и настрой '
                  'размытие и затемнение. Фон применяется на всех экранах, '
                  'а размытие видно сразу в предпросмотре.',
            ),
            _Block(
              icon: Icons.cloud_sync_outlined,
              title: '8. Синхронизация',
              text:
                  '«Ещё» → «Настройки» → «Облачная синхронизация»: войди через Google, '
                  'чтобы прогресс, чаты, настройки и ключи ИИ переносились на другое '
                  'устройство. Ключи можно не отправлять — тумблер в настройках. '
                  'Без входа всё хранится локально.',
            ),
            _Block(
              icon: Icons.swap_horiz_outlined,
              title: '9. Резервные модели',
              text:
                  '«Ещё» → «Резервные модели»: добавь второе подключение (другой провайдер '
                  'или модель). Если основное откажет, TERMAI автоматически попробует резерв.',
            ),
            _Block(
              icon: Icons.emoji_events_outlined,
              title: '10. Прогресс',
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: C.card, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: C.card2,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: C.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: C.text)),
              const SizedBox(height: 4),
              Text(text,
                  style:
                      TextStyle(fontSize: 12.5, height: 1.45, color: C.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}
