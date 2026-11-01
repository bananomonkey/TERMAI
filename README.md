<div align="center">

<img src="mobile/assets/icon/termai.png" width="112" alt="TERMAI"/>

# TERMAI

**Тренажёр навыков с ИИ-наставником**

Linux · Kubernetes · DevOps · английский · Go — прямо на телефоне.<br/>
Не «посмотри видео», а «сделай и пойми, что произошло».

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-24%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-установка)
[![License](https://img.shields.io/badge/License-MIT-success?style=for-the-badge)](LICENSE)

[![Download APK](https://img.shields.io/badge/Download_APK-Releases-2ea44f?style=for-the-badge)](https://github.com/bananomonkey/TERMAI/releases)

</div>

---

> **TERMAI** — карманный тренажёр, где ты учишься делать, а не смотреть.
> Термай, ИИ-наставник, объясняет ошибки, задаёт вопросы и помогает дойти
> до результата — в терминале, языке или инженерной практике.

## ✨ Что умеет

| Возможность | Что даёт |
|---|---|
| 🗺️ **Направления обучения** | DevOps, английский и Go — отдельные пространства со своим маршрутом, XP и статистикой. |
| ☸️ **Практический Kubernetes** | 34 урока: Pod, Deployment, Service, ConfigMap/Secret, PV/PVC, Ingress, диагностика и итоговый проект. |
| 🚪 **Понятный старт** | Мультивыбор направлений, ввод API-ключа и необязательный вход через Google. |
| 🖥️ **Живой терминал** | `ls`, `cd`, `cat`, `git`, `docker`, `kubectl` работают мгновенно; Kubernetes-задания проверяют состояние мини-кластера. |
| 🧠 **ИИ-наставник** | Чат по текущей задаче, объяснение ошибок, режим «Собеседование». История бесед сохраняется по задачам. |
| 📝 **Урок из 4 слайдов** | Справка с поиском → задача → терминал → решение. Свайпы, как в хороших мобильных курсах. |
| 🔁 **Интервальное повторение** | Закладки на сложные темы и возврат к ним через день, два, четыре… |
| 🏆 **XP, серии и достижения** | Общий прогресс и отдельный XP каждого направления. |
| 🔐 **Свой API-ключ** | DeepSeek, OpenAI, Gemini, Qwen, OpenRouter, Groq, Mistral, GigaChat, YandexGPT, Ollama. Ключ не покидает устройство. |
| ☁️ **Google-синхронизация** | Необязательный вход через Google: прогресс, направления и чаты восстанавливаются на новом устройстве. |

## 🎬 Как проходит урок

| 1. Теория | 2. Мини-тест | 3. Практика | 4. Разбор |
|:---:|:---:|:---:|:---:|
| Короткая справка с поиском по термину | Пара вопросов, чтобы закрепить | Команды в песочнице или задания по теме | Наставник объясняет, что получилось и почему |

## 📱 Установка

1. Открой [Releases](https://github.com/bananomonkey/TERMAI/releases) и скачай `TERMAI.apk`.
2. Разреши установку из неизвестного источника, если Android попросит.
3. При первом запуске вставь API-ключ провайдера — например, DeepSeek.
4. Выбери одно или несколько направлений и начни с первой задачи.

> Прогресс хранится локально. Интернет нужен только для ИИ и необязательной
> синхронизации.

## 🛠️ Сборка из исходников

```bash
git clone https://github.com/bananomonkey/TERMAI.git
cd TERMAI/mobile

flutter pub get
flutter run                  # запуск на подключённом устройстве
flutter build apk --release  # готовый APK
```

Требуется Flutter 3.47+ и Android SDK 24+.

## 🧩 Технологии

| Слой | Что используется |
|---|---|
| UI | Flutter, Material 3, кастомная тема «cocoa» |
| ИИ | REST-клиенты популярных провайдеров, строгий JSON-режим |
| Песочница | Быстрый Dart-симулятор + ИИ там, где нужен контекст |
| Хранение | JSON в папке приложения, без внешней БД |
| Синхронизация | Firebase Authentication + Cloud Firestore (опционально) |
| Напоминания | `flutter_local_notifications` + timezone |

## 📂 Структура

```
mobile/
├── lib/
│   ├── main.dart          — запуск, сплэш, тема, навигация
│   ├── store.dart         — состояние, направления, прогресс, терминал, чаты
│   ├── directions.dart    — каталог направлений и их маршруты
│   ├── ai.dart            — провайдеры ИИ и промпты
│   ├── sandbox.dart       — оффлайн-симулятор команд
│   ├── k8s_sandbox.dart   — мини-кластер и проверка Kubernetes-практики
│   ├── models.dart        — курсы, задачи, прогресс, чаты
│   ├── sync_service.dart  — Google-вход и Firestore
│   └── ui/                — экраны: курсы, урок, ментор, настройки
├── assets/                — курсы, иконки, текстуры
└── android/               — нативная оболочка и подпись APK
```

## ☁️ Google-синхронизация

Синхронизация полностью опциональна: без неё приложение работает локально.

Настройка Firebase, Firestore и release-подписи описана в
[`mobile/README.md`](mobile/README.md#google-синхронизация-прогресса-firebase).

Коротко: включить Google Sign-In в Firebase, добавить SHA-1 подписи,
создать Firestore и заполнить `mobile/lib/firebase_options.dart`
и `mobile/lib/sync_config.dart`.

## 🔒 Приватность

- API-ключ хранится только на устройстве и не попадает в git.
- По умолчанию прогресс не покидает телефон.
- При включённой синхронизации в Firestore пишется только твой документ
  `users_progress/{uid}`: прогресс, чаты и email аккаунта.
- `google-services.json` и ключи подписи в репозиторий не коммитятся.
- Полная политика — в [PRIVACY.md](PRIVACY.md).

## 🚢 Выпуск

Чек-лист для Google Play, iOS и других платформ, тексты для магазина и
QA-список — в [RELEASE.md](RELEASE.md).

## 🤝 Участие

Идеи, баги и Pull Request'ы приветствуются. Если нашёл проблему — открой
[issue](https://github.com/bananomonkey/TERMAI/issues) с шагом воспроизведения и версией Android.

## 📄 Лицензия

[MIT](LICENSE)

<div align="center">

<br/>

<img src="mobile/assets/icon/clawd.png" width="64" alt="Барсик"/>

**Барсик уже ждёт первую команду.**

`$ docker run -it termai`

</div>
