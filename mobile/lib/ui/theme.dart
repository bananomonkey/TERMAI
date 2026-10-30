// theme.dart — палитры 60-30-10 и живая смена темы из настроек.
// 60% фон · 30% поверхности/элементы (secondary) · 10% акцент.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';

class ThemePreset {
  final String id, title;
  final Brightness brightness;
  final Color bg; // 60%
  final Color surface, card, card2, border; // 30%: поверхности
  final Color secondary; // 30%: элементы, префикс терминала, черты ИИ
  final Color accent, accentDark; // 10%: кнопки действия
  final Color text, muted;
  final Color good, warn, danger;
  final Color termBg, termText;
  const ThemePreset({
    required this.id,
    required this.title,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.card,
    required this.card2,
    required this.secondary,
    required this.accent,
    required this.accentDark,
    required this.text,
    required this.muted,
    required this.good,
    required this.warn,
    required this.danger,
    required this.border,
    required this.termBg,
    required this.termText,
  });
}

const themePresets = <ThemePreset>[
  // VS Code Dark Modern: графит + фирменный синий акцент.
  ThemePreset(
    id: 'dark',
    title: 'Dark Modern',
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    surface: Color(0xFF0B0B0B),
    card: Color(0xFF121212),
    card2: Color(0xFF1A1A1A),
    secondary: Color(0xFF569CD6),
    accent: Color(0xFF0078D4),
    accentDark: Color(0xFF0063B1),
    text: Color(0xFFCCCCCC),
    muted: Color(0xFF8C8C8C),
    good: Color(0xFF4EC9B0),
    warn: Color(0xFFDCDCAA),
    danger: Color(0xFFF48771),
    border: Color(0xFF2A2A2A),
    termBg: Color(0xFF050505),
    termText: Color(0xFFCCCCCC),
  ),
  // Синий — второй допустимый вариант оформления.
  ThemePreset(
    id: 'navy',
    title: 'Синий',
    brightness: Brightness.dark,
    bg: Color(0xFF16233D),
    surface: Color(0xFF1D2C4A),
    card: Color(0xFF243553),
    card2: Color(0xFF2C4062),
    secondary: Color(0xFF8FAAD9),
    accent: Color(0xFF5FB0FF),
    accentDark: Color(0xFF3A8EE6),
    text: Color(0xFFECF3FD),
    muted: Color(0xFFA6B8D4),
    good: Color(0xFF4FE0A5),
    warn: Color(0xFFE8B36E),
    danger: Color(0xFFE88492),
    border: Color(0xFF3A5278),
    termBg: Color(0xFF101B2E),
    termText: Color(0xFFC5D5EC),
  ),
  // Светлая — быстрый дневной режим для яркого солнца и светлых помещений.
  ThemePreset(
    id: 'light',
    title: 'Светлая',
    brightness: Brightness.light,
    bg: Color(0xFFF3F5F8),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    card2: Color(0xFFE9EEF5),
    secondary: Color(0xFF3B6EA8),
    accent: Color(0xFF0078D4),
    accentDark: Color(0xFF0063B1),
    text: Color(0xFF1B2430),
    muted: Color(0xFF5C6B7D),
    good: Color(0xFF1F8A5B),
    warn: Color(0xFF9A6B00),
    danger: Color(0xFFC0392B),
    border: Color(0xFFD5DDE8),
    termBg: Color(0xFFF0F3F7),
    termText: Color(0xFF1B2430),
  ),
];

/// Пользовательские палитры, собранные из Config.customThemes.
/// Заполняется контроллером при загрузке/сохранении конфига.
final List<ThemePreset> customThemePresets = [];

ThemePreset presetById(String id) {
  for (final p in customThemePresets) {
    if (p.id == id) return p;
  }
  return themePresets.firstWhere((p) => p.id == id,
      orElse: () => themePresets.first);
}

