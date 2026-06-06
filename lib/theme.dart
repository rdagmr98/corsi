import 'package:flutter/material.dart';

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
    bodyLarge: TextStyle(color: kText),
    bodyMedium: TextStyle(color: kText),
    bodySmall: TextStyle(color: kTextDim),
    titleLarge: TextStyle(color: kText, fontWeight: FontWeight.bold),
    titleMedium: TextStyle(color: kText, fontWeight: FontWeight.w600),
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
