// theme.dart — палитры 60-30-10 и живая смена темы из настроек.
// 60% фон · 30% поверхности/элементы (secondary) · 10% акцент.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThemePreset {
  final String id, title;
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
  // Тёплый бизнес: коричневый + бежевый + терракота — основная тема.
  ThemePreset(
    id: 'cocoa',
    title: 'Какао',
    bg: Color(0xFF1B1713),
    surface: Color(0xFF241F1A),
    card: Color(0xFF2B2520),
    card2: Color(0xFF332C25),
    secondary: Color(0xFFA78B6F),
    accent: Color(0xFFD97757),
    accentDark: Color(0xFFC05F42),
    text: Color(0xFFEDE6DE),
    muted: Color(0xFF9C9083),
    good: Color(0xFFA3BE8C),
    warn: Color(0xFFD9A05B),
    danger: Color(0xFFCF6A5A),
    border: Color(0xFF3A322A),
    termBg: Color(0xFF15110E),
    termText: Color(0xFFD6CCC0),
  ),
  // Синий — второй допустимый вариант оформления.
  ThemePreset(
    id: 'navy',
    title: 'Синий',
    bg: Color(0xFF0A1226),
    surface: Color(0xFF101A33),
    card: Color(0xFF16213F),
    card2: Color(0xFF1D2A4C),
    secondary: Color(0xFF6E8BC4),
    accent: Color(0xFF4DA3FF),
    accentDark: Color(0xFF2E86E0),
    text: Color(0xFFE6EDF8),
    muted: Color(0xFF8296B8),
    good: Color(0xFF3FD69A),
    warn: Color(0xFFE5B567),
    danger: Color(0xFFE0707F),
    border: Color(0xFF223158),
    termBg: Color(0xFF070E1F),
    termText: Color(0xFFB9C9E4),
  ),
];

ThemePreset presetById(String id) => themePresets.firstWhere((p) => p.id == id,
    orElse: () => themePresets.first);

/// C — живые цвета: все виджеты читают их отсюда, смена пресета в настройках
/// перекрашивает всё приложение (MaterialApp перестраивается от notifyListeners).
class C {
  static ThemePreset p = themePresets.first;
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

  /// Свечение активного элемента под карточкой.
  static Color glow({Color? color, int alpha = 70}) =>
      (color ?? p.good).withAlpha(alpha);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: C.accent,
      secondary: C.accent,
      surface: C.surface,
      error: C.danger,
    ),
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
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
        backgroundColor: C.accentDark,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        side: BorderSide(color: C.border),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
