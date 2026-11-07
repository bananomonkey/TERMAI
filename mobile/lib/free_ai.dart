// free_ai.dart — бесплатный доступ TERMAI через пул ключей z.ai (free-тариф).
//
// Ключи НЕ лежат в репозитории (код открыт): они передаются в сборку через
// --dart-define=TERMAI_ZAI_KEYS=key1,key2,key3 из секретов GitHub Actions.
// Round-robin: каждый вызов начинает перебор со следующего ключа, поэтому
// нагрузка пользователей распределяется по ключам статистически равномерно.
// При 429 штатный перебор endpoints в AIClient автоматически переходит на
// следующий ключ (penalty-механизм), так что лимит одного ключа не роняет
// запрос.
import 'models.dart';

class FreeAiPool {
  FreeAiPool._();

  static final FreeAiPool instance = FreeAiPool._();

  static const String baseUrl = 'https://api.z.ai/api/paas/v4';

  /// Бесплатные модели z.ai: 4.5-flash — основной free-тариф,
  /// glm-4-flash — запасной (старее, но тоже бесплатный).
  static const List<String> models = ['glm-4.5-flash', 'glm-4-flash'];

  static final List<String> keys = String.fromEnvironment('TERMAI_ZAI_KEYS')
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  int _cursor = 0;

  bool get configured => keys.isNotEmpty;

  /// rotate — endpoints по всем ключам и моделям, начиная с ротационного
  /// курсора: первый запрос уходит на ключ N, следующий на N+1 и т.д.
  List<AiEndpoint> rotate() {
    if (keys.isEmpty) return const [];
    final n = keys.length;
    final out = <AiEndpoint>[];
    for (var i = 0; i < n; i++) {
      final key = keys[(_cursor + i) % n];
      for (final model in models) {
        out.add(AiEndpoint(
          provider: 'zai',
          apiKey: key,
          model: model,
          baseUrl: baseUrl,
        ));
      }
    }
    _cursor = (_cursor + 1) % n;
    return out;
  }
}
