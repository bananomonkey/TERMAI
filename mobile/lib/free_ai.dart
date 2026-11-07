// free_ai.dart — бесплатный доступ TERMAI через пул ключей z.ai (free-тариф).
//
// Ключи НЕ лежат в репозитории (код открыт): они передаются в сборку через
// --dart-define=TERMAI_ZAI_KEYS=key1,key2,key3,key4 из секретов GitHub Actions.
//
// Балансировка объединяет два уровня. ЛИМИТЫ ПАРАЛЛЕЛИЗМА у z.ai действуют
// НА КАЖДУЮ МОДЕЛЬ ОТДЕЛЬНО в рамках ключа, поэтому полезная ёмкость пула —
// это матрица «ключ × модель». Round-robin по этой матрице распределяет
// нагрузку пользователей: 4 ключа × (GLM-4.5-Flash: 2 слота +
// GLM-4.7-Flash: 1 слот) ≈ 12 одновременных запросов без 429.
// При 429 endpoints помечаются isFree и «остывают» на секунды, а не минуты —
// штатный перебор в AIClient сразу пробует следующий ключ/модель.
import 'models.dart';

class FreeAiPool {
  FreeAiPool._();

  static final FreeAiPool instance = FreeAiPool._();

  static const String baseUrl = 'https://api.z.ai/api/paas/v4';

  /// Бесплатные текстовые модели z.ai с лимитами параллелизма:
  /// glm-4.5-flash — 2 параллельных запроса на ключ,
  /// glm-4.7-flash — 1 запрос на ключ. Слоты считаются на модель отдельно.
  static const List<String> models = ['glm-4.5-flash', 'glm-4.7-flash'];

  // ВАЖНО: String.fromEnvironment возвращает значение dart-define только
  // внутри const-выражения. В static final без const компилятор подставляет
  // пустую строку — из-за этого пул был «не задан» даже с секретом в CI.
  static const String _keysRaw = String.fromEnvironment('TERMAI_ZAI_KEYS');
  static final List<String> keys =
      _keysRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  int _cursor = 0;

  bool get configured => keys.isNotEmpty;

  /// rotate — endpoints по всей матрице «ключ × модель». Порядок идёт
  /// сначала ПО КЛЮЧАМ внутри модели: одинаковые модели разных ключей
  /// встречаются реже — параллельные запросы с разных устройств почти
  /// всегда попадают в разные ключи, а уже потом в разные модели.
  List<AiEndpoint> rotate() {
    if (keys.isEmpty) return const [];
    final n = keys.length;
    final out = <AiEndpoint>[];
    for (final model in models) {
      for (var i = 0; i < n; i++) {
        out.add(AiEndpoint(
          provider: 'zai',
          apiKey: keys[(_cursor + i) % n],
          model: model,
          baseUrl: baseUrl,
          isFree: true,
        ));
      }
    }
    // Следующий вызов начинает с другого ключа: у 4 пользователей запросы
    // уходят на 4 разных ключа, у большего числа — в разные модели.
    _cursor = (_cursor + 1) % n;
    return out;
  }
}
