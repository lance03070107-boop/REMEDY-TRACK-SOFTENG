import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/app_constants.dart';
import '../core/state/dose_state_machine.dart';
import '../core/utils/app_logger.dart';
import '../firebase_options.dart';
import 'alarm_id_generator.dart';
import 'alarm_scheduler.dart';
import 'crashlytics_service.dart';

/// Helper returning user-facing display names for alarm audio tones
String _getToneTitle(String soundName) =>
    NotificationService.getToneTitle(soundName);

/// Top-level background action handler for lock-screen notification actions.
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.i('Action received: ${response.actionId}',
      tag: 'NotificationBackground');

  final actionId = response.actionId;
  final payload = response.payload;
  if (actionId == null || payload == null || payload.isEmpty) return;

  String medicationId = '';
  int notifId = 0;
  int? primaryNotifId;
  DateTime scheduledTime = DateTime.now();
  String userId = '';
  String medName = 'Medication';
  double doseAmount = 1.0;
  String strength = '';
  String formName = 'tablet';
  int colorTag = 0xFF1E66F5;
  String instructions = 'Take as prescribed with water.';
  String soundId = '';
  String customPath = '';
  bool vibrate = true;
  int snoozeCount = 0;

  try {
    if (payload.startsWith('{')) {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      medicationId = json['medId'] as String? ?? '';
      notifId = (json['notifId'] as num?)?.toInt() ?? 0;
      primaryNotifId = (json['primaryNotifId'] as num?)?.toInt();
      scheduledTime =
          DateTime.tryParse(json['sched'] as String? ?? '') ?? DateTime.now();
      userId = json['userId'] as String? ?? '';
      doseAmount = (json['doseAmount'] as num?)?.toDouble() ?? 1.0;
      strength = json['strength'] as String? ?? '';
      formName = json['form'] as String? ?? 'tablet';
      medName = json['medName'] as String? ?? 'Medication';
      colorTag = (json['colorTag'] as num?)?.toInt() ?? 0xFF1E66F5;
      instructions =
          json['instructions'] as String? ?? 'Take as prescribed with water.';
      soundId = json['soundId'] as String? ?? '';
      customPath = json['customPath'] as String? ?? '';
      vibrate = json['vibrate'] as bool? ?? true;
      snoozeCount = (json['snoozeCount'] as num?)?.toInt() ?? 0;
    } else {
      final parts = payload.split('|');
      medicationId = parts[0];
      notifId = int.tryParse(parts[1]) ?? 0;
      scheduledTime = DateTime.tryParse(parts[2]) ?? DateTime.now();
      userId = parts.length > 3 ? parts[3] : '';
      medName = parts.length > 4 ? parts[4] : 'Medication';
      doseAmount = parts.length > 5 ? (double.tryParse(parts[5]) ?? 1.0) : 1.0;
      formName = parts.length > 7 ? parts[7] : 'tablet';
    }
  } catch (e, s) {
    AppLogger.w('Payload parse notice: $e',
        tag: 'NotificationBackground', error: e, stackTrace: s);
  }

  if (medicationId.isEmpty) return;

  final primaryId = primaryNotifId ?? AlarmIdGenerator.getPrimaryId(notifId);
  final now = DateTime.now();
  final delayMinutes = now.difference(scheduledTime).inMinutes;
  final notifPlugin = FlutterLocalNotificationsPlugin();
  final isEligibleForAutoDecrement = (formName.toLowerCase() == 'tablet' ||
      formName.toLowerCase() == 'capsule');
  final logId = DoseStateMachine.generateLogId(medicationId, scheduledTime);

  if (actionId == AppConstants.actionTaken ||
      actionId == AppConstants.actionSkip) {
    final status = (actionId == AppConstants.actionSkip)
        ? 'skipped'
        : (delayMinutes > AppConstants.lateGracePeriodMinutes
            ? 'late'
            : 'taken');

    final firestoreDocMap = <String, dynamic>{
      'id': logId,
      'userId': userId,
      'medicationId': medicationId,
      'medicationName': medName,
      'doseAmount': doseAmount,
      'scheduledTime': scheduledTime.toUtc().toIso8601String(),
      'recordedTime': now.toUtc().toIso8601String(),
      'status': status,
      'isPrn': false,
    };

    bool syncedSuccessfully = false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      if (Firebase.apps.isNotEmpty) {
        final firestore = FirebaseFirestore.instance;
        await firestore.runTransaction((transaction) async {
          final logDocRef =
              firestore.collection(AppConstants.colIntakeLogs).doc(logId);
          final existingLogDoc = await transaction.get(logDocRef);

          final existingStatus = existingLogDoc.data()?['status'] as String?;
          final bool alreadyTaken = existingLogDoc.exists &&
              (existingStatus == 'taken' || existingStatus == 'late');

          // Terminal state protection: if already marked taken or late, ignore skip action
          if (alreadyTaken && actionId == AppConstants.actionSkip) {
            return;
          }

          if (actionId == AppConstants.actionTaken &&
              isEligibleForAutoDecrement &&
              !alreadyTaken &&
              userId.isNotEmpty) {
            final invRef = firestore
                .collection(AppConstants.colInventory)
                .doc('inv_$medicationId');
            final invDoc = await transaction.get(invRef);

            if (invDoc.exists && invDoc.data() != null) {
              final invData = invDoc.data()!;
              final currentStock =
                  (invData['currentStock'] as num?)?.toDouble() ?? 0.0;
              final updatedStock = (currentStock - doseAmount)
                  .clamp(AppConstants.minStock, AppConstants.maxStock);
              transaction.set(
                  invRef,
                  {
                    ...invData,
                    'currentStock': updatedStock,
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                  SetOptions(merge: true));
            }
          }

          // Store ISO-8601 UTC strings consistently for IntakeLog.fromJson & range queries
          transaction.set(
            logDocRef,
            {
              ...firestoreDocMap,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });

        syncedSuccessfully = true;
        AppLogger.i('Atomically synced intake to Firestore: $logId',
            tag: 'NotificationBackground');
      }
    } catch (e, s) {
      AppLogger.w('Firestore background sync notice (queued locally): $e',
          tag: 'NotificationBackground', error: e, stackTrace: s);
    }

    // Only queue locally if background Firestore sync did not succeed
    if (!syncedSuccessfully) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final pendingList =
            prefs.getStringList('pending_background_intakes') ?? [];
        pendingList.add(jsonEncode({
          ...firestoreDocMap,
          'form': formName,
          'alreadySynced': false,
        }));
        await prefs.setStringList('pending_background_intakes', pendingList);
      } catch (e, s) {
        AppLogger.w('Local queue notice: $e',
            tag: 'NotificationBackground', error: e, stackTrace: s);
      }
    }

    // Persist acknowledgement immediately so background / foreground checks do not re-trigger this dose
    if (medicationId.isNotEmpty) {
      await AlarmScheduler.markDoseAcknowledged(
        medicationId,
        scheduledTime,
        terminal: true,
      );
    }

    // Stop native alarm audio and cancel both primary and escalation notifications
    try {
      const channel = MethodChannel('com.remedytrack.app/alarm_window');
      await channel.invokeMethod('stopNativeAlarmSound');
      await channel.invokeMethod('cancelNativeAlarm', {'id': primaryId});
      await channel.invokeMethod(
        'cancelNativeAlarm',
        {'id': AlarmIdGenerator.getEscalationId(primaryId)},
      );
      if (notifId != primaryId) {
        await channel.invokeMethod('cancelNativeAlarm', {'id': notifId});
      }
    } catch (_) {}

    try {
      await notifPlugin.cancel(primaryId);
      await notifPlugin.cancel(AlarmIdGenerator.getEscalationId(primaryId));
      if (notifId != primaryId) {
        await notifPlugin.cancel(notifId);
      }
    } catch (e, s) {
      AppLogger.w('Cancel notification notice: $e',
          tag: 'NotificationBackground', error: e, stackTrace: s);
    }
  } else if (actionId == AppConstants.actionSnooze) {
    // Enforce 3-snooze limit and 60-minute window (ISO/IEC 25010 & Capstone requirement)
    if (snoozeCount >= DoseStateMachine.maxSnoozeLimit ||
        delayMinutes > DoseStateMachine.missedThresholdMinutes) {
      AppLogger.i(
          'Snooze rejected: limit ($snoozeCount) or 60m cutoff reached.',
          tag: 'NotificationBackground');
      if (medicationId.isNotEmpty) {
        await AlarmScheduler.markDoseAcknowledged(
          medicationId,
          scheduledTime,
          terminal: false,
        );
      }
      try {
        await notifPlugin.cancel(primaryId);
        await notifPlugin.cancel(AlarmIdGenerator.getEscalationId(primaryId));
      } catch (e, s) {
        AppLogger.w('Snooze cutoff cancel notice: $e',
            tag: 'NotificationBackground', error: e, stackTrace: s);
      }
      return;
    }

    try {
      await NotificationService().ensureTimeZoneInitialized();
      if (medicationId.isNotEmpty) {
        await AlarmScheduler.markDoseAcknowledged(
          medicationId,
          scheduledTime,
          terminal: false,
        );
      }

      try {
        const channel = MethodChannel('com.remedytrack.app/alarm_window');
        await channel.invokeMethod('stopNativeAlarmSound');
        await channel.invokeMethod('cancelNativeAlarm', {'id': primaryId});
        await channel.invokeMethod(
          'cancelNativeAlarm',
          {'id': AlarmIdGenerator.getEscalationId(primaryId)},
        );
      } catch (_) {}

      await notifPlugin.cancel(primaryId);
      await notifPlugin.cancel(AlarmIdGenerator.getEscalationId(primaryId));
      if (notifId != primaryId) {
        await notifPlugin.cancel(notifId);
      }

      final prefs = await SharedPreferences.getInstance();
      final snoozeMinutes = prefs.getInt(AppConstants.keySnoozeMinutes) ??
          AppConstants.defaultSnoozeDurationMinutes;
      final tone = soundId.isNotEmpty
          ? soundId
          : (prefs.getString(AppConstants.keyAlarmSound) ??
              AppConstants.defaultAlarmSound);

      final snoozeUntilLocal = now.add(Duration(minutes: snoozeMinutes));
      final snoozeTime =
          tz.TZDateTime.now(tz.local).add(Duration(minutes: snoozeMinutes));
      final channelId = AppConstants.getAlarmChannelId(tone);
      final resolvedResourceTone =
          AppConstants.availableAlarmSounds.contains(tone)
              ? tone
              : AppConstants.defaultAlarmSound;
      final toneTitle = _getToneTitle(tone);

      final androidDetails = AndroidNotificationDetails(
        channelId,
        'Medication Alarms ($toneTitle)',
        channelDescription: AppConstants.alarmChannelDescriptionV3,
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        ongoing: true,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.public,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        sound: RawResourceAndroidNotificationSound(resolvedResourceTone),
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

      final nextSnoozeCount = snoozeCount + 1;
      final snoozePayload = jsonEncode({
        'medId': medicationId,
        'notifId': primaryId,
        'primaryNotifId': primaryId,
        'sched': scheduledTime.toIso8601String(),
        'userId': userId,
        'medName': medName,
        'doseAmount': doseAmount,
        'strength': strength,
        'form': formName,
        'colorTag': colorTag,
        'instructions': instructions,
        'soundId': tone,
        'customPath': customPath,
        'vibrate': vibrate,
        'snoozeCount': nextSnoozeCount,
        'triggerAt': snoozeTime.toIso8601String(),
      });

      final snoozeLogMap = <String, dynamic>{
        'id': logId,
        'userId': userId,
        'medicationId': medicationId,
        'medicationName': medName,
        'doseAmount': doseAmount,
        'scheduledTime': scheduledTime.toUtc().toIso8601String(),
        'recordedTime': now.toUtc().toIso8601String(),
        'status': 'snoozed',
        'snoozeUntil': snoozeUntilLocal.toUtc().toIso8601String(),
        'snoozeCount': nextSnoozeCount,
        'isPrn': false,
        'notes':
            'Snoozed for ${snoozeMinutes}m ($nextSnoozeCount/${DoseStateMachine.maxSnoozeLimit})',
      };

      bool snoozeSynced = false;
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        if (Firebase.apps.isNotEmpty && userId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection(AppConstants.colIntakeLogs)
              .doc(logId)
              .set(
                {
                  ...snoozeLogMap,
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );
          snoozeSynced = true;
        }
      } catch (e, s) {
        AppLogger.w('Snooze Firestore sync notice (queuing offline): $e',
            tag: 'NotificationBackground', error: e, stackTrace: s);
      }

      if (!snoozeSynced) {
        try {
          final pendingList =
              prefs.getStringList('pending_background_intakes') ?? [];
          pendingList.add(jsonEncode({
            'log': snoozeLogMap,
            'decrementInventory': false,
            'alreadySynced': false,
          }));
          await prefs.setStringList('pending_background_intakes', pendingList);
        } catch (e, s) {
          AppLogger.w('Snooze local queue notice: $e',
              tag: 'NotificationBackground', error: e, stackTrace: s);
        }
      }

      await notifPlugin.zonedSchedule(
        primaryId,
        'SNOOZED: Time for your $medName',
        'Prescribed dose reminder snoozed for $snoozeMinutes minutes (Snooze $nextSnoozeCount/${DoseStateMachine.maxSnoozeLimit}).',
        snoozeTime,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: snoozePayload,
      );

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          const channel = MethodChannel('com.remedytrack.app/alarm_window');
          await channel.invokeMethod('scheduleNativeAlarm', {
            'id': primaryId,
            'triggerTimeMillis': snoozeTime.millisecondsSinceEpoch,
            'payload': snoozePayload,
          });
        } catch (_) {}
      }
    } catch (e, s) {
      AppLogger.w('Snooze scheduling notice: $e',
          tag: 'NotificationBackground', error: e, stackTrace: s);
    }
  }
}

