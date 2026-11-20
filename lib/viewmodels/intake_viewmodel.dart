import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_mapper.dart';
import '../core/scheduling/schedule_expander.dart';
import '../core/state/dose_state_machine.dart';
import '../core/utils/app_logger.dart';
import '../core/validation/medication_validator.dart';
import '../models/intake_log.dart';
import '../models/medication.dart';
import '../repositories/intake_repository.dart';
import '../services/alarm_id_generator.dart';
import '../services/alarm_scheduler.dart';
import '../services/crashlytics_service.dart';

class IntakeViewModel extends ChangeNotifier {
  final IntakeRepository _intakeRepository;
  final AlarmScheduler _alarmScheduler;

  StreamSubscription<List<IntakeLog>>? _logsSubscription;
  String? _activeUserId;
  List<IntakeLog> _allLogs = [];
  bool _isLoading = false;
  String? _errorMessage;
  static bool _isFlushingPendingIntakes = false;

  IntakeViewModel({
    required IntakeRepository intakeRepository,
    AlarmScheduler? alarmScheduler,
  })  : _intakeRepository = intakeRepository,
        _alarmScheduler = alarmScheduler ?? AlarmScheduler();

  List<IntakeLog> get allLogs => List.unmodifiable(_allLogs);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  @visibleForTesting
  void setLogsForTesting(List<IntakeLog> logs) {
    _allLogs = logs;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Cancels active Firestore stream and clears in-memory state on sign-out or account switch.
  void resetState() {
    _logsSubscription?.cancel();
    _logsSubscription = null;
    _activeUserId = null;
    _allLogs = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void retry(String userId) {
    _errorMessage = null;
    listenToIntakeLogs(userId, forceReload: true);
  }

  void listenToIntakeLogs(String userId, {bool forceReload = false}) {
    if (userId.isEmpty) return;
    if (!forceReload &&
        _activeUserId == userId &&
        _logsSubscription != null &&
        !_isLoading &&
        _errorMessage == null) {
      return;
    }

    if (_activeUserId != null && _activeUserId != userId) {
      _allLogs = [];
      _errorMessage = null;
    }

    _activeUserId = userId;
    _logsSubscription?.cancel();
    _isLoading = true;
    notifyListeners();

    unawaited(flushPendingBackgroundIntakes(userId));

    _logsSubscription =
        _intakeRepository.streamIntakeLogs(userId, limit: 2000).listen(
      (logs) {
        _allLogs = logs;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (Object e, StackTrace s) async {
        final mapped = ErrorMapper.map(e, s);
        if (mapped is! PermissionException && mapped is! AuthException) {
          try {
            final cached =
                await _intakeRepository.getIntakeLogs(userId, limit: 2000);
            _allLogs = cached;
            _isLoading = false;
            _errorMessage = null;
            notifyListeners();
            return;
          } catch (cacheErr, cacheStack) {
            AppLogger.w('Intake cache fallback failed: $cacheErr',
                tag: 'IntakeVM', error: cacheErr, stackTrace: cacheStack);
          }
        }
        _errorMessage = mapped.message;
        _isLoading = false;
        unawaited(CrashlyticsService.recordError(e, s));
        notifyListeners();
      },
    );
  }

  static String _entrySignature(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final logMap = decoded['log'];
        final id = (logMap is Map<String, dynamic>
                ? logMap['id']
                : decoded['id'])
            ?.toString();
        final ts = (decoded['timestamp'] ??
                (logMap is Map<String, dynamic>
                    ? logMap['recordedTime']
                    : decoded['recordedTime']))
            ?.toString();
        if (id != null && id.isNotEmpty) {
          return '$id|${ts ?? ''}';
        }
      }
    } catch (_) {}
    return raw;
  }

  /// Returns how many unsynced queued doses currently exist for [userId].
  static Future<int> getPendingBackgroundIntakeCount(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      final pendingRaw =
          prefs.getStringList('pending_background_intakes') ?? const [];
      if (pendingRaw.isEmpty) return 0;
      int count = 0;
      for (final raw in pendingRaw) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          if (map['alreadySynced'] == true) continue;
          final logMap = map['log'] as Map<String, dynamic>?;
          final entryUid = (logMap?['userId'] ?? map['userId'])?.toString() ?? '';
          if (entryUid.isEmpty || userId.isEmpty || entryUid == userId) {
            count++;
          }
        } catch (_) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Flushes pending intakes logged from lock-screen notification action buttons or alarm screen while offline.
  /// Reloads SharedPreferences before and after processing so entries written concurrently
  /// by the background isolate are never erased.
  Future<void> flushPendingBackgroundIntakes(String userId) async {
    if (_isFlushingPendingIntakes) return;
    _isFlushingPendingIntakes = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      final pendingRaw =
          prefs.getStringList('pending_background_intakes') ?? const [];
      if (pendingRaw.isEmpty) return;

      final processedCounts = <String, int>{};
      for (final raw in pendingRaw) {
        final sig = _entrySignature(raw);
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          if (map['alreadySynced'] == true) {
            processedCounts[sig] = (processedCounts[sig] ?? 0) + 1;
            continue;
          }

          final IntakeLog intakeLog;
          final bool shouldDecrement;

          if (map['log'] is Map<String, dynamic>) {
            final logMap = Map<String, dynamic>.from(
              map['log'] as Map<String, dynamic>,
            );
            if (userId.isNotEmpty &&
                (logMap['userId'] as String? ?? '').isEmpty) {
              logMap['userId'] = userId;
            }
            if ((logMap['id'] as String? ?? '').isEmpty ||
                (logMap['medicationId'] as String? ?? '').isEmpty) {
              throw const FormatException(
                'Malformed pending intake entry: missing id or medicationId',
              );
            }
            intakeLog = IntakeLog.fromJson(logMap);
            shouldDecrement = map['decrementInventory'] as bool? ?? false;
          } else {
            final logId = map['id'] as String?;
            final medId = map['medicationId'] as String?;
            final medName = map['medicationName'] as String?;
            final schedRaw = map['scheduledTime'] as String?;
            final recRaw = map['recordedTime'] as String?;
            final schedParsed =
                schedRaw != null ? DateTime.tryParse(schedRaw)?.toLocal() : null;
            final recParsed =
                recRaw != null ? DateTime.tryParse(recRaw)?.toLocal() : null;
            if (logId == null ||
                logId.isEmpty ||
                medId == null ||
                medId.isEmpty ||
                schedParsed == null) {
              throw const FormatException(
                'Malformed legacy pending intake entry',
              );
            }

            final formName = (map['form'] as String? ?? 'tablet').toLowerCase();
            final isTabletOrCapsule =
                formName == 'tablet' || formName == 'capsule';

            intakeLog = IntakeLog(
              id: logId,
              userId:
                  userId.isNotEmpty ? userId : (map['userId'] as String? ?? ''),
              medicationId: medId,
              medicationName: medName ?? 'Medication',
              doseAmount: (map['doseAmount'] as num?)?.toDouble() ?? 1.0,
              scheduledTime: schedParsed,
              recordedTime: recParsed ?? DateTime.now(),
              status: DoseStatus.values.firstWhere(
                (s) => s.name == map['status'],
                orElse: () => DoseStatus.taken,
              ),
              isPrn: map['isPrn'] as bool? ?? false,
              notes: map['notes'] as String?,
            );

            shouldDecrement = isTabletOrCapsule &&
                (intakeLog.status == DoseStatus.taken ||
                    intakeLog.status == DoseStatus.late);
          }

          // Never submit queued background intakes owned by another signed-in account
          if (intakeLog.userId.isNotEmpty &&
              userId.isNotEmpty &&
              intakeLog.userId != userId) {
            continue;
          }

          await _intakeRepository.recordIntakeAtomic(
            intakeLog: intakeLog,
            decrementInventory: shouldDecrement,
          );
          _upsertLocalLog(intakeLog);
          processedCounts[sig] = (processedCounts[sig] ?? 0) + 1;
        } catch (itemErr, stack) {
          unawaited(CrashlyticsService.recordError(itemErr, stack));
        }
      }

      if (processedCounts.isEmpty) return;

      // Re-read the latest persisted list so entries appended concurrently by a
      // background isolate during our flush are preserved intact.
      try {
        await prefs.reload();
      } catch (_) {}
      final latestList =
          prefs.getStringList('pending_background_intakes') ?? const [];
      final remainingPending = <String>[];
      final toRemove = Map<String, int>.from(processedCounts);
      for (final entry in latestList) {
        final sig = _entrySignature(entry);
        final rem = toRemove[sig] ?? 0;
        if (rem > 0) {
          toRemove[sig] = rem - 1;
        } else {
          remainingPending.add(entry);
        }
      }

      if (remainingPending.isEmpty) {
        await prefs.remove('pending_background_intakes');
      } else {
        await prefs.setStringList(
            'pending_background_intakes', remainingPending);
      }
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
    } finally {
      _isFlushingPendingIntakes = false;
    }
  }

  bool checkIsDuplicateDose(String medicationId, {DateTime? atTime}) {
    final now = atTime ?? DateTime.now();
    return _allLogs.any((log) {
      if (log.medicationId != medicationId) return false;
      if (log.status != DoseStatus.taken && log.status != DoseStatus.late) {
        return false;
      }
      if (log.recordedTime == null) return false;
      final diff = now.difference(log.recordedTime!).inMinutes.abs();
      return diff < AppConstants.duplicateDoseThresholdMinutes;
    });
  }

  void validatePrnSafety(Medication medication, {DateTime? atTime}) {
    if (!medication.isPrn) return;
    final now = atTime ?? DateTime.now();

    if (medication.minIntervalHours != null &&
        medication.minIntervalHours! > 0) {
      final minIntervalDuration = Duration(hours: medication.minIntervalHours!);
      final recentPrnIntake = _allLogs.where((l) {
        if (l.medicationId != medication.id) return false;
        if (l.status != DoseStatus.taken && l.status != DoseStatus.late) {
          return false;
        }
        if (l.recordedTime == null) return false;
        return now.difference(l.recordedTime!) < minIntervalDuration;
      }).toList()
        ..sort((a, b) => b.recordedTime!.compareTo(a.recordedTime!));

      if (recentPrnIntake.isNotEmpty) {
        final lastTime = recentPrnIntake.first.recordedTime!;
        final remainingSeconds =
            (minIntervalDuration - now.difference(lastTime)).inSeconds;
        final remainingMinutes = ((remainingSeconds + 59) ~/ 60).clamp(1, 10000);
        throw ClinicalSafetyException(
          risk: ClinicalSafetyRisk.prnMinInterval,
          message:
              'Too soon for another dose: ${medication.name} requires at least ${medication.minIntervalHours} hours between doses.',
          clinicalRecommendation:
              'Wait another $remainingMinutes minutes before taking your next dose.',
          safetyContext: {
            'minIntervalHours': medication.minIntervalHours,
            'lastTakenTime': lastTime.toIso8601String(),
            'remainingMinutes': remainingMinutes,
          },
        );
      }
    }

    if (medication.dailyMaxDose != null && medication.dailyMaxDose! > 0) {
      final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));
      final takenInLast24h = _allLogs.where((l) {
        if (l.medicationId != medication.id) return false;
        if (l.status != DoseStatus.taken && l.status != DoseStatus.late) {
          return false;
        }
        if (l.recordedTime == null) return false;
        return l.recordedTime!.isAfter(twentyFourHoursAgo);
      });

      double totalDoseLast24h = 0;
      for (final log in takenInLast24h) {
        totalDoseLast24h += log.doseAmount;
      }

      if (totalDoseLast24h + medication.doseAmount >
          medication.dailyMaxDose! + 1e-6) {
        final attemptedTotal = totalDoseLast24h + medication.doseAmount;
        throw ClinicalSafetyException(
          risk: ClinicalSafetyRisk.prnMaxDailyDose,
          message:
              'Daily safe limit reached: taking ${MedicationValidator.formatQuantity(medication.doseAmount)} more would reach ${MedicationValidator.formatQuantity(attemptedTotal)}, above the 24-hour maximum of ${MedicationValidator.formatQuantity(medication.dailyMaxDose!)}.',
          clinicalRecommendation:
              'Do not take this dose. Ask your doctor or pharmacist if pain or symptoms continue.',
          safetyContext: {
            'dailyMaxDose': medication.dailyMaxDose,
            'currentTotal24h': totalDoseLast24h,
            'attemptedDose': medication.doseAmount,
          },
        );
      }
    }
  }

  void validateScheduledDoseSafety({
    required Medication medication,
    required DateTime scheduledTime,
    required DateTime nextScheduledTime,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();

    if (checkIsDuplicateDose(medication.id, atTime: now)) {
      throw ClinicalSafetyException(
        risk: ClinicalSafetyRisk.duplicateDose,
        message:
            'Duplicate dose detected: A dose for ${medication.name} was already recorded within the last ${AppConstants.duplicateDoseThresholdMinutes} minutes.',
        clinicalRecommendation:
            'Do not repeat this dose. Contact your doctor or pharmacist if unsure.',
        safetyContext: {
          'medicationId': medication.id,
          'duplicateThresholdMinutes':
              AppConstants.duplicateDoseThresholdMinutes,
        },
      );
    }

    if (now.difference(scheduledTime).inMinutes >
        AppConstants.lateGracePeriodMinutes) {
      throw ClinicalSafetyException(
        risk: ClinicalSafetyRisk.doseStacking,
        message: 'Missed dose window exceeded.',
        clinicalRecommendation:
            'Missed dose. Ask your doctor or pharmacist what to do.',
        safetyContext: {
          'scheduledTime': scheduledTime.toIso8601String(),
          'nextScheduledTime': nextScheduledTime.toIso8601String(),
        },
      );
    }
  }

  void _upsertLocalLog(IntakeLog log) {
    final idx = _allLogs.indexWhere((l) => l.id == log.id);
    final updated = List<IntakeLog>.from(_allLogs);
    if (idx != -1) {
      updated[idx] = log;
    } else {
      updated.insert(0, log);
    }
    updated.sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));
    _allLogs = updated;
    notifyListeners();
  }

  Future<void> recordIntakeAtomic({
    required IntakeLog intakeLog,
    required bool decrementInventory,
  }) async {
    try {
      await _intakeRepository.recordIntakeAtomic(
        intakeLog: intakeLog,
        decrementInventory: decrementInventory,
      );
      _upsertLocalLog(intakeLog);
      _errorMessage = null;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _cancelMatchingScheduledAlarm(
    Medication medication,
    DateTime scheduledTime,
  ) async {
    final times = medication.schedule?.timesOfDay ?? const <String>[];
    final timeStr =
        '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}';
    final idx = times.indexOf(timeStr);
    final notifId = AlarmIdGenerator.generateDoseAlarmId(
      medicationId: medication.id,
      scheduledDateTime: scheduledTime,
      timeIndex: idx >= 0 ? idx : 0,
    );
    await _alarmScheduler.cancelDoseAlarms(notifId);
    await _alarmScheduler.cancelDoseAlarmsForOccurrence(
      medicationId: medication.id,
      scheduledTime: scheduledTime,
    );
  }

  Future<bool> takeDose({
    required Medication medication,
    required DateTime scheduledTime,
    String? notes,
    DateTime? atTime,
  }) async {
    final now = atTime ?? DateTime.now();
    final delayMinutes = now.difference(scheduledTime).inMinutes;

    final status = (delayMinutes > AppConstants.lateGracePeriodMinutes)
        ? DoseStatus.late
        : DoseStatus.taken;

    final intakeLog = IntakeLog(
      id: IntakeLog.generateIdempotentId(
        userId: medication.userId,
        medicationId: medication.id,
        scheduledTime: scheduledTime,
        isPrn: false,
      ),
      userId: medication.userId,
      medicationId: medication.id,
      medicationName: medication.name,
      doseAmount: medication.doseAmount,
      scheduledTime: scheduledTime,
      recordedTime: now,
      status: status,
      notes: notes,
      isPrn: false,
    );

    try {
      await AlarmScheduler.markDoseAcknowledged(
        medication.id,
        scheduledTime,
        terminal: true,
      );
      await _intakeRepository.recordIntakeAtomic(
        intakeLog: intakeLog,
        decrementInventory: isEligibleForAutoDecrement(medication),
      );
      _upsertLocalLog(intakeLog);
      await _cancelMatchingScheduledAlarm(medication, scheduledTime);
      _errorMessage = null;
      return true;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return false;
    }
  }

  bool isEligibleForAutoDecrement(Medication medication) {
    return medication.form == MedicationForm.tablet ||
        medication.form == MedicationForm.capsule;
  }

  Future<bool> correctMissedDoseAsTaken({
    required Medication medication,
    required IntakeLog missedLog,
    String? notes,
    DateTime? atTime,
  }) async {
    final now = atTime ?? DateTime.now();
    final updatedLog = missedLog.copyWith(
      status: DoseStatus.late,
      recordedTime: now,
      notes: notes ?? 'Late correction: Confirmed as taken after missing alarm',
    );

    try {
      await _intakeRepository.recordIntakeAtomic(
        intakeLog: updatedLog,
        decrementInventory: isEligibleForAutoDecrement(medication),
      );
      _upsertLocalLog(updatedLog);
      _errorMessage = null;
      return true;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return false;
    }
  }

  Future<bool> undoTakenDose({
    required Medication medication,
    required IntakeLog takenLog,
  }) async {
    try {
      await _intakeRepository.undoTakeDoseAtomic(
        intakeLog: takenLog,
        restoreInventory: isEligibleForAutoDecrement(medication),
      );
      await AlarmScheduler.unmarkDoseAcknowledged(
        medication.id,
        takenLog.scheduledTime,
      );
      final now = DateTime.now();
      if (takenLog.scheduledTime.isAfter(now)) {
        unawaited(_alarmScheduler.scheduleRecurringMedication(medication));
      }
      final isPastGrace = now.difference(takenLog.scheduledTime).inMinutes >
          AppConstants.lateGracePeriodMinutes;
      if (isPastGrace) {
        _upsertLocalLog(
          IntakeLog(
            id: takenLog.id,
            userId: takenLog.userId,
            medicationId: takenLog.medicationId,
            medicationName: takenLog.medicationName,
            doseAmount: takenLog.doseAmount,
            scheduledTime: takenLog.scheduledTime,
            status: DoseStatus.missed,
            snoozeCount: takenLog.snoozeCount,
            notes: 'Undone by user',
            isPrn: takenLog.isPrn,
          ),
        );
      } else {
        _allLogs = _allLogs.where((l) => l.id != takenLog.id).toList();
        notifyListeners();
      }
      _errorMessage = null;
      return true;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return false;
    }
  }

  Future<void> logPrnDose({
    required Medication medication,
    String? notes,
  }) async {
    validatePrnSafety(medication);

    final now = DateTime.now();
    final intakeLog = IntakeLog(
      id: IntakeLog.generateIdempotentId(
        userId: medication.userId,
        medicationId: medication.id,
        scheduledTime: now,
        isPrn: true,
      ),
      userId: medication.userId,
      medicationId: medication.id,
      medicationName: medication.name,
      doseAmount: medication.doseAmount,
      scheduledTime: now,
      recordedTime: now,
      status: DoseStatus.taken,
      notes: notes,
      isPrn: true,
    );

    try {
      await _intakeRepository.recordIntakeAtomic(
        intakeLog: intakeLog,
        decrementInventory: isEligibleForAutoDecrement(medication),
      );
      _upsertLocalLog(intakeLog);
      _errorMessage = null;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
    }
  }

  Future<bool> skipDose({
    required Medication medication,
    required DateTime scheduledTime,
    String? reason,
  }) async {
    final intakeLog = IntakeLog(
      id: IntakeLog.generateIdempotentId(
        userId: medication.userId,
        medicationId: medication.id,
        scheduledTime: scheduledTime,
        isPrn: false,
      ),
      userId: medication.userId,
      medicationId: medication.id,
      medicationName: medication.name,
      doseAmount: medication.doseAmount,
      scheduledTime: scheduledTime,
      recordedTime: DateTime.now(),
      status: DoseStatus.skipped,
      notes: reason ?? 'Skipped by user',
    );

    try {
      await AlarmScheduler.markDoseAcknowledged(
        medication.id,
        scheduledTime,
        terminal: true,
      );
      await _intakeRepository.recordIntakeAtomic(
        intakeLog: intakeLog,
        decrementInventory: false,
      );
      _upsertLocalLog(intakeLog);
      await _cancelMatchingScheduledAlarm(medication, scheduledTime);
      _errorMessage = null;
      return true;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return false;
    }
  }

  Future<bool> snoozeDose({
    required Medication medication,
    required DateTime scheduledTime,
    int snoozeMinutes = AppConstants.defaultSnoozeDurationMinutes,
  }) async {
    final now = DateTime.now();
    final delayMinutes = now.difference(scheduledTime).inMinutes;

    if (delayMinutes > DoseStateMachine.missedThresholdMinutes) {
      _errorMessage =
          'Cannot snooze dose: 60-minute alarm acknowledgment window has expired.';
      notifyListeners();
      return false;
    }

    final matchingLog = _allLogs.cast<IntakeLog?>().firstWhere(
          (l) =>
              l?.medicationId == medication.id &&
              l?.scheduledTime.year == scheduledTime.year &&
              l?.scheduledTime.month == scheduledTime.month &&
              l?.scheduledTime.day == scheduledTime.day &&
              l?.scheduledTime.hour == scheduledTime.hour &&
              l?.scheduledTime.minute == scheduledTime.minute,
          orElse: () => null,
        );

    final currentSnoozeCount = matchingLog?.snoozeCount ?? 0;
    if (currentSnoozeCount >= DoseStateMachine.maxSnoozeLimit) {
      _errorMessage =
          'Cannot snooze dose: Maximum of ${DoseStateMachine.maxSnoozeLimit} snoozes reached.';
      notifyListeners();
      return false;
    }

    // Determine accurate timeIndex based on schedule to prevent slot collision (A5)
    int calculatedTimeIndex = 0;
    if (medication.schedule != null) {
      final times = medication.schedule!.timesOfDay;
      for (int i = 0; i < times.length; i++) {
        final parsed = ScheduleExpander.parseTimeOfDay(times[i]);
        if (parsed != null &&
            parsed.$1 == scheduledTime.hour &&
            parsed.$2 == scheduledTime.minute) {
          calculatedTimeIndex = i;
          break;
        }
      }
    }

    final snoozeTime = now.add(Duration(minutes: snoozeMinutes));
    final nextSnoozeCount = currentSnoozeCount + 1;
    final intakeLog = IntakeLog(
      id: IntakeLog.generateIdempotentId(
        userId: medication.userId,
        medicationId: medication.id,
        scheduledTime: scheduledTime,
        isPrn: false,
      ),
      userId: medication.userId,
      medicationId: medication.id,
      medicationName: medication.name,
      doseAmount: medication.doseAmount,
      scheduledTime: scheduledTime,
      recordedTime: now,
      status: DoseStatus.snoozed,
      snoozeUntil: snoozeTime,
      snoozeCount: nextSnoozeCount,
      notes:
          'Snoozed for ${snoozeMinutes}m ($nextSnoozeCount/${DoseStateMachine.maxSnoozeLimit})',
    );

    try {
      await AlarmScheduler.markDoseAcknowledged(
        medication.id,
        scheduledTime,
        terminal: false,
      );
      await _intakeRepository.recordIntakeAtomic(
        intakeLog: intakeLog,
        decrementInventory: false,
      );
      _upsertLocalLog(intakeLog);
      await _cancelMatchingScheduledAlarm(medication, scheduledTime);
      final notifId = AlarmIdGenerator.generateDoseAlarmId(
        medicationId: medication.id,
        scheduledDateTime: scheduledTime,
        timeIndex: calculatedTimeIndex,
      );
      await _alarmScheduler.scheduleSnoozeAlarm(
        notificationId: notifId,
        medication: medication,
        originalScheduledTime: scheduledTime,
        snoozeMinutes: snoozeMinutes,
        snoozeCount: nextSnoozeCount,
      );
      _errorMessage = null;
      return true;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _logsSubscription?.cancel();
    super.dispose();
  }
}
