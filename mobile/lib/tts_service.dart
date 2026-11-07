// tts_service.dart — системный Android TTS для TERMAI.
//
// Озвучиваем только готовый текст: Markdown, код, JSON и служебные вызовы
// приложения вычищаются, длинные ответы делятся на куски. Одновременно
// звучит только один ответ; новый запуск останавливает предыдущий.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'local_tts.dart';
import 'models.dart';

class TtsEngineOption {
  final String name, label;
  const TtsEngineOption(this.name, this.label);
}

class TtsVoiceOption {
  final String name, locale, label;
  const TtsVoiceOption(this.name, this.locale, this.label);
}

class TtsService extends ChangeNotifier {
  TtsService._();
  static final TtsService instance = TtsService._();

  FlutterTts? _tts;
  bool _speaking = false;
  int _token = 0;
  String _lastError = '';
  String _activeText = '';

  bool get speaking => _speaking;
  String get lastError => _lastError;
  String get activeText => _activeText;

  Future<FlutterTts> _ensure() async {
    if (_tts != null) return _tts!;
    final tts = FlutterTts();
    try {
      await tts.awaitSpeakCompletion(true);
      tts.setStartHandler(() {
        _speaking = true;
        notifyListeners();
      });
      tts.setCompletionHandler(_finish);
      tts.setCancelHandler(_finish);
      tts.setErrorHandler((message) {
        _lastError = message.toString();
        _finish();
      });
    } catch (e) {
      _lastError = 'Системный TTS недоступен: $e';
    }
    _tts = tts;
    return tts;
  }

  void _finish() {
    if (_speaking) {
      _speaking = false;
      notifyListeners();
    }
  }

  Future<void> init() async {
    try {
      await _ensure();
    } catch (_) {}
  }

