import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/time_formatter.dart';
import '../../core/validation/medication_validator.dart';
import '../../models/intake_log.dart';
import '../../models/medication.dart';
import '../../viewmodels/settings_viewmodel.dart';
import 'pill_avatar.dart';
import 'status_chip.dart';

/// Ergonomic, high-contrast dose card for daily scheduled and As-Needed medications.
/// Guarantees WCAG AA compliance with minimum 48dp touch targets on all buttons,
/// clear visual hierarchy, and tactile feedback.
class DoseCard extends StatelessWidget {
  final Medication medication;
  final DateTime scheduledTime;
  final DoseStatus status;
  final IntakeLog? log;
  final VoidCallback? onTake;
  final VoidCallback? onSnooze;
  final VoidCallback? onSkip;
  final VoidCallback? onUndo;
  final VoidCallback? onLateCorrection;
  final bool showActions;
  final double? stockCount;
  final bool isLowStock;

  const DoseCard({
    super.key,
    required this.medication,
    required this.scheduledTime,
    required this.status,
    this.log,
    this.onTake,
    this.onSnooze,
    this.onSkip,
    this.onUndo,
    this.onLateCorrection,
    this.showActions = false,
    this.stockCount,
    this.isLowStock = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>() ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);
    final settingsVm = context.watch<SettingsViewModel?>();
    final is24h = settingsVm?.is24HourFormat ?? false;
    final timeStr = TimeFormatter.formatTime(scheduledTime, is24Hour: is24h);
    final isTaken = status == DoseStatus.taken || status == DoseStatus.late;
    final isActionable =
        status == DoseStatus.pending || status == DoseStatus.snoozed;

    return Container(
      margin: const EdgeInsets.only(bottom: DesignTokens.spaceMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: DesignTokens.radiusCard,
        border: Border.all(
          color: isTaken
              ? statusColors.taken.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Row: Scheduled Time + Compact Stock Badge + Status Chip
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.7),
                    borderRadius: DesignTokens.radiusPill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        timeStr,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (stockCount != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: isLowStock
                              ? statusColors.lowStock.withValues(alpha: 0.16)
                              : theme.colorScheme.surfaceContainer,
                          borderRadius: DesignTokens.radiusPill,
                        ),
                        child: Text(
                          '${MedicationValidator.formatCompactStockCount(stockCount!)} left',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isLowStock
                                ? statusColors.lowStock
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    StatusChip(status: status, compact: true),
                  ],
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceMd),

            // Middle: Pill Avatar + Medication Details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PillAvatar.fromMedication(
                  medication: medication,
                  size: 52,
                  isTaken: isTaken,
                  showBadge: true,
                ),
                const SizedBox(width: DesignTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medication.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${MedicationValidator.formatDoseWithUnit(medication.doseAmount, medication.form)} • ${medication.strength}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (medication.instructions.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 13,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  medication.instructions.trim(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // Bottom Actions Row (Always >= 48dp height touch targets when enabled)
            if (showActions && isActionable) ...[
              const SizedBox(height: DesignTokens.spaceLg),
              Row(
                children: [
                  // Primary "Take" Button (Floating Pill)
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: DesignTokens.minTouchTarget,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: statusColors.taken,
                          foregroundColor:
                              DesignTokens.onColorFor(statusColors.taken),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          elevation: 1,
                        ),
                        onPressed: onTake != null
                            ? () {
                                HapticFeedback.lightImpact();
                                onTake!();
                              }
                            : null,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Take Dose',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),

                  // Snooze Button (10 min)
                  SizedBox(
                    height: DesignTokens.minTouchTarget,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: onSnooze != null
                          ? () {
                              HapticFeedback.lightImpact();
                              onSnooze!();
                            }
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.snooze_rounded, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${settingsVm?.snoozeMinutes ?? 10}m',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),

                  // Skip Button
                  SizedBox(
                    height: DesignTokens.minTouchTarget,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: onSkip != null
                          ? () {
                              HapticFeedback.lightImpact();
                              onSkip!();
                            }
                          : null,
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
            ] else if (isTaken) ...[
              const SizedBox(height: DesignTokens.spaceLg),
              // Taken Confirmation Row with Undo Option
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: statusColors.taken,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            log?.recordedTime != null
                                ? 'Taken at ${TimeFormatter.formatTime(log!.recordedTime!, is24Hour: is24h)}'
                                : 'Recorded as Taken',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: statusColors.taken,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onUndo != null)
                    SizedBox(
                      height: DesignTokens.minTouchTarget,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.outline,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onUndo!();
                        },
                        icon: const Icon(Icons.undo_rounded, size: 16),
                        label:
                            const Text('Undo', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ] else if (status == DoseStatus.missed) ...[
              // Missed Dose Row with Late Confirmation Option
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.cancel_rounded,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Missed dose',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onLateCorrection != null)
                    SizedBox(
                      height: DesignTokens.minTouchTarget,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onLateCorrection!();
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded,
                            size: 16),
                        label: const Text('I took this',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ] else if (status == DoseStatus.skipped) ...[
              Row(
                children: [
                  Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (log?.notes != null &&
                              log!.notes!.isNotEmpty &&
                              !log!.notes!.startsWith('Skipped via '))
                          ? 'Skipped: ${log!.notes}'
                          : 'Skipped',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
