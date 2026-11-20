import 'package:flutter/material.dart';
import 'catppuccin_colors.dart';

/// Centralized design tokens for RemedyTrack UI/UX.
/// Enforces WCAG AA compliance (48dp min touch targets), predictable spacing scales,
/// ergonomic corner radii, and accessible high-contrast text sizing.
class DesignTokens {
  const DesignTokens._();

  /// Returns the theme-appropriate medication color swatch list.
  static List<Color> medicationPaletteFor(Brightness brightness) =>
      CatppuccinColors.medicationPaletteFor(brightness);

  /// Maps any stored medication color tag to a high-contrast theme-appropriate color.
  static Color adaptiveMedicationColor(Color rawColor, Brightness brightness) =>
      CatppuccinColors.adaptiveMedicationColor(rawColor, brightness);

  /// Selects a high-contrast foreground color (>= 4.5:1) for [background].
  static Color onColorFor(Color background) =>
      CatppuccinColors.onColorFor(background);

  /// Returns an accessible human-readable color name for screen readers.
  static String colorNameFor(Color color) =>
      CatppuccinColors.colorNameFor(color);

  // --- SPACING SCALE (4dp grid) ---
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 20.0;
  static const double spaceXxl = 24.0;
  static const double spaceSection = 32.0;
  static const double spaceHuge = 48.0;

  // --- CORNER RADII ---
  static const double radiusSmValue = 10.0;
  static const double radiusMdValue = 14.0;
  static const double radiusCardValue = 20.0;
  static const double radiusContainerValue = 24.0;
  static const double radiusPillValue = 999.0;

  static final BorderRadius radiusSm = BorderRadius.circular(radiusSmValue);
  static final BorderRadius radiusMd = BorderRadius.circular(radiusMdValue);
  static final BorderRadius radiusCard = BorderRadius.circular(radiusCardValue);
  static final BorderRadius radiusContainer =
      BorderRadius.circular(radiusContainerValue);
  static final BorderRadius radiusPill = BorderRadius.circular(radiusPillValue);

  // --- ACCESSIBILITY TOUCH TARGETS ---
  /// Minimum 48x48dp interactive touch target size mandated by WCAG AA & thesis specifications.
  static const double minTouchTarget = 48.0;

  // --- ANIMATIONS & MOTION ---
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Curve curveSpring = Curves.easeOutCubic;
  static const Curve curveEnter = Curves.easeOutBack;

  // --- TYPOGRAPHY SCALE ---
  /// Generates a unified TextTheme with Outfit display styles and Plus Jakarta Sans body styles.
  static TextTheme createTextTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 57,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
        color: scheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 45,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        color: scheme.onSurface,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: scheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        height: 1.5,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        height: 1.45,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: scheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
