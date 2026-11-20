import 'package:flutter/material.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/status_colors.dart';
import '../../models/intake_log.dart';

/// Accessible badge pairing exact Catppuccin StatusColors with both an Icon and Text label.
/// Ensures full accessibility for color-blind users and high-contrast environments.
class StatusBadge extends StatelessWidget {
  final DoseStatus status;
  final bool isLowStock;

  const StatusBadge({
    super.key,
    required this.status,
    this.isLowStock = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusColors = Theme.of(context).extension<StatusColors>();
    final theme = Theme.of(context);

    // Fallback if extension missing
    final fallbackColors = theme.brightness == Brightness.dark
        ? StatusColors.dark
        : StatusColors.light;
    final colors = statusColors ?? fallbackColors;

    Color bg;
    Color fg;
    IconData icon;
    String label;

    if (isLowStock) {
      bg = colors.lowStock.withValues(alpha: 0.18);
      fg = colors.lowStock;
      icon = Icons.warning_amber_rounded;
      label = AppStrings.statusLowStock;
    } else {
      switch (status) {
        case DoseStatus.taken:
          bg = colors.taken.withValues(alpha: 0.18);
          fg = colors.taken;
          icon = Icons.check_circle_rounded;
          label = AppStrings.statusTaken;
          break;
        case DoseStatus.late:
          bg = colors.late.withValues(alpha: 0.18);
          fg = colors.late;
          icon = Icons.schedule_rounded;
          label = AppStrings.statusLate;
          break;
        case DoseStatus.missed:
          bg = colors.missed.withValues(alpha: 0.18);
          fg = colors.missed;
          icon = Icons.cancel_rounded;
          label = AppStrings.statusMissed;
          break;
        case DoseStatus.skipped:
          bg = colors.skipped.withValues(alpha: 0.18);
          fg = colors.skipped;
          icon = Icons.remove_circle_outline_rounded;
          label = AppStrings.statusSkipped;
          break;
        case DoseStatus.snoozed:
          bg = colors.snoozed.withValues(alpha: 0.18);
          fg = colors.snoozed;
          icon = Icons.snooze_rounded;
          label = AppStrings.statusSnoozed;
          break;
        case DoseStatus.pending:
          bg = theme.colorScheme.surfaceContainerHigh;
          fg = theme.colorScheme.onSurfaceVariant;
          icon = Icons.access_time_rounded;
          label = AppStrings.statusPending;
          break;
      }
    }

    return Semantics(
      label: 'Dose status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: fg.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
