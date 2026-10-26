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
    bg: Color(0xFF2C211A),
    surface: Color(0xFF35281F),
    card: Color(0xFF3E3025),
    card2: Color(0xFF493A2D),
    secondary: Color(0xFFC2A487),
    accent: Color(0xFFE08A67),
    accentDark: Color(0xFFC96F4D),
    text: Color(0xFFF3ECE4),
    muted: Color(0xFFBBA897),
    good: Color(0xFFA9C98F),
    warn: Color(0xFFE8B36E),
    danger: Color(0xFFE07D6C),
    border: Color(0xFF5A4636),
    termBg: Color(0xFF1E1712),
    termText: Color(0xFFE0D4C6),
  ),
  // Синий — второй допустимый вариант оформления.
  ThemePreset(
    id: 'navy',
    title: 'Синий',
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
