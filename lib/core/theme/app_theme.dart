import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'status_colors.dart';

/// Production ThemeData definitions for RemedyTrack.
/// Built strictly with exact Catppuccin Latte and Mocha ColorSchemes without `ColorScheme.fromSeed`.
class AppTheme {
  const AppTheme._();

  static const ColorScheme latteColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF23648E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDDF2FC),
    onPrimaryContainer: Color(0xFF24445C),
    secondary: Color(0xFF0E747A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFA7D8F0),
    onSecondaryContainer: Color(0xFF24445C),
    tertiary: Color(0xFF3B669E),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFDDF2FC),
    onTertiaryContainer: Color(0xFF24445C),
    error: Color(0xFFC42B2B),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFF4FAFE),
    onSurface: Color(0xFF24445C),
    onSurfaceVariant: Color(0xFF4E6678),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFEAF6FD),
    surfaceContainer: Color(0xFFDDF2FC),
    surfaceContainerHigh: Color(0xFFCBE9F9),
    surfaceContainerHighest: Color(0xFFA7D8F0),
    outline: Color(0xFF567084),
    outlineVariant: Color(0xFFA7D8F0),
  );

  static const ColorScheme mochaColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFA7D8F0),
    onPrimary: Color(0xFF0B1C29),
    primaryContainer: Color(0xFF24445C),
    onPrimaryContainer: Color(0xFFDDF2FC),
    secondary: Color(0xFF94E2D5),
    onSecondary: Color(0xFF0B1C29),
    secondaryContainer: Color(0xFF1C3B52),
    onSecondaryContainer: Color(0xFFDDF2FC),
    tertiary: Color(0xFFCBA6F7),
    onTertiary: Color(0xFF0B1C29),
    tertiaryContainer: Color(0xFF244963),
    onTertiaryContainer: Color(0xFFF4FAFE),
    error: Color(0xFFF38BA8),
    onError: Color(0xFF0B1C29),
    surface: Color(0xFF163247),
    onSurface: Color(0xFFF4FAFE),
    onSurfaceVariant: Color(0xFFDDF2FC),
    surfaceContainerLowest: Color(0xFF0B1C29),
    surfaceContainerLow: Color(0xFF112839),
    surfaceContainer: Color(0xFF1C3B52),
    surfaceContainerHigh: Color(0xFF244963),
    surfaceContainerHighest: Color(0xFF2E5A78),
    outline: Color(0xFF8ECAE6),
    outlineVariant: Color(0xFF2E5A78),
  );

  /// High Contrast ColorScheme overrides for accessibility
  static const ColorScheme highContrastDarkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF89B4FA),
    onPrimary: Color(0xFF000000),
    secondary: Color(0xFF94E2D5),
    onSecondary: Color(0xFF000000),
    tertiary: Color(0xFFCBA6F7),
    onTertiary: Color(0xFF000000),
    error: Color(0xFFF38BA8),
    onError: Color(0xFF000000),
    surface: Color(0xFF11111B), // Crust as dark background
    onSurface: Color(0xFFFFFFFF), // High contrast text
    onSurfaceVariant: Color(0xFFF5E0DC),
    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF11111B),
    surfaceContainer: Color(0xFF181825),
    surfaceContainerHigh: Color(0xFF313244),
    surfaceContainerHighest: Color(0xFF45475A),
    outline: Color(0xFFFFFFFF), // 2dp contrast outline
    outlineVariant: Color(0xFFCDD6F4),
  );

  static ThemeData light({bool isHighContrast = false}) {
    const scheme = latteColorScheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: DesignTokens.createTextTheme(scheme),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: isHighContrast ? 0 : 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
              24), // Soft baby-blue healthcare rounded cards
          side: isHighContrast
              ? BorderSide(color: scheme.outline, width: 2)
              : BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                  width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50), // WCAG touch target
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          elevation: 1,
          shadowColor: scheme.primary.withValues(alpha: 0.25),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          elevation: 1.5,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(
              color: scheme.outline, width: isHighContrast ? 2 : 1.2),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        shape: const StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        elevation: 2,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: const Color(0xFFA7D8F0),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: const Color(0xFFA7D8F0),
        indicatorShape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 4,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)), // M3 Extra-large
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              BorderSide(color: scheme.outline, width: isHighContrast ? 2 : 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: scheme.outlineVariant, width: isHighContrast ? 2 : 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        StatusColors.light,
      ],
    );
  }

  static ThemeData dark({bool isHighContrast = false}) {
    final scheme = isHighContrast ? highContrastDarkScheme : mochaColorScheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: DesignTokens.createTextTheme(scheme),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: isHighContrast ? 0 : 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: isHighContrast
              ? const BorderSide(color: Colors.white, width: 2)
              : BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(
              color: scheme.outline, width: isHighContrast ? 2 : 1.2),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        shape: const StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        elevation: 2,
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.22),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.22),
        indicatorShape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              BorderSide(color: scheme.outline, width: isHighContrast ? 2 : 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: scheme.outlineVariant, width: isHighContrast ? 2 : 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        StatusColors.dark,
      ],
    );
  }
}
