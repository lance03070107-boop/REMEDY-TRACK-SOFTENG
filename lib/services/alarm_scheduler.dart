import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../core/constants/app_constants.dart';
import '../core/scheduling/schedule_expander.dart';
import '../core/state/dose_state_machine.dart';
import '../core/utils/app_logger.dart';
import '../models/medication.dart';
import 'alarm_id_generator.dart';
import 'crashlytics_service.dart';
import 'local_medication_cache.dart';
import 'notification_service.dart';

/// Schedules exact, battery-resilient alarms for medication doses and snooze escalations.
/// Incorporates graceful degraded mode for Android 12+/13+/14+, looping STREAM_ALARM audio,
/// collision-proof FNV-1a IDs, and a fair round-robin rolling window across the iOS 64-notification ceiling.
class AlarmScheduler {
  final NotificationService _notificationService;

  /// Key used to persist active dose alarm IDs so rescheduling does not wipe low-stock alerts.
  static const String keyActiveDoseAlarmIds = 'remedy_active_dose_alarm_ids';

  /// Keys used to persist handled/terminal doses so dismissed or taken doses do not re-trigger.
  static const String keyTerminalDoseMap = 'remedy_terminal_dose_map';
  static const String keyHandledSlotDoseMap = 'remedy_handled_slot_dose_map';
  static const int _ackRetentionMs = 48 * 60 * 60 * 1000;
  static const int _maxAckEntries = 120;

  /// Global lock serializing all alarm cancellations and reschedulings to eliminate race conditions
  static Future<void> _rescheduleLock = Future.value();

  /// Direct callback invoked when an alarm triggers in the foreground or via active timer
  static void Function(Map<String, dynamic> alarmData)? onAlarmTriggered;

  /// Active in-memory timers for scheduled doses within the rolling window.
  /// Guarantees that alarms pop up immediately like an alarm clock when triggered.
  static final Map<int, Timer> _activeDoseTimers = {};
  static final Map<int, String> _activeDoseLogIds = {};

  /// Synchronous in-memory caches of terminal (taken/skipped) and slot-handled (snoozed/shown) dose log IDs.
  static final Set<String> _terminalDoseIds = <String>{};
  static final Set<String> _handledSlotDoseIds = <String>{};

