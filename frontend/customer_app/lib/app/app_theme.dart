import 'package:flutter/material.dart';

import 'design_system/design_system.dart';

abstract final class AppTheme {
  static const navy = AppPalette.navy500;

  static ThemeData build(
    Brightness brightness, {
    Locale locale = const Locale('en'),
  }) {
    final colors = AppColors.forBrightness(brightness);
    final typography = AppTypography.forLocale(locale);
    final dark = brightness == Brightness.dark;
    // Explicit roles preserve the source palette instead of generating new hues.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary500,
      onPrimary: colors.accent700,
      primaryContainer: dark ? colors.primary700 : colors.primary100,
      onPrimaryContainer: dark ? colors.primary50 : colors.primary700,
      secondary: colors.accent500,
      onSecondary: AppPalette.neutralLightBackground,
      secondaryContainer: dark ? colors.accent600 : colors.accent100,
      onSecondaryContainer: dark ? colors.accent50 : colors.accent700,
      tertiary: colors.info,
      onTertiary: AppPalette.neutralLightBackground,
      tertiaryContainer: colors.infoMuted,
      onTertiaryContainer: colors.accent700,
      error: colors.error,
      onError: AppPalette.neutralLightBackground,
      errorContainer: colors.errorMuted,
      onErrorContainer: colors.error,
      surface: colors.surface,
      onSurface: colors.foreground,
      onSurfaceVariant: colors.disabledBackground,
      outline: colors.disabledBackground,
      outlineVariant: colors.border,
      surfaceContainerLowest: colors.background,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.accent,
      surfaceContainerHighest: colors.disabled,
      inverseSurface: dark ? AppColors.light.surface : AppColors.dark.surface,
      onInverseSurface: dark
          ? AppColors.light.foreground
          : AppColors.dark.foreground,
      inversePrimary: dark ? colors.primary700 : colors.primary200,
      surfaceTint: Colors.transparent,
    );
    final textTheme = typography.textTheme.apply(
      bodyColor: colors.foreground,
      displayColor: colors.foreground,
    );
    final actionColor = dark ? colors.primary400 : colors.primary700;
    return ThemeData(
      useMaterial3: true,
      // Keep Figma component geometry identical on web and mobile.
      visualDensity: VisualDensity.standard,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      disabledColor: colors.disabledBackground,
      dividerColor: colors.border,
      fontFamily: typography.body.fontFamily,
      fontFamilyFallback: AppTypography.fallbackFamilies,
      textTheme: textTheme,
      extensions: [colors, typography],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: actionColor, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: colors.disabled,
          disabledForegroundColor: colors.disabledBackground,
          textStyle: typography.button,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: actionColor,
          textStyle: typography.button,
          minimumSize: const Size(48, 48),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}
