import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand_colors.dart';

/// Material 3 themes for Wetruck apps. Built on top of [BrandColors] so the
/// shipper and transporter apps share an identical visual language.
class WetruckTheme {
  const WetruckTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.primary,
      brightness: Brightness.light,
      primary: BrandColors.primary,
      onPrimary: BrandColors.onPrimary,
      surface: BrandColors.surface,
      onSurface: BrandColors.onSurface,
      error: BrandColors.danger,
    );
    return _base(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.primary,
      brightness: Brightness.dark,
      primary: BrandColors.primaryLight,
      onPrimary: BrandColors.onSurface,
      surface: BrandColors.surfaceDark,
      onSurface: BrandColors.onSurfaceDark,
      error: BrandColors.danger,
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    // Latin-script primary font (Inter — clean, modern, free) plus a Ge'ez-
    // script fallback so Amharic and Tigrinya render correctly. Without the
    // fallback, every Ge'ez glyph shows as a tofu box on Android.
    final textTheme = GoogleFonts.interTextTheme()
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith();
    final String ethiopicFallback =
        GoogleFonts.notoSansEthiopic().fontFamily ?? 'NotoSansEthiopic';
    final mergedTextTheme = textTheme.copyWith(
      // Apply the Ge'ez fallback to every style by re-creating each TextStyle
      // with `fontFamilyFallback`. Flutter falls back per-character.
      bodySmall: textTheme.bodySmall?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      bodyMedium: textTheme.bodyMedium?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      bodyLarge: textTheme.bodyLarge?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      titleSmall: textTheme.titleSmall?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      titleMedium: textTheme.titleMedium?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      titleLarge: textTheme.titleLarge?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      headlineSmall:
          textTheme.headlineSmall?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      headlineMedium:
          textTheme.headlineMedium?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      headlineLarge:
          textTheme.headlineLarge?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      displaySmall:
          textTheme.displaySmall?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      displayMedium:
          textTheme.displayMedium?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      displayLarge:
          textTheme.displayLarge?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      labelSmall: textTheme.labelSmall?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      labelMedium: textTheme.labelMedium?.copyWith(fontFamilyFallback: [ethiopicFallback]),
      labelLarge: textTheme.labelLarge?.copyWith(fontFamilyFallback: [ethiopicFallback]),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: mergedTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        // With `borderSide: none` on the base border, error state has no
        // visible affordance — the field stays the same color and only
        // the helper text turns red. Override the error states with a
        // visible red outline so users actually see which fields are bad.
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BrandColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BrandColors.danger, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