  Future<List<TtsEngineOption>> engines() async {
    try {
      final tts = await _ensure();
      final raw = await tts.getEngines;
      final result = <TtsEngineOption>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final name = (e['name'] ?? '').toString();
          if (name.isEmpty) continue;
          final label = (e['label'] ?? name).toString();
          result.add(TtsEngineOption(name, label));
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<List<TtsVoiceOption>> russianVoices() async {
    try {
      final tts = await _ensure();
      final raw = await tts.getVoices;
      final result = <TtsVoiceOption>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final name = (e['name'] ?? '').toString();
          final locale = (e['locale'] ?? '').toString();
          if (!locale.toLowerCase().startsWith('ru')) continue;
          if (name.isEmpty) continue;
          final network = name.toLowerCase().contains('network');
          result.add(TtsVoiceOption(
            name,
            locale,
            '${locale.isEmpty ? 'ru' : locale} · ${network ? 'онлайн' : 'локальный'} · $name',
          ));
        }
      }
      result.sort((a, b) => a.label.compareTo(b.label));
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isRussianAvailable() async {
    try {
      final tts = await _ensure();
      final r = await tts.isLanguageAvailable('ru-RU');
      return r == true || r == 1 || r == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> _apply(Config c) async {
    final tts = await _ensure();
    try {
      if (c.ttsEngine.isNotEmpty) await tts.setEngine(c.ttsEngine);
      final language = c.ttsVariant.isNotEmpty
          ? c.ttsVariant
          : (c.ttsLocale.isNotEmpty ? c.ttsLocale : 'ru-RU');
      await tts.setLanguage(language);
      if (c.ttsVoice.isNotEmpty) {
        await tts.setVoice({
          'name': c.ttsVoice,
          'locale': c.ttsLocale.isEmpty ? language : c.ttsLocale,
        });
      }
      await tts.setSpeechRate(c.ttsRate.clamp(0.2, 1.0));
      await tts.setPitch(c.ttsPitch.clamp(0.5, 1.5));
      await tts.setVolume(c.ttsVolume.clamp(0.0, 1.0));
    } catch (e) {
      _lastError = 'Не удалось применить голос: $e';
    }
  }

  /// speak — озвучить готовый ответ. [config] передаётся явно, чтобы сервис
  /// не зависел от глобального контроллера и легко тестировался.
  Future<void> speak(String raw, Config config) async {
    final cleaned = sanitizeForSpeech(raw);
    if (cleaned.isEmpty) return;
    final chunks = chunkForSpeech(cleaned);
    if (chunks.isEmpty) return;
    final token = ++_token;
    _lastError = '';
    _activeText = cleaned;
    try {
      // Глушим оба движка до старта: если системный голос был в середине
      // фразы, а включался Piper (или наоборот) — звучали одновременно.
      try {
        (await _ensure()).stop();
      } catch (_) {}
      try {
        await LocalTtsService.instance.stop();
      } catch (_) {}
      // Локальный Piper используется, только если модель явно выбрана и
      // уже установлена. Иначе — системный голос Android.
      if (config.ttsUseLocal && config.ttsLocalModelId.isNotEmpty) {
        await LocalTtsService.instance.init();
        if (await LocalTtsService.instance
            .isInstalled(config.ttsLocalModelId)) {
          _speaking = true;
          notifyListeners();
          final ok = await LocalTtsService.instance.speak(cleaned, config);
          if (ok) return;
          _lastError = LocalTtsService.instance.lastError;
          _speaking = false;
        }
      }
      final tts = await _ensure();
      await tts.stop();
      await _apply(config);
      if (token != _token) return;
      _speaking = true;
      notifyListeners();
      for (final chunk in chunks) {
        if (token != _token) return;
        await tts.speak(chunk);
      }
    } catch (e) {
      _lastError = 'Озвучивание не удалось: $e';
    } finally {
      if (token == _token) {
        _activeText = '';
        _speaking = false;
        notifyListeners();
      }
    }
  }

  Future<void> sample(Config config) async {
    await speak(
      'Привет! Это голос Термая. Я читаю только готовые ответы, '
      'без кода и служебных команд.',
      config,
    );
  }

  Future<void> stop() async {
    _token++;
    try {
      await _tts?.stop();
    } catch (_) {}
    await LocalTtsService.instance.stop();
    _activeText = '';
    _speaking = false;
    notifyListeners();
  }
}

/// sanitizeForSpeech — чистит Markdown, код, JSON, ссылки и tool-вызовы.
/// Возвращает обычный текст, пригодный для произнесения.
String sanitizeForSpeech(String raw) {
  var text = raw;
  text = text.replaceAll(
      RegExp(r'<termai>[\s\S]*?</termai>', caseSensitive: false), ' ');
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  text = text.replaceAll(RegExp(r'~~~[\s\S]*?~~~'), ' ');
  text = text.replaceAll(RegExp(r'`[^`\n]*`'), ' ');
  text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
  text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1) ?? ' ');
  text = text.replaceAll(RegExp(r'https?://\S+'), ' ');
  text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*[\[{].*[\]}]\s*$', multiLine: true), ' ');
  text = text.replaceAll(RegExp(r'[*_~|>]'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Чистый JSON/массив без обычного текста не озвучиваем.
  if (RegExp(r'^\s*[\[{].*[\]}]\s*$', dotAll: true).hasMatch(text)) {
    return '';
  }
  if (!RegExp(r'[A-Za-zА-Яа-яЁё0-9]').hasMatch(text)) return '';
  return text;
}

/// chunkForSpeech — делит длинный ответ на безопасные куски по словам.
List<String> chunkForSpeech(String text, {int maxChars = 420}) {
  final clean = text.trim();
  if (clean.isEmpty) return const [];
  if (clean.length <= maxChars) return [clean];
  final words = clean.split(RegExp(r'\s+'));
  final chunks = <String>[];
  final buffer = StringBuffer();
  for (final word in words) {
    if (buffer.isNotEmpty && buffer.length + 1 + word.length > maxChars) {
      chunks.add(buffer.toString());
      buffer.clear();
    }
    if (word.length > maxChars) {
      var rest = word;
      while (rest.length > maxChars) {
        chunks.add(rest.substring(0, maxChars));
        rest = rest.substring(maxChars);
      }
      if (rest.isNotEmpty) buffer.write(rest);
      continue;
    }
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(word);
  }
  if (buffer.isNotEmpty) chunks.add(buffer.toString());
  return chunks;
}
