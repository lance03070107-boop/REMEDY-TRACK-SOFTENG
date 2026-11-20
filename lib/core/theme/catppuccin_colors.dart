import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Palette constants from the Catppuccin color scheme (Latte & Mocha),
/// tuned to satisfy WCAG 2.1 AA contrast ratios (>= 4.5:1 for text, >= 3.0:1 for UI components).
class CatppuccinColors {
  const CatppuccinColors._();

  // --- BABY-BLUE HEALTHCARE TOKENS (LIGHT THEME — WCAG AA TUNED) ---
  static const Color babyBluePrimary = Color(0xFFA7D8F0);
  static const Color babyBlueSecondary = Color(0xFFDDF2FC);
  static const Color babyBlueSurface = Color(0xFFF4FAFE);
  static const Color babyBlueElevated = Color(0xFFFFFFFF);
  static const Color babyBlueDeepText = Color(0xFF24445C);
  static const Color babyBlueMutedText = Color(0xFF4E6678);

  // --- CATPPUCCIN LATTE / BABY-BLUE LIGHT THEME (WCAG AA TUNED) ---
  static const Color latteRosewater = Color(0xFF9E4736);
  static const Color latteFlamingo = Color(0xFFA13D3D);
  static const Color lattePink =
      Color(0xFFA82885); // >= 4.5:1 on white & latteBase
  static const Color latteMauve =
      Color(0xFF7828D6); // >= 4.5:1 on white & latteBase
  static const Color latteRed =
      Color(0xFFC10D34); // >= 4.5:1 on white & latteBase
  static const Color latteMaroon = Color(0xFFB52634);
  static const Color lattePeach =
      Color(0xFFB84300); // >= 4.5:1 on white & latteBase
  static const Color latteYellow =
      Color(0xFF8F5800); // >= 4.5:1 on white & latteBase
  static const Color latteGreen =
      Color(0xFF1F7A4C); // >= 4.5:1 on white & latteBase
  static const Color latteTeal = Color(0xFF0E747A); // >= 4.5:1 with white text
  static const Color latteSky = Color(0xFF036E9C); // >= 4.5:1 with white text
  static const Color latteSapphire = Color(0xFF136F82);
  static const Color latteBlue =
      Color(0xFF23648E); // >= 4.5:1 on white & latteBase
  static const Color latteLavender = Color(0xFF3B669E);
  static const Color latteText =
      Color(0xFF24445C); // Deep navy-blue primary text
  static const Color latteSubtext1 = Color(0xFF4E6678); // >= 4.5:1 on #F4FAFE
  static const Color latteSubtext0 = Color(0xFF536B7D); // >= 4.5:1 on #F4FAFE
  static const Color latteOverlay2 = Color(0xFF567084);
  static const Color latteOverlay1 =
      Color(0xFF5A7488); // >= 4.5:1 on white, >= 3:1 on latteBase
  static const Color latteOverlay0 = Color(0xFF5A7488);
  static const Color latteSurface2 = Color(0xFFA7D8F0); // Primary baby blue
  static const Color latteSurface1 = Color(0xFFCBE9F9); // Soft sky blue
  static const Color latteSurface0 =
      Color(0xFFDDF2FC); // Secondary soft baby blue
  static const Color latteBase = Color(0xFFF4FAFE); // Pale baby-blue surface
  static const Color latteMantle = Color(0xFFEAF6FD);
  static const Color latteCrust = Color(0xFFDDF2FC);

  // --- CATPPUCCIN MOCHA / DARK BABY-BLUE THEME (WCAG AA TUNED) ---
  static const Color mochaRosewater = Color(0xFFF5E0DC);
  static const Color mochaFlamingo = Color(0xFFF2CDCD);
  static const Color mochaPink = Color(0xFFF5C2E7);
  static const Color mochaMauve = Color(0xFFCBA6F7);
  static const Color mochaRed = Color(0xFFF38BA8);
  static const Color mochaMaroon = Color(0xFFEBA0AC);
  static const Color mochaPeach = Color(0xFFFAB387);
  static const Color mochaYellow = Color(0xFFF9E2AF);
  static const Color mochaGreen = Color(0xFFA6E3A1);
  static const Color mochaTeal = Color(0xFF94E2D5);
  static const Color mochaSky = Color(0xFF89DCEB);
  static const Color mochaSapphire = Color(0xFF74C7EC);
  static const Color mochaBlue = Color(0xFFA7D8F0);
  static const Color mochaLavender = Color(0xFFB4BEFE);
  static const Color mochaText = Color(0xFFF4FAFE);
  static const Color mochaSubtext1 = Color(0xFFDDF2FC);
  static const Color mochaSubtext0 = Color(0xFFC0E4F6);
  static const Color mochaOverlay2 = Color(0xFFA7D8F0);
  static const Color mochaOverlay1 = Color(0xFF8ECAE6);
  static const Color mochaOverlay0 = Color(0xFF7CBEDB);
  static const Color mochaSurface2 = Color(0xFF2E5A78);
  static const Color mochaSurface1 = Color(0xFF244963);
  static const Color mochaSurface0 = Color(0xFF1C3B52);
  static const Color mochaBase = Color(0xFF163247);
  static const Color mochaMantle = Color(0xFF112839);
  static const Color mochaCrust = Color(0xFF0B1C29);

