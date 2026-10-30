// sync_service.dart — Google-вход и облачное хранилище прогресса.
//
// Схема Firestore:
//   users_progress/{uid} = {
//     progress: '<JSON прогресса>',
//     updated_at: <millisecondsSinceEpoch>,
//     email: '...',
//   }
//
// Пока firebase_options.dart содержит заглушки, сервис ничего не делает:
// приложение полностью работает на локальном файле.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'sync_config.dart';

class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._();
  SyncService._();

  Future<void>? _initFuture;
  bool _ready = false;
  bool _busy = false;
  bool _googleReady = false;
  String _error = '';
  User? _user;
  Timer? _pushTimer;
  String? _pendingJson;

  /// Синхронизация имеет смысл только на мобильных платформах.
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Настоящая конфигурация Firebase или заглушка из firebase_options.dart.
  bool get configured {
    try {
      final o = DefaultFirebaseOptions.currentPlatform;
      return googleServerClientId.isNotEmpty &&
          o.apiKey.isNotEmpty &&
          !o.apiKey.startsWith('REPLACE') &&
          !o.apiKey.startsWith('PLACEHOLDER');
    } catch (_) {
      return false;
    }
  }

  bool get ready => _ready;
  bool get busy => _busy;
  bool get signedIn => _user != null;
  String get email => _user?.email ?? '';
  String get error => _error;

  /// init — инициализирует Firebase и подхватывает сохранённую сессию.
  /// Повторные вызовы ждут тот же Future.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    if (!supported) {
      _error = 'Облачная синхронизация доступна только на Android/iOS.';
      notifyListeners();
      return;
    }
    if (!configured) {
      _error = 'Firebase не настроен: заполни lib/firebase_options.dart.';
      notifyListeners();
      return;
    }
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _ready = true;
      _user = FirebaseAuth.instance.currentUser;
      FirebaseAuth.instance.authStateChanges().listen((u) {
        _user = u;
        notifyListeners();
      });
    } catch (e) {
      _error = _msg(e);
    }
    notifyListeners();
  }

  /// signIn — нативный выбор Google-аккаунта и вход в Firebase.
  Future<String> signIn() async {
    await init();
    if (!_ready) {
      return _error.isEmpty ? 'Firebase не инициализирован.' : _error;
    }
    if (googleServerClientId.isEmpty) {
      return 'Укажи Web client ID в mobile/lib/sync_config.dart '
          '(Firebase → Authentication → Google → Web client ID).';
    }
    _busy = true;
    _error = '';
    notifyListeners();
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize(
          serverClientId: googleServerClientId,
        );
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google не вернул idToken');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      _user = result.user;
      return '';
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return '';
      return _msg(e);
    } catch (e) {
      return _msg(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    _user = null;
    notifyListeners();
  }

  /// pull — читает облачный прогресс. Возвращает JSON и время сохранения.
  Future<Map<String, dynamic>?> pull() async {
    final u = _user;
    if (!_ready || u == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users_progress')
          .doc(u.uid)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      final json = data?['progress'] as String?;
      if (json == null || json.isEmpty) return null;
      return {
        'json': json,
        'updated_at': (data?['updated_at'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      _error = _msg(e);
      notifyListeners();
      return null;
    }
  }

  /// push — сохраняет JSON прогресса в облако.
  Future<String> push(String json) async {
    final u = _user;
    if (!_ready || u == null) return '';
    try {
      await FirebaseFirestore.instance
          .collection('users_progress')
          .doc(u.uid)
          .set({
        'progress': json,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'email': u.email ?? '',
      });
      return '';
    } catch (e) {
      _error = _msg(e);
      notifyListeners();
      return _msg(e);
    }
  }

  /// pushConfig — сохраняет JSON конфига (ключи, фолбэки) в отдельную
  /// коллекцию users_config/{uid}. Работает только если syncKeysToCloud = true.
  Future<String> pushConfig(String json) async {
    final u = _user;
    if (!_ready || u == null) return '';
    try {
      await FirebaseFirestore.instance
          .collection('users_config')
          .doc(u.uid)
          .set({
        'config': json,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'email': u.email ?? '',
      });
      return '';
    } catch (e) {
      _error = _msg(e);
      notifyListeners();
      return _msg(e);
    }
  }

  /// pullConfig — читает облачный конфиг пользователя.
  Future<Map<String, dynamic>?> pullConfig() async {
    final u = _user;
    if (!_ready || u == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users_config')
          .doc(u.uid)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      final json = data?['config'] as String?;
      if (json == null || json.isEmpty) return null;
      return {
        'json': json,
        'updated_at': (data?['updated_at'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      _error = _msg(e);
      notifyListeners();
      return null;
    }
  }

  /// deleteCloudData — удалить облачную копию прогресса текущего пользователя.
  Future<String> deleteCloudData() async {
    final u = _user;
    if (!_ready || u == null) return 'Сначала войди через Google.';
    try {
      await FirebaseFirestore.instance
          .collection('users_progress')
          .doc(u.uid)
          .delete();
      return '';
    } catch (e) {
      return _msg(e);
    }
  }

  /// schedulePush — отложенная отправка, чтобы не дёргать сеть на каждую команду.
  void schedulePush(String json) {
    if (!_ready || _user == null) return;
    _pendingJson = json;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 3), () {
      final pending = _pendingJson;
      _pendingJson = null;
      if (pending != null) push(pending);
    });
  }

  String _msg(Object e) {
    var s = e.toString();
    s = s.replaceFirst(RegExp(r'^Exception:\s*'), '');
    return s.length > 240 ? s.substring(0, 240) : s;
  }
}
