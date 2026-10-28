// usage.dart — расход токенов без оценки стоимости.
//
// Провайдеры возвращают usage в ответе на запрос; мы складываем вход/выход
// по моделям. Долларовую оценку намеренно не показываем: тарифы меняются,
// а ручная таблица быстро устаревает.

/// Оценка окна контекста в токенах, когда провайдер не вернул usage.
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil().clamp(1, 1 << 30);
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
