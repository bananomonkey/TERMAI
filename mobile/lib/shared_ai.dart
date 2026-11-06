// shared_ai.dart — общий бесплатный доступ TERMAI через серверный шлюз.
//
// Серверный ключ общего шлюза НИКОГДА не попадает в APK, Firebase Remote Config или
// Firestore. Приложение ходит на наш серверный Worker, а Worker хранит ключ
// в защищённой конфигурации. Здесь только публичная конфигурация акции,
// согласие пользователя и Firebase ID token для авторизации запросов.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'firebase_options.dart';
import 'models.dart';

class SharedAiPromo {
  final bool enabled;
  final DateTime? endsAt;
  final int noticeVersion;
  final String model;
  final String privacyUrl;

  const SharedAiPromo({
    required this.enabled,
    required this.endsAt,
    required this.noticeVersion,
    required this.model,
    required this.privacyUrl,
  });

  bool get active =>
      enabled && endsAt != null && DateTime.now().isBefore(endsAt!);

  factory SharedAiPromo.fromJson(Map<String, dynamic> j) => SharedAiPromo(
        enabled: j['enabled'] as bool? ?? false,
        endsAt: DateTime.tryParse((j['ends_at'] ?? '').toString()),
        noticeVersion: (j['notice_version'] as num?)?.toInt() ?? 1,
        model: (j['model'] ?? '').toString().trim().isEmpty
            ? 'deepseek-v4.1-flash:free'
            : (j['model'] ?? '').toString().trim(),
        privacyUrl: (j['privacy_url'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'notice_version': noticeVersion,
        'model': model,
        'privacy_url': privacyUrl,
      };
}

class SharedAiService extends ChangeNotifier {
  SharedAiService._();
  static final SharedAiService instance = SharedAiService._();

  /// URL серверного шлюза задаётся при сборке:
  /// flutter build apk --dart-define=TERMAI_AI_PROXY_URL=https://...
  /// Значение — корень Worker без /v1. Пусто — общий доступ выключен.
  static const String _definedProxy =
      String.fromEnvironment('TERMAI_AI_PROXY_URL', defaultValue: '');

  SharedAiPromo? _promo;
  String _error = '';
  bool _loading = false;
  Future<void>? _refreshing;
  Timer? _expiryTimer;
  Future<String>? _tokenFuture;
  Future<void>? _binding;
  StreamSubscription<User?>? _authSub;
  bool _signedIn = false;

  String get proxyRoot {
    var value = _definedProxy.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('/v1')) {
      value = value.substring(0, value.length - 3);
    }
    return value;
  }

  bool get proxyConfigured => proxyRoot.isNotEmpty;
  String get chatBase => '$proxyRoot/v1';
  String get configUrl => '$proxyRoot/config';
  SharedAiPromo? get promo => _promo;
  bool get loading => _loading;
  String get error => _error;
  int get noticeVersion => _promo?.noticeVersion ?? 1;
  String get model => _promo?.model ?? 'deepseek-v4.1-flash:free';
  String get privacyUrl => _promo?.privacyUrl ?? '';
  bool get promoActive => proxyConfigured && (_promo?.active ?? false);
  DateTime? get endsAt => _promo?.endsAt;

  String get remainingLabel {
    final end = endsAt;
    if (end == null) return '';
    final left = end.difference(DateTime.now());
    if (left.isNegative) return 'завершён';
    final days = left.inDays;
    final hours = left.inHours % 24;
    if (days > 0) return 'осталось $days дн. $hours ч.';
    final minutes = left.inMinutes % 60;
    return 'осталось $hours ч. $minutes мин.';
  }

  /// signedIn — вошёл ли пользователь через Google. Общий доступ выдаётся
  /// только таким пользователям: анонимный вход больше не используется.
  bool get signedIn {
    if (_signedIn) return true;
    if (_authSub != null) return false;
    // До подписки на authStateChanges проверяем текущую сессию напрямую.
    try {
      final u = FirebaseAuth.instance.currentUser;
      return u != null && !u.isAnonymous;
    } catch (_) {
      return false;
    }
  }

  /// bindAuth — подписывается на состояние Firebase Auth, чтобы общий доступ
  /// сам выключался после выхода из Google-аккаунта.
  Future<void> bindAuth() {
    if (_binding != null) return _binding!;
    final future = _bindAuth();
    _binding = future;
    return future.whenComplete(() {
      if (identical(_binding, future)) _binding = null;
    });
  }

  Future<void> _bindAuth() async {
    try {
      if (Firebase.apps.isEmpty) {
        final options = DefaultFirebaseOptions.currentPlatform;
        if (options.apiKey.isEmpty || options.apiKey.startsWith('REPLACE')) {
          return;
        }
        try {
          await Firebase.initializeApp(options: options);
        } on FirebaseException catch (e) {
          if (e.code != 'duplicate-app') rethrow;
        }
      }
      void apply(User? u) {
        final signed = u != null && !u.isAnonymous;
        if (signed == _signedIn) return;
        _signedIn = signed;
        notifyListeners();
      }

      apply(FirebaseAuth.instance.currentUser);
      await _authSub?.cancel();
      _authSub = FirebaseAuth.instance.authStateChanges().listen(apply);
    } catch (_) {
      // Firebase не настроен — общий доступ просто недоступен.
    }
  }

  /// isUsable — можно ли прямо сейчас отправлять запросы через общий шлюз.
  bool isUsable(Config config) {
    if (!proxyConfigured || _promo == null) return false;
    if (!config.sharedAiEnabled) return false;
    if (config.sharedAiConsentVersion < _promo!.noticeVersion) return false;
    if (!signedIn) return false;
    return _promo!.active;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool force = false}) {
    if (!proxyConfigured) {
      _error = 'Сервер общего доступа не указан в этой сборке.';
      return Future.value();
    }
    if (_refreshing != null && !force) return _refreshing!;
    final future = _refresh(force: force);
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<void> _refresh({required bool force}) async {
    if (_loading) return;
    _loading = true;
    _error = '';
    notifyListeners();
    try {
      final res = await http.get(Uri.parse(configUrl), headers: {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) throw Exception('неверный ответ сервера');
      _promo = SharedAiPromo.fromJson(decoded.cast<String, dynamic>());
      await _saveCache();
    } catch (e) {
      _error = 'Сервер общего доступа недоступен: $e';
      // Если есть свежий кэш и акция ещё не закончилась — работаем по нему.
      if (_promo == null || !(_promo?.active ?? false)) {
        await _loadCache();
      }
    } finally {
      _loading = false;
      _scheduleExpiry();
      notifyListeners();
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final end = _promo?.endsAt;
    if (end == null) return;
    final delay = end.difference(DateTime.now());
    if (delay.isNegative) return;
    _expiryTimer = Timer(delay + const Duration(seconds: 1), () {
      notifyListeners();
    });
  }

  File? _cacheFile;

  Future<File?> _cache() async {
    if (_cacheFile != null) return _cacheFile;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _cacheFile = File('${dir.path}/shared_ai_promo.json');
      return _cacheFile;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache() async {
    final f = await _cache();
    final p = _promo;
    if (f == null || p == null) return;
    try {
      await f.writeAsString(jsonEncode({
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
        'promo': p.toJson(),
      }));
    } catch (_) {}
  }

  Future<void> _loadCache() async {
    try {
      final f = await _cache();
      if (f == null || !await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return;
      final fetchedAt = (decoded['fetched_at'] as num?)?.toInt() ?? 0;
      // Кэш нужен только на случай короткого сбоя сети.
      if (DateTime.now().millisecondsSinceEpoch - fetchedAt >
          const Duration(hours: 12).inMilliseconds) {
        return;
      }
      final promo = decoded['promo'];
      if (promo is Map) {
        _promo = SharedAiPromo.fromJson(promo.cast<String, dynamic>());
      }
    } catch (_) {}
  }

  Future<void> clearCache() async {
    final f = await _cache();
    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// idToken — Firebase ID token для авторизации на нашем Worker.
  /// Общий доступ работает только для пользователей, вошедших через Google;
  /// анонимные сессии не используются.
  Future<String> idToken() {
    if (_tokenFuture != null) return _tokenFuture!;
    final future = _getIdToken();
    _tokenFuture = future;
    return future.whenComplete(() {
      if (identical(_tokenFuture, future)) _tokenFuture = null;
    });
  }

  Future<String> _getIdToken() async {
    try {
      if (Firebase.apps.isEmpty) {
        final options = DefaultFirebaseOptions.currentPlatform;
        if (options.apiKey.isEmpty || options.apiKey.startsWith('REPLACE')) {
          throw Exception('Firebase не настроен в этой сборке.');
        }
        try {
          await Firebase.initializeApp(options: options);
        } on FirebaseException catch (e) {
          // Синхронизация могла инициализировать Firebase параллельно.
          if (e.code != 'duplicate-app') rethrow;
        }
      }
      await bindAuth();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) {
        throw Exception(
            'shared_auth: общий доступ доступен после входа через Google.');
      }
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        throw Exception('shared_auth: пустой Firebase ID token');
      }
      return token;
    } on FirebaseAuthException catch (e) {
      throw Exception('shared_auth: ${e.code} ${e.message ?? ''}');
    } catch (e) {
      throw Exception('shared_auth: $e');
    }
  }
}
