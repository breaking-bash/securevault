import 'package:flutter/material.dart';

const _seed = Color(0xFF0572EC);

ThemeData _base(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  ).copyWith(
    primary: isLight ? const Color(0xFF0572EC) : const Color(0xFF4C9AFF),
    surface: isLight ? const Color(0xFFEFF2F7) : const Color(0xFF050507),
    surfaceContainerHighest:
        isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1F),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    inputDecorationTheme: _inputTheme(scheme),
    // Minimalist flat app bar — large bold titles, no elevation tint.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    // Thin full-width dividers between rows (Bitwarden-style lists).
    dividerTheme: DividerThemeData(
      thickness: 0.6,
      space: 0.6,
      color: scheme.outlineVariant.withValues(alpha: isLight ? 0.6 : 0.5),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      minLeadingWidth: 24,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.22),
      elevation: 3,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      extendedTextStyle:
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      shape: const StadiumBorder(),
    ),
    // Cards are reserved for a few callout surfaces; keep them flat & subtle.
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: scheme.surfaceContainerHighest,
    ),
  );
}

ThemeData buildLightTheme() => _base(Brightness.light);

ThemeData buildDarkTheme() => _base(Brightness.dark);

InputDecorationTheme _inputTheme(ColorScheme scheme) => InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

/// 1Password's violet field-label colour.
Color fieldLabelColor(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark
        ? const Color(0xFFA99BFF)
        : const Color(0xFF5B3FD6);
