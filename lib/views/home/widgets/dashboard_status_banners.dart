import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/status_colors.dart';
import '../../../core/validation/medication_validator.dart';
import '../../../services/alarm_scheduler.dart';
import '../../../viewmodels/inventory_viewmodel.dart';

/// Top status banners for [DashboardView]:
/// alarm readiness banner and low-stock refill alert.
class DashboardStatusBanners extends StatelessWidget {
  const DashboardStatusBanners({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kIsWeb)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Web view: use the mobile app for lock-screen medication alarms.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ValueListenableBuilder<bool>(
            valueListenable:
                context.read<AlarmScheduler>().isExactAlarmDegradedNotifier,
            builder: (context, isDegraded, _) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Material(
                  color: isDegraded
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.6)
                      : theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.go('/settings/reliability'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14.0, vertical: 10.0),
                      child: Row(
                        children: [
                          Icon(
                            isDegraded
                                ? Icons.warning_amber_rounded
                                : Icons.alarm_on_rounded,
                            size: 18,
                            color: isDegraded
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isDegraded
                                  ? 'Background alarm pop-up or permission needed. Tap to enable full-screen ringing.'
                                  : 'Medication alarms are active and ready.',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: isDegraded
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: isDegraded
                                ? theme.colorScheme.error
                                : theme.colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Medicine Stock summary card on [DashboardView].
class DashboardStockSummaryCard extends StatelessWidget {
  const DashboardStockSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>() ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);
    final peachColor = statusColors.lowStock;
    final missedColor = statusColors.missed;

    return Consumer<InventoryViewModel>(
      builder: (context, invVm, _) {
        final lowStockCount = invVm.lowStockItems.length;
        final outOfStockCount =
            invVm.inventoryItems.where((i) => i.currentStock <= 0).length;
        final totalTracked = invVm.inventoryItems.length;
        final compactLowCount = MedicationValidator.formatCompactStockCount(
            lowStockCount.toDouble());
        final compactTotal = MedicationValidator.formatCompactStockCount(
            totalTracked.toDouble());
        final alertColor = outOfStockCount > 0 ? missedColor : peachColor;
        final onAlertColor =
            ThemeData.estimateBrightnessForColor(alertColor) == Brightness.dark
                ? Colors.white
                : const Color(0xFF111827);

        return Semantics(
          button: true,
          label: lowStockCount > 0
              ? 'Medication Stock: $lowStockCount medicines low on stock. Tap to review and refill.'
              : 'Medication Stock: $totalTracked medicines tracked. Tap to manage.',
          child: Container(
            margin: const EdgeInsets.only(bottom: 16.0),
            decoration: BoxDecoration(
              color: lowStockCount > 0
                  ? alertColor.withValues(alpha: 0.12)
                  : theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: lowStockCount > 0
                    ? alertColor
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: lowStockCount > 0 ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => context.go('/inventory'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18.0, vertical: 14.0),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: lowStockCount > 0
                              ? alertColor.withValues(alpha: 0.2)
                              : theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          outOfStockCount > 0
                              ? Icons.error_outline_rounded
                              : Icons.inventory_2_rounded,
                          color: lowStockCount > 0
                              ? alertColor
                              : theme.colorScheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Stock & Supply',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (lowStockCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: alertColor,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      outOfStockCount > 0
                                          ? '$outOfStockCount EMPTY'
                                          : '$compactLowCount LOW',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: onAlertColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              outOfStockCount > 0
                                  ? '$outOfStockCount medicine(s) out of stock ($compactLowCount total low). Tap to refill.'
                                  : lowStockCount > 0
                                      ? '$compactLowCount medicine(s) running low. Tap to review & refill.'
                                      : 'All medicines well stocked ($compactTotal tracked). Tap to view stock.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Stock',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
