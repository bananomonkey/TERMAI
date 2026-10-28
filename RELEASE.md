# Выпуск TERMAI

## Статус платформ

| Платформа | Статус | Что нужно |
|---|---|---|
| Android (APK) | ✅ Готово | GitHub Actions собирает APK и AAB |
| Google Play (AAB) | 🟡 Почти готово | аккаунт Play Console, иконка 512×512, скриншоты, Data safety |
| iOS / App Store | ⚪ Не начато | Mac + Xcode + Apple Developer, папка `ios/` |
| Web | ⚪ Требует доработки | заменить `dart:io`/`path_provider` на кросс-платформенное хранилище |
| Linux | 🟡 Есть каркас | проверить плагины и собрать `flutter build linux` |
| Windows / macOS | ⚪ Не начато | `flutter create --platforms=windows,macos .` + проверка плагинов |

## Android: релиз

Версия задаётся в `mobile/pubspec.yaml` (`version: 1.16.0+37`).

1. Секреты GitHub (Settings → Secrets → Actions):
   - `ANDROID_KEYSTORE_BASE64`
   - `ANDROID_STORE_PASSWORD`
   - `ANDROID_KEY_PASSWORD`
   - `ANDROID_KEY_ALIAS`
2. SHA-1 ключа добавлен в Firebase (Project settings → Your apps).
3. Запушить тег:

```bash
git tag v1.16.0
git push origin v1.16.0
```

Workflow `Release` соберёт:
- `TERMAI.apk` — для установки вручную;
- `TERMAI.aab` — для Google Play.

Оба файла прикрепляются к GitHub Release. Ручной запуск без релиза:
**Actions → Release → Run workflow** (APK/AAB будут в Artifacts).

## Google Play: чек-лист

- [ ] Аккаунт Google Play Console (разовая оплата).
- [ ] Создать приложение, package `com.vlad.termai`.
- [ ] Загрузить `TERMAI.aab` во внутреннее тестирование.
- [ ] Иконка 512×512 PNG.
- [ ] Feature graphic 1024×500 PNG.
- [ ] Минимум 2–3 скриншота телефона.
- [ ] Краткое (до 80 символов) и полное описание.
- [ ] Privacy Policy URL — ссылка на `PRIVACY.md` (например, GitHub Pages или raw-ссылка).
- [ ] Data safety: указать, что email и прогресс могут храниться в Firebase,
      аналитики и рекламы нет.
- [ ] Content rating: образовательное приложение, 13+.
- [ ] Target API level — актуальный на момент публикации.
- [ ] Проверить вход через Google на подписанном AAB из Play.

## iOS: что понадобится

1. Mac с Xcode и CocoaPods.
2. `cd mobile && flutter create --platforms=ios .`
3. Bundle ID `com.vlad.termai`, команда разработчика Apple.
4. Для Google-входа добавить в `Info.plist` URL scheme
   `REVERSED_CLIENT_ID` из `GoogleService-Info.plist`.
5. `flutter build ipa --release`, загрузка в App Store Connect.

## Web: что мешает

Сейчас `store.dart` использует `dart:io` и `path_provider`, которых нет в
браузере. Для web нужно:

- вынести хранение прогресса в интерфейс (`LocalStore`);
- сделать реализации для IO и web (`shared_preferences`/IndexedDB);
- проверить `flutter_local_notifications` и `sensors_plus`;
- настроить Firebase web и `google_sign_in_web`.

## Тексты для магазина

**Короткое описание (RU):**

> TERMAI — тренажёр навыков с ИИ-наставником: Linux, Docker, Git, языки и любые курсы.

**Полное описание (RU):**

> TERMAI — карманный тренажёр, где ты учишься делать, а не смотреть.
> Курсы-тропинки, короткие уроки, практика в терминале или тесты, ментор,
> который объясняет ошибки, XP, серии и достижения. Курсы можно собрать под
> любую цель: Linux, Docker, Git, иностранные языки, школьные предметы или
> профессию. Прогресс хранится локально, а по желанию синхронизируется через
> Google-аккаунт.

## QA перед релизом

- [ ] Онбординг проходится и пропускается.
- [ ] Вход через Google работает на чистой установке.
- [ ] Облачный прогресс подтягивается на втором устройстве.
- [ ] Курс-теория открывается без вкладки «Терминал».
- [ ] Курс с терминалом выполняет команды и завершает задачу.
- [ ] Чаты сохраняются по задачам, переименовываются и удаляются.
- [ ] Экспорт сохраняет файл и не показывает JSON.
- [ ] Тёмная тема, поворот экрана, клавиатура не ломают вёрстку.