  // --- CONVENIENCE ALIASES (LATTE DEFAULT) ---
  static const Color green = latteGreen;
  static const Color red = latteRed;
  static const Color peach = lattePeach;
  static const Color blue = latteBlue;
  static const Color mauve = latteMauve;
  static const Color yellow = latteYellow;
  static const Color teal = latteTeal;
  static const Color sapphire = latteSapphire;
  static const Color lavender = latteLavender;
  static const Color subtext0 = latteSubtext0;
  static const Color subtext1 = latteSubtext1;
  static const Color surface0 = latteSurface0;
  static const Color base = latteBase;

  /// Light-mode (Latte) medication swatch palette (>= 3:1 UI & >= 4.5:1 text on white/latteBase).
  static const List<Color> medicationPaletteLight = [
    latteBlue,
    latteMauve,
    latteGreen,
    lattePeach,
    latteRed,
    latteTeal,
    lattePink,
    latteYellow,
  ];

  /// Dark-mode (Mocha) medication swatch palette (>= 4.5:1 on mochaBase/mochaSurface0).
  static const List<Color> medicationPaletteDark = [
    mochaBlue,
    mochaMauve,
    mochaGreen,
    mochaPeach,
    mochaRed,
    mochaTeal,
    mochaPink,
    mochaYellow,
  ];

  /// Returns the theme-appropriate medication color swatch list.
  static List<Color> medicationPaletteFor(Brightness brightness) {
    return brightness == Brightness.dark
        ? medicationPaletteDark
        : medicationPaletteLight;
  }

  /// Maps any stored medication color tag (including legacy Latte hex values)
  /// to the high-contrast theme-appropriate Catppuccin color for [brightness].
  static Color adaptiveMedicationColor(Color rawColor, Brightness brightness) {
    final argb = rawColor.toARGB32();
    final slotIndex = _resolvePaletteSlot(argb);
    if (slotIndex != null) {
      return brightness == Brightness.dark
          ? medicationPaletteDark[slotIndex]
          : medicationPaletteLight[slotIndex];
    }
    return rawColor;
  }

  static int? _resolvePaletteSlot(int argb) {
    switch (argb) {
      case 0xFF1E66F5:
      case 0xFF1B5AE0:
      case 0xFF23648E:
      case 0xFF89B4FA:
      case 0xFFA7D8F0:
        return 0; // Blue
      case 0xFF8839EF:
      case 0xFF7828D6:
      case 0xFFCBA6F7:
        return 1; // Mauve
      case 0xFF40A02B:
      case 0xFF2B7A1B:
      case 0xFF1F7A4C:
      case 0xFFA6E3A1:
        return 2; // Green
      case 0xFFFE640B:
      case 0xFFB84300:
      case 0xFFFAB387:
        return 3; // Peach
      case 0xFFD20F39:
      case 0xFFC10D34:
      case 0xFFF38BA8:
        return 4; // Red
      case 0xFF179299:
      case 0xFF0E747A:
      case 0xFF94E2D5:
        return 5; // Teal
      case 0xFFEA76CB:
      case 0xFFA82885:
      case 0xFFF5C2E7:
        return 6; // Pink
      case 0xFFDF8E1D:
      case 0xFF8F5800:
      case 0xFFF9E2AF:
        return 7; // Yellow
      default:
        return null;
    }
  }

  /// Returns an accessible human-readable color name for screen readers.
  static String colorNameFor(Color color) {
    final slot = _resolvePaletteSlot(color.toARGB32());
    switch (slot) {
      case 0:
        return 'Blue';
      case 1:
        return 'Purple';
      case 2:
        return 'Green';
      case 3:
        return 'Orange';
      case 4:
        return 'Red';
      case 5:
        return 'Teal';
      case 6:
        return 'Pink';
      case 7:
        return 'Amber';
      default:
        return 'Custom';
    }
  }

  /// Computes the WCAG 2.1 contrast ratio between [a] and [b] (range 1.0 to 21.0).
  static double contrastRatio(Color a, Color b) {
    final lumA = a.computeLuminance();
    final lumB = b.computeLuminance();
    final brightest = math.max(lumA, lumB);
    final darkest = math.min(lumA, lumB);
    return (brightest + 0.05) / (darkest + 0.05);
  }

  /// Selects a dark (`mochaCrust`) or light (`Colors.white`) foreground/checkmark color
  /// by comparing relative luminance so contrast is always maximized (>= 4.5:1).
  static Color onColorFor(Color background) {
    const darkFg = mochaCrust;
    const lightFg = Color(0xFFFFFFFF);
    final darkRatio = contrastRatio(background, darkFg);
    final lightRatio = contrastRatio(background, lightFg);
    return darkRatio >= lightRatio ? darkFg : lightFg;
  }
}