Color _hexColor(String? raw, Color fallback) {
  if (raw == null) return fallback;
  var s = raw.trim().replaceFirst('#', '');
  if (s.length == 8) s = s.substring(2); // ARGB -> RGB
  if (s.length != 6) return fallback;
  final v = int.tryParse(s, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// presetFromCustom — превращает сохранённую ИИ-палитру в ThemePreset.
ThemePreset presetFromCustom(CustomThemeData data) {
  final darkBase = themePresets.first;
  final lightBase = themePresets.last;
  final bg = _hexColor(data.colors['bg'], darkBase.bg);
  final isLight = (data.colors['brightness'] ?? '').toLowerCase() == 'light' ||
      bg.computeLuminance() > 0.55;
  final base = isLight ? lightBase : darkBase;
  Color fallback(String key) => switch (key) {
        'surface' => base.surface,
        'card' => base.card,
        'card2' => base.card2,
        'secondary' => base.secondary,
        'accent' => base.accent,
        'accentDark' => base.accentDark,
        'text' => base.text,
        'muted' => base.muted,
        'good' => base.good,
        'warn' => base.warn,
        'danger' => base.danger,
        'border' => base.border,
        'termBg' => base.termBg,
        'termText' => base.termText,
        _ => base.bg,
      };
  Color c(String key) => _hexColor(data.colors[key], fallback(key));
  return ThemePreset(
    id: data.id,
    title: data.title,
    brightness: isLight ? Brightness.light : Brightness.dark,
    bg: bg,
    surface: c('surface'),
    card: c('card'),
    card2: c('card2'),
    secondary: c('secondary'),
    accent: c('accent'),
    accentDark: c('accentDark'),
    text: c('text'),
    muted: c('muted'),
    good: c('good'),
    warn: c('warn'),
    danger: c('danger'),
    border: c('border'),
    termBg: c('termBg'),
    termText: c('termText'),
  );
}

/// rebuildCustomThemePresets — вызывается после загрузки/сохранения Config.
void rebuildCustomThemePresets(List<CustomThemeData> themes) {
  customThemePresets
    ..clear()
    ..addAll(themes.where((t) => t.id.isNotEmpty).map(presetFromCustom));
}

/// C — живые цвета: все виджеты читают их отсюда, смена пресета в настройках
/// перекрашивает всё приложение (MaterialApp перестраивается от notifyListeners).
class C {
  static ThemePreset p = themePresets.first;

  /// Яркость кнопок: 1.0 — как в палитре, больше — светлее, меньше — темнее.
  static double buttonBrightness = 1.0;

  static bool get isLight => p.brightness == Brightness.light;
  static Color get bg => p.bg;
  static Color get surface => p.surface;
  static Color get card => p.card;
  static Color get card2 => p.card2;
  static Color get border => p.border;
  static Color get secondary => p.secondary;
  static Color get accent => p.accent;
  static Color get accentDark => p.accentDark;
  static Color get text => p.text;
  static Color get muted => p.muted;
  static Color get good => p.good;
  static Color get warn => p.warn;
  static Color get danger => p.danger;
  static Color get termBg => p.termBg;
  static Color get termText => p.termText;

  /// Отдельные цвета для кнопок и быстрых панелей: ползунок яркости
  /// не должен перекрашивать фоновые секции и текст.
  static Color get button => _tone(p.card, buttonBrightness);
  static Color get button2 => _tone(p.card2, buttonBrightness);
  static Color get buttonBorder => _tone(p.border, buttonBrightness);
  static Color get buttonAccent => _tone(p.accentDark, buttonBrightness);

  static Color _tone(Color base, double value) {
    final delta = (value - 1.0).clamp(-0.5, 0.5);
    if (delta.abs() < 0.001) return base;
    final target = delta > 0 ? Colors.white : Colors.black;
    return Color.lerp(base, target, delta.abs() * 0.7)!;
  }

  /// Свечение активного элемента под карточкой.
  static Color glow({Color? color, int alpha = 70}) =>
      (color ?? p.good).withAlpha(alpha);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: C.p.brightness,
    fontFamily: 'Inter',
  );
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    cardColor: C.card,
    colorScheme: base.colorScheme.copyWith(
      primary: C.accent,
      onPrimary: Colors.white,
      secondary: C.accent,
      surface: C.surface,
      onSurface: C.text,
      error: C.danger,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: C.text,
      displayColor: C.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      systemOverlayStyle:
          C.isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
    ),
    dividerColor: C.border,
    dividerTheme: DividerThemeData(color: C.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.card2,
      contentTextStyle: TextStyle(color: C.text),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.card,
      hintStyle: TextStyle(color: C.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: C.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.accent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.buttonAccent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        side: BorderSide(color: C.buttonBorder),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
