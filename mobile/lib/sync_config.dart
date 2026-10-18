// sync_config.dart — параметры Google-входа, которые не генерирует
// flutterfire configure.
//
// Открой Firebase Console → Authentication → Sign-in method → Google.
// В блоке «Web SDK configuration» скопируй Web client ID (…apps.googleusercontent.com)
// и вставь сюда. Именно он нужен google_sign_in на Android, чтобы Firebase
// принял idToken.
//
// Пустая строка = вход через Google не настроен (кнопка покажет подсказку).
const String googleServerClientId =
    '545966007024-qjd8h1m8jh35fv1g4cqavd98ntqciu64.apps.googleusercontent.com';