/// Service managing the local notification plugin and channel infrastructure.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Helper returning user-facing display names for alarm audio tones
  static String getToneTitle(String soundName) {
    switch (soundName) {
      case 'remedy_alarm_classic':
        return 'Classic Medical Alarm';
      case 'remedy_alarm_gentle':
        return 'Gentle Chime';
      case 'remedy_alarm_beep':
        return 'Urgent Clinical Beep';
      case 'remedy_alarm_bell':
        return 'Soft Melody Bell';
      case 'remedy_alarm_digital':
        return 'Digital Pulse';
      case 'remedy_alarm_harp':
        return 'Morning Harp';
      default:
        return 'Medication Alarm';
    }
  }

  String? _pendingLaunchPayload;
  String? _pendingLaunchActionId;
  void Function(String payload, String? actionId)? _onActionReceived;

  void Function(String payload, String? actionId)? get onActionReceived =>
      _onActionReceived;

  set onActionReceived(
      void Function(String payload, String? actionId)? handler) {
    _onActionReceived = handler;
    if (_onActionReceived != null && _pendingLaunchPayload != null) {
      final payload = _pendingLaunchPayload!;
      final actionId = _pendingLaunchActionId;
      _pendingLaunchPayload = null;
      _pendingLaunchActionId = null;
      _onActionReceived!(payload, actionId);
    }
  }

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    if (!_isMobile) return null;
    try {
      return await flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
    } catch (e, s) {
      AppLogger.w('Error getting notification launch details: $e',
          tag: 'NotificationService', error: e, stackTrace: s);
      return null;
    }
  }

  bool _timeZoneInitialized = false;

  /// Ensures [tz.local] is configured once per isolate (idempotent).
  Future<void> ensureTimeZoneInitialized() async {
    if (_timeZoneInitialized || kIsWeb) return;
    try {
      tz_data.initializeTimeZones();
      try {
        final tzInfo = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
        AppLogger.d('Configured native timezone: ${tzInfo.identifier}',
            tag: 'NotificationService');
      } catch (e, s) {
        AppLogger.w('Native timezone notice (using default): $e',
            tag: 'NotificationService', error: e, stackTrace: s);
      }
      _timeZoneInitialized = true;
    } catch (e, s) {
      AppLogger.w('Timezone initialization notice: $e',
          tag: 'NotificationService', error: e, stackTrace: s);
    }
  }

  Future<void> initialize() async {
    if (!_isMobile) return;

    try {
      await ensureTimeZoneInitialized();

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      final darwinCategories = <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          'MED_ALARM_CATEGORY',
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              AppConstants.actionTaken,
              'Taken',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
            DarwinNotificationAction.plain(
              AppConstants.actionSnooze,
              'Snooze',
            ),
            DarwinNotificationAction.plain(
              AppConstants.actionSkip,
              'Skip',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ];

      final darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: darwinCategories,
      );

      final initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await flutterLocalNotificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          if (response.payload != null) {
            if (_onActionReceived != null) {
              _onActionReceived!(response.payload!, response.actionId);
            } else {
              _pendingLaunchPayload = response.payload;
              _pendingLaunchActionId = response.actionId;
            }
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      await _createNotificationChannels();
    } catch (e, s) {
      AppLogger.w('Notification initialization notice: $e',
          tag: 'NotificationService', error: e, stackTrace: s);
    }
  }

  Future<void> _createNotificationChannels() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final androidPlugin = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          // Purge obsolete/legacy notification channels so Android rebinds audio & vibration cleanly
          try {
            await androidPlugin
                .deleteNotificationChannel(AppConstants.alarmChannelId);
            await androidPlugin
                .deleteNotificationChannel(AppConstants.alarmChannelIdV2);
            for (final tone in AppConstants.availableAlarmSounds) {
              await androidPlugin.deleteNotificationChannel(
                  '${AppConstants.alarmChannelIdV2}_$tone');
            }
            AppLogger.d('Obsolete notification channels deleted successfully.',
                tag: 'NotificationService');
          } catch (e, s) {
            AppLogger.w('Obsolete channel deletion notice: $e',
                tag: 'NotificationService', error: e, stackTrace: s);
          }

          // Create dedicated, immutable V3 notification channels for each acoustic tone
          for (final tone in AppConstants.availableAlarmSounds) {
            final channelId = AppConstants.getAlarmChannelId(tone);
            final toneTitle = _getToneTitle(tone);

            final channel = AndroidNotificationChannel(
              channelId,
              'Medication Alarms ($toneTitle)',
              description:
                  'Urgent alarm-clock alerts with $toneTitle acoustic sound.',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(tone),
              audioAttributesUsage: AudioAttributesUsage.alarm,
              enableVibration: true,
              vibrationPattern:
                  Int64List.fromList([0, 800, 400, 800, 400, 1000]),
            );
            await androidPlugin.createNotificationChannel(channel);
          }

          // Create silent visual tray channel for primary alarms where native
          // RemedyAlarmPlayer owns the authoritative STREAM_ALARM audio playback.
          const visualTrayChannel = AndroidNotificationChannel(
            'remedy_alarm_visual_tray_v1',
            'Medication Alarm Actions',
            description:
                'Full-screen medication alarm quick actions (Taken / Snooze / Skip) paired with RemedyTrack alarm audio.',
            importance: Importance.max,
            playSound: false,
            enableVibration: false,
          );
          await androidPlugin.createNotificationChannel(visualTrayChannel);

          const refillChannel = AndroidNotificationChannel(
            AppConstants.refillChannelId,
            AppConstants.refillChannelName,
            description: AppConstants.refillChannelDescription,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          );

          await androidPlugin.createNotificationChannel(refillChannel);
          AppLogger.d('All V3 medication alarm channels created.',
              tag: 'NotificationService');
        }
      } catch (e, s) {
        AppLogger.w('Android notification channel setup notice: $e',
            tag: 'NotificationService', error: e, stackTrace: s);
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e, s) {
      AppLogger.w('Cancel notification notice: $e',
          tag: 'NotificationService', error: e, stackTrace: s);
    }
  }

  Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e, s) {
      AppLogger.w('Cancel all notifications notice: $e',
          tag: 'NotificationService', error: e, stackTrace: s);
    }
  }

  Future<void> showLowStockAlert({
    required int notificationId,
    required String medicationName,
    required double currentStock,
    required String unit,
    required double threshold,
  }) async {
    if (kIsWeb) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        AppConstants.refillChannelId,
        AppConstants.refillChannelName,
        channelDescription: AppConstants.refillChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      );
      const darwinDetails = DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.timeSensitive,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await flutterLocalNotificationsPlugin.show(
        notificationId,
        'Refill Reserve Alert: $medicationName',
        'Stock balance is ${currentStock.toStringAsFixed(currentStock % 1 == 0 ? 0 : 1)} $unit, at or below your refill reserve (${threshold.toStringAsFixed(threshold % 1 == 0 ? 0 : 1)} $unit).',
        details,
        payload: 'REFILL:$medicationName',
      );
    } catch (e, stack) {
      AppLogger.w('Failed to display low-stock alert: $e', tag: 'Notification');
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'NotificationService.showLowStockAlert'));
    }
  }

  /// Displays a foreground notification for incoming caregiver/escalation FCM messages.
  Future<void> showCaregiverAlert({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        AppConstants.refillChannelId,
        AppConstants.refillChannelName,
        channelDescription: AppConstants.refillChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      );
      const darwinDetails = DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.timeSensitive,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );
      final id = 10000 + DateTime.now().millisecondsSinceEpoch.remainder(70000);
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e, stack) {
      AppLogger.w('Failed to display foreground caregiver alert: $e',
          tag: 'Notification');
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'NotificationService.showCaregiverAlert'));
    }
  }

  Future<void> previewAlarmTone(
    String soundName, {
    String? customTitle,
    String? customBody,
  }) async {
    if (kIsWeb) return;
    try {
      final channelId = AppConstants.getAlarmChannelId(soundName);
      final toneTitle = _getToneTitle(soundName);

      final androidDetails = AndroidNotificationDetails(
        channelId,
        'Medication Alarms ($toneTitle)',
        channelDescription: AppConstants.alarmChannelDescriptionV3,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(soundName),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );
      final darwinDetails = DarwinNotificationDetails(
        sound: '$soundName.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await flutterLocalNotificationsPlugin.show(
        88888,
        customTitle ?? 'Alarm Tone Preview',
        customBody ?? 'Playing $toneTitle. Tap to dismiss.',
        details,
      );
    } catch (e, s) {
      AppLogger.w('previewAlarmTone notice: $e',
          tag: 'NotificationService', error: e, stackTrace: s);
    }
  }
}
