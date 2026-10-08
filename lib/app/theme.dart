import 'package:flutter/material.dart';

const _seed = Color(0xFF0F766E);

/// Colores semánticos para montos y estados.
class MoneyColors {
  static Color income(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
  static Color expense(BuildContext c) => Theme.of(c).colorScheme.onSurface;
  static Color saving(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
  static Color ok(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF34D399) : const Color(0xFF059669);
  static Color warning(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  static Color danger(BuildContext c) => Theme.of(c).colorScheme.error;
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}
