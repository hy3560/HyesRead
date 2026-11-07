import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// Production palette shared by the app and its visual regression fixtures.
ThemeData hyesReadTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final tokens = dark ? HyesTokens.dark : HyesTokens.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: tokens.vermilion,
    brightness: brightness,
  ).copyWith(
    primary: tokens.vermilion,
    onPrimary: Colors.white,
    surface: tokens.surface,
    onSurface: tokens.ink,
    onSurfaceVariant: tokens.secondary,
    surfaceContainerLowest: tokens.raised,
    surfaceContainerLow: tokens.surface,
    surfaceContainer: tokens.raised,
    outlineVariant: tokens.divider,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [tokens],
    scaffoldBackgroundColor: tokens.background,
    textTheme: TextTheme(
      displayLarge: tokens.display,
      headlineMedium: tokens.title,
      bodyMedium: tokens.body,
      bodySmall: tokens.caption,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.background,
      foregroundColor: tokens.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dividerColor: scheme.outlineVariant,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.76)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(48, 48),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selectedColor: scheme.primaryContainer,
      backgroundColor: scheme.surfaceContainerLow,
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    ),
  );
}
