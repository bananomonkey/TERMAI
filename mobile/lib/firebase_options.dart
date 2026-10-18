// firebase_options.dart — ЗАГЛУШКА.
//
// Замените значения ниже данными из Firebase Console:
// Project settings → Your apps → Android → firebaseConfig.
// Подробная инструкция — в mobile/README.md.
//
// Можно вместо этого выполнить `flutterfire configure`: он перезапишет файл,
// но также добавит google-services.json и Gradle-плагин (файл не коммитить).
//
// Пока стоят заглушки, синхронизация в приложении отключена и локальный
// прогресс работает как обычно.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static const String placeholder = 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions не поддерживает эту платформу.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDUjA0FZOGbhYLePfWrVYIUhdbMmZPZUe0',
    appId: '1:545966007024:android:489405b40d3d9a94a59835',
    messagingSenderId: '545966007024',
    projectId: 'termai-4fdcc',
    storageBucket: 'termai-4fdcc.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: placeholder,
    appId: '1:000000000000:ios:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'termai',
    storageBucket: 'termai.appspot.com',
    iosBundleId: 'com.vlad.termai',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: placeholder,
    appId: '1:000000000000:ios:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'termai',
    storageBucket: 'termai.appspot.com',
    iosBundleId: 'com.vlad.termai',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: placeholder,
    appId: '1:000000000000:web:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'termai',
    storageBucket: 'termai.appspot.com',
    authDomain: 'termai.firebaseapp.com',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: placeholder,
    appId: '1:000000000000:web:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'termai',
    storageBucket: 'termai.appspot.com',
    authDomain: 'termai.firebaseapp.com',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: placeholder,
    appId: '1:000000000000:web:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'termai',
    storageBucket: 'termai.appspot.com',
    authDomain: 'termai.firebaseapp.com',
  );
}
