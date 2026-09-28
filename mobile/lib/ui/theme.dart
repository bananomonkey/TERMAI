// theme.dart — палитры 60-30-10 и живая смена темы из настроек.
// 60% фон · 30% поверхности/элементы (secondary) · 10% акцент.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThemePreset {
  final String id, title;
  final Color bg;        // 60%
  final Color surface, card, card2, border; // 30%: поверхности
  final Color secondary; // 30%: элементы, префикс терминала, черты ИИ
  final Color accent, accentDark; // 10%: кнопки действия
  final Color text, muted;
  final Color good, warn, danger;
  final Color termBg, termText;
  const ThemePreset({
    required this.id, required this.title,
    required this.bg, required this.surface, required this.card, required this.card2,
    required this.secondary, required this.accent, required this.accentDark,
    required this.text, required this.muted, required this.good, required this.warn,
    required this.danger, required this.border, required this.termBg, required this.termText,
  });
}

const themePresets = <ThemePreset>[
  // Приятный зелёный — «приложение-эко»
  ThemePreset(
    id: 'emerald', title: 'Изумруд',
    bg: Color(0xFF121A15), surface: Color(0xFF19241D), card: Color(0xFF1F2C24), card2: Color(0xFF26352B),
    secondary: Color(0xFF6FA287), accent: Color(0xFF7FD1A7), accentDark: Color(0xFF5FB087),
    text: Color(0xFFE3EEE7), muted: Color(0xFF8AA396), good: Color(0xFF7FD1A7), warn: Color(0xFFD9C36B),
    danger: Color(0xFFE08A7A), border: Color(0xFF2A3A31), termBg: Color(0xFF0E1511), termText: Color(0xFFBFD8C8),
  ),
  // Классическая тёмная консоль
  ThemePreset(
    id: 'matrix', title: 'Матрица',
    bg: Color(0xFF0B0E0B), surface: Color(0xFF111611), card: Color(0xFF151C15), card2: Color(0xFF1B241B),
    secondary: Color(0xFF4C6B4C), accent: Color(0xFF89D185), accentDark: Color(0xFF6FB46C),
    text: Color(0xFFDCE8DC), muted: Color(0xFF7C8F7C), good: Color(0xFF89D185), warn: Color(0xFFD6C08A),
    danger: Color(0xFFE08A7A), border: Color(0xFF202A20), termBg: Color(0xFF070907), termText: Color(0xFFA8D8A8),
  ),
  // Фирменный синий Docker — фон с синим подтоном
  ThemePreset(
    id: 'docker', title: 'Голубой Docker',
    bg: Color(0xFF16202B), surface: Color(0xFF1C2836), card: Color(0xFF223040), card2: Color(0xFF293A4D),
    secondary: Color(0xFF5E81AC), accent: Color(0xFF0DB7ED), accentDark: Color(0xFF0B99C6),
    text: Color(0xFFE4EBF2), muted: Color(0xFF8595A6), good: Color(0xFF7FBFA0), warn: Color(0xFFE2B34C),
    danger: Color(0xFFE06C75), border: Color(0xFF2C3A4A), termBg: Color(0xFF101820), termText: Color(0xFFABB2BF),
  ),
  // Чёрный + синий — как в редакторах кода
  ThemePreset(
    id: 'coding', title: 'Тёмный кодинг',
    bg: Color(0xFF0D1117), surface: Color(0xFF161B22), card: Color(0xFF1C2128), card2: Color(0xFF22272E),
    secondary: Color(0xFF8B949E), accent: Color(0xFF58A6FF), accentDark: Color(0xFF3F8FE8),
    text: Color(0xFFE6EDF3), muted: Color(0xFF7D8590), good: Color(0xFF3FB950), warn: Color(0xFFD29922),
    danger: Color(0xFFE06C75), border: Color(0xFF30363D), termBg: Color(0xFF0A0D12), termText: Color(0xFFABB2BF),
  ),
  // Тёплый бизнес: коричневый + бежевый + терракота
  ThemePreset(
    id: 'cocoa', title: 'Какао',
    bg: Color(0xFF1B1713), surface: Color(0xFF241F1A), card: Color(0xFF2B2520), card2: Color(0xFF332C25),
    secondary: Color(0xFFA78B6F), accent: Color(0xFFD97757), accentDark: Color(0xFFC05F42),
    text: Color(0xFFEDE6DE), muted: Color(0xFF9C9083), good: Color(0xFFA3BE8C), warn: Color(0xFFD9A05B),
    danger: Color(0xFFCF6A5A), border: Color(0xFF3A322A), termBg: Color(0xFF15110E), termText: Color(0xFFD6CCC0),
  ),
];

ThemePreset presetById(String id) =>
    themePresets.firstWhere((p) => p.id == id, orElse: () => themePresets.first);

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
