import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:convert';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/scheduling/schedule_expander.dart';
import 'core/state/dose_state_machine.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
import 'firebase_options.dart';
import 'models/intake_log.dart';
import 'models/medication.dart';
import 'repositories/caregiver_repository.dart';
import 'repositories/intake_repository.dart';
import 'repositories/inventory_repository.dart';
import 'repositories/medication_repository.dart';
import 'repositories/user_repository.dart';
import 'services/alarm_id_generator.dart';
import 'services/alarm_scheduler.dart';
import 'services/alarm_sound_service.dart';
import 'services/analytics_service.dart';
import 'services/background_worker.dart';
import 'services/connectivity_service.dart';
import 'services/crashlytics_service.dart';
import 'services/fcm_service.dart';
import 'services/local_medication_cache.dart';
import 'services/missed_dose_reconciler.dart';
import 'services/notification_service.dart';
import 'services/pdf_report_service.dart';
import 'services/permission_service.dart';
import 'services/secure_storage_service.dart';
import 'viewmodels/adherence_viewmodel.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/caregiver_viewmodel.dart';
import 'viewmodels/intake_viewmodel.dart';
import 'viewmodels/inventory_viewmodel.dart';
import 'viewmodels/medication_viewmodel.dart';
import 'viewmodels/settings_viewmodel.dart';
import 'views/widgets/app_lock_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local notifications & timezone database on the critical path
  final notificationService = NotificationService();
  try {
    await notificationService.initialize();
  } catch (e, stack) {
    unawaited(CrashlyticsService.recordError(e, stack));
  }

  // Attempt initial Firebase bootstrap
  final firebaseSuccess = await _bootstrapFirebase();
  if (firebaseSuccess) {
    try {
      await CrashlyticsService.initialize();
    } catch (e, stack) {
      AppLogger.w('Crashlytics initialization notice: $e',
          tag: 'Bootstrap', error: e, stackTrace: stack);
    }
  }

  runApp(const RemedyTrackRoot());

  // Defer non-critical audio engine and WorkManager initialization until after first frame
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeDeferredServices());
  });
}

Future<void> _initializeDeferredServices() async {
  try {
    await AlarmSoundService().initialize();
  } catch (e, stack) {
    unawaited(CrashlyticsService.recordError(e, stack));
  }

  try {
    await BackgroundWorker.initialize();
  } catch (e, stack) {
    unawaited(CrashlyticsService.recordError(e, stack));
  }
}

String? _lastBootstrapError;

Future<bool> _bootstrapFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      try {
        final initFuture = Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        // Prevent blocked/stalled CDN script fetches on mobile WebKit from hanging forever before runApp
        await (kIsWeb
            ? initFuture.timeout(const Duration(seconds: 12))
            : initFuture);
      } catch (optionsErr, optionsStack) {
        AppLogger.w('Firebase options initialization notice: $optionsErr',
            tag: 'Bootstrap', error: optionsErr, stackTrace: optionsStack);
        if (!kIsWeb) {
          try {
            await Firebase.initializeApp();
          } catch (nativeErr, nativeStack) {
            AppLogger.e('Firebase native initialization failure: $nativeErr',
                tag: 'Bootstrap', error: nativeErr, stackTrace: nativeStack);
            rethrow;
          }
        } else {
          rethrow;
        }
      }
    }

    // Initialize Firebase App Check only when explicitly enabled via --dart-define=ENABLE_APP_CHECK=true
    // so sideloaded release APKs and web deployments without enforced Play Integrity / reCAPTCHA
    // never have Firestore or Auth requests blocked by unconfigured attestation providers.
    try {
      const enableAppCheck =
          bool.fromEnvironment('ENABLE_APP_CHECK', defaultValue: false);
      const webRecaptchaKey = String.fromEnvironment('RECAPTCHA_V3_SITE_KEY');
      if (enableAppCheck && !kIsWeb) {
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
          appleProvider: kDebugMode
              ? AppleProvider.debug
              : AppleProvider.appAttestWithDeviceCheckFallback,
        );
      } else if (enableAppCheck && webRecaptchaKey.isNotEmpty) {
        await FirebaseAppCheck.instance.activate(
          webProvider: ReCaptchaV3Provider(webRecaptchaKey),
        );
      }
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
    }

    // Enable disk/IndexedDB offline persistence on both mobile (100 MB bounded cache)
    // and web so offline dose logging decrements stock and syncs automatically on reconnect.
    // Falls back gracefully to memory cache if IndexedDB is unavailable (e.g., private browsing
    // or failed-precondition multi-tab lock).
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: kIsWeb ? null : 104857600, // 100 MB on mobile
        webExperimentalAutoDetectLongPolling: true,
      );
      AppLogger.i(
          'Firestore configured (persistence=true, webAutoLongPolling=true).',
          tag: 'Bootstrap');
    } catch (e, s) {
      AppLogger.w(
          'IndexedDB/disk Firestore persistence unavailable; falling back to memory cache: $e',
          tag: 'Bootstrap',
          error: e,
          stackTrace: s);
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: false,
          webExperimentalAutoDetectLongPolling: true,
        );
      } catch (fallbackErr, fallbackStack) {
        AppLogger.w('Firestore memory fallback settings notice: $fallbackErr',
            tag: 'Bootstrap', error: fallbackErr, stackTrace: fallbackStack);
      }
    }

    _lastBootstrapError = null;
    AppLogger.i('Firebase initialized successfully.', tag: 'Bootstrap');
    return Firebase.apps.isNotEmpty;
  } catch (e, s) {
    _lastBootstrapError = e.toString();
    AppLogger.e('Firebase bootstrap failure: $e',
        tag: 'Bootstrap', error: e, stackTrace: s);
    return false;
  }
}

