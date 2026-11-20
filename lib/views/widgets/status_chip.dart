import 'package:flutter/material.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/status_colors.dart';
import '../../models/intake_log.dart';

/// Semantic, accessible status chip representing dose states with both icon and text.
/// Ensures full WCAG accessibility across light, dark, and high-contrast modes.
class StatusChip extends StatelessWidget {
  final DoseStatus status;
  final bool isLowStock;
  final bool compact;

  const StatusChip({
    super.key,
    required this.status,
    this.isLowStock = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusColors = Theme.of(context).extension<StatusColors>();
    final theme = Theme.of(context);

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
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          border: Border.all(
            color: fg.withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 13 : 15, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
