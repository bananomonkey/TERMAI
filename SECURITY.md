# Безопасность TERMAI

## Firebase API key в `mobile/lib/firebase_options.dart`

Строка вида `AIzaSy...` — это **клиентский ключ Firebase / Google API**, а не
серверный секрет. Он по определению поставляется внутри APK и нужен приложению,
чтобы обращаться к Firebase Auth и Firestore. Такой ключ есть в любом
мобильном приложении на Firebase, и сам по себе он не даёт доступа к вашему
аккаунту или биллингу.

GitHub secret scanning всё равно помечает строки формата `AIza...` как
«публично утёкший секрет» — это ожидаемое поведение сканера, а не признак
взлома. Удаление строки из последнего коммита ничего не меняет: ключ остаётся
в истории git и в уже собранных APK.

### Что сделать, чтобы закрыть риск

1. Откройте [Google Cloud Console → APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials)
   для проекта `termai-4fdcc`.
2. Найдите ключ `AIzaSyDUjA0FZOGbhYLePfWrVYIUhdbMmZPZUe0` и откройте его.
3. **Application restrictions → Android apps**:
   - package name: `com.vlad.termai`;
   - SHA-1 release-подписи (и debug, если собираете локально).
4. **API restrictions → Restrict key**: оставьте только
   - Identity Toolkit API,
   - Cloud Firestore API,
   - Firebase Installations API,
   - Token Service API.
5. Если ключ уже использовали или хотите закрыть алерт GitHub:
   - создайте новый ключ с теми же ограничениями;
   - замените значение в `mobile/lib/firebase_options.dart`;
   - старый ключ удалите (Delete / Revoke);
   - алерт GitHub закройте как «Revoked».
6. Проверьте Firestore Rules: доступ к `users_progress/{uid}` должен быть
   разрешён только `request.auth.uid == uid`.

Web client ID (`...apps.googleusercontent.com` в `mobile/lib/sync_config.dart`)
тоже публичный идентификатор OAuth-клиента и не является секретом.

### Файлы, которые нельзя коммитить

В `.gitignore` уже исключены `google-services.json`, `key.properties` и
`*.jks`. Если добавляете новые секреты — используйте GitHub Actions Secrets
или локальный файл вне репозитория.
