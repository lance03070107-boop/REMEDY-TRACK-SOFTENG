import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../core/utils/app_logger.dart';
import 'crashlytics_service.dart';
import 'notification_service.dart';

enum ReliabilityStatus { granted, denied, restricted, permanentlyDenied }

class AlarmPermissionState {
  final bool notificationsGranted;
  final bool exactAlarmsGranted;
  final bool batteryOptimizationIgnored;
  final bool fullScreenIntentAllowed;
  final bool overlayAllowed;

  const AlarmPermissionState({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
    required this.batteryOptimizationIgnored,
    this.fullScreenIntentAllowed = true,
    this.overlayAllowed = true,
  });

  bool get isFullyCompliant =>
      notificationsGranted &&
      exactAlarmsGranted &&
      batteryOptimizationIgnored &&
      fullScreenIntentAllowed &&
      overlayAllowed;
  bool get canFireAlarms => notificationsGranted;
}

class OEMInstruction {
  final String brand;
  final String steps;

  const OEMInstruction({required this.brand, required this.steps});
}

/// Service managing system permissions with special focus on Android exact alarms,
/// DND access, OEM battery kill prevention, and diagnostic health verifications.
class PermissionService {
  /// One-stop gate checking and requesting all critical alarm and notification permissions:
  /// a. POST_NOTIFICATIONS (Android 13+)
  /// b. SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM (Android 12+)
  /// c. Full-Screen Intent permission (Android 14+)
  /// d. Battery optimization exemption
  /// If critical permissions are denied and a BuildContext is provided, shows an explanatory dialog.
  Future<AlarmPermissionState> ensureAlarmPermissions(
      {BuildContext? context}) async {
    if (kIsWeb) {
      return const AlarmPermissionState(
        notificationsGranted: true,
        exactAlarmsGranted: true,
        batteryOptimizationIgnored: true,
        fullScreenIntentAllowed: true,
      );
    }

    bool notifGranted = true;
    bool exactGranted = true;
    bool batteryIgnored = true;
    bool fullScreenAllowed = true;
    bool overlayAllowed = true;

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = NotificationService()
            .flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          final enabled =
              await androidPlugin.areNotificationsEnabled() ?? false;
          if (!enabled) {
            final requested =
                await androidPlugin.requestNotificationsPermission();
            notifGranted = requested ?? false;
          } else {
            notifGranted = true;
          }

          final exact = await androidPlugin.requestExactAlarmsPermission();
          exactGranted = exact ?? true;
        } else {
          final status = await ph.Permission.notification.request();
          notifGranted = status.isGranted;
        }

        final battStatus =
            await ph.Permission.ignoreBatteryOptimizations.status;
        batteryIgnored = battStatus.isGranted;

