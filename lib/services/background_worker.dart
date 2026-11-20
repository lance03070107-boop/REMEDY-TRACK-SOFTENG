import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/utils/app_logger.dart';
import '../firebase_options.dart';
import '../repositories/intake_repository.dart';
import '../repositories/medication_repository.dart';
import 'alarm_scheduler.dart';
import 'missed_dose_reconciler.dart';
import 'notification_service.dart';

const String missedDoseReconcileTaskKey =
    'remedy_missed_dose_reconcile_periodic_task';

/// Background isolate entry-point for WorkManager on Android and iOS BGTaskScheduler.
/// Best-effort execution when the app is in the background or killed.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.i('Executing background task: $task', tag: 'WorkManager');
    try {
      if (task == missedDoseReconcileTaskKey ||
          task == Workmanager.iOSBackgroundTask) {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('remedy_active_user_id') ?? '';
        if (userId.isEmpty) {
          await AlarmScheduler().cancelAllAlarms();
          AppLogger.i(
            'Background task skipped refill (no signed-in user); ensured alarms cancelled.',
            tag: 'WorkManager',
          );
          return true;
        }

        // 1. Ensure timezone location is initialized for this background isolate
        await NotificationService().ensureTimeZoneInitialized();

        // 2. Refill the rolling-window alarm buffer from local medication cache (A1)
        await AlarmScheduler.refillRollingWindowFromCache();

        // 3. Run missed-dose reconciliation against local/cloud repositories
        try {
          if (Firebase.apps.isEmpty) {
            await Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform,
            );
          }
          final reconciler = MissedDoseReconciler(
            medicationRepository: FirebaseMedicationRepository(),
            intakeRepository: FirebaseIntakeRepository(),
          );
          final reconciled = await reconciler.reconcileMissedDoses(userId);
          AppLogger.i(
            'Background MissedDoseReconciler completed (reconciled=$reconciled) for user: $userId',
            tag: 'WorkManager',
          );
        } catch (recErr, recStack) {
          AppLogger.w(
            'Background MissedDoseReconciler notice: $recErr',
            tag: 'WorkManager',
            error: recErr,
            stackTrace: recStack,
          );
        }

        // 4. Record background heartbeat timestamp for ISO/IEC 25010 diagnostics
        await prefs.setInt('remedy_last_bg_reconcile_ms',
            DateTime.now().millisecondsSinceEpoch);
        AppLogger.d(
            'Background reconciliation heartbeat recorded for user: $userId',
            tag: 'WorkManager');
      }
      return true;
    } catch (e, s) {
      AppLogger.w('Task execution notice: $e',
          tag: 'WorkManager', error: e, stackTrace: s);
      return true;
    }
  });
}

class BackgroundWorker {
  const BackgroundWorker._();

  /// Initializes WorkManager and registers periodic 15-minute background reconciliation.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );

      // Register periodic task (minimum Android interval is 15 minutes)
      await Workmanager().registerPeriodicTask(
        'periodic-missed-dose-reconciler',
        missedDoseReconcileTaskKey,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.notRequired,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      AppLogger.i('WorkManager periodic reconciliation registered.',
          tag: 'BackgroundWorker');
    } catch (e, s) {
      AppLogger.w('WorkManager initialization notice: $e',
          tag: 'BackgroundWorker', error: e, stackTrace: s);
    }
  }
}
