// theme.dart — тёмная тема в духе Coddy: графитовый фон, голубой акцент,
// крупные скругления, мягкие подписи.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kBg = Color(0xFF14161A);
const kSurface = Color(0xFF1D2129);
const kCard = Color(0xFF232833);
const kCard2 = Color(0xFF2A2F3A);
const kAccent = Color(0xFF2AA5DC);
const kAccentDark = Color(0xFF1B7FAE);
const kText = Color(0xFFE8EAED);
const kMuted = Color(0xFF8B93A1);
const kGood = Color(0xFF7BC47F);
const kWarn = Color(0xFFE2B34C);
const kDanger = Color(0xFFE5604F);
const kBorder = Color(0xFF2C313C);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(
      primary: kAccent,
      secondary: kAccent,
      surface: kSurface,
      error: kDanger,
    ),
    textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kText,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    dividerColor: kBorder,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kCard2,
      contentTextStyle: TextStyle(color: kText),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      hintStyle: const TextStyle(color: kMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kAccent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccentDark,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: const BorderSide(color: kBorder),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: kBorder, thickness: 1, space: 1),
  );
}