        fullScreenAllowed = await canUseFullScreenIntent();
        overlayAllowed = await canDrawOverlays();
      } else {
        final iosPlugin = NotificationService()
            .flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          final res = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          notifGranted = res ?? false;
        } else {
          final status = await ph.Permission.notification.request();
          notifGranted = status.isGranted;
        }
      }
    } catch (e) {
      AppLogger.w('ensureAlarmPermissions check fallback: $e',
          tag: 'Permission');
    }

    final state = AlarmPermissionState(
      notificationsGranted: notifGranted,
      exactAlarmsGranted: exactGranted,
      batteryOptimizationIgnored: batteryIgnored,
      fullScreenIntentAllowed: fullScreenAllowed,
      overlayAllowed: overlayAllowed,
    );

    if (context != null && context.mounted && !notifGranted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.notifications_active_rounded,
              size: 36, color: Colors.amber),
          title: const Text('Alarm Permissions Required'),
          content: const Text(
            'RemedyTrack needs Notification and Alarm permissions so you never miss life-critical medication doses. '
            'Please grant notifications in system settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    } else if (context != null && context.mounted && !overlayAllowed) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon:
              const Icon(Icons.alarm_on_rounded, size: 36, color: Colors.blue),
          title: const Text('Enable Background Alarm Pop-up'),
          content: const Text(
            'So your alarm rings and pops up full-screen like a real alarm clock over your home screen and other apps (instead of only showing a banner), '
            'please turn ON "Appear on top" (Display over other apps) for RemedyTrack.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                openOverlaySettings();
              },
              child: const Text('Enable Background Pop-up'),
            ),
          ],
        ),
      );
    } else if (context != null && context.mounted && !fullScreenAllowed) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon:
              const Icon(Icons.alarm_on_rounded, size: 36, color: Colors.blue),
          title: const Text('Alarm Clock Pop-up Permission'),
          content: const Text(
            'To wake up your screen and display the full-screen alarm clock when locked, '
            'Android 14+ requires granting "Full-screen intents".\n\n'
            'Tap "Enable" to open system settings and turn it on for RemedyTrack.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                openFullScreenIntentSettings();
              },
              child: const Text('Enable Alarm Pop-ups'),
            ),
          ],
        ),
      );
    } else if (context != null && context.mounted && !batteryIgnored) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.battery_charging_full_rounded,
              size: 36, color: Colors.green),
          title: const Text('Allow Background Alarm Ringing'),
          content: const Text(
            'To prevent Android battery saver from silencing or delaying your medication alarms while the app is closed, '
            'please allow RemedyTrack to run in the background without battery restrictions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                openBatteryOptimizationSettings();
              },
              child: const Text('Allow Background Alarms'),
            ),
          ],
        ),
      );
    }

    return state;
  }

  Future<ReliabilityStatus> checkNotificationPermission() async {
    if (kIsWeb) return ReliabilityStatus.granted;
    try {
      final status = await ph.Permission.notification.status;
      return _mapStatus(status);
    } catch (e, st) {
      AppLogger.w('checkNotificationPermission failed: $e', tag: 'Permission');
      await CrashlyticsService.recordError(e, st,
          reason: 'checkNotificationPermission');
      return ReliabilityStatus.granted;
    }
  }

  Future<ReliabilityStatus> requestNotificationPermission() async {
    if (kIsWeb) return ReliabilityStatus.granted;
    try {
      final status = await ph.Permission.notification.request();
      return _mapStatus(status);
    } catch (e, st) {
      AppLogger.w('requestNotificationPermission failed: $e',
          tag: 'Permission');
      await CrashlyticsService.recordError(e, st,
          reason: 'requestNotificationPermission');
      return ReliabilityStatus.granted;
    }
  }

  Future<ReliabilityStatus> checkExactAlarmPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final status = await ph.Permission.scheduleExactAlarm.status;
        return _mapStatus(status);
      } catch (e, st) {
        AppLogger.w('checkExactAlarmPermission failed: $e', tag: 'Permission');
        await CrashlyticsService.recordError(e, st,
            reason: 'checkExactAlarmPermission');
        return ReliabilityStatus.granted;
      }
    }
    return ReliabilityStatus.granted;
  }

  Future<ReliabilityStatus> requestExactAlarmPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final status = await ph.Permission.scheduleExactAlarm.request();
        return _mapStatus(status);
      } catch (e, st) {
        AppLogger.w('requestExactAlarmPermission failed: $e',
            tag: 'Permission');
        await CrashlyticsService.recordError(e, st,
            reason: 'requestExactAlarmPermission');
        return ReliabilityStatus.granted;
      }
    }
    return ReliabilityStatus.granted;
  }

  Future<ReliabilityStatus> checkBatteryOptimizationStatus() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final status = await ph.Permission.ignoreBatteryOptimizations.status;
        return _mapStatus(status);
      } catch (e, st) {
        AppLogger.w('checkBatteryOptimizationStatus failed: $e',
            tag: 'Permission');
        await CrashlyticsService.recordError(e, st,
            reason: 'checkBatteryOptimizationStatus');
        return ReliabilityStatus.granted;
      }
    }
    return ReliabilityStatus.granted;
  }

  Future<ReliabilityStatus> requestIgnoreBatteryOptimization() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await openBatteryOptimizationSettings();
        final status = await ph.Permission.ignoreBatteryOptimizations.status;
        return _mapStatus(status);
      } catch (e, st) {
        AppLogger.w('requestIgnoreBatteryOptimization failed: $e',
            tag: 'Permission');
        await CrashlyticsService.recordError(e, st,
            reason: 'requestIgnoreBatteryOptimization');
        return ReliabilityStatus.granted;
      }
    }
    return ReliabilityStatus.granted;
  }

  Future<ReliabilityStatus> checkDoNotDisturbStatus() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final status = await ph.Permission.accessNotificationPolicy.status;
        return _mapStatus(status);
      } catch (e, st) {
        AppLogger.w('checkDoNotDisturbStatus failed: $e', tag: 'Permission');
        await CrashlyticsService.recordError(e, st,
            reason: 'checkDoNotDisturbStatus');
        return ReliabilityStatus.granted;
      }
    }
    return ReliabilityStatus.granted;
  }

  Future<ReliabilityStatus> requestDoNotDisturbAccess() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final status = await ph.Permission.accessNotificationPolicy.request();
        return _mapStatus(status);
      } catch (e, st) {
        AppLogger.w('requestDoNotDisturbAccess failed: $e', tag: 'Permission');
        await CrashlyticsService.recordError(e, st,
            reason: 'requestDoNotDisturbAccess');
        return ReliabilityStatus.granted;
      }
    }
    return ReliabilityStatus.granted;
  }

  Future<bool> openAppSettings() async {
    if (kIsWeb) return false;
    try {
      return await ph.openAppSettings();
    } catch (e, st) {
      AppLogger.w('openAppSettings failed: $e', tag: 'Permission');
      await CrashlyticsService.recordError(e, st, reason: 'openAppSettings');
      return false;
    }
  }

  static const MethodChannel _alarmWindowChannel =
      MethodChannel('com.remedytrack.app/alarm_window');

  Future<bool> canUseFullScreenIntent() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res = await _alarmWindowChannel
          .invokeMethod<bool>('canUseFullScreenIntent');
      return res ?? true;
    } catch (e) {
      AppLogger.w('canUseFullScreenIntent fallback: $e', tag: 'Permission');
      return true;
    }
  }

  Future<void> openFullScreenIntentSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmWindowChannel.invokeMethod('openFullScreenIntentSettings');
    } catch (e) {
      AppLogger.w('openFullScreenIntentSettings fallback: $e',
          tag: 'Permission');
    }
  }

  Future<bool> canDrawOverlays() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res =
          await _alarmWindowChannel.invokeMethod<bool>('canDrawOverlays');
      return res ?? true;
    } catch (e) {
      AppLogger.w('canDrawOverlays fallback: $e', tag: 'Permission');
      return true;
    }
  }

  Future<void> openOverlaySettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmWindowChannel.invokeMethod('openOverlaySettings');
    } catch (e) {
      AppLogger.w('openOverlaySettings fallback: $e', tag: 'Permission');
      await openAppSettings();
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmWindowChannel
          .invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      AppLogger.w('openBatteryOptimizationSettings fallback: $e',
          tag: 'Permission');
      await openAppSettings();
    }
  }

  Future<void> wakeUpScreen() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmWindowChannel.invokeMethod('wakeUpScreen');
    } catch (e) {
      AppLogger.w('wakeUpScreen fallback: $e', tag: 'Permission');
    }
  }

  /// Checks FCM token health status and returns a diagnostic message.
  Future<({bool isHealthy, String details})> checkFcmTokenHealth() async {
    if (kIsWeb) {
      return (isHealthy: true, details: 'FCM active (Web Push)');
    }
    if (Firebase.apps.isEmpty) {
      return (isHealthy: false, details: 'Firebase not initialized');
    }
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        final truncated = token.length > 16
            ? '${token.substring(0, 8)}...${token.substring(token.length - 8)}'
            : token;
        return (isHealthy: true, details: 'Connected ($truncated)');
      }
      return (isHealthy: false, details: 'Token unavailable');
    } catch (e) {
      return (isHealthy: false, details: 'Token check error: $e');
    }
  }

  ReliabilityStatus _mapStatus(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
        return ReliabilityStatus.granted;
      case ph.PermissionStatus.denied:
        return ReliabilityStatus.denied;
      case ph.PermissionStatus.restricted:
        return ReliabilityStatus.restricted;
      case ph.PermissionStatus.permanentlyDenied:
        return ReliabilityStatus.permanentlyDenied;
      default:
        return ReliabilityStatus.denied;
    }
  }

  /// Tailored instructions for aggressive OEM background battery killers
  List<OEMInstruction> getOemInstructions() {
    return const [
      OEMInstruction(
        brand: 'Xiaomi / POCO / Redmi (MIUI / HyperOS)',
        steps:
            '1. Go to Settings > Apps > Manage Apps > RemedyTrack.\n2. Enable "Autostart".\n3. Set "Battery Saver" to "No restrictions".\n4. Enable "Display pop-up windows while running in the background".',
      ),
      OEMInstruction(
        brand: 'Samsung (One UI)',
        steps:
            '1. Go to Settings > Battery and Device Care > Battery > Background usage limits.\n2. Add RemedyTrack to "Never sleeping apps".\n3. In App Info > Alarms & Reminders, toggle "Allow setting alarms and reminders" ON.',
      ),
      OEMInstruction(
        brand: 'Oppo / Realme (ColorOS / Realme UI)',
        steps:
            '1. Go to Settings > App Management > RemedyTrack > Battery Usage.\n2. Allow "Auto-launch", "Secondary launch", and "Run in background".\n3. Lock app in recent tasks view.',
      ),
      OEMInstruction(
        brand: 'Vivo / iQOO (Funtouch OS / OriginOS)',
        steps:
            '1. Go to Settings > Battery > High background power consumption.\n2. Toggle RemedyTrack to ON to allow uninterrupted alarm dispatch.',
      ),
      OEMInstruction(
        brand: 'Huawei / Honor (EMUI / Magic UI)',
        steps:
            '1. Go to Settings > Battery > App Launch.\n2. Find RemedyTrack, turn off "Manage Automatically".\n3. Turn ON "Auto-launch", "Secondary launch", and "Run in background".',
      ),
    ];
  }
}
