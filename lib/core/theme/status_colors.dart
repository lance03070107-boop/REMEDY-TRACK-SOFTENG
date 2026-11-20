import 'package:flutter/material.dart';

/// Dose status color tokens adhering to the Catppuccin palette.
/// Never use raw hex or Colors.xxx inside widgets; always consume via
/// `Theme.of(context).extension<StatusColors>()`.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  static StatusColors? of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>();

  const StatusColors({
    required this.taken,
    required this.onTaken,
    required this.late,
    required this.onLate,
    required this.missed,
    required this.onMissed,
    required this.skipped,
    required this.onSkipped,
    required this.snoozed,
    required this.onSnoozed,
    required this.lowStock,
    required this.onLowStock,
  });

  final Color taken;
  final Color onTaken;
  final Color late;
  final Color onLate;
  final Color missed;
  final Color onMissed;
  final Color skipped;
  final Color onSkipped;
  final Color snoozed;
  final Color onSnoozed;
  final Color lowStock;
  final Color onLowStock;

  /// Latte (Light) dose status colors — tuned for >= 4.5:1 WCAG AA contrast
  /// against both `latteBase` (0xFFF4FAFE) and `on*` (0xFFFFFFFF).
  static const StatusColors light = StatusColors(
    taken: Color(0xFF1F7A4C),
    onTaken: Color(0xFFFFFFFF),
    late: Color(0xFF8F5800),
    onLate: Color(0xFFFFFFFF),
    missed: Color(0xFFC42B2B),
    onMissed: Color(0xFFFFFFFF),
    skipped: Color(0xFF4E6678),
    onSkipped: Color(0xFFFFFFFF),
    snoozed: Color(0xFF0A6E9A),
    onSnoozed: Color(0xFFFFFFFF),
    lowStock: Color(
        0xFFB45309), // Accessible amber-peach for low stock, distinct from red
    onLowStock: Color(0xFFFFFFFF),
  );

  /// Mocha (Dark) dose status colors — tuned for >= 4.5:1 WCAG AA contrast
  /// against both `mochaBase` (0xFF163247) and `on*` (0xFF0B1C29).
  static const StatusColors dark = StatusColors(
    taken: Color(0xFFA6E3A1),
    onTaken: Color(0xFF0B1C29),
    late: Color(0xFFF9E2AF),
    onLate: Color(0xFF0B1C29),
    missed: Color(0xFFF38BA8),
    onMissed: Color(0xFF0B1C29),
    skipped: Color(0xFFC0E4F6),
    onSkipped: Color(0xFF0B1C29),
    snoozed: Color(0xFF89DCEB),
    onSnoozed: Color(0xFF0B1C29),
    lowStock: Color(0xFFFAB387), // Peach for low stock, not red
    onLowStock: Color(0xFF0B1C29),
  );

  @override
  StatusColors copyWith({
    Color? taken,
    Color? onTaken,
    Color? late,
    Color? onLate,
    Color? missed,
    Color? onMissed,
    Color? skipped,
    Color? onSkipped,
    Color? snoozed,
    Color? onSnoozed,
    Color? lowStock,
    Color? onLowStock,
  }) {
    return StatusColors(
      taken: taken ?? this.taken,
      onTaken: onTaken ?? this.onTaken,
      late: late ?? this.late,
      onLate: onLate ?? this.onLate,
      missed: missed ?? this.missed,
      onMissed: onMissed ?? this.onMissed,
      skipped: skipped ?? this.skipped,
      onSkipped: onSkipped ?? this.onSkipped,
      snoozed: snoozed ?? this.snoozed,
      onSnoozed: onSnoozed ?? this.onSnoozed,
      lowStock: lowStock ?? this.lowStock,
      onLowStock: onLowStock ?? this.onLowStock,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      taken: Color.lerp(taken, other.taken, t)!,
      onTaken: Color.lerp(onTaken, other.onTaken, t)!,
      late: Color.lerp(late, other.late, t)!,
      onLate: Color.lerp(onLate, other.onLate, t)!,
      missed: Color.lerp(missed, other.missed, t)!,
      onMissed: Color.lerp(onMissed, other.onMissed, t)!,
      skipped: Color.lerp(skipped, other.skipped, t)!,
      onSkipped: Color.lerp(onSkipped, other.onSkipped, t)!,
      snoozed: Color.lerp(snoozed, other.snoozed, t)!,
      onSnoozed: Color.lerp(onSnoozed, other.onSnoozed, t)!,
      lowStock: Color.lerp(lowStock, other.lowStock, t)!,
      onLowStock: Color.lerp(onLowStock, other.onLowStock, t)!,
    );
  }
}
