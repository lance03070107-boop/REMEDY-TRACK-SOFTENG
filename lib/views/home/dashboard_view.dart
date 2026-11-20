import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/scheduling/schedule_expander.dart';
import '../../core/state/dose_state_machine.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/utils/time_formatter.dart';
import '../../core/validation/medication_validator.dart';
import '../../models/intake_log.dart';
import '../../models/inventory_item.dart';
import '../../models/medication.dart';
import '../../services/alarm_scheduler.dart';
import '../../services/permission_service.dart';
import '../../viewmodels/adherence_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/caregiver_viewmodel.dart';
import '../../viewmodels/intake_viewmodel.dart';
import '../../viewmodels/inventory_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../widgets/dose_card.dart';
import '../widgets/pill_avatar.dart';
import '../widgets/progress_ring.dart';
import '../widgets/state_views.dart';
import 'widgets/dashboard_status_banners.dart';

class DoseItemData {
  final Medication medication;
  final DateTime scheduledTime;
  final IntakeLog? log;

  const DoseItemData({
    required this.medication,
    required this.scheduledTime,
    this.log,
  });
}

/// Primary Dashboard displaying Today's schedule grouped by Morning/Afternoon/Evening/Night.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final Set<String> _inFlightDoseIds = <String>{};

  String _doseKey(DoseItemData item) =>
      DoseStateMachine.generateLogId(item.medication.id, item.scheduledTime);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authVm = context.read<AuthViewModel>();
      final caregiverVm = context.read<CaregiverViewModel>();
      if (authVm.isAuthenticated) {
        final uid = caregiverVm.activeProfileId ?? authVm.currentUserId;
        context.read<MedicationViewModel>().listenToMedications(
              uid,
              isOwnProfile: !caregiverVm.isCaregiverMode,
            );
        context.read<IntakeViewModel>().listenToIntakeLogs(uid);
        context.read<InventoryViewModel>().listenToInventory(
              uid,
              isOwnProfile: !caregiverVm.isCaregiverMode,
            );
        if (!kIsWeb && !caregiverVm.isCaregiverMode) {
          unawaited(
            context.read<AlarmScheduler>().checkExactAlarmCapability(),
          );
          unawaited(
            PermissionService().ensureAlarmPermissions(context: context),
          );
        }
      }
    });
  }

  List<DoseItemData> _computeTodayDoses(
    List<Medication> medications,
    List<IntakeLog> logs,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<DoseItemData> items = [];

    for (final med in medications) {
      if (!med.isActive || med.isPrn || med.schedule == null) continue;
      final schedule = med.schedule!;

      // Check if scheduled today using unified ScheduleExpander
      if (!ScheduleExpander.isScheduledOnDate(schedule, today)) continue;

      for (final timeStr in ScheduleExpander.effectiveTimesOfDay(schedule)) {
        final parsed = ScheduleExpander.parseTimeOfDay(timeStr);
        if (parsed == null) continue;
        final scheduledTime =
            DateTime(today.year, today.month, today.day, parsed.$1, parsed.$2);

        // Find authoritative log for this scheduled minute (deduplicates legacy server/client duplicates)
        final matchingLogs = logs.where(
          (l) =>
              l.medicationId == med.id &&
              l.scheduledTime.year == scheduledTime.year &&
              l.scheduledTime.month == scheduledTime.month &&
              l.scheduledTime.day == scheduledTime.day &&
              l.scheduledTime.hour == scheduledTime.hour &&
              l.scheduledTime.minute == scheduledTime.minute,
        );
        final matchingLog = AdherenceViewModel.selectPreferredLog(matchingLogs);

        items.add(DoseItemData(
          medication: med,
          scheduledTime: scheduledTime,
          log: matchingLog,
        ));
      }
    }

    items.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return items;
  }

  DoseItemData? _findNextUpcomingDose(List<DoseItemData> items) {
    final now = DateTime.now();
    // First check for any currently due dose within the active grace window
    for (final item in items) {
      final status = _determineStatus(item);
      if ((status == DoseStatus.pending || status == DoseStatus.snoozed) &&
          !item.scheduledTime.isAfter(now)) {
        return item;
      }
    }
    // Otherwise return the earliest upcoming pending/snoozed dose today
    for (final item in items) {
      final status = _determineStatus(item);
      if (status == DoseStatus.pending || status == DoseStatus.snoozed) {
        return item;
      }
    }
    return null;
  }

  Future<void> _handleDoseAction(DoseItemData item, bool isTake) async {
    final doseId = _doseKey(item);
    if (_inFlightDoseIds.contains(doseId)) return;

    final intakeVm = context.read<IntakeViewModel>();
    final invVm = context.read<InventoryViewModel>();

    if (isTake) {
      // Duplicate-dose protection check
      final isDuplicate = intakeVm.checkIsDuplicateDose(item.medication.id);
      if (isDuplicate) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AppStrings.duplicateDoseWarningTitle),
            content: const Text(AppStrings.duplicateDoseWarningBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Record Anyway'),
              ),
            ],
          ),
        );
        if (confirm != true || !mounted) return;
      }

      setState(() => _inFlightDoseIds.add(doseId));
      final shouldDecrement =
          intakeVm.isEligibleForAutoDecrement(item.medication);
      if (shouldDecrement) {
        invVm.adjustLocalStock(item.medication.id, -item.medication.doseAmount);
      }

      try {
        final didSucceed = await intakeVm.takeDose(
          medication: item.medication,
          scheduledTime: item.scheduledTime,
        );
        if (!didSucceed && shouldDecrement) {
          invVm.adjustLocalStock(
              item.medication.id, item.medication.doseAmount);
        }
      } finally {
        if (mounted) {
          setState(() => _inFlightDoseIds.remove(doseId));
        } else {
          _inFlightDoseIds.remove(doseId);
        }
      }
    } else {
      setState(() => _inFlightDoseIds.add(doseId));
      try {
        await intakeVm.skipDose(
          medication: item.medication,
          scheduledTime: item.scheduledTime,
        );
      } finally {
        if (mounted) {
          setState(() => _inFlightDoseIds.remove(doseId));
        } else {
          _inFlightDoseIds.remove(doseId);
        }
      }
    }
  }

  DoseStatus _determineStatus(DoseItemData item) {
    final now = DateTime.now();
    if (item.log != null) {
      if (item.log!.status == DoseStatus.snoozed) {
        final snoozeAnchor = item.log!.snoozeUntil ?? item.scheduledTime;
        if (now.difference(snoozeAnchor).inMinutes >
            AppConstants.lateGracePeriodMinutes) {
          return DoseStatus.missed;
        }
      }
      if (item.log!.status == DoseStatus.pending &&
          item.scheduledTime.isBefore(
            now.subtract(
                const Duration(minutes: AppConstants.lateGracePeriodMinutes)),
          )) {
        return DoseStatus.missed;
      }
      return item.log!.status;
    }
    final isMissed = item.scheduledTime.isBefore(
      now.subtract(
          const Duration(minutes: AppConstants.lateGracePeriodMinutes)),
    );
    if (isMissed) {
      return DoseStatus.missed;
    }
    return DoseStatus.pending;
  }

  Future<void> _handleSnoozeDose(DoseItemData item) async {
    final intakeVm = context.read<IntakeViewModel>();
    await intakeVm.snoozeDose(
      medication: item.medication,
      scheduledTime: item.scheduledTime,
    );
  }

  Future<void> _handleSkipDose(DoseItemData item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Skip ${item.medication.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skipped doses do not deduct inventory. Please indicate reason (optional):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Fasting before a test'),
                  onPressed: () =>
                      Navigator.pop(ctx, 'Fasting before a test'),
                ),
                ActionChip(
                  label: const Text('Side Effects'),
                  onPressed: () => Navigator.pop(ctx, 'Side Effects'),
                ),
                ActionChip(
                  label: const Text('Doctor Advised'),
                  onPressed: () => Navigator.pop(ctx, 'Doctor Advised'),
                ),
                ActionChip(
                  label: const Text('Supply Empty'),
                  onPressed: () => Navigator.pop(ctx, 'Supply Empty'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, 'Skipped'),
            child: const Text('Confirm Skip'),
          ),
        ],
      ),
    );

    if (reason != null && mounted) {
      await context.read<IntakeViewModel>().skipDose(
            medication: item.medication,
            scheduledTime: item.scheduledTime,
            reason: reason,
          );
    }
  }

  Future<void> _handleUndoDose(DoseItemData item) async {
    if (item.log == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo Taken Dose?'),
        content: Text(
          'Revert this dose of ${item.medication.name} back to scheduled? If inventory was deducted, stock will be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Undo Taken'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final doseId = _doseKey(item);
      if (_inFlightDoseIds.contains(doseId)) return;
      setState(() => _inFlightDoseIds.add(doseId));
      final intakeVm = context.read<IntakeViewModel>();
      final invVm = context.read<InventoryViewModel>();
      final shouldRestore =
          intakeVm.isEligibleForAutoDecrement(item.medication);
      if (shouldRestore) {
        invVm.adjustLocalStock(item.medication.id, item.medication.doseAmount);
      }
      try {
        final didSucceed = await intakeVm.undoTakenDose(
          medication: item.medication,
          takenLog: item.log!,
        );
        if (!didSucceed && shouldRestore) {
          invVm.adjustLocalStock(
              item.medication.id, -item.medication.doseAmount);
        }
      } finally {
        if (mounted) {
          setState(() => _inFlightDoseIds.remove(doseId));
        } else {
          _inFlightDoseIds.remove(doseId);
        }
      }
    }
  }

  Future<void> _handleLateCorrection(DoseItemData item) async {
    final doseId = _doseKey(item);
    if (_inFlightDoseIds.contains(doseId)) return;
    setState(() => _inFlightDoseIds.add(doseId));
    final intakeVm = context.read<IntakeViewModel>();
    final invVm = context.read<InventoryViewModel>();
    final shouldDecrement =
        intakeVm.isEligibleForAutoDecrement(item.medication);
    if (shouldDecrement) {
      invVm.adjustLocalStock(item.medication.id, -item.medication.doseAmount);
    }
    final missedLog = item.log ??
        IntakeLog(
          id: DoseStateMachine.generateLogId(
              item.medication.id, item.scheduledTime),
          userId: context.read<AuthViewModel>().currentUserId,
          medicationId: item.medication.id,
          medicationName: item.medication.name,
          scheduledTime: item.scheduledTime,
          status: DoseStatus.missed,
          doseAmount: item.medication.doseAmount,
        );
    try {
      final didSucceed = await intakeVm.correctMissedDoseAsTaken(
        medication: item.medication,
        missedLog: missedLog,
      );
      if (!didSucceed && shouldDecrement) {
        invVm.adjustLocalStock(item.medication.id, item.medication.doseAmount);
      }
    } finally {
      if (mounted) {
        setState(() => _inFlightDoseIds.remove(doseId));
      } else {
        _inFlightDoseIds.remove(doseId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medVm = context.watch<MedicationViewModel>();
    final intakeVm = context.watch<IntakeViewModel>();
    final caregiverVm = context.watch<CaregiverViewModel>();
    final settingsVm = context.watch<SettingsViewModel?>();

    if (medVm.isLoading || intakeVm.isLoading) {
      return const Scaffold(
          body: LoadingView(message: 'Loading your medications...'));
    }

    final authVm = context.watch<AuthViewModel>();
    final inventoryVm = context.watch<InventoryViewModel>();
    final syncErrorMessage = medVm.errorMessage ??
        intakeVm.errorMessage ??
        inventoryVm.errorMessage;
    final hasSyncError =
        medVm.hasError || intakeVm.hasError || inventoryVm.hasError;
    final statusColors = theme.extension<StatusColors>() ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);

    final todayDoses = _computeTodayDoses(medVm.medications, intakeVm.allLogs);
    final nextDose = _findNextUpcomingDose(todayDoses);

    int upcomingCount = 0;
    int completedCount = 0;
    int missedCount = 0;
    for (final d in todayDoses) {
      final st = _determineStatus(d);
      if (st == DoseStatus.taken || st == DoseStatus.late) {
        completedCount++;
      } else if (st == DoseStatus.missed) {
        missedCount++;
      } else if (st == DoseStatus.pending || st == DoseStatus.snoozed) {
        upcomingCount++;
      }
    }
    final lowStockCount = inventoryVm.lowStockItems.length;

    // Grouping by TimeBucket
    final morning = todayDoses
        .where((d) =>
            DateTimeUtils.getTimeBucket(
                TimeOfDay.fromDateTime(d.scheduledTime)) ==
            TimeBucket.morning)
        .toList();
    final afternoon = todayDoses
        .where((d) =>
            DateTimeUtils.getTimeBucket(
                TimeOfDay.fromDateTime(d.scheduledTime)) ==
            TimeBucket.afternoon)
        .toList();
    final evening = todayDoses
        .where((d) =>
            DateTimeUtils.getTimeBucket(
                TimeOfDay.fromDateTime(d.scheduledTime)) ==
            TimeBucket.evening)
        .toList();
    final night = todayDoses
        .where((d) =>
            DateTimeUtils.getTimeBucket(
                TimeOfDay.fromDateTime(d.scheduledTime)) ==
            TimeBucket.night)
        .toList();

    final rawName = caregiverVm.isCaregiverMode
        ? (caregiverVm.activeProfileName ?? 'Patient')
        : authVm.currentUserDisplayName;
    final firstName =
        rawName.trim().isNotEmpty ? rawName.trim().split(' ').first : 'Friend';
    final formattedDate = DateFormat('EEEE, MMM d').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                firstName[0].toUpperCase(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hi, $firstName 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    formattedDate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              caregiverVm.isCaregiverMode
                  ? Icons.family_restroom_rounded
                  : Icons.family_restroom_outlined,
            ),
            tooltip: 'Caregiver & Family Sharing',
            onPressed: () => context.push('/caregiver'),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Medication Schedule',
            onPressed: () => context.push('/schedule'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            children: [
              if (caregiverVm.isCaregiverMode)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Material(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 10.0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 20,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Viewing ${caregiverVm.activeProfileName ?? 'Patient'}\'s Schedule (View Only)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              caregiverVm.setActiveProfile(null, null);
                              final uid = authVm.currentUserId;
                              if (uid.isNotEmpty) {
                                medVm.listenToMedications(
                                  uid,
                                  isOwnProfile: true,
                                );
                                intakeVm.listenToIntakeLogs(uid);
                                context
                                    .read<InventoryViewModel>()
                                    .listenToInventory(uid);
                              }
                            },
                            child: const Text('My Meds'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (hasSyncError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Material(
                    color: theme.colorScheme.errorContainer
                        .withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14.0, vertical: 10.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 20,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              syncErrorMessage ??
                                  'Unable to sync with cloud. Showing saved data.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              if (authVm.isAuthenticated) {
                                final uid = caregiverVm.activeProfileId ??
                                    authVm.currentUserId;
                                medVm.clearError();
                                intakeVm.clearError();
                                inventoryVm.clearError();
                                medVm.retry(uid);
                                intakeVm.retry(uid);
                                inventoryVm.retry(uid);
                              }
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const DashboardStatusBanners(),

              // 4 Status Summary Cards (Upcoming, Completed, Missed, Low Stock)
              Row(
                children: [
                  Expanded(
                    child: _buildStatusSummaryCard(
                      context,
                      label: 'Upcoming',
                      count: upcomingCount,
                      icon: Icons.schedule_rounded,
                      accentColor: theme.colorScheme.primary,
                      backgroundColor: theme.brightness == Brightness.dark
                          ? theme.colorScheme.surfaceContainerLow
                          : const Color(0xFFDDF2FC),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatusSummaryCard(
                      context,
                      label: 'Completed',
                      count: completedCount,
                      icon: Icons.check_circle_rounded,
                      accentColor: statusColors.taken,
                      backgroundColor: theme.brightness == Brightness.dark
                          ? theme.colorScheme.surfaceContainerLow
                          : statusColors.taken.withValues(alpha: 0.10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildStatusSummaryCard(
                      context,
                      label: 'Missed',
                      count: missedCount,
                      icon: Icons.error_outline_rounded,
                      accentColor: missedCount > 0
                          ? statusColors.missed
                          : theme.colorScheme.onSurfaceVariant,
                      backgroundColor: theme.brightness == Brightness.dark
                          ? theme.colorScheme.surfaceContainerLow
                          : (missedCount > 0
                              ? statusColors.missed.withValues(alpha: 0.10)
                              : theme.colorScheme.surfaceContainerLowest),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatusSummaryCard(
                      context,
                      label: 'Low Stock',
                      count: lowStockCount,
                      icon: Icons.inventory_2_outlined,
                      accentColor: lowStockCount > 0
                          ? statusColors.lowStock
                          : theme.colorScheme.primary,
                      backgroundColor: theme.brightness == Brightness.dark
                          ? theme.colorScheme.surfaceContainerLow
                          : (lowStockCount > 0
                              ? statusColors.lowStock.withValues(alpha: 0.12)
                              : const Color(0xFFDDF2FC)),
                      onTap: () => context.go('/inventory'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Daily Adherence Progress Ring Card
              Builder(
                builder: (context) {
                  final takenCount = completedCount;
                  final totalCount = todayDoses.length;
                  final progress =
                      totalCount > 0 ? (takenCount / totalCount) : 1.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? theme.colorScheme.surfaceContainerLow
                          : const Color(0xFFDDF2FC),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.6),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        ProgressRing(
                          progress: progress,
                          takenCount: takenCount,
                          totalCount: totalCount,
                          size: 88,
                          strokeWidth: 8,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Today's Progress",
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                totalCount == 0
                                    ? 'No scheduled doses for today.'
                                    : (takenCount == totalCount
                                        ? 'All doses completed for today! Great job.'
                                        : '$takenCount of $totalCount doses taken today.'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Next / Due Dose Hero Countdown Card
              if (nextDose != null)
                Card(
                  color: theme.colorScheme.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                      width: 1.4,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.alarm_rounded,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nextDose.scheduledTime.isAfter(DateTime.now())
                                    ? '${AppStrings.nextDoseLabel} ${DateTimeUtils.formatCountdown(nextDose.scheduledTime)}'
                                    : 'Due Now',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${nextDose.medication.name} (${nextDose.medication.strength})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${TimeFormatter.formatTime(nextDose.scheduledTime, is24Hour: settingsVm?.is24HourFormat ?? false)}'
                                ' • ${MedicationValidator.formatDoseWithUnit(nextDose.medication.doseAmount, nextDose.medication.form)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (caregiverVm.isCaregiverMode)
                          const Chip(
                            label: Text('View Only',
                                style: TextStyle(fontSize: 11)),
                          )
                        else
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(88, 48),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () => _handleDoseAction(nextDose, true),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Take'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (nextDose != null) const SizedBox(height: 16),

              // Dedicated Medicine Stock / Inventory Manager Card
              const DashboardStockSummaryCard(),

              // Quick PRN Log Banner
              if (medVm.medications.any((m) => m.isPrn) &&
                  !caregiverVm.isCaregiverMode) ...[
                _buildPrnQuickLogBanner(
                    context, medVm.medications.where((m) => m.isPrn).toList()),
                const SizedBox(height: 16),
              ],

              if (medVm.medications.isEmpty) ...[
                _buildEmptyRegimenCard(context),
              ] else if (todayDoses.isEmpty) ...[
                _buildNoDosesScheduledCard(context),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppStrings.todaySchedule,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push('/schedule'),
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: const Text('Full Schedule'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildBucketSection(
                    AppStrings.morningGroup, Icons.wb_sunny_outlined, morning),
                _buildBucketSection(
                    AppStrings.afternoonGroup, Icons.wb_twilight, afternoon),
                _buildBucketSection(AppStrings.eveningGroup,
                    Icons.nights_stay_outlined, evening),
                _buildBucketSection(
                    AppStrings.nightGroup, Icons.bedtime_outlined, night),
              ],

              const SizedBox(height: 24),
              // Non-intrusive legal disclaimer
              Center(
                child: Text(
                  AppStrings.medicalDisclaimer,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButton: caregiverVm.isCaregiverMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/medications/add'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Medication'),
            ),
    );
  }

  Widget _buildBucketSection(
    String title,
    IconData bucketIcon,
    List<DoseItemData> items,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Icon(bucketIcon, size: 18, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 26.0, bottom: 12.0),
            child: Text(
              AppStrings.noMedicationsScheduled,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...items.map((item) => _buildDoseCard(item)),
      ],
    );
  }

  Widget _buildStatusSummaryCard(
    BuildContext context, {
    required String label,
    required int count,
    required IconData icon,
    required Color accentColor,
    required Color backgroundColor,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final compactCount =
        MedicationValidator.formatCompactStockCount(count.toDouble());
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  compactCount,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(
        label: '$label: $compactCount',
        child: cardContent,
      );
    }

    return Semantics(
      button: true,
      label: '$label: $compactCount. Tap to view.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: cardContent,
        ),
      ),
    );
  }

  Widget _buildDoseCard(DoseItemData item) {
    final caregiverVm = context.watch<CaregiverViewModel>();
    final inventoryVm = context.watch<InventoryViewModel>();
    final status = _determineStatus(item);
    final invItem =
        inventoryVm.inventoryItems.cast<InventoryItem?>().firstWhere(
              (i) => i?.medicationId == item.medication.id,
              orElse: () => null,
            );

    if (caregiverVm.isCaregiverMode) {
      return DoseCard(
        medication: item.medication,
        scheduledTime: item.scheduledTime,
        status: status,
        log: item.log,
        stockCount: invItem?.currentStock,
        isLowStock: invItem?.isLowStock ?? false,
        onTake: () {},
        onSnooze: () {},
        onSkip: () {},
      );
    }

    final isBusy = _inFlightDoseIds.contains(_doseKey(item));
    return DoseCard(
      medication: item.medication,
      scheduledTime: item.scheduledTime,
      status: status,
      log: item.log,
      showActions: true,
      stockCount: invItem?.currentStock,
      isLowStock: invItem?.isLowStock ?? false,
      onTake: isBusy ? null : () => _handleDoseAction(item, true),
      onSnooze: isBusy ? null : () => _handleSnoozeDose(item),
      onSkip: isBusy ? null : () => _handleSkipDose(item),
      onUndo: (!isBusy &&
              (item.log?.status == DoseStatus.taken ||
                  item.log?.status == DoseStatus.late))
          ? () => _handleUndoDose(item)
          : null,
      onLateCorrection: (!isBusy && status == DoseStatus.missed)
          ? () => _handleLateCorrection(item)
          : null,
    );
  }

  Widget _buildEmptyRegimenCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.medication_liquid_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Medications Prescribed Yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your daily prescriptions to configure alarm-style reminders, track doses, and monitor pill inventory.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.push('/medications/add'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add First Medication'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDosesScheduledCard(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>() ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColors.taken.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline_rounded,
                  color: statusColors.taken, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Doses Scheduled Today',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'You have no regular doses scheduled today. Tap the calendar icon above to view upcoming days.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrnQuickLogBanner(
      BuildContext context, List<Medication> prnMeds) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showPrnLogModal(context, prnMeds),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            if (prnMeds.length == 1)
              PillAvatar.fromMedication(
                medication: prnMeds.first,
                size: 38,
              )
            else
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.medication_rounded,
                    color: theme.colorScheme.secondary, size: 20),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'As-Needed Medications',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  Text(
                    'Tap to record an extra dose (${prnMeds.length} available)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: theme.colorScheme.secondary),
          ],
        ),
      ),
    );
  }

  Future<void> _showPrnLogModal(
      BuildContext context, List<Medication> prnMeds) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.medication_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Log As-Needed Dose',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: prnMeds.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final med = prnMeds[idx];
                      final doseLabel = MedicationValidator.formatDoseWithUnit(
                        med.doseAmount,
                        med.form,
                      );
                      final trimmedStrength = med.strength.trim();
                      final trimmedInstructions = med.instructions.trim();
                      final subtitleParts = <String>[
                        if (trimmedStrength.isNotEmpty) trimmedStrength,
                        doseLabel,
                        if (trimmedInstructions.isNotEmpty) trimmedInstructions,
                      ];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: PillAvatar.fromMedication(
                          medication: med,
                          size: 42,
                        ),
                        title: Text(med.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(subtitleParts.join(' • ')),
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final intakeVm = context.read<IntakeViewModel>();
                            final invVm = context.read<InventoryViewModel>();
                            try {
                              await intakeVm.logPrnDose(medication: med);
                              if (intakeVm.isEligibleForAutoDecrement(med) &&
                                  !intakeVm.hasError) {
                                invVm.adjustLocalStock(med.id, -med.doseAmount);
                              }
                              if (!context.mounted) return;
                              if (intakeVm.hasError) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(intakeVm.errorMessage ??
                                        'Could not save this dose. Please try again.'),
                                    backgroundColor: theme.colorScheme.error,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Logged ${med.name} dose.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e, s) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ErrorMapper.map(e, s).message),
                                    backgroundColor: theme.colorScheme.error,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Log Dose'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
