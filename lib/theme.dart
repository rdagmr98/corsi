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

const kBg = Color(0xFF0D1B2A); // palette navy di AVES Tecnici
const kSurface = Color(0xFF152234);
const kCard = Color(0xFF1A2E44);
const kPrimary = Color(0xFF3B82F6);
const kAccent = Color(0xFF10B981);
const kWarning = Color(0xFFF59E0B);
const kError = Color(0xFFEF4444);
const kText = Color(0xFFECEFF1);
const kTextDim = Color(0xFF8FA3B5);
const kBorder = Color(0xFF263850);

ThemeData buildTheme() => ThemeData.dark().copyWith(
  scaffoldBackgroundColor: kBg,
  colorScheme: const ColorScheme.dark(
    primary: kPrimary,
    secondary: kAccent,
    surface: kSurface,
    error: kError,
    // Pillola di NavigationRail e chip selezionati: blu tenue, non verde.
    secondaryContainer: Color(0xFF1E3F66),
    onSecondaryContainer: kText,
    outline: kBorder,
  ),
  cardColor: kCard,
  dividerColor: kBorder,
  cardTheme: CardThemeData(
    color: kCard,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: kBorder),
    ),
  ),
  navigationRailTheme: NavigationRailThemeData(
    indicatorColor: kPrimary.withValues(alpha: 0.18),
    indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  dividerTheme: const DividerThemeData(color: kBorder, thickness: 0.8),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: kText, fontSize: 15),
    bodyMedium: TextStyle(color: kText, fontSize: 14),
    bodySmall: TextStyle(color: kTextDim, fontSize: 12),
    titleLarge: TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 22),
    titleMedium: TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 17),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF183148),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF39C5FF), width: 1.6),
    ),
    labelStyle: const TextStyle(color: kTextDim),
    hintStyle: const TextStyle(color: kTextDim),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kPrimary,
      side: const BorderSide(color: kPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kSurface,
    foregroundColor: kText,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  chipTheme: ChipThemeData(
    backgroundColor: kCard,
    labelStyle: const TextStyle(color: kText, fontSize: 12),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    side: const BorderSide(color: kBorder),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: kCard,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: kBorder),
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: kSurface,
    surfaceTintColor: Colors.transparent,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: kCard,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: kBorder),
    ),
    titleTextStyle: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w600),
    contentTextStyle: const TextStyle(color: kText, fontSize: 14),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: kCard,
    contentTextStyle: const TextStyle(color: kText, fontSize: 13),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: kBorder),
    ),
    insetPadding: const EdgeInsets.all(16),
  ),
);

/// Barra progresso bicolore: teoria (kPrimary) + pratica (kAccent) + residuo (kSurface).
Widget splitBar(double pT, double pP, {double height = 4}) => ClipRRect(
  borderRadius: BorderRadius.circular(height / 2),
  child: SizedBox(
    height: height,
    child: LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      final wT = w * pT.clamp(0.0, 1.0);
      final wP = w * pP.clamp(0.0, (1.0 - pT.clamp(0.0, 1.0)));
      return Row(children: [
        if (wT > 0) Container(width: wT, color: kPrimary),
        if (wP > 0) Container(width: wP, color: kAccent),
        Expanded(child: Container(color: kSurface)),
      ]);
    }),
  ),
);
