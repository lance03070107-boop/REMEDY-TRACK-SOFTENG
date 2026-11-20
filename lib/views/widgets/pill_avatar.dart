import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/status_colors.dart';
import '../../models/medication.dart';

/// Ergonomic, high-contrast avatar representing medication dosage forms with vector geometry.
/// Provides instant visual identification across dosage forms (tablet, capsule, syrup, etc.)
/// and supports semantic accessibility tags.
class PillAvatar extends StatelessWidget {
  final MedicationForm form;
  final Color color;
  final double size;
  final bool isTaken;
  final bool showBadge;

  const PillAvatar({
    super.key,
    required this.form,
    required this.color,
    this.size = 48.0,
    this.isTaken = false,
    this.showBadge = false,
  });

  /// Returns the bundled custom asset icon path for [form].
  static String assetPathForForm(MedicationForm form) =>
      'assets/branding/med_forms/${form.name}.png';

  factory PillAvatar.fromMedication({
    Key? key,
    required Medication medication,
    double size = 48.0,
    bool isTaken = false,
    bool showBadge = false,
  }) {
    return PillAvatar(
      key: key,
      form: medication.form,
      color: Color(medication.colorTag),
      size: size,
      isTaken: isTaken,
      showBadge: showBadge,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>() ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);
    final effectiveColor =
        DesignTokens.adaptiveMedicationColor(color, theme.brightness);
    final effectiveSize = size.clamp(28.0, 120.0);
    final iconSize = effectiveSize * 0.52;

    return Semantics(
      label: '${form.name} medication avatar${isTaken ? ", taken" : ""}',
      image: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: effectiveSize,
            height: effectiveSize,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.16),
              borderRadius: _getBorderRadius(effectiveSize),
              border: Border.all(
                color: effectiveColor.withValues(alpha: 0.85),
                width: effectiveSize > 56 ? 2.5 : 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: effectiveColor.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: _buildFormVisual(iconSize, effectiveColor),
            ),
          ),
          if (showBadge && isTaken)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: effectiveSize * 0.38,
                height: effectiveSize * 0.38,
                decoration: BoxDecoration(
                  color: statusColors.taken,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: effectiveSize * 0.24,
                  color: statusColors.onTaken,
                ),
              ),
            ),
        ],
      ),
    );
  }

  BorderRadius _getBorderRadius(double s) {
    switch (form) {
      case MedicationForm.capsule:
        return BorderRadius.circular(s * 0.5);
      case MedicationForm.tablet:
        return BorderRadius.circular(s * 0.4);
      case MedicationForm.syrup:
        return BorderRadius.circular(s * 0.3);
      case MedicationForm.inhaler:
        return BorderRadius.circular(s * 0.25);
      case MedicationForm.drops:
        return BorderRadius.circular(s * 0.45);
      case MedicationForm.injection:
        return BorderRadius.circular(s * 0.3);
      case MedicationForm.topical:
        return BorderRadius.circular(s * 0.28);
    }
  }

  Widget _buildFormVisual(double iconSize, Color effectiveColor) {
    final assetSize = (iconSize * 1.42).clamp(20.0, 96.0);
    return Image.asset(
      assetPathForForm(form),
      width: assetSize,
      height: assetSize,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _buildFallbackIcon(iconSize, effectiveColor),
    );
  }

  Widget _buildFallbackIcon(double iconSize, Color effectiveColor) {
    switch (form) {
      case MedicationForm.tablet:
        return Icon(
          Icons.circle_outlined,
          size: iconSize,
          color: effectiveColor,
        );
      case MedicationForm.capsule:
        return Icon(
          Icons.medication_rounded,
          size: iconSize,
          color: effectiveColor,
        );
      case MedicationForm.syrup:
        return Icon(
          Icons.liquor_rounded,
          size: iconSize,
          color: effectiveColor,
        );
      case MedicationForm.inhaler:
        return Icon(
          Icons.air_rounded,
          size: iconSize,
          color: effectiveColor,
        );
      case MedicationForm.drops:
        return Icon(
          Icons.water_drop_rounded,
          size: iconSize,
          color: effectiveColor,
        );
      case MedicationForm.injection:
        return Icon(
          Icons.vaccines_rounded,
          size: iconSize,
          color: effectiveColor,
        );
      case MedicationForm.topical:
        return Icon(
          Icons.clean_hands_rounded,
          size: iconSize,
          color: effectiveColor,
        );
    }
  }
}
