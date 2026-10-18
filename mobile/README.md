# TERMAI mobile (Flutter)

Тренажёр с ИИ-наставником. Локальный прогресс хранится в
`termai-progress.json` в папке приложения и работает без интернета и аккаунта.

## Сборка

```bash
flutter pub get
flutter run
flutter build apk --release
```

## Google-синхронизация прогресса (Firebase)

Синхронизация опциональна. Пока `lib/firebase_options.dart` содержит
заглушки, приложение полностью работает локально и ничего не отправляет.

### 1. Создать Firebase-проект и приложение

1. <https://console.firebase.google.com> → создать проект.
2. Authentication → Sign-in method → включить **Google**.
3. Project settings → Your apps → добавить Android-приложение
   `com.vlad.termai`.
4. Добавить SHA-1 отпечаток релизного ключа:
   `cd android && ./gradlew signingReport`.
5. Создать Firestore (production mode).

### 2. Заполнить конфигурацию (без flutterfire CLI)

Project settings → Your apps → Android → `firebaseConfig`. Перенеси значения
в `lib/firebase_options.dart` (блок `android`):

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIza…',
  appId: '1:1234567890:android:abcdef',
  messagingSenderId: '1234567890',
  projectId: 'my-project',
  storageBucket: 'my-project.appspot.com',
);
```

Это клиентские идентификаторы, не пароль — их можно коммитить.
`google-services.json` и Gradle-плагин google-services не нужны: Firebase
инициализируется явными `options`, а `google_sign_in` получает
`serverClientId` из Dart.

Альтернатива: `flutterfire configure` сам создаст
`lib/firebase_options.dart` и `google-services.json`. В этом случае
`google-services.json` не коммить, а в CI передавай его через секрет.

### 3. Включить Google Sign-In

Firebase Console → Authentication → Google → **Web SDK configuration**.
Скопируй **Web client ID** (`…apps.googleusercontent.com`) в
`lib/sync_config.dart`:

```dart
const String googleServerClientId = '1234567890-xxxx.apps.googleusercontent.com';
```

### 4. Разрешить доступ к Firestore

Правила:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users_progress/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

Документ пользователя: `users_progress/{uid}` с полями
`progress` (JSON-строка), `updated_at`, `email`. Прогресс пишется с
задержкой 3 секунды после изменений. При входе на новом устройстве
подтягивается облачная копия, если в ней больше решённых задач (или чатов).

### 5. Подпись APK (нужна для Google-входа)

Google проверяет SHA-1 сертификата, которым подписан APK. Если CI каждый раз
подписывает debug-ключом, SHA-1 меняется и вход ломается. Поэтому нужен
постоянный release-ключ.

```bash
cd mobile/android
keytool -genkeypair -v -keystore app/termai-release.jks \
  -alias termai -keyalg RSA -keysize 2048 -validity 10000
keytool -list -v -keystore app/termai-release.jks -alias termai | grep SHA1
```

1. Полученный SHA-1 добавь в Firebase Console → Project settings →
   Your apps → Android → **Add fingerprint**.
2. Для локальной сборки скопируй `key.properties.example` в
   `android/key.properties` и заполни.
3. Для GitHub Actions добавь секреты:
   - `ANDROID_KEYSTORE_BASE64` — `base64 -w0 android/app/termai-release.jks`;
   - `ANDROID_STORE_PASSWORD`;
   - `ANDROID_KEY_PASSWORD`;
   - `ANDROID_KEY_ALIAS` = `termai`.
4. Workflow сам восстановит ключ; без секретов соберётся debug-подписанный APK.

### 6. CI

Пока в `firebase_options.dart` заглушки, релизный APK собирается без
синхронизации. После заполнения конфигурации закоммить файл — CI соберёт APK
с рабочим входом. `google-services.json` в git не попадает (он в `.gitignore`),
потому что приложение передаёт настройки Firebase через Dart.
