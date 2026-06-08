import 'package:flutter/material.dart';

const _moduleOrder = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17, 50, 51, 53, 54];
const _modulePalette = [
  Color(0xFF6366F1), Color(0xFF3B82F6), Color(0xFF06B6D4), Color(0xFF14B8A6),
  Color(0xFF22C55E), Color(0xFF84CC16), Color(0xFFF59E0B), Color(0xFFF97316),
  Color(0xFFEF4444), Color(0xFFEC4899), Color(0xFFA855F7), Color(0xFF8B5CF6),
  Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFD97706), Color(0xFF64748B),
  Color(0xFF78716C), Color(0xFF854D0E), Color(0xFF166534),
];

Color moduleColor(int moduleNumber) {
  final idx = _moduleOrder.indexOf(moduleNumber);
  if (idx < 0) return const Color(0xFF6B7280);
  return _modulePalette[idx];
}

const kBg = Color(0xFF0A0F1E);
const kSurface = Color(0xFF111827);
const kCard = Color(0xFF1A2235);
const kPrimary = Color(0xFF3B82F6);
const kAccent = Color(0xFF10B981);
const kWarning = Color(0xFFF59E0B);
const kError = Color(0xFFEF4444);
const kText = Color(0xFFE5E7EB);
const kTextDim = Color(0xFF6B7280);
const kBorder = Color(0xFF1F2937);

ThemeData buildTheme() => ThemeData.dark().copyWith(
  scaffoldBackgroundColor: kBg,
  colorScheme: const ColorScheme.dark(
    primary: kPrimary,
    secondary: kAccent,
    surface: kSurface,
    error: kError,
  ),
  cardColor: kCard,
  dividerColor: kBorder,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: kText, fontSize: 15),
    bodyMedium: TextStyle(color: kText, fontSize: 14),
    bodySmall: TextStyle(color: kTextDim, fontSize: 12),
    titleLarge: TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 22),
    titleMedium: TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 17),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: kPrimary),
    ),
    labelStyle: const TextStyle(color: kTextDim),
    hintStyle: const TextStyle(color: kTextDim),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kPrimary,
      side: const BorderSide(color: kPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kSurface,
    foregroundColor: kText,
    elevation: 0,
  ),
  chipTheme: const ChipThemeData(
    backgroundColor: kCard,
    labelStyle: TextStyle(color: kText, fontSize: 12),
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  ),
);
