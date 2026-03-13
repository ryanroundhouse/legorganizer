import 'package:flutter/material.dart';

abstract final class BrandColors {
  static const Color midnight = Color(0xFF090021);
  static const Color cosmic = Color(0xFF1A0E47);
  static const Color violet = Color(0xFF5B2ECF);
  static const Color magenta = Color(0xFFD74FFF);
  static const Color sunset = Color(0xFFFFD766);
  static const Color glow = Color(0xFFFF7ABD);
  static const Color lavenderSurface = Color(0xFFF5F1FF);
}

ThemeData buildLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: BrandColors.violet,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE2D8FF),
    onPrimaryContainer: Color(0xFF2A116B),
    secondary: BrandColors.magenta,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF7D9FF),
    onSecondaryContainer: Color(0xFF5D1A7A),
    tertiary: BrandColors.sunset,
    onTertiary: Color(0xFF3D2A00),
    tertiaryContainer: Color(0xFFFFECB3),
    onTertiaryContainer: Color(0xFF493400),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: BrandColors.lavenderSurface,
    onSurface: Color(0xFF1E1732),
    onSurfaceVariant: Color(0xFF564D73),
    outline: Color(0xFF837A9D),
    outlineVariant: Color(0xFFD5CCE9),
    shadow: Color(0x29000000),
    scrim: Colors.black54,
    inverseSurface: Color(0xFF322B46),
    onInverseSurface: Color(0xFFF5EEFF),
    inversePrimary: Color(0xFFCDBDFF),
    surfaceContainerHighest: Color(0xFFEDE4FF),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.secondary,
      foregroundColor: scheme.onSecondary,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStatePropertyAll(scheme.secondaryContainer),
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(color: scheme.onSecondaryContainer),
    ),
  );
}

ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFBAA5FF),
    onPrimary: Color(0xFF2A116B),
    primaryContainer: Color(0xFF43208E),
    onPrimaryContainer: Color(0xFFE9DFFF),
    secondary: Color(0xFFFFA5F4),
    onSecondary: Color(0xFF5A145B),
    secondaryContainer: Color(0xFF7A2A7F),
    onSecondaryContainer: Color(0xFFFFD6FA),
    tertiary: Color(0xFFFFD780),
    onTertiary: Color(0xFF493400),
    tertiaryContainer: Color(0xFF6A4F00),
    onTertiaryContainer: Color(0xFFFFECB3),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: BrandColors.midnight,
    onSurface: Color(0xFFECE8FF),
    onSurfaceVariant: Color(0xFFBEB7DA),
    outline: Color(0xFF8A83A5),
    outlineVariant: Color(0xFF3C3557),
    shadow: Colors.black,
    scrim: Colors.black54,
    inverseSurface: Color(0xFFECE8FF),
    onInverseSurface: Color(0xFF29243B),
    inversePrimary: BrandColors.violet,
    surfaceContainerHighest: Color(0xFF2A2341),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: BrandColors.cosmic,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.secondary,
      foregroundColor: scheme.onSecondary,
    ),
    cardTheme: CardThemeData(
      color: Color.alphaBlend(BrandColors.cosmic.withValues(alpha: 0.45), scheme.surface),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStatePropertyAll(scheme.secondaryContainer),
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(color: scheme.onSecondaryContainer),
    ),
  );
}