/// Root application widget managing initialization state, release-mode connection
/// error gating, dependency injection, and theme management.
class RemedyTrackRoot extends StatefulWidget {
  const RemedyTrackRoot({super.key});

  @override
  State<RemedyTrackRoot> createState() => _RemedyTrackRootState();
}

class _RemedyTrackRootState extends State<RemedyTrackRoot> {
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    setState(() => _isRetrying = true);
    final success = await _bootstrapFirebase();
    if (success) {
      await CrashlyticsService.initialize();
    }
    if (mounted) {
      setState(() => _isRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isFirebaseAvailable = Firebase.apps.isNotEmpty;

    // In release builds, Firebase connection failure is blocking
    if (!isFirebaseAvailable) {
      return MaterialApp(
        title: 'RemedyTrack',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: FirebaseConnectionErrorView(
          isRetrying: _isRetrying,
          onRetry: _handleRetry,
          errorMessage: _lastBootstrapError,
        ),
      );
    }

    return const RemedyTrackApp();
  }
}

/// Blocking screen displayed in release mode when Firebase services cannot be reached.
class FirebaseConnectionErrorView extends StatefulWidget {
  final bool isRetrying;
  final VoidCallback onRetry;
  final String? errorMessage;

  const FirebaseConnectionErrorView({
    super.key,
    required this.isRetrying,
    required this.onRetry,
    this.errorMessage,
  });