  static Map<String, int> _decodePrunedAckMap(String? rawJson, int cutoffMs) {
    final result = <String, int>{};
    if (rawJson == null || rawJson.isEmpty) return result;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final ts = (value as num?)?.toInt() ?? 0;
          if (ts >= cutoffMs) {
            result[key.toString()] = ts;
          }
        });
      }
    } catch (_) {}

    if (result.length > _maxAckEntries) {
      final sorted = result.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return Map<String, int>.fromEntries(sorted.take(_maxAckEntries));
    }
    return result;
  }

  /// Returns true if the specified dose has already been taken or skipped.
  static bool isDoseTerminal(String medicationId, DateTime scheduledTime) {
    if (medicationId.isEmpty) return false;
    final logId = DoseStateMachine.generateLogId(medicationId, scheduledTime);
    return _terminalDoseIds.contains(logId);
  }

  /// Returns true if the original scheduled slot was already handled (taken, skipped, snoozed, or already triggered).
  static bool isDoseSlotHandled(String medicationId, DateTime scheduledTime) {
    if (medicationId.isEmpty) return false;
    final logId = DoseStateMachine.generateLogId(medicationId, scheduledTime);
    return _terminalDoseIds.contains(logId) ||
        _handledSlotDoseIds.contains(logId);
  }

  /// Persists that a dose slot has been handled (or terminally taken/skipped) across isolates and restarts.
  static Future<void> markDoseAcknowledged(
    String medicationId,
    DateTime scheduledTime, {
    bool terminal = true,
  }) async {
    if (medicationId.isEmpty) return;
    final logId = DoseStateMachine.generateLogId(medicationId, scheduledTime);
    _handledSlotDoseIds.add(logId);
    if (terminal) {
      _terminalDoseIds.add(logId);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cutoffMs = DateTime.now().millisecondsSinceEpoch - _ackRetentionMs;
      final schedMs = scheduledTime.millisecondsSinceEpoch;

      final handledMap = _decodePrunedAckMap(
        prefs.getString(keyHandledSlotDoseMap),
        cutoffMs,
      );
      handledMap[logId] = schedMs;
      await prefs.setString(
        keyHandledSlotDoseMap,
        jsonEncode(_decodePrunedAckMap(jsonEncode(handledMap), cutoffMs)),
      );

      if (terminal) {
        final terminalMap = _decodePrunedAckMap(
          prefs.getString(keyTerminalDoseMap),
          cutoffMs,
        );
        terminalMap[logId] = schedMs;
        await prefs.setString(
          keyTerminalDoseMap,
          jsonEncode(_decodePrunedAckMap(jsonEncode(terminalMap), cutoffMs)),
        );
      }
    } catch (e, s) {
      AppLogger.w('Failed to persist acknowledged dose state: $e',
          tag: 'AlarmScheduler', error: e, stackTrace: s);
    }
  }

  /// Clears a dose's acknowledged/terminal flags (e.g., when the user taps Undo on a taken dose).
  static Future<void> unmarkDoseAcknowledged(
    String medicationId,
    DateTime scheduledTime,
  ) async {
    if (medicationId.isEmpty) return;
    final logId = DoseStateMachine.generateLogId(medicationId, scheduledTime);
    _terminalDoseIds.remove(logId);
    _handledSlotDoseIds.remove(logId);

    try {
      final prefs = await SharedPreferences.getInstance();
      final cutoffMs = DateTime.now().millisecondsSinceEpoch - _ackRetentionMs;

      final handledMap = _decodePrunedAckMap(
        prefs.getString(keyHandledSlotDoseMap),
        cutoffMs,
      )..remove(logId);
      await prefs.setString(keyHandledSlotDoseMap, jsonEncode(handledMap));

      final terminalMap = _decodePrunedAckMap(
        prefs.getString(keyTerminalDoseMap),
        cutoffMs,
      )..remove(logId);
      await prefs.setString(keyTerminalDoseMap, jsonEncode(terminalMap));
    } catch (e, s) {
      AppLogger.w('Failed to unmark acknowledged dose state: $e',
          tag: 'AlarmScheduler', error: e, stackTrace: s);
    }
  }

  /// Synchronizes in-memory handled/terminal dose caches with [SharedPreferences].
  static Future<void> refreshAcknowledgedDosesFromPrefs({
    bool reloadPrefs = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (reloadPrefs) {
        try {
          await prefs.reload();
        } catch (_) {}
      }
      final cutoffMs = DateTime.now().millisecondsSinceEpoch - _ackRetentionMs;
      final terminalMap = _decodePrunedAckMap(
        prefs.getString(keyTerminalDoseMap),
        cutoffMs,
      );
      final handledMap = _decodePrunedAckMap(
        prefs.getString(keyHandledSlotDoseMap),
        cutoffMs,
      );
      _terminalDoseIds
        ..clear()
        ..addAll(terminalMap.keys);
      _handledSlotDoseIds
        ..clear()
        ..addAll(handledMap.keys);
    } catch (e, s) {
      AppLogger.w('Failed to refresh acknowledged doses from prefs: $e',
          tag: 'AlarmScheduler', error: e, stackTrace: s);
    }
  }

  /// Clears stored dose acknowledgement caches (e.g., on sign-out).
  static Future<void> clearAcknowledgedDoses() async {
    _terminalDoseIds.clear();
    _handledSlotDoseIds.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyTerminalDoseMap);
      await prefs.remove(keyHandledSlotDoseMap);
    } catch (e, s) {
      AppLogger.w('Failed to clear acknowledged doses: $e',
          tag: 'AlarmScheduler', error: e, stackTrace: s);
    }
  }

  /// Observable state signaling if alarms are operating in degraded (inexact) mode.
  final ValueNotifier<bool> isExactAlarmDegradedNotifier =
      ValueNotifier<bool>(false);

  /// Hard cap on scheduled notifications to prevent hitting iOS's 64 pending limit.
  /// (30 primary + 30 escalation = 60 <= 64 iOS ceiling)
  static const int maxRollingWindowAlarms = AppConstants.maxRollingWindowAlarms;

  AlarmScheduler({NotificationService? notificationService})
      : _notificationService = notificationService ?? NotificationService();

  bool get isExactAlarmDegraded => isExactAlarmDegradedNotifier.value;

  /// Executes [task] strictly serialized through the global queue to prevent race conditions.
  static Future<T> _serialized<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _rescheduleLock = _rescheduleLock.then((_) async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }

  /// Checks if the host Android OS currently permits exact alarm dispatch and background pop-ups.
  Future<bool> checkExactAlarmCapability() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final canSchedule = await Permission.scheduleExactAlarm.isGranted;
        bool canOverlay = true;
        try {
          const channel = MethodChannel('com.remedytrack.app/alarm_window');
          canOverlay =
              await channel.invokeMethod<bool>('canDrawOverlays') ?? true;
        } catch (_) {}
        isExactAlarmDegradedNotifier.value = !(canSchedule && canOverlay);
        return canSchedule;
      } catch (e, s) {
        AppLogger.w('Exact alarm capability check notice: $e',
            tag: 'AlarmScheduler', error: e, stackTrace: s);
      }
    }
    return true;
  }

  /// Shared builder creating identical AndroidNotificationDetails and DarwinNotificationDetails
  /// for medication dose alarms.
  static NotificationDetails buildAlarmNotificationDetails({
    required String tone,
    required String title,
    required String body,
  }) {
    final channelId = AppConstants.getAlarmChannelId(tone);
    final resolvedResourceTone = AppConstants.availableAlarmSounds.contains(tone)
        ? tone
        : AppConstants.defaultAlarmSound;
    final toneTitle = NotificationService.getToneTitle(tone);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      'Medication Alarms ($toneTitle)',
      channelDescription: AppConstants.alarmChannelDescriptionV3,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      ongoing: true,
      visibility: NotificationVisibility.public,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      sound: RawResourceAndroidNotificationSound(resolvedResourceTone),
      onlyAlertOnce: true,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          AppConstants.actionTaken,
          'Taken',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          AppConstants.actionSnooze,
          'Snooze',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          AppConstants.actionSkip,
          'Skip',
          showsUserInterface: true,
        ),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: '$resolvedResourceTone.wav',
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'MED_ALARM_CATEGORY',
    );

    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  /// Shared builder creating canonical JSON payload matching NotificationService expectations.
  static String buildAlarmPayload({
    required Medication medication,
    required int notificationId,
    required int primaryNotifId,
    required DateTime scheduledDateTime,
    required String soundId,
    int snoozeCount = 0,
    DateTime? triggerDateTime,
  }) {
    return jsonEncode({
      'medId': medication.id,
      'notifId': notificationId,
      'primaryNotifId': primaryNotifId,
      'sched': scheduledDateTime.toIso8601String(),
      'triggerAt': (triggerDateTime ?? scheduledDateTime).toIso8601String(),
      'userId': medication.userId,
      'medName': medication.name,
      'doseAmount': medication.doseAmount,
      'strength': medication.strength,
      'form': medication.form.name,
      'colorTag': medication.colorTag,
      'instructions': medication.instructions,
      'soundId': soundId,
      'customPath': medication.customSoundPath ?? '',
      'vibrate': medication.vibrationEnabled,
      'snoozeCount': snoozeCount,
    });
  }

  /// Schedules a dose alarm with lock-screen action buttons (Taken / Snooze / Skip).
  Future<void> scheduleDoseAlarm({
    required int notificationId,
    required Medication medication,
    required DateTime scheduledDateTime,
    DateTime? triggerDateTimeOverride,
    int escalationMinutes = AppConstants.defaultEscalationMinutes,
    int snoozeCount = 0,
  }) async {
    if (kIsWeb) return;

    try {
      if (isDoseTerminal(medication.id, scheduledDateTime)) return;
      if (snoozeCount == 0 &&
          isDoseSlotHandled(medication.id, scheduledDateTime)) {
        return;
      }

      await _notificationService.ensureTimeZoneInitialized();

      final effectiveTriggerTime = triggerDateTimeOverride ?? scheduledDateTime;
      final tzScheduledTime =
          tz.TZDateTime.from(effectiveTriggerTime, tz.local);
      if (tzScheduledTime.isBefore(tz.TZDateTime.now(tz.local))) {
        return; // Never schedule in the past
      }

      final canExact = await checkExactAlarmCapability();
      final scheduleMode = canExact
          ? AndroidScheduleMode.alarmClock
          : AndroidScheduleMode.inexactAllowWhileIdle;

      // Read user's chosen alarm tone from medication or persistent settings
      final prefs = await SharedPreferences.getInstance();
      final defaultTone = prefs.getString(AppConstants.keyAlarmSound) ??
          AppConstants.defaultAlarmSound;
      final tone = medication.alarmSoundId.isNotEmpty
          ? medication.alarmSoundId
          : defaultTone;

      final formattedAmount =
          medication.doseAmount == medication.doseAmount.truncateToDouble()
              ? medication.doseAmount.toInt().toString()
              : medication.doseAmount.toString();
      final inst = medication.instructions.trim();
      final bodyText = inst.isNotEmpty
          ? 'Prescribed dose: $formattedAmount ${medication.form.name}. $inst'
          : 'Prescribed dose: $formattedAmount ${medication.form.name}';

      final notificationDetails = buildAlarmNotificationDetails(
        tone: tone,
        title: 'Time for your ${medication.name}',
        body: bodyText,
      );

      final payload = buildAlarmPayload(
        medication: medication,
        notificationId: notificationId,
        primaryNotifId: notificationId,
        scheduledDateTime: scheduledDateTime,
        soundId: tone,
        snoozeCount: snoozeCount,
        triggerDateTime: effectiveTriggerTime,
      );

      try {
        await _notificationService.flutterLocalNotificationsPlugin
            .zonedSchedule(
          notificationId,
          'Time for your ${medication.name}',
          bodyText,
          tzScheduledTime,
          notificationDetails,
          androidScheduleMode: scheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
      } on PlatformException catch (e) {
        if (e.code == 'exact_alarms_not_permitted') {
          AppLogger.w(
            'Exact alarms not permitted; falling back to inexact schedule.',
            tag: 'AlarmScheduler',
          );
          isExactAlarmDegradedNotifier.value = true;
          await _notificationService.flutterLocalNotificationsPlugin
              .zonedSchedule(
            notificationId,
            'Time for your ${medication.name}',
            bodyText,
            tzScheduledTime,
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload,
          );
        } else {
          rethrow;
        }
      }

      // Schedule native Android AlarmClock so the screen wakes and MainActivity pops up directly
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          const channel = MethodChannel('com.remedytrack.app/alarm_window');
          await channel.invokeMethod('scheduleNativeAlarm', {
            'id': notificationId,
            'triggerTimeMillis': effectiveTriggerTime.millisecondsSinceEpoch,
            'payload': payload,
          });
        } catch (e, s) {
          AppLogger.w('Native AlarmClock scheduling error: $e',
              tag: 'AlarmScheduler', error: e, stackTrace: s);
        }
      }

      // Verify scheduling registration in the native notification engine
      if (!kIsWeb) {
        final pending = await _notificationService
            .flutterLocalNotificationsPlugin
            .pendingNotificationRequests();
        final scheduled = pending.any((req) => req.id == notificationId);
        if (!scheduled) {
          AppLogger.e(
            'Verification warning: Notification ID $notificationId not found in pending requests.',
            tag: 'AlarmScheduler',
          );
        }
      }

      // Active foreground/wake alarm trigger timer: pops up alarm screen immediately when due
      final durationUntilAlarm = effectiveTriggerTime.difference(DateTime.now());
      if (!durationUntilAlarm.isNegative && durationUntilAlarm.inHours < 24) {
        _activeDoseTimers[notificationId]?.cancel();
        _activeDoseLogIds[notificationId] =
            DoseStateMachine.generateLogId(medication.id, scheduledDateTime);
        _activeDoseTimers[notificationId] = Timer(durationUntilAlarm, () {
          _activeDoseTimers.remove(notificationId);
          _activeDoseLogIds.remove(notificationId);
          if (isDoseTerminal(medication.id, scheduledDateTime)) return;
          if (snoozeCount == 0 &&
              isDoseSlotHandled(medication.id, scheduledDateTime)) {
            return;
          }
          if (snoozeCount == 0) {
            unawaited(markDoseAcknowledged(
              medication.id,
              scheduledDateTime,
              terminal: false,
            ));
          }
          if (onAlarmTriggered != null) {
            onAlarmTriggered!({
              'medId': medication.id,
              'userId': medication.userId,
              'notifId': notificationId,
              'primaryNotifId': notificationId,
              'sched': scheduledDateTime.toIso8601String(),
              'medName': medication.name,
              'doseAmount': medication.doseAmount,
              'strength': medication.strength,
              'form': medication.form.name,
              'colorTag': medication.colorTag,
              'instructions': medication.instructions,
              'soundId': tone,
              'customPath': medication.customSoundPath ?? '',
              'vibrate': medication.vibrationEnabled,
              'snoozeCount': snoozeCount,
            });
          }
        });
      }

      // Schedule escalation alert if configured
      if (escalationMinutes > 0) {
        final escalationTrigger =
            effectiveTriggerTime.add(Duration(minutes: escalationMinutes));
        final escalationTime =
            tzScheduledTime.add(Duration(minutes: escalationMinutes));
        final escalationId = AlarmIdGenerator.getEscalationId(notificationId);

        final escalationPayload = buildAlarmPayload(
          medication: medication,
          notificationId: escalationId,
          primaryNotifId: notificationId,
          scheduledDateTime: scheduledDateTime,
          soundId: tone,
          snoozeCount: snoozeCount,
          triggerDateTime: escalationTrigger,
        );

        await _notificationService.flutterLocalNotificationsPlugin
            .zonedSchedule(
          escalationId,
          'URGENT REMINDER: ${medication.name}',
          'You have an unconfirmed dose of ${medication.name} from $escalationMinutes minutes ago.',
          escalationTime,
          notificationDetails,
          androidScheduleMode: scheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: escalationPayload,
        );
      }
    } catch (e, stack) {
      AppLogger.e('Failed to schedule dose alarm: $e',
          tag: 'AlarmScheduler', error: e, stackTrace: stack);
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'AlarmScheduler.scheduleDoseAlarm'));
    }
  }

  /// Schedules a quick snooze reminder for a specific dose.
  Future<void> scheduleSnoozeAlarm({
    required int notificationId,
    required Medication medication,
    required DateTime originalScheduledTime,
    int snoozeMinutes = AppConstants.defaultSnoozeDurationMinutes,
    int snoozeCount = 1,
  }) async {
    if (kIsWeb) return;
    await markDoseAcknowledged(
      medication.id,
      originalScheduledTime,
      terminal: false,
    );
    await cancelDoseAlarms(notificationId);
    final snoozeTime = DateTime.now().add(Duration(minutes: snoozeMinutes));
    await scheduleDoseAlarm(
      notificationId: notificationId,
      medication: medication,
      scheduledDateTime: originalScheduledTime,
      triggerDateTimeOverride: snoozeTime,
      escalationMinutes: 0,
      snoozeCount: snoozeCount,
    );
  }

  /// Cancels both primary and escalation alarm IDs.
  Future<void> cancelDoseAlarms(int notificationId) async {
    if (kIsWeb) return;
    final primaryId = AlarmIdGenerator.getPrimaryId(notificationId);
    _activeDoseTimers[primaryId]?.cancel();
    _activeDoseTimers.remove(primaryId);
    _activeDoseLogIds.remove(primaryId);
    _activeDoseTimers[notificationId]?.cancel();
    _activeDoseTimers.remove(notificationId);
    _activeDoseLogIds.remove(notificationId);

    await _notificationService.cancelNotification(primaryId);
    await _notificationService.cancelNotification(
      AlarmIdGenerator.getEscalationId(primaryId),
    );
    if (notificationId != primaryId) {
      await _notificationService.cancelNotification(notificationId);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        const channel = MethodChannel('com.remedytrack.app/alarm_window');
        await channel.invokeMethod('cancelNativeAlarm', {'id': primaryId});
        if (notificationId != primaryId) {
          await channel
              .invokeMethod('cancelNativeAlarm', {'id': notificationId});
        }
      } catch (e, stack) {
        unawaited(
          CrashlyticsService.recordError(
            e,
            stack,
            reason: 'cancelNativeAlarm channel error',
          ),
        );
      }
    }
  }

  /// Cancels every scheduled primary, escalation, or snooze alarm associated with a dose occurrence.
  Future<void> cancelDoseAlarmsForOccurrence({
    required String medicationId,
    required DateTime scheduledTime,
  }) async {
    if (medicationId.isEmpty) return;
    final targetLogId =
        DoseStateMachine.generateLogId(medicationId, scheduledTime);

    final matchingTimerIds = _activeDoseLogIds.entries
        .where((e) => e.value == targetLogId)
        .map((e) => e.key)
        .toList();
    for (final id in matchingTimerIds) {
      _activeDoseTimers[id]?.cancel();
      _activeDoseTimers.remove(id);
      _activeDoseLogIds.remove(id);
    }

    if (kIsWeb) return;

    final Set<int> idsToCancel = <int>{...matchingTimerIds};
    try {
      final pending = await _notificationService
          .flutterLocalNotificationsPlugin
          .pendingNotificationRequests();
      for (final req in pending) {
        final rawPayload = req.payload;
        if (rawPayload == null || rawPayload.isEmpty) continue;
        try {
          final decoded = jsonDecode(rawPayload);
          if (decoded is Map<String, dynamic> &&
              decoded['medId'] == medicationId) {
            final schedRaw = decoded['sched'] as String?;
            final sched = schedRaw != null ? DateTime.tryParse(schedRaw) : null;
            if (sched != null &&
                DoseStateMachine.generateLogId(medicationId, sched) ==
                    targetLogId) {
              idsToCancel.add(req.id);
              final primary = (decoded['primaryNotifId'] as num?)?.toInt();
              if (primary != null) idsToCancel.add(primary);
            }
          }
        } catch (_) {}
      }
    } catch (e, s) {
      AppLogger.w('Inspect pending dose requests notice: $e',
          tag: 'AlarmScheduler', error: e, stackTrace: s);
    }

    for (var timeIdx = 0; timeIdx < AppConstants.maxTimeSlots; timeIdx++) {
      idsToCancel.add(AlarmIdGenerator.generateDoseAlarmId(
        medicationId: medicationId,
        scheduledDateTime: scheduledTime,
        timeIndex: timeIdx,
      ));
    }

    for (final id in idsToCancel) {
      await cancelDoseAlarms(id);
    }
  }

  /// Reschedules all upcoming doses for all active medications using a fair round-robin rolling window.
  /// Strictly serialized through the global queue to eliminate race conditions between Firestore streams and local updates.
  Future<void> rescheduleAllAlarms(List<Medication> activeMedications) {
    if (kIsWeb) return Future.value();
    return _serialized(() => _rescheduleAllAlarmsInternal(activeMedications));
  }

  /// Cancels all scheduled dose alarms and in-memory timers (e.g., on user sign-out).
  Future<void> cancelAllAlarms({bool clearAcknowledged = true}) async {
    for (final timer in _activeDoseTimers.values) {
      timer.cancel();
    }
    _activeDoseTimers.clear();
    _activeDoseLogIds.clear();

    if (kIsWeb) {
      if (clearAcknowledged) {
        await clearAcknowledgedDoses();
      }
      return;
    }

    await _serialized(() => _rescheduleAllAlarmsInternal(const []));
    if (clearAcknowledged) {
      await clearAcknowledgedDoses();
    }
  }

  /// Tracks notification IDs currently presented on [AlarmRingingScreen] so
  /// background/stream-triggered [rescheduleAllAlarms] never cancels an active alarm notification.
  static final Set<int> activeRingingNotificationIds = <int>{};

  Future<void> _rescheduleAllAlarmsInternal(
      List<Medication> activeMedications) async {
    try {
      await _notificationService.ensureTimeZoneInitialized();
      await refreshAcknowledgedDosesFromPrefs();

      // Cancel and flush all previous in-memory active timers
      for (final timer in _activeDoseTimers.values) {
        timer.cancel();
      }
      _activeDoseTimers.clear();
      _activeDoseLogIds.clear();

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();

      // Index active non-PRN medications for snooze preservation across unrelated edits
      final Map<String, Medication> activeMedById = {
        for (final m in activeMedications)
          if (m.isActive && !m.isPrn && m.schedule != null) m.id: m,
      };

      // Protect notifications of doses that are currently ringing or due within the active
      // grace window and not yet terminal so stream syncs never wipe out an active notification.
      final Set<int> protectedDueIds = <int>{...activeRingingNotificationIds};
      final graceWindowStart = now.subtract(
        const Duration(minutes: AppConstants.lateGracePeriodMinutes),
      );
      for (final med in activeMedById.values) {
        final recentOccurrences = ScheduleExpander.expandOccurrences(
          medication: med,
          start: graceWindowStart,
          end: now.add(const Duration(minutes: 1)),
        );
        for (final occ in recentOccurrences) {
          if (!isDoseTerminal(med.id, occ.scheduledDateTime)) {
            protectedDueIds.add(occ.notificationId);
          }
        }
      }

      final List<
          ({
            int notifId,
            Medication med,
            DateTime scheduledTime,
            DateTime triggerTime,
            int snoozeCount,
          })> preservedSnoozes = [];
      final Set<int> idsToCancel = <int>{};

      final previousAlarmIds = prefs.getStringList(keyActiveDoseAlarmIds) ?? [];
      for (final idStr in previousAlarmIds) {
        final id = int.tryParse(idStr);
        if (id != null) {
          final primaryId = AlarmIdGenerator.getPrimaryId(id);
          idsToCancel.add(primaryId);
          idsToCancel.add(AlarmIdGenerator.getEscalationId(primaryId));
        }
      }

      // Inspect every pending local notification outside low-stock alert range [900000..999999]
      try {
        final pendingRequests = await _notificationService
            .flutterLocalNotificationsPlugin
            .pendingNotificationRequests();
        for (final req in pendingRequests) {
          if (req.id >= 900000 && req.id <= 999999) continue;
          idsToCancel.add(req.id);

          if (activeMedById.isNotEmpty &&
              req.payload != null &&
              req.payload!.isNotEmpty) {
            try {
              final decoded = jsonDecode(req.payload!);
              if (decoded is Map<String, dynamic>) {
                final snoozeCount =
                    (decoded['snoozeCount'] as num?)?.toInt() ?? 0;
                final medId = decoded['medId'] as String?;
                final schedRaw = decoded['sched'] as String?;
                final triggerRaw = decoded['triggerAt'] as String?;
                if (snoozeCount > 0 &&
                    medId != null &&
                    schedRaw != null &&
                    triggerRaw != null) {
                  final med = activeMedById[medId];
                  final schedTime = DateTime.tryParse(schedRaw);
                  final triggerTime = DateTime.tryParse(triggerRaw);
                  if (med != null &&
                      schedTime != null &&
                      triggerTime != null &&
                      triggerTime.isAfter(now) &&
                      !isDoseTerminal(medId, schedTime)) {
                    final notifId =
                        (decoded['primaryNotifId'] as num?)?.toInt() ?? req.id;
                    preservedSnoozes.add((
                      notifId: notifId,
                      med: med,
                      scheduledTime: schedTime,
                      triggerTime: triggerTime,
                      snoozeCount: snoozeCount,
                    ));
                  }
                }
              }
            } catch (_) {}
          }
        }
      } catch (e, s) {
        AppLogger.w('Pending requests cleanup notice: $e',
            tag: 'AlarmScheduler', error: e, stackTrace: s);
      }

      idsToCancel.removeAll(protectedDueIds);
      for (final id in idsToCancel) {
        await _notificationService.cancelNotification(id);
      }

      // Cancel all native Android AlarmClock schedules so deleted/edited/signed-out
      // alarms never fire from AlarmManager even without a cached ID match.
      // Pass stopActivePlayer=false when refreshing schedules so an actively ringing
      // alarm is never silenced mid-ring by a Firestore stream update.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final shouldStopPlayer =
            activeMedications.isEmpty && activeRingingNotificationIds.isEmpty;
        try {
          const channel = MethodChannel('com.remedytrack.app/alarm_window');
          await channel.invokeMethod('cancelAllNativeAlarms', {
            'stopActivePlayer': shouldStopPlayer,
          });
        } catch (e) {
          for (final id in idsToCancel) {
            try {
              const channel = MethodChannel('com.remedytrack.app/alarm_window');
              await channel.invokeMethod('cancelNativeAlarm', {'id': id});
            } catch (_) {}
          }
          AppLogger.d('cancelAllNativeAlarms fallback notice: $e',
              tag: 'AlarmScheduler');
        }
      }

      final windowEnd = now.add(const Duration(days: 7));

      // 1. Gather upcoming occurrences grouped by medication using ScheduleExpander
      final Map<String, List<ScheduledDoseOccurrence>> medOccurrences = {};
      for (final med in activeMedications) {
        if (!med.isActive || med.isPrn || med.schedule == null) continue;
        final list = ScheduleExpander.expandOccurrences(
          medication: med,
          start: now,
          end: windowEnd,
        )
            .where((occ) =>
                !isDoseSlotHandled(occ.medication.id, occ.scheduledDateTime))
            .toList();
        if (list.isNotEmpty) {
          medOccurrences[med.id] = list;
        }
      }

      // 2. Fair round-robin allocation per medication across the 30-alarm limit (A1)
      final List<ScheduledDoseOccurrence> toSchedule = [];
      final activeMedIds = medOccurrences.keys.toList();

      while (toSchedule.length < maxRollingWindowAlarms &&
          medOccurrences.values.any((list) => list.isNotEmpty)) {
        bool addedAny = false;
        for (final medId in activeMedIds) {
          final list = medOccurrences[medId];
          if (list != null && list.isNotEmpty) {
            toSchedule.add(list.removeAt(0));
            addedAny = true;
            if (toSchedule.length >= maxRollingWindowAlarms) break;
          }
        }
        if (!addedAny) break;
      }

      // Sort chronological before scheduling
      toSchedule
          .sort((a, b) => a.scheduledDateTime.compareTo(b.scheduledDateTime));

      final escalationMinutes =
          prefs.getInt(AppConstants.keyEscalationMinutes) ??
              AppConstants.defaultEscalationMinutes;

      final Set<int> newAlarmIds = <int>{};
      for (final occ in toSchedule) {
        newAlarmIds.add(occ.notificationId);
        await scheduleDoseAlarm(
          notificationId: occ.notificationId,
          medication: occ.medication,
          scheduledDateTime: occ.scheduledDateTime,
          escalationMinutes: escalationMinutes,
        );
      }

      // Re-schedule preserved active snoozes cleanly (only while user remains signed in & med active)
      for (final snooze in preservedSnoozes) {
        newAlarmIds.add(snooze.notifId);
        await scheduleDoseAlarm(
          notificationId: snooze.notifId,
          medication: snooze.med,
          scheduledDateTime: snooze.scheduledTime,
          triggerDateTimeOverride: snooze.triggerTime,
          escalationMinutes: 0,
          snoozeCount: snooze.snoozeCount,
        );
      }

      await prefs.setStringList(
        keyActiveDoseAlarmIds,
        newAlarmIds.map((id) => id.toString()).toList(),
      );

      AppLogger.i(
        'Fair rolling-window scheduled ${toSchedule.length} alarms (+${preservedSnoozes.length} active snoozes) across ${activeMedIds.length} active medications.',
        tag: 'AlarmScheduler',
      );
    } catch (e, stack) {
      AppLogger.e('rescheduleAllAlarms error: $e',
          tag: 'AlarmScheduler', error: e, stackTrace: stack);
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'AlarmScheduler.rescheduleAllAlarms'));
    }
  }

  /// Refills the rolling-window alarms using cached medications from local store.
  /// Designed to be executed safely in background isolates (WorkManager),
  /// after device reboot, or during offline lifecycle updates.
  static Future<void> refillRollingWindowFromCache() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeUserId = prefs.getString('remedy_active_user_id') ?? '';
      if (activeUserId.isEmpty) {
        await AlarmScheduler().cancelAllAlarms(clearAcknowledged: false);
        AppLogger.i(
          'Skipped rolling-window refill (no active user); cleared stale alarms.',
          tag: 'AlarmScheduler',
        );
        return;
      }

      final cachedMeds = await LocalMedicationCache.loadMedications();
      final userMeds = cachedMeds
          .where((m) => m.userId.isEmpty || m.userId == activeUserId)
          .toList();

      final scheduler = AlarmScheduler();
      if (userMeds.isEmpty) {
        await scheduler.cancelAllAlarms(clearAcknowledged: false);
        AppLogger.i(
          'No cached medications for active user; cleared scheduled alarms.',
          tag: 'AlarmScheduler',
        );
        return;
      }

      await scheduler.rescheduleAllAlarms(userMeds);
      AppLogger.i(
        'Successfully refueled rolling-window alarms from local cache (${userMeds.length} meds).',
        tag: 'AlarmScheduler',
      );
    } catch (e, stack) {
      AppLogger.e('refillRollingWindowFromCache error: $e',
          tag: 'AlarmScheduler', error: e, stackTrace: stack);
    }
  }

  /// Schedules recurring alarms for a single medication by delegating through the serialized reschedule queue.
  /// Updates local medication cache and synchronizes active notification IDs atomically.
  Future<void> scheduleRecurringMedication(Medication medication) {
    if (kIsWeb ||
        !medication.isActive ||
        medication.isPrn ||
        medication.schedule == null) {
      return Future.value();
    }
    return _serialized(() async {
      final cachedMeds = await LocalMedicationCache.loadMedications();
      final updatedList = [
        ...cachedMeds.where((m) => m.id != medication.id),
        medication,
      ];
      await LocalMedicationCache.saveMedications(updatedList);
      await _rescheduleAllAlarmsInternal(updatedList);
    });
  }
}
