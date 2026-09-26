# TERMAI

**Терминал + ИИ** — десктопный тренажёр командной строки с ИИ-наставником (DeepSeek).
Docker, Linux, Git — и любые курсы, которые ИИ соберёт под твою цель («хочу девопс»).
Всё выполняется в виртуальной песочнице: ошибки безопасны, реальная машина не страдает.

## Как устроено обучение

Каждая задача в формате интерактивных платформ:

1. **Теория** — markdown с примерами команд и блоками кода.
2. **Мини-тест** — 2 вопроса по теории; пока не пройдёшь — практика закрыта.
3. **Практика** — выполняешь команды в симулируемом терминале.
4. **Проверка** — ИИ-проверяющий смотрит историю команд и состояние песочницы.

Плюс: XP и уровни, серии дней, экзамены, интервальное повторение (закладки ☆),
достижения, чат с ментором, свои задачи и целые курсы от ИИ, пересборка курса
под твой стиль. Ещё: диктовка 🎙 (whisper.cpp), вложения в чат (📎 файлы и фото,
если модель поддерживает изображения), Tab-автодополнение, таймер времени,
сброс песочницы задачи.

## Скачивание

Иди в [Releases](../../releases) и скачай архив под свою ОС:

- **Linux**: распакуй → `chmod +x termai-linux-amd64` → запуск.
- **Windows**: распакуй → запусти `termai-windows-amd64.exe`
  (SmartScreen предупредит — «Подробнее» → «Выполнить в любом случае»).
- **macOS (Apple Silicon / Intel)**: распакуй → в терминале
  `xattr -d com.apple.quarantine termai-macos-*` → запуск.
- **Android**: скачай `TERMAI.apk` со страницы релиза и установи
  (разреши установку из неизвестных источников).

Затем: настройки (шестерёнка) → вставь API-ключ DeepSeek
([platform.deepseek.com](https://platform.deepseek.com)) → готово.

## Диктовка (whisper.cpp, локально)

Распознавание речи работает офлайн через [whisper.cpp](https://github.com/ggml-org/whisper.cpp):

```bash
git clone https://github.com/ggml-org/whisper.cpp
cd whisper.cpp && cmake -B build && cmake --build build -j
# бинарник: build/bin/whisper-cli
```

В TERMAI: Настройки → «Скачать модель ggml-base» (~148 МБ) — пути подставятся сами
(можно указать свои; для большей точности возьми `ggml-small.bin`).
Запись звука — через `parecord`/`arecord` (есть в любом настольном Linux).

## Горячие клавиши (настраиваются в настройках)

| Действие | По умолчанию |
|---|---|
| Очистить терминал | Ctrl+L |
| Завершить задачу | Ctrl+Enter |
| Фокус в чат ментора | Ctrl+K |
| Фокус в терминал | Ctrl+T |
| Теория ⇄ Терминал | Ctrl+/ |
| Новая задача от ИИ | Ctrl+N |
| Закладки/Повторение | Ctrl+R |
| Статистика | Ctrl+I |
| Файлы песочницы | Ctrl+F |

Локальные команды терминала (мгновенно, без ИИ): `docker ps [-a]`, `docker images`,
`docker volume ls`, `docker network ls`, `docker rm [-f]`, `docker rmi`, `docker stop`,
`docker start`, `docker restart`, `ls`, `cat`, `pwd`, `echo`, `cd`, `state`, `clear`.
Tab — автодополнение команд, имён контейнеров/образов/файлов.

## Сборка из исходников

Нужен Go 1.22+. На Linux — `sudo apt install libgl1-mesa-dev xorg-dev`.

```bash
go mod tidy
go build -ldflags "-s -w" -o termai .
```

APK для Android собирается в GitHub Actions (джоба `android` в
`.github/workflows/release.yml`) через `fyne-cross`:

```bash
fyne-cross android -app-id com.vlad.termai -name TERMAI -icon icon.png
```

Готовый `TERMAI.apk` прикладывается к релизу вместе с десктопными сборками.

## Лицензия

MIT — см. [LICENSE](LICENSE).