  @override
  State<FirebaseConnectionErrorView> createState() =>
      _FirebaseConnectionErrorViewState();
}

class _FirebaseConnectionErrorViewState
    extends State<FirebaseConnectionErrorView> {
  bool _showErrorDetails = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: 52,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    "Can't Connect to Server",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'RemedyTrack requires a verified cloud connection to protect your dosage schedules and medical history under RA 10173 (Data Privacy Act).\n\nPlease check your internet connection and tap retry.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: widget.isRetrying ? null : widget.onRetry,
                    icon: widget.isRetrying
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      widget.isRetrying ? 'Connecting...' : 'Retry Connection',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.errorMessage != null &&
                      widget.errorMessage!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showErrorDetails = !_showErrorDetails;
                        });
                      },
                      child: Text(
                        _showErrorDetails
                            ? 'Hide Diagnostic Details'
                            : 'View Diagnostic Details',
                        style: TextStyle(
                          color: theme.colorScheme.outline,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (_showErrorDetails)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary application shell with MultiProvider and AppLockOverlay integration.
class RemedyTrackApp extends StatefulWidget {
  final MedicationRepository? medicationRepository;
  final IntakeRepository? intakeRepository;
  final InventoryRepository? inventoryRepository;
  final UserRepository? userRepository;
  final CaregiverRepository? caregiverRepository;

  const RemedyTrackApp({
    super.key,
    this.medicationRepository,
    this.intakeRepository,
    this.inventoryRepository,
    this.userRepository,
    this.caregiverRepository,
  });

  @override
  State<RemedyTrackApp> createState() => _RemedyTrackAppState();
}

class _RemedyTrackAppState extends State<RemedyTrackApp>
    with WidgetsBindingObserver {
  late final NotificationService _notificationService;
  late final AlarmScheduler _alarmScheduler;
  late final FcmService _fcmService;
  late final PdfReportService _pdfReportService;
  late final SecureStorageService _secureStorage;
  late final ConnectivityService _connectivityService;
  late final AnalyticsService _analyticsService;

  late final MedicationRepository _medRepo;
  late final IntakeRepository _intakeRepo;
  late final InventoryRepository _invRepo;
  late final UserRepository _userRepo;
  late final CaregiverRepository _caregiverRepo;

  late final SettingsViewModel _settingsVm;
  late final AuthViewModel _authVm;
  late final MedicationViewModel _medVm;
  late final IntakeViewModel _intakeVm;
  late final InventoryViewModel _invVm;
  late final AdherenceViewModel _adherenceVm;
  late final CaregiverViewModel _caregiverVm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Services
    _notificationService = NotificationService();
    _alarmScheduler = AlarmScheduler(notificationService: _notificationService);
    _fcmService = FcmService();
    _pdfReportService = PdfReportService();
    _secureStorage = SecureStorageService();
    _connectivityService = ConnectivityService();
    _connectivityService.addListener(_onConnectivityChanged);
    _analyticsService = AnalyticsService();
    _analyticsService.initialize();

    bool isDeviceOnline() => _connectivityService.isOnline;

    // Repositories strictly using live Cloud Firestore & FirebaseAuth (or injected for widget tests)
    _medRepo = widget.medicationRepository ??
        FirebaseMedicationRepository(isOnline: isDeviceOnline);
    _intakeRepo = widget.intakeRepository ??
        FirebaseIntakeRepository(isOnline: isDeviceOnline);
    _invRepo = widget.inventoryRepository ??
        FirebaseInventoryRepository(isOnline: isDeviceOnline);
    _userRepo = widget.userRepository ?? FirebaseUserRepository();
    _caregiverRepo =
        widget.caregiverRepository ?? FirebaseCaregiverRepository();

    _settingsVm = SettingsViewModel(analyticsService: _analyticsService);
    _authVm = AuthViewModel(
      userRepository: _userRepo,
      fcmService: _fcmService,
      secureStorage: _secureStorage,
      isOnline: isDeviceOnline,
    );
    _medVm = MedicationViewModel(
      medicationRepository: _medRepo,
      inventoryRepository: _invRepo,
      alarmScheduler: _alarmScheduler,
    );
    _intakeVm = IntakeViewModel(
      intakeRepository: _intakeRepo,
      alarmScheduler: _alarmScheduler,
    );
    _invVm = InventoryViewModel(
      inventoryRepository: _invRepo,
      resolveMedicationName: (medId) {
        for (final med in _medVm.medications) {
          if (med.id == medId) return med.name;
        }
        return null;
      },
    );
    _adherenceVm = AdherenceViewModel(
      pdfReportService: _pdfReportService,
      intakeRepository: _intakeRepo,
    );
    _caregiverVm = CaregiverViewModel(
      caregiverRepository: _caregiverRepo,
      userRepository: _userRepo,
      fcmService: _fcmService,
    );
    _authVm.onBeforeSignOut = _resetAllUserViewModels;
    _authVm.onFlushPendingBeforeSignOut =
        _intakeVm.flushPendingBackgroundIntakes;
    _authVm.addListener(_onAuthStateChanged);

    // Full-screen intent & notification tap routing to AlarmRingingScreen
    _notificationService.onActionReceived = (payload, actionId) {
      _handleNotificationAction(payload, actionId);
    };

    AppRouter.onAlarmScreenDismissed = _handleAlarmScreenDismissed;

    // Active alarm triggers (from foreground timer or exact schedule)
    AlarmScheduler.onAlarmTriggered = (alarmData) {
      if (_caregiverVm.isCaregiverMode) return;
      final alarmUserId = alarmData['userId']?.toString() ?? '';
      if (alarmUserId.isNotEmpty &&
          _authVm.currentUserId.isNotEmpty &&
          alarmUserId != _authVm.currentUserId) {
        return;
      }
      final medId = alarmData['medId']?.toString() ?? '';
      final sched =
          DateTime.tryParse(alarmData['sched']?.toString() ?? '') ??
              DateTime.now();
      if (medId.isEmpty || AlarmScheduler.isDoseTerminal(medId, sched)) {
        return;
      }

      final uri = Uri(
        path: '/alarm-ring',
        queryParameters: {
          'medId': medId,
          'userId': alarmUserId.isNotEmpty ? alarmUserId : _authVm.currentUserId,
          'notifId': alarmData['notifId']?.toString() ?? '0',
          'schedTime': sched.toIso8601String(),
          'medName': alarmData['medName']?.toString() ?? 'Medication',
          'doseAmount': alarmData['doseAmount']?.toString() ?? '1.0',
          'strength': alarmData['strength']?.toString() ?? '',
          'formName': alarmData['form']?.toString() ?? 'tablet',
          'colorTag': alarmData['colorTag']?.toString() ?? '0xFF1E66F5',
          'instructions': alarmData['instructions']?.toString() ??
              'Take as prescribed with water.',
          'soundId': alarmData['soundId']?.toString() ?? '',
          'customPath': alarmData['customPath']?.toString() ?? '',
          'snoozeCount': (alarmData['snoozeCount'] ?? 0).toString(),
        },
      );
      _presentOrQueueAlarmScreen(
        uri: uri,
        medId: medId,
        schedTime: sched,
      );
    };

    // Foreground active dose alarm monitor: pops up alarm screen when due while using app
    _foregroundDoseMonitorTimer =
        Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_checkForegroundDueDoses());
    });

    // Native Android AlarmClock trigger listener: auto-routes to /alarm-ring when screen wakes
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      const nativeChannel = MethodChannel('com.remedytrack.app/alarm_window');
      nativeChannel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'onNativeAlarmTriggered') {
          final payload = call.arguments?.toString();
          if (payload != null && payload.isNotEmpty) {
            await _handleNotificationAction(payload, null);
          }
        }
      });
    }

    // Drain cold-start notification launch details after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_flushPendingThenReconcile());
      unawaited(AlarmScheduler.refillRollingWindowFromCache());

      // Drain cold-start native alarm clock launch details first
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          const nativeChannel =
              MethodChannel('com.remedytrack.app/alarm_window');
          final pendingNativePayload =
              await nativeChannel.invokeMethod<String>('getPendingAlarmLaunch');
          if (pendingNativePayload != null && pendingNativePayload.isNotEmpty) {
            await _handleNotificationAction(pendingNativePayload, null);
            return;
          }
        } catch (e, s) {
          AppLogger.w('Failed to read pending native alarm launch: $e',
              tag: 'Main', error: e, stackTrace: s);
        }
      }

      final launchDetails =
          await _notificationService.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final response = launchDetails.notificationResponse;
        if (response != null && response.payload != null) {
          await _handleNotificationAction(response.payload!, response.actionId);
        }
      }
    });
  }

  Timer? _foregroundDoseMonitorTimer;
  final Set<String> _foregroundTriggeredDoseKeys = <String>{};
  bool _isCheckingForegroundDoses = false;

  void _onAuthStateChanged() {
    if (!_authVm.isAuthenticated) {
      _foregroundTriggeredDoseKeys.clear();
      if (_caregiverVm.isCaregiverMode) {
        _caregiverVm.setActiveProfile(null, null);
      }
    }
  }

  Future<void> _checkForegroundDueDoses() async {
    if (_isCheckingForegroundDoses) return;
    if (AppRouter.isAlarmRingingActive) return;
    if (_caregiverVm.isCaregiverMode) return;
    final uid = _authVm.currentUserId;
    if (uid.isEmpty) return;

    _isCheckingForegroundDoses = true;
    try {
      await AlarmScheduler.refreshAcknowledgedDosesFromPrefs(
        reloadPrefs: false,
      );

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      List<Medication> meds = const [];
      try {
        final cachedMeds = await LocalMedicationCache.loadMedications();
        meds = cachedMeds
            .where((m) => m.userId.isEmpty || m.userId == uid)
            .toList();
      } catch (e) {
        AppLogger.d('Foreground cache read skipped: $e', tag: 'Main');
      }
      if (meds.isEmpty) {
        try {
          meds = await _medRepo.getMedications(uid);
        } catch (e) {
          AppLogger.d('Foreground due check fallback skipped: $e',
              tag: 'Main');
          return;
        }
      }
      if (meds.isEmpty) return;

      // Collect candidate doses currently within their 60-second due window [0..59s]
      final List<({Medication med, DateTime schedDateTime, int timeIndex})>
          dueCandidates = [];
      for (final med in meds) {
        if (med.userId.isNotEmpty && med.userId != uid) continue;
        if (!med.isActive || med.isPrn || med.schedule == null) continue;
        if (!ScheduleExpander.isScheduledOnDate(med.schedule!, today)) continue;

        final times = med.schedule!.timesOfDay;
        for (var i = 0; i < times.length; i++) {
          final parsed = ScheduleExpander.parseTimeOfDay(times[i]);
          if (parsed == null) continue;
          final schedDateTime = DateTime(
              today.year, today.month, today.day, parsed.$1, parsed.$2);
          final diffSec = now.difference(schedDateTime).inSeconds;
          if (diffSec < 0 || diffSec >= 60) continue;

          final doseKey = '${med.id}_${schedDateTime.toIso8601String()}';
          if (_foregroundTriggeredDoseKeys.contains(doseKey) ||
              AlarmScheduler.isDoseSlotHandled(med.id, schedDateTime)) {
            continue;
          }
          dueCandidates.add((
            med: med,
            schedDateTime: schedDateTime,
            timeIndex: i,
          ));
        }
      }

      if (dueCandidates.isEmpty) return;

      // Verify against today's recorded IntakeLogs so already taken/skipped/snoozed
      // doses (including quick lock-screen actions) never re-trigger.
      final Map<String, IntakeLog> todayLogsById = {};
      try {
        final logs = await _intakeRepo.getLogsForDateRange(
          uid,
          today,
          today.add(const Duration(days: 1)),
        );
        for (final log in logs) {
          todayLogsById[log.id] = log;
        }
      } catch (e) {
        AppLogger.d('Foreground intake lookup skipped: $e', tag: 'Main');
      }

      for (final candidate in dueCandidates) {
        final med = candidate.med;
        final schedDateTime = candidate.schedDateTime;
        final logId = DoseStateMachine.generateLogId(med.id, schedDateTime);
        final existingLog = todayLogsById[logId];
        final doseKey = '${med.id}_${schedDateTime.toIso8601String()}';

        if (existingLog != null) {
          _foregroundTriggeredDoseKeys.add(doseKey);
          await AlarmScheduler.markDoseAcknowledged(
            med.id,
            schedDateTime,
            terminal: existingLog.status != DoseStatus.snoozed,
          );
          continue;
        }

        _foregroundTriggeredDoseKeys.add(doseKey);
        await AlarmScheduler.markDoseAcknowledged(
          med.id,
          schedDateTime,
          terminal: false,
        );

        final notifId = AlarmIdGenerator.generateDoseAlarmId(
          medicationId: med.id,
          scheduledDateTime: schedDateTime,
          timeIndex: candidate.timeIndex,
        );
        AlarmScheduler.onAlarmTriggered?.call({
          'medId': med.id,
          'userId': med.userId.isNotEmpty ? med.userId : uid,
          'notifId': notifId,
          'sched': schedDateTime.toIso8601String(),
          'medName': med.name,
          'doseAmount': med.doseAmount,
          'strength': med.strength,
          'form': med.form.name,
          'colorTag': med.colorTag,
          'instructions': med.instructions,
          'soundId': med.alarmSoundId,
          'customPath': med.customSoundPath ?? '',
        });
      }
    } finally {
      _isCheckingForegroundDoses = false;
    }
  }

  String? _lastHandledNotificationActionKey;
  String? _activeRingingDoseKey;
  final Map<String, DateTime> _recentlyPresentedDoseKeys = <String, DateTime>{};
  final List<({String doseKey, String medId, DateTime schedTime, Uri uri})>
      _pendingAlarmQueue = [];

  static String _buildCanonicalDoseKey(String medId, DateTime schedTime) {
    final normalized = DateTime(
      schedTime.year,
      schedTime.month,
      schedTime.day,
      schedTime.hour,
      schedTime.minute,
    );
    return '${medId}_${normalized.toIso8601String()}';
  }

  void _presentOrQueueAlarmScreen({
    required Uri uri,
    required String medId,
    required DateTime schedTime,
    bool forceFromUserTap = false,
  }) {
    if (medId.isEmpty || AlarmScheduler.isDoseTerminal(medId, schedTime)) {
      return;
    }
    final doseKey = _buildCanonicalDoseKey(medId, schedTime);
    final now = DateTime.now();

    // If this exact dose is already actively ringing on screen, never push a duplicate route.
    if (AppRouter.isAlarmRingingActive && _activeRingingDoseKey == doseKey) {
      return;
    }

    // Ignore duplicate automatic triggers for the same dose within 45 seconds
    // (e.g., when native broadcast, foreground timer, and local notification fire together).
    if (!forceFromUserTap) {
      final lastPresented = _recentlyPresentedDoseKeys[doseKey];
      if (lastPresented != null &&
          now.difference(lastPresented).inSeconds < 45) {
        return;
      }
    }

    // If another medication's alarm is currently ringing on screen, enqueue this dose
    // so it presents immediately after the current alarm is handled instead of overriding it.
    if (AppRouter.isAlarmRingingActive) {
      final alreadyQueued =
          _pendingAlarmQueue.any((entry) => entry.doseKey == doseKey);
      if (!alreadyQueued) {
        _pendingAlarmQueue.add((
          doseKey: doseKey,
          medId: medId,
          schedTime: schedTime,
          uri: uri,
        ));
      }
      return;
    }

    _activeRingingDoseKey = doseKey;
    _recentlyPresentedDoseKeys[doseKey] = now;
    unawaited(PermissionService().wakeUpScreen());
    final router = AppRouter.getRouter(_authVm);
    if (router.canPop()) {
      unawaited(router.push(uri.toString()));
    } else {
      router.go(uri.toString());
    }
  }

  void _handleAlarmScreenDismissed() {
    _activeRingingDoseKey = null;
    if (_pendingAlarmQueue.isEmpty) return;

    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted || AppRouter.isAlarmRingingActive) return;
      while (_pendingAlarmQueue.isNotEmpty) {
        final next = _pendingAlarmQueue.removeAt(0);
        if (!AlarmScheduler.isDoseTerminal(next.medId, next.schedTime)) {
          _presentOrQueueAlarmScreen(
            uri: next.uri,
            medId: next.medId,
            schedTime: next.schedTime,
            forceFromUserTap: true,
          );
          break;
        }
      }
    });
  }

  void _resetAllUserViewModels() {
    _medVm.resetState();
    _intakeVm.resetState();
    _invVm.resetState();
    _adherenceVm.resetState();
    _caregiverVm.resetState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_flushPendingThenReconcile());
      unawaited(
        AlarmScheduler.refreshAcknowledgedDosesFromPrefs(reloadPrefs: true)
            .then((_) => _checkForegroundDueDoses()),
      );
      _notificationService
          .getNotificationAppLaunchDetails()
          .then((launchDetails) {
        if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
          final response = launchDetails.notificationResponse;
          if (response != null && response.payload != null) {
            _handleNotificationAction(response.payload!, response.actionId);
          }
        }
      }).catchError((_) {});
    }
  }

  void _onConnectivityChanged() {
    if (_connectivityService.isOnline) {
      unawaited(_flushPendingThenReconcile());
    }
  }

  /// Flushes queued offline/background intakes FIRST so reconciliation never
  /// erroneously marks queued taken doses as missed.
  Future<void> _flushPendingThenReconcile() async {
    final uid = _authVm.currentUserId;
    if (uid.isEmpty) return;
    await _intakeVm.flushPendingBackgroundIntakes(uid);
    final reconciler = MissedDoseReconciler(
      medicationRepository: _medRepo,
      intakeRepository: _intakeRepo,
    );
    await reconciler.reconcileMissedDoses(uid);
  }

  @override
  void dispose() {
    _foregroundDoseMonitorTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _connectivityService.removeListener(_onConnectivityChanged);
    _authVm.removeListener(_onAuthStateChanged);
    _authVm.onBeforeSignOut = null;
    _authVm.onFlushPendingBeforeSignOut = null;
    _connectivityService.dispose();
    _settingsVm.dispose();
    _authVm.dispose();
    _medVm.dispose();
    _intakeVm.dispose();
    _invVm.dispose();
    _adherenceVm.dispose();
    _caregiverVm.dispose();
    super.dispose();
  }

  Future<void> _handleNotificationAction(
      String payload, String? actionId) async {
    final actionKey = '$actionId|$payload';
    if (_lastHandledNotificationActionKey == actionKey) {
      AppLogger.d('Duplicate notification launch intent ignored',
          tag: 'RemedyTrackApp');
      return;
    }
    _lastHandledNotificationActionKey = actionKey;

    String medId = '';
    int notifId = 0;
    int? primaryNotifId;
    DateTime schedTime = DateTime.now();
    String userId = '';
    String medName = 'Medication';
    double doseAmount = 1.0;
    String strength = '';
    String formName = 'tablet';
    String colorTag = '0xFF1E66F5';
    String instructions = 'Take as prescribed with water.';
    String soundId = '';
    String customPath = '';
    bool vibrate = true;
    int snoozeCount = 0;

    try {
      if (payload.trim().startsWith('{')) {
        final map = jsonDecode(payload) as Map<String, dynamic>;
        medId = map['medId']?.toString() ?? '';
        notifId = (map['notifId'] as num?)?.toInt() ??
            int.tryParse(map['notifId']?.toString() ?? '') ??
            0;
        primaryNotifId = (map['primaryNotifId'] as num?)?.toInt();
        schedTime =
            DateTime.tryParse(map['sched']?.toString() ?? '') ?? DateTime.now();
        userId = map['userId']?.toString() ?? '';
        medName = map['medName']?.toString() ?? 'Medication';
        doseAmount = (map['doseAmount'] as num?)?.toDouble() ?? 1.0;
        strength = map['strength']?.toString() ?? '';
        formName = map['form']?.toString() ?? 'tablet';
        colorTag = map['colorTag']?.toString() ?? '0xFF1E66F5';
        instructions =
            map['instructions']?.toString() ?? 'Take as prescribed with water.';
        soundId = map['soundId']?.toString() ?? '';
        customPath = map['customPath']?.toString() ?? '';
        vibrate = map['vibrate'] as bool? ?? true;
        snoozeCount = (map['snoozeCount'] as num?)?.toInt() ?? 0;
      } else {
        final parts = payload.split('|');
        if (parts.length >= 3) {
          medId = parts[0];
          notifId = int.tryParse(parts[1]) ?? 0;
          schedTime = DateTime.tryParse(parts[2]) ?? DateTime.now();
          userId = parts.length > 3 ? parts[3] : '';
          medName = parts.length > 4 ? parts[4] : 'Medication';
          doseAmount =
              parts.length > 5 ? (double.tryParse(parts[5]) ?? 1.0) : 1.0;
          strength = parts.length > 6 ? parts[6] : '';
          formName = parts.length > 7 ? parts[7] : 'tablet';
          colorTag = parts.length > 8 ? parts[8] : '0xFF1E66F5';
          instructions =
              parts.length > 9 ? parts[9] : 'Take as prescribed with water.';
          soundId = parts.length > 10 ? parts[10] : '';
          customPath = parts.length > 11 ? parts[11] : '';
        }
      }
    } catch (e, s) {
      AppLogger.w('Notification payload parse error: $e',
          tag: 'RemedyTrackApp', error: e, stackTrace: s);
    }

    if (medId.isEmpty) return;
    await AlarmScheduler.refreshAcknowledgedDosesFromPrefs();
    if (userId.isNotEmpty &&
        _authVm.currentUserId.isNotEmpty &&
        userId != _authVm.currentUserId) {
      return;
    }

    final primaryId = primaryNotifId ?? AlarmIdGenerator.getPrimaryId(notifId);

    if (actionId == null || actionId.isEmpty) {
      if (AlarmScheduler.isDoseTerminal(medId, schedTime)) {
        await _alarmScheduler.cancelDoseAlarmsForOccurrence(
          medicationId: medId,
          scheduledTime: schedTime,
        );
        return;
      }

      try {
        final cachedMeds = await LocalMedicationCache.loadMedications();
        final cachedMed = cachedMeds.cast<Medication?>().firstWhere(
              (m) => m?.id == medId,
              orElse: () => null,
            );
        if (cachedMed != null && !cachedMed.isActive) {
          await _alarmScheduler.cancelDoseAlarmsForOccurrence(
            medicationId: medId,
            scheduledTime: schedTime,
          );
          return;
        }
      } catch (_) {}

      final doseKey = '${medId}_${schedTime.toIso8601String()}';
      _foregroundTriggeredDoseKeys.add(doseKey);
      if (snoozeCount == 0) {
        unawaited(AlarmScheduler.markDoseAcknowledged(
          medId,
          schedTime,
          terminal: false,
        ));
      }

      final uri = Uri(
        path: '/alarm-ring',
        queryParameters: {
          'medId': medId,
          'userId': userId.isNotEmpty ? userId : _authVm.currentUserId,
          'notifId': primaryId.toString(),
          'schedTime': schedTime.toIso8601String(),
          'medName': medName,
          'doseAmount': doseAmount.toString(),
          'strength': strength,
          'formName': formName,
          'colorTag': colorTag,
          'instructions': instructions,
          'soundId': soundId,
          'customPath': customPath,
          'snoozeCount': snoozeCount.toString(),
        },
      );
      _presentOrQueueAlarmScreen(
        uri: uri,
        medId: medId,
        schedTime: schedTime,
      );
      return;
    }

    // Action button handling: stop active audio, remove from pending queue, and cancel persistent alarm
    final handledDoseKey = _buildCanonicalDoseKey(medId, schedTime);
    _pendingAlarmQueue.removeWhere((entry) => entry.doseKey == handledDoseKey);
    await AlarmSoundService().stopAlarm();
    await _alarmScheduler.cancelDoseAlarmsForOccurrence(
      medicationId: medId,
      scheduledTime: schedTime,
    );
    await _alarmScheduler.cancelDoseAlarms(primaryId);
    if (notifId != primaryId) {
      await _notificationService.cancelNotification(notifId);
    }
    if (AppRouter.isAlarmRingingActive &&
        _activeRingingDoseKey == handledDoseKey) {
      final router = AppRouter.getRouter(_authVm);
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/home');
      }
      _handleAlarmScreenDismissed();
    }

    final formEnum = MedicationForm.values.firstWhere(
      (f) => f.name.toLowerCase() == formName.toLowerCase(),
      orElse: () => MedicationForm.tablet,
    );
    final isTabletOrCapsule =
        formEnum == MedicationForm.tablet || formEnum == MedicationForm.capsule;

    if (actionId == AppConstants.actionTaken) {
      await AlarmScheduler.markDoseAcknowledged(
        medId,
        schedTime,
        terminal: true,
      );
      final now = DateTime.now();
      final isLate = now.difference(schedTime).inMinutes >
          AppConstants.lateGracePeriodMinutes;
      final log = IntakeLog(
        id: DoseStateMachine.generateLogId(medId, schedTime),
        userId: userId.isNotEmpty ? userId : _authVm.currentUserId,
        medicationId: medId,
        medicationName: medName,
        scheduledTime: schedTime,
        recordedTime: now,
        status: isLate ? DoseStatus.late : DoseStatus.taken,
        doseAmount: doseAmount,
        isPrn: false,
      );

      if (isTabletOrCapsule) {
        _invVm.adjustLocalStock(medId, -doseAmount);
      }

      try {
        await _intakeVm
            .recordIntakeAtomic(
              intakeLog: log,
              decrementInventory: isTabletOrCapsule,
            )
            .timeout(const Duration(seconds: 12));
        AppLogger.i('Dose recorded as taken via notification action button.',
            tag: 'RemedyTrackApp');
      } catch (e, s) {
        AppLogger.w('Notification Take sync failed, queuing offline: $e',
            tag: 'RemedyTrackApp', error: e, stackTrace: s);
        try {
          final prefs = await SharedPreferences.getInstance();
          final pendingList =
              prefs.getStringList('pending_background_intakes') ?? [];
          pendingList.add(jsonEncode({
            'log': log.toJson(),
            'decrementInventory': isTabletOrCapsule,
            'timestamp': DateTime.now().toIso8601String(),
          }));
          await prefs.setStringList('pending_background_intakes', pendingList);
        } catch (cacheErr, cacheStack) {
          AppLogger.e('Failed to queue offline Taken intake log',
              tag: 'RemedyTrackApp', error: cacheErr, stackTrace: cacheStack);
          if (isTabletOrCapsule) {
            _invVm.adjustLocalStock(medId, doseAmount);
          }
        }
      }
    } else if (actionId == AppConstants.actionSkip) {
      await AlarmScheduler.markDoseAcknowledged(
        medId,
        schedTime,
        terminal: true,
      );
      final log = IntakeLog(
        id: DoseStateMachine.generateLogId(medId, schedTime),
        userId: userId.isNotEmpty ? userId : _authVm.currentUserId,
        medicationId: medId,
        medicationName: medName,
        scheduledTime: schedTime,
        recordedTime: DateTime.now(),
        status: DoseStatus.skipped,
        doseAmount: doseAmount,
        isPrn: false,
      );

      try {
        await _intakeVm
            .recordIntakeAtomic(
              intakeLog: log,
              decrementInventory: false,
            )
            .timeout(const Duration(seconds: 12));
        AppLogger.i('Dose recorded as skipped via notification action button.',
            tag: 'RemedyTrackApp');
      } catch (e, s) {
        AppLogger.w('Notification Skip sync failed, queuing offline: $e',
            tag: 'RemedyTrackApp', error: e, stackTrace: s);
        try {
          final prefs = await SharedPreferences.getInstance();
          final pendingList =
              prefs.getStringList('pending_background_intakes') ?? [];
          pendingList.add(jsonEncode({
            'log': log.toJson(),
            'decrementInventory': false,
            'timestamp': DateTime.now().toIso8601String(),
          }));
          await prefs.setStringList('pending_background_intakes', pendingList);
        } catch (cacheErr, cacheStack) {
          AppLogger.e('Failed to queue offline Skip intake log',
              tag: 'RemedyTrackApp', error: cacheErr, stackTrace: cacheStack);
        }
      }
    } else if (actionId == AppConstants.actionSnooze) {
      await AlarmScheduler.markDoseAcknowledged(
        medId,
        schedTime,
        terminal: false,
      );
      final now = DateTime.now();
      final delayMinutes = now.difference(schedTime).inMinutes;

      // Clinical 3-snooze and 60-minute safety checks (A5)
      if (snoozeCount >= DoseStateMachine.maxSnoozeLimit ||
          delayMinutes > DoseStateMachine.missedThresholdMinutes) {
        AppLogger.i(
            'Snooze rejected via lock screen: limit ($snoozeCount) or 60m window reached.',
            tag: 'RemedyTrackApp');
        return;
      }

      final snoozeMins = _settingsVm.snoozeMinutes;
      final snoozeTime = now.add(Duration(minutes: snoozeMins));
      final nextSnoozeCount = snoozeCount + 1;

      final snoozeLog = IntakeLog(
        id: DoseStateMachine.generateLogId(medId, schedTime),
        userId: userId.isNotEmpty ? userId : _authVm.currentUserId,
        medicationId: medId,
        medicationName: medName,
        scheduledTime: schedTime,
        recordedTime: now,
        status: DoseStatus.snoozed,
        snoozeUntil: snoozeTime,
        snoozeCount: nextSnoozeCount,
        doseAmount: doseAmount,
        isPrn: false,
        notes:
            'Snoozed for ${snoozeMins}m ($nextSnoozeCount/${DoseStateMachine.maxSnoozeLimit})',
      );

      try {
        await _intakeVm
            .recordIntakeAtomic(
              intakeLog: snoozeLog,
              decrementInventory: false,
            )
            .timeout(const Duration(seconds: 6));
      } catch (e, s) {
        AppLogger.w('Snooze sync failed, queuing offline: $e',
            tag: 'RemedyTrackApp', error: e, stackTrace: s);
        try {
          final prefs = await SharedPreferences.getInstance();
          final pendingList =
              prefs.getStringList('pending_background_intakes') ?? [];
          pendingList.add(jsonEncode({
            'log': snoozeLog.toJson(),
            'decrementInventory': false,
            'timestamp': DateTime.now().toIso8601String(),
          }));
          await prefs.setStringList('pending_background_intakes', pendingList);
        } catch (cacheErr, cacheStack) {
          AppLogger.e('Failed to queue offline snooze log',
              tag: 'RemedyTrackApp', error: cacheErr, stackTrace: cacheStack);
        }
      }

      final med = Medication(
        id: medId,
        userId: userId.isNotEmpty ? userId : _authVm.currentUserId,
        name: medName,
        doseAmount: doseAmount,
        strength: strength,
        form: formEnum,
        colorTag: int.tryParse(colorTag) ?? 0xFF1E66F5,
        instructions: instructions,
        alarmSoundId: soundId.isNotEmpty ? soundId : _settingsVm.alarmSound,
        customSoundPath: customPath.isNotEmpty ? customPath : null,
        vibrationEnabled: vibrate,
        createdAt: now,
        updatedAt: now,
      );

      await _alarmScheduler.scheduleSnoozeAlarm(
        notificationId: primaryId,
        medication: med,
        originalScheduledTime: schedTime,
        snoozeMinutes: snoozeMins,
        snoozeCount: nextSnoozeCount,
      );
      AppLogger.i(
          'Dose snoozed for $snoozeMins mins via notification action button.',
          tag: 'RemedyTrackApp');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Services & Repositories
        Provider<NotificationService>.value(value: _notificationService),
        Provider<AlarmScheduler>.value(value: _alarmScheduler),
        Provider<AlarmSoundService>.value(value: AlarmSoundService()),
        Provider<SecureStorageService>.value(value: _secureStorage),
        ChangeNotifierProvider<ConnectivityService>.value(
            value: _connectivityService),
        Provider<AnalyticsService>.value(value: _analyticsService),
        Provider<MedicationRepository>.value(value: _medRepo),
        Provider<IntakeRepository>.value(value: _intakeRepo),
        Provider<InventoryRepository>.value(value: _invRepo),
        Provider<UserRepository>.value(value: _userRepo),
        Provider<CaregiverRepository>.value(value: _caregiverRepo),

        // ViewModels
        ChangeNotifierProvider<SettingsViewModel>.value(value: _settingsVm),
        ChangeNotifierProvider<AuthViewModel>.value(value: _authVm),
        ChangeNotifierProvider<MedicationViewModel>.value(value: _medVm),
        ChangeNotifierProvider<IntakeViewModel>.value(value: _intakeVm),
        ChangeNotifierProvider<InventoryViewModel>.value(value: _invVm),
        ChangeNotifierProvider<AdherenceViewModel>.value(value: _adherenceVm),
        ChangeNotifierProvider<CaregiverViewModel>.value(
          value: _caregiverVm,
        ),
      ],
      child: Consumer<SettingsViewModel>(
        builder: (context, settingsVm, _) {
          return MaterialApp.router(
            title: 'RemedyTrack',
            debugShowCheckedModeBanner: false,
            routerConfig: AppRouter.getRouter(_authVm),
            themeMode: settingsVm.themeMode,
            theme: AppTheme.light(isHighContrast: settingsVm.isHighContrast),
            darkTheme: AppTheme.dark(isHighContrast: settingsVm.isHighContrast),
            builder: (context, child) =>
                AppLockOverlay(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}
