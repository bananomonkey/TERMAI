// usage.dart — расход токенов и оценка стоимости.
//
// Провайдеры возвращают usage в ответе на запрос; мы складываем вход/выход по
// модели и умножаем на тариф провайдера. Тарифы — публичные прайсы на 1M токенов
// (USD) и они приблизительные: цены меняются, кэш/скидки не учитываются.
// Если модели нет в таблице — показываем токены без цены.

/// (вход $/1M, выход $/1M)
const usagePrices = <String, (double, double)>{
  'deepseek-chat': (0.27, 1.10),
  'deepseek-reasoner': (0.55, 2.19),
  'deepseek/deepseek-chat': (0.27, 1.10),
  'deepseek/deepseek-reasoner': (0.55, 2.19),
  'gpt-4o-mini': (0.15, 0.60),
  'gpt-4o': (2.50, 10.00),
  'gpt-4.1-mini': (0.40, 1.60),
  'gpt-4.1': (2.00, 8.00),
  'o3-mini': (1.10, 4.40),
  'gemini-2.0-flash': (0.10, 0.40),
  'gemini-2.5-flash': (0.30, 2.50),
  'gemini-2.5-pro': (1.25, 10.00),
  'qwen-plus': (0.40, 1.20),
  'qwen-max': (1.60, 6.40),
  'qwen-turbo': (0.05, 0.20),
  'anthropic/claude-3.5-sonnet': (3.00, 15.00),
  'claude-3.5-sonnet': (3.00, 15.00),
  'meta-llama/llama-3.3-70b-instruct': (0.12, 0.30),
  'llama-3.3-70b-versatile': (0.59, 0.79),
  'llama-3.1-8b-instant': (0.05, 0.08),
  'mistral-large-latest': (2.00, 6.00),
  'mistral-small-latest': (0.20, 0.60),
  'yandexgpt-lite': (0.20, 0.20),
  'yandexgpt-pro': (0.60, 0.60),
};

/// priceFor — тариф по имени модели. Совпадение ищем от самого длинного
/// ключа к короткому, чтобы «deepseek-reasoner» не поймал «deepseek-chat».
(double, double)? priceFor(String model) {
  final m = model.trim().toLowerCase();
  if (m.isEmpty) return null;
  final keys = usagePrices.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (m == k || m.contains(k) || k.contains(m)) return usagePrices[k];
  }
  return null;
}

/// costFor — стоимость [prompt] входящих и [completion] исходящих токенов.
/// Возвращает null, если тариф модели неизвестен.
double? costFor(String model, int prompt, int completion) {
  final p = priceFor(model);
  if (p == null) return null;
  return (prompt / 1e6) * p.$1 + (completion / 1e6) * p.$2;
}

/// Оценка окна контекста в токенах, когда провайдер не вернул usage.
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil().clamp(1, 1 << 30);
}

/// money — «$0.0123» / «$1.23» в зависимости от величины.
String money(double usd) {
  if (usd <= 0) return '\$0.00';
  if (usd < 0.01) return '\$${usd.toStringAsFixed(4)}';
  if (usd < 1) return '\$${usd.toStringAsFixed(3)}';
  return '\$${usd.toStringAsFixed(2)}';
}

/// prettyTokens — 12345 → «12 345».
String prettyTokens(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
