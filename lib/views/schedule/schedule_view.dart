import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/scheduling/schedule_expander.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/time_formatter.dart';
import '../../core/validation/medication_validator.dart';
import '../../models/dose_schedule.dart';
import '../../models/intake_log.dart';
import '../../viewmodels/adherence_viewmodel.dart';
import '../../viewmodels/caregiver_viewmodel.dart';
import '../../viewmodels/intake_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../widgets/pill_avatar.dart';
import '../widgets/state_views.dart';

/// Weekly & monthly schedule inspection view illustrating active dosage regimens.
class ScheduleView extends StatefulWidget {
  const ScheduleView({super.key});

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  DateTime _selectedDate = DateTime.now();

  bool _isScheduledOnDate(DoseSchedule schedule, DateTime date) {
    return ScheduleExpander.isScheduledOnDate(schedule, date);
  }

  IntakeLog? _findMatchingLog(
    List<IntakeLog> logs,
    String medId,
    DateTime scheduledTime,
  ) {
    final matching = logs.where(
      (l) =>
          l.medicationId == medId &&
          l.scheduledTime.year == scheduledTime.year &&
          l.scheduledTime.month == scheduledTime.month &&
          l.scheduledTime.day == scheduledTime.day &&
          l.scheduledTime.hour == scheduledTime.hour &&
          l.scheduledTime.minute == scheduledTime.minute,
    );
    return AdherenceViewModel.selectPreferredLog(matching);
  }

  DoseStatus _computeDoseStatus(IntakeLog? log, DateTime scheduledTime) {
    final now = DateTime.now();
    if (log != null) {
      if (log.status == DoseStatus.snoozed) {
        final snoozeAnchor = log.snoozeUntil ?? scheduledTime;
        if (now.difference(snoozeAnchor).inMinutes >
            AppConstants.lateGracePeriodMinutes) {
          return DoseStatus.missed;
        }
      }
      if (log.status == DoseStatus.pending &&
          scheduledTime.isBefore(
            now.subtract(
                const Duration(minutes: AppConstants.lateGracePeriodMinutes)),
          )) {
        return DoseStatus.missed;
      }
      return log.status;
    }
    if (scheduledTime.isBefore(
      now.subtract(
          const Duration(minutes: AppConstants.lateGracePeriodMinutes)),
    )) {
      return DoseStatus.missed;
    }
    return DoseStatus.pending;
  }

  Widget _buildStatusChip(DoseStatus status) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>() ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case DoseStatus.taken:
        bg = statusColors.taken.withValues(alpha: 0.15);
        fg = statusColors.taken;
        label = 'Taken';
        icon = Icons.check_circle_rounded;
        break;
      case DoseStatus.late:
        bg = statusColors.late.withValues(alpha: 0.15);
        fg = statusColors.late;
        label = 'Late';
        icon = Icons.warning_amber_rounded;
        break;
      case DoseStatus.skipped:
        bg = statusColors.skipped.withValues(alpha: 0.15);
        fg = statusColors.skipped;
        label = 'Skipped';
        icon = Icons.cancel_outlined;
        break;
      case DoseStatus.missed:
        bg = statusColors.missed.withValues(alpha: 0.15);
        fg = statusColors.missed;
        label = 'Missed';
        icon = Icons.error_outline_rounded;
        break;
      case DoseStatus.snoozed:
        bg = statusColors.snoozed.withValues(alpha: 0.15);
        fg = statusColors.snoozed;
        label = 'Snoozed';
        icon = Icons.snooze_rounded;
        break;
      case DoseStatus.pending:
        bg = theme.colorScheme.primary.withValues(alpha: 0.12);
        fg = theme.colorScheme.primary;
        label = 'Pending';
        icon = Icons.schedule_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medVm = context.watch<MedicationViewModel>();
    final intakeVm = context.watch<IntakeViewModel>();
    final settingsVm = context.watch<SettingsViewModel?>();
    final caregiverVm = context.watch<CaregiverViewModel?>();

    // Filter medications scheduled on the selected date
    final scheduledMeds = medVm.medications
        .where((m) =>
            m.isActive &&
            !m.isPrn &&
            m.schedule != null &&
            _isScheduledOnDate(m.schedule!, _selectedDate))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_rounded),
            tooltip: 'Jump to Today',
            onPressed: () => setState(() => _selectedDate = DateTime.now()),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caregiverVm?.isCaregiverMode ?? false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.secondaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_rounded,
                    size: 18,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Caregiver Read-Only View — Viewing ${caregiverVm?.activeProfileName ?? 'Patient'}\'s schedule',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 14-day horizontal date selector strip
          Container(
            height: 84,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              itemBuilder: (context, index) {
                final date = DateTime.now().add(Duration(days: index - 3));
                final isSelected = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                final isToday = date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;
                final dayBorderRadius = BorderRadius.circular(16);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Material(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHigh,
                    borderRadius: dayBorderRadius,
                    child: InkWell(
                      borderRadius: dayBorderRadius,
                      onTap: () => setState(() => _selectedDate = date),
                      child: Container(
                        width: 56,
                        decoration: BoxDecoration(
                          borderRadius: dayBorderRadius,
                          border: isToday && !isSelected
                              ? Border.all(
                                  color: theme.colorScheme.primary, width: 1.5)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('E').format(date),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('d').format(date),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEEE, MMMM d').format(_selectedDate),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${scheduledMeds.length} ${scheduledMeds.length == 1 ? 'medication' : 'medications'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: scheduledMeds.isEmpty
                ? EmptyStateView(
                    icon: Icons.event_available_rounded,
                    title: 'No Medications Scheduled',
                    subtitle:
                        'No maintenance doses are prescribed for ${DateFormat('MMMM d, yyyy').format(_selectedDate)}.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: scheduledMeds.length,
                    itemBuilder: (context, index) {
                      final med = scheduledMeds[index];
                      final schedule = med.schedule!;
                      final times = ScheduleExpander.effectiveTimesOfDay(schedule);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  PillAvatar.fromMedication(
                                    medication: med,
                                    size: 36,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          med.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    MedicationValidator.formatDoseWithUnit(
                                        med.doseAmount, med.form),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.secondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              ...times.map((t) {
                                final parsed =
                                    ScheduleExpander.parseTimeOfDay(t);
                                if (parsed == null) {
                                  return const SizedBox.shrink();
                                }
                                final scheduledDateTime = DateTime(
                                  _selectedDate.year,
                                  _selectedDate.month,
                                  _selectedDate.day,
                                  parsed.$1,
                                  parsed.$2,
                                );
                                final log = _findMatchingLog(
                                  intakeVm.allLogs,
                                  med.id,
                                  scheduledDateTime,
                                );
                                final status =
                                    _computeDoseStatus(log, scheduledDateTime);

                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.access_time_rounded,
                                                size: 16,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant),
                                            const SizedBox(width: 6),
                                            Text(
                                              TimeFormatter.formatTime(
                                                scheduledDateTime,
                                                is24Hour: settingsVm
                                                        ?.is24HourFormat ??
                                                    false,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                        _buildStatusChip(status),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
