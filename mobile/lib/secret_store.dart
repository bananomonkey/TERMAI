// secret_store.dart — локальное защищённое хранилище токенов.
//
// Здесь только секреты, которые не должны попадать в termai.json,
// downloads.json, облако, логи и диагностику. Если secure storage
// недоступен (например, в тестах), значение остаётся в памяти процесса.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecretStore {
  SecretStore._();

  static const _hfTokenKey = 'huggingface_token';
  static const _aiKeysKey = 'ai_provider_keys';
  static final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  static final Map<String, String> _memory = {};

  static Future<String> readHfToken() async {
    if (_memory.containsKey(_hfTokenKey)) return _memory[_hfTokenKey] ?? '';
    try {
      final value = await _storage.read(key: _hfTokenKey);
      if (value != null) _memory[_hfTokenKey] = value;
      return value ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> writeHfToken(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) {
      _memory.remove(_hfTokenKey);
      try {
        await _storage.delete(key: _hfTokenKey);
      } catch (_) {}
      return;
    }
    _memory[_hfTokenKey] = clean;
    try {
      await _storage.write(key: _hfTokenKey, value: clean);
    } catch (_) {}
  }

  static Future<void> clearHfToken() => writeHfToken('');

  /// Ключи ИИ хранятся отдельно от termai.json. Формат — JSON-строка,
  /// чтобы не размазывать секреты по нескольким файлам.
  static Future<Map<String, dynamic>> readAiSecrets() async {
    if (_memory.containsKey(_aiKeysKey)) {
      try {
        return jsonDecode(_memory[_aiKeysKey]!) as Map<String, dynamic>;
      } catch (_) {
        return const {};
      }
    }
    try {
      final raw = await _storage.read(key: _aiKeysKey);
      if (raw == null || raw.isEmpty) return const {};
      _memory[_aiKeysKey] = raw;
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const {};
  }

  static Future<void> writeAiSecrets({
    required String mainProvider,
    required String main,
    required List<Map<String, String>> fallbacks,
    Map<String, Map<String, String>> profiles = const {},
  }) async {
    final cleanFallbacks = fallbacks
        .where((f) => (f['api_key'] ?? '').trim().isNotEmpty)
        .toList(growable: false);
    final cleanProfiles = <String, Map<String, String>>{};
    for (final entry in profiles.entries) {
      final key = (entry.value['api_key'] ?? '').trim();
      if (key.isEmpty) continue;
      cleanProfiles[entry.key] = {
        'provider': entry.key,
        'model': (entry.value['model'] ?? '').trim(),
        'base_url': (entry.value['base_url'] ?? '').trim(),
        'api_key': key,
      };
    }
    if (main.trim().isEmpty &&
        cleanFallbacks.isEmpty &&
        cleanProfiles.isEmpty) {
      _memory.remove(_aiKeysKey);
      try {
        await _storage.delete(key: _aiKeysKey);
      } catch (_) {}
      return;
    }
    final raw = jsonEncode({
      'schema': 2,
      'main_provider': mainProvider.trim(),
      'main': main.trim(),
      'fallbacks': cleanFallbacks,
      if (cleanProfiles.isNotEmpty) 'profiles': cleanProfiles,
    });
    _memory[_aiKeysKey] = raw;
    try {
      await _storage.write(key: _aiKeysKey, value: raw);
    } catch (_) {}
  }

  /// Маска для диагностики и UI: никогда не показываем сам токен.
  static String mask(String value) {
    if (value.isEmpty) return 'не задан';
    if (value.length <= 8) return '••••';
    return '${value.substring(0, 3)}••••${value.substring(value.length - 2)}';
  }

  /// Удаляет распространённые токены из ошибок/диагностики перед показом.
  /// Само значение секрета этот метод нигде не сохраняет и не логирует.
  static String redact(String value) {
    var out = value;
    out = out.replaceAll(
      RegExp(
        r'(sk-[A-Za-z0-9_\-]{6,}|hf_[A-Za-z0-9_\-]{6,}|gsk_[A-Za-z0-9_\-]{6,}|or-v1-[A-Za-z0-9_\-]{6,}|AIza[A-Za-z0-9_\-]{12,})',
        caseSensitive: false,
      ),
      '••••',
    );
    out = out.replaceAll(
        RegExp(r'Bearer\s+[^\s"}]+', caseSensitive: false), 'Bearer ••••');
    out = out.replaceAllMapped(
      RegExp(r'((?:api[_-]?key|token|secret)\s*[=:]\s*)[^\s,;}]+',
          caseSensitive: false),
      (m) => '${m.group(1)}••••',
    );
    return out;
  }
}
