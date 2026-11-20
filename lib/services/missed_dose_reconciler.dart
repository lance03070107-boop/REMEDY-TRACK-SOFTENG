import 'dart:async';
import '../core/scheduling/schedule_expander.dart';
import '../core/state/dose_state_machine.dart';
import '../core/utils/app_logger.dart';
import '../models/intake_log.dart';
import '../repositories/intake_repository.dart';
import '../repositories/medication_repository.dart';
import 'alarm_scheduler.dart';

/// Service performing missed dose reconciliation across app lifecycle events.
///
/// ARCHITECTURAL TRUTHS & LIMITATIONS:
/// When an Android/iOS app is killed, Flutter/Dart cannot execute in the background continuously.
/// Neither Android Doze nor iOS background execution guarantees exact 60-minute background execution.
/// Therefore, the source of truth for "missed" doses is this reconciliation engine, executed:
/// 1. On cold app startup (main.dart)
/// 2. On app resume from background (WidgetsBindingObserver)
/// 3. In background via WorkManager periodic task (best-effort every 15 minutes on Android)
/// 4. On the server via scheduled Cloud Functions (for online caregiver escalation)
///
/// Rule: Any scheduled dose whose alarm time + 60 minutes has elapsed without an intake log
/// (or whose snooze window has expired without intake) is transitioned to DoseStatus.missed.
/// Missed doses DO NOT decrement inventory.
class MissedDoseReconciler {
  final MedicationRepository _medicationRepository;
  final IntakeRepository _intakeRepository;

  MissedDoseReconciler({
    required MedicationRepository medicationRepository,
    required IntakeRepository intakeRepository,
  })  : _medicationRepository = medicationRepository,
        _intakeRepository = intakeRepository;

  /// Performs reconciliation pass for the given [userId].
  /// Scans scheduled occurrences from the last 48 hours up to (now - 60 minutes).
  /// Returns the number of doses reconciled to 'missed'.
  Future<int> reconcileMissedDoses(String userId) async {
    if (userId.isEmpty) return 0;

    int reconciledCount = 0;
    try {
      final now = DateTime.now();
      final cutoffTime = now.subtract(
          const Duration(minutes: DoseStateMachine.missedThresholdMinutes));
      final lookbackStart = now.subtract(const Duration(hours: 48));

      // 1. Fetch active medications with schedules
      final medications = await _medicationRepository.getMedications(userId);
      final activeScheduledMeds = medications.where(
        (m) => m.isActive && !m.isPrn && m.schedule != null,
      );

      // 2. Fetch existing logs in the lookback window
      final existingLogs = await _intakeRepository.getLogsForDateRange(
        userId,
        lookbackStart,
        now,
      );
      final Map<String, IntakeLog> existingLogsMap = {
        for (final log in existingLogs) log.id: log,
      };

      // 3. Evaluate each scheduled occurrence
      for (final med in activeScheduledMeds) {
        // Enforce medication creation / schedule-edit anchor so newly created or
        // newly added schedule times don't retroactively generate missed doses (B5).
        final scheduleUpdatedAt = med.schedule?.updatedAt;
        final effectiveAnchor =
            (scheduleUpdatedAt != null && scheduleUpdatedAt.isAfter(med.createdAt))
                ? scheduleUpdatedAt
                : med.createdAt;
        final occurrences = ScheduleExpander.getOccurrencesInRange(
          schedule: med.schedule!,
          start: lookbackStart,
          end: cutoffTime,
          createdAfter: effectiveAnchor,
        );

        for (final scheduledOccurrence in occurrences) {
          final deterministicId = DoseStateMachine.generateLogId(
            med.id,
            scheduledOccurrence,
          );

          final existingLog = existingLogsMap[deterministicId];
          bool shouldMarkMissed = false;

          if (existingLog == null) {
            // No log exists -> unacknowledged for >60m
            shouldMarkMissed = true;
          } else if (existingLog.status == DoseStatus.snoozed) {
            // Log exists but was snoozed: check if snooze window has expired (B4)
            final snoozeAnchor =
                existingLog.snoozeUntil ?? existingLog.scheduledTime;
            if (now.difference(snoozeAnchor).inMinutes >
                DoseStateMachine.missedThresholdMinutes) {
              shouldMarkMissed = true;
            }
          }

          if (shouldMarkMissed) {
            final missedLog = IntakeLog(
              id: deterministicId,
              userId: userId,
              medicationId: med.id,
              medicationName: med.name,
              doseAmount: med.doseAmount,
              scheduledTime: scheduledOccurrence,
              recordedTime: now,
              status: DoseStatus.missed,
              snoozeCount: existingLog?.snoozeCount ?? 0,
              isPrn: false,
            );

            // Record atomically without decrementing inventory
            await _intakeRepository.recordIntakeAtomic(
              intakeLog: missedLog,
              decrementInventory: false,
            );

            // Mark occurrence terminal and cancel any lingering notifications/escalations
            try {
              await AlarmScheduler.markDoseAcknowledged(
                med.id,
                scheduledOccurrence,
                terminal: true,
              );
              await AlarmScheduler().cancelDoseAlarmsForOccurrence(
                medicationId: med.id,
                scheduledTime: scheduledOccurrence,
              );
            } catch (_) {}

            existingLogsMap[deterministicId] = missedLog;
            reconciledCount++;
            AppLogger.i(
                'Reconciled missed dose for medId=${med.id} at $scheduledOccurrence',
                tag: 'MissedDoseReconciler');
          }
        }
      }
    } catch (e, s) {
      AppLogger.w('Reconciliation notice: $e',
          tag: 'MissedDoseReconciler', error: e, stackTrace: s);
    }

    return reconciledCount;
  }
}
