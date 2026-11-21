import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/state/dose_state_machine.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../core/validation/medication_validator.dart';
import '../../models/intake_log.dart';
import '../../models/medication.dart';
import '../../services/alarm_scheduler.dart';
import '../../services/alarm_sound_service.dart';
import '../../services/crashlytics_service.dart';
import '../../services/notification_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/intake_viewmodel.dart';
import '../../viewmodels/inventory_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../widgets/pill_avatar.dart';
import 'widgets/alarm_modals.dart';

/// Full-screen alarm view for scheduled medication reminders.
/// Pairs looping STREAM_ALARM audio with a live countdown dial, staggered entrance
/// motion (respecting reduced-motion preferences), single primary Take confirmation,
/// bounded Snooze controls, and Skip reason sheets.
class AlarmRingingScreen extends StatefulWidget {
  final String medicationId;
  final String userId;
  final int notificationId;
  final DateTime scheduledTime;
  final String medicationName;
  final String strength;
  final double doseAmount;
  final String formName;
  final int colorTag;
  final String instructions;
  final String? soundId;
  final String? customSoundPath;
  final int initialSnoozeCount;

  const AlarmRingingScreen({
    super.key,
    required this.medicationId,
    this.userId = '',
    required this.notificationId,
    required this.scheduledTime,
    required this.medicationName,
    this.strength = '',
    this.doseAmount = 1.0,
    this.formName = 'tablet',
    this.colorTag = 0xFF1E66F5,
    this.instructions = 'Take as prescribed with water.',
    this.soundId,
    this.customSoundPath,
    this.initialSnoozeCount = 0,
  });

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with TickerProviderStateMixin {
  static const int _ringDurationSeconds = 300;
  static const List<String> alarmFrameAssets = [
    'assets/branding/alarm_frames/alarm_frame_01.png',
    'assets/branding/alarm_frames/alarm_frame_02.png',
    'assets/branding/alarm_frames/alarm_frame_03.png',
    'assets/branding/alarm_frames/alarm_frame_04.png',
    'assets/branding/alarm_frames/alarm_frame_05.png',
    'assets/branding/alarm_frames/alarm_frame_06.png',
    'assets/branding/alarm_frames/alarm_frame_07.png',
    'assets/branding/alarm_frames/alarm_frame_08.png',
  ];

  late final AnimationController _entranceController;
  late final AnimationController _dialSweepController;
  bool _didStartEntrance = false;

  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();
  int _secondsRemaining = _ringDurationSeconds;
  int _currentSnoozeCount = 0;
  bool _isMuted = false;
  bool _hasTimedOut = false;
  bool _isProcessing = false;

  String? _resolvedSoundId;
  String? _resolvedCustomPath;
  bool _resolvedVibration = true;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _dialSweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
          if (_secondsRemaining > 0) {
            _secondsRemaining--;
          } else if (!_hasTimedOut) {
            _hasTimedOut = true;
            _handleTimeout();
          }
        });
      }
    });

    HapticFeedback.heavyImpact();
    _loadSnoozeCount();
    if (widget.notificationId != 0) {
      AlarmScheduler.activeRingingNotificationIds.add(widget.notificationId);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Cancel the primary scheduled tray notification and native alarm immediately so
        // the system notification channel never double-rings while this ringing screen is open.
        if (widget.notificationId != 0) {
          unawaited(
            context
                .read<NotificationService>()
                .cancelNotification(widget.notificationId),
          );
        }
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          const MethodChannel('com.remedytrack.app/alarm_window')
              .invokeMethod<void>(
                'cancelNativeAlarm',
                {'id': widget.notificationId},
              )
              .catchError((_) {});
        }
      }
      _startRingingAudio();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final framePath in alarmFrameAssets) {
      precacheImage(AssetImage(framePath), context);
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_didStartEntrance) {
      _didStartEntrance = true;
      if (reduceMotion) {
        _entranceController.value = 1.0;
      } else {
        _entranceController.forward(from: 0.0);
      }
    }
    _syncDialMotion(reduceMotion);
  }

  void _syncDialMotion(bool reduceMotion) {
    if (reduceMotion || _isMuted || _isProcessing) {
      if (_dialSweepController.isAnimating) {
        _dialSweepController.stop();
      }
    } else if (!_dialSweepController.isAnimating) {
      _dialSweepController.repeat();
    }
  }

  void _loadSnoozeCount() {
    final intakeVm = context.read<IntakeViewModel>();
    final matchingLogs = intakeVm.allLogs.where(
      (l) =>
          l.medicationId == widget.medicationId &&
          l.scheduledTime.year == widget.scheduledTime.year &&
          l.scheduledTime.month == widget.scheduledTime.month &&
          l.scheduledTime.day == widget.scheduledTime.day &&
          l.scheduledTime.hour == widget.scheduledTime.hour &&
          l.scheduledTime.minute == widget.scheduledTime.minute,
    );

    int maxCount = widget.initialSnoozeCount;
    for (final l in matchingLogs) {
      if (l.status == DoseStatus.snoozed) {
        if (l.snoozeCount > maxCount) maxCount = l.snoozeCount;
      }
    }
    setState(() => _currentSnoozeCount = maxCount);
  }

  Future<void> _startRingingAudio() async {
    final medVm = context.read<MedicationViewModel>();
    final settingsVm = context.read<SettingsViewModel>();

    final med = medVm.medications.cast<Medication?>().firstWhere(
          (m) => m?.id == widget.medicationId,
          orElse: () => null,
        );

    _resolvedSoundId = widget.soundId?.isNotEmpty == true
        ? widget.soundId
        : (med?.alarmSoundId ?? settingsVm.alarmSound);
    _resolvedCustomPath = widget.customSoundPath?.isNotEmpty == true
        ? widget.customSoundPath
        : med?.customSoundPath;
    _resolvedVibration = med?.vibrationEnabled ?? true;

    final soundService = AlarmSoundService();
    await soundService.startAlarm(
      soundId: _resolvedSoundId,
      customPath: _resolvedCustomPath,
      vibration: _resolvedVibration,
    );

    if (mounted) {
      setState(() {
        _isMuted = soundService.isMuted;
      });
      _syncDialMotion(MediaQuery.disableAnimationsOf(context));
    }
  }

  @override
  void dispose() {
    AlarmScheduler.activeRingingNotificationIds.remove(widget.notificationId);
    _entranceController.dispose();
    _dialSweepController.dispose();
    _clockTimer?.cancel();
    AlarmSoundService().stopAlarm();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    final soundService = AlarmSoundService();
    await soundService.toggleMute(
      soundId: _resolvedSoundId,
      customPath: _resolvedCustomPath,
      vibration: _resolvedVibration,
    );
    if (mounted) {
      setState(() {
        _isMuted = soundService.isMuted;
      });
      _syncDialMotion(MediaQuery.disableAnimationsOf(context));
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isMuted ? 'Alarm sound muted' : 'Alarm sound unmuted'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _silenceNotification() async {
    await AlarmSoundService().stopAlarm();
    if (!mounted) return;
    final notifService = context.read<NotificationService>();
    final alarmScheduler = context.read<AlarmScheduler>();
    await AlarmScheduler.markDoseAcknowledged(
      widget.medicationId,
      widget.scheduledTime,
      terminal: false,
    );
    await notifService.cancelNotification(widget.notificationId);
    await alarmScheduler.cancelDoseAlarms(widget.notificationId);
    await alarmScheduler.cancelDoseAlarmsForOccurrence(
      medicationId: widget.medicationId,
      scheduledTime: widget.scheduledTime,
    );
  }

  Future<void> _handleTaken() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });
    _syncDialMotion(MediaQuery.disableAnimationsOf(context));

    await HapticFeedback.heavyImpact();

    // 1. Mark dose terminally handled & immediately silence alarm audio and notifications
    await AlarmScheduler.markDoseAcknowledged(
      widget.medicationId,
      widget.scheduledTime,
      terminal: true,
    );
    await _silenceNotification();

    if (!mounted) {
      _isProcessing = false;
      return;
    }
    final intakeVm = context.read<IntakeViewModel>();
    final invVm = context.read<InventoryViewModel?>();
    final medVm = context.read<MedicationViewModel>();
    final authVm = context.read<AuthViewModel>();

    final med = medVm.medications.cast<Medication?>().firstWhere(
          (m) => m?.id == widget.medicationId,
          orElse: () => null,
        );

    final formEnum = med?.form ??
        MedicationForm.values.firstWhere(
          (f) => f.name.toLowerCase() == widget.formName.toLowerCase(),
          orElse: () => MedicationForm.tablet,
        );

    // RA 10173 & Capstone contract: atomic inventory decrement for tablets & capsules
    final shouldDecrement =
        formEnum == MedicationForm.tablet || formEnum == MedicationForm.capsule;

    String effectiveUserId = widget.userId;
    if (effectiveUserId.isEmpty) {
      effectiveUserId = authVm.currentUserId;
    }
    if (effectiveUserId.isEmpty) {
      effectiveUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    }
    if (effectiveUserId.isEmpty && med != null) {
      effectiveUserId = med.userId;
    }

    final isLate = DateTime.now().difference(widget.scheduledTime).inMinutes >
        AppConstants.lateGracePeriodMinutes;

    final intakeLog = IntakeLog(
      id: DoseStateMachine.generateLogId(
          widget.medicationId, widget.scheduledTime),
      userId: effectiveUserId,
      medicationId: widget.medicationId,
      medicationName: widget.medicationName,
      doseAmount: widget.doseAmount,
      scheduledTime: widget.scheduledTime,
      recordedTime: DateTime.now(),
      status: isLate ? DoseStatus.late : DoseStatus.taken,
      isPrn: false,
    );

    // Optimistic inventory update so stock badge updates immediately even offline
    if (shouldDecrement) {
      invVm?.adjustLocalStock(widget.medicationId, -widget.doseAmount);
    }

    // Brief visual confirmation of the green check, then dismiss screen immediately
    await Future<void>.delayed(const Duration(milliseconds: 180));
    _isProcessing = false;
    _exitScreen();

    // Background asynchronous database write: do NOT block UI dismissal waiting for Firestore!
    // IntakeRepository handles offline/slow writes with a 6s transaction timeout + 1.5s cache batch,
    // so we omit an aggressive outer timeout that could duplicate-queue an in-flight write.
    unawaited(() async {
      try {
        await intakeVm.recordIntakeAtomic(
          intakeLog: intakeLog,
          decrementInventory: shouldDecrement,
        );

        final rootCtx = AppRouter.rootNavigatorKey.currentContext;
        if (rootCtx != null && rootCtx.mounted) {
          final statusColors =
              Theme.of(rootCtx).extension<StatusColors>() ?? StatusColors.light;
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              content: Text('Dose recorded: ${widget.medicationName} taken!'),
              backgroundColor: statusColors.taken,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        // Offline fallback: Queue into pending_background_intakes so data is NEVER lost
        var queuedOffline = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          final pendingList =
              prefs.getStringList('pending_background_intakes') ?? [];
          pendingList.add(jsonEncode({
            'log': intakeLog.toJson(),
            'decrementInventory': shouldDecrement,
            'timestamp': DateTime.now().toIso8601String(),
          }));
          await prefs.setStringList('pending_background_intakes', pendingList);
          queuedOffline = true;
        } catch (cacheErr, cacheStack) {
          AppLogger.e('Failed to queue offline intake log',
              tag: 'AlarmRinging', error: cacheErr, stackTrace: cacheStack);
          unawaited(CrashlyticsService.recordError(cacheErr, cacheStack));
          if (shouldDecrement) {
            invVm?.adjustLocalStock(widget.medicationId, widget.doseAmount);
          }
        }

        final rootCtx = AppRouter.rootNavigatorKey.currentContext;
        if (rootCtx != null && rootCtx.mounted) {
          final statusColors =
              Theme.of(rootCtx).extension<StatusColors>() ?? StatusColors.light;
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              content: Text(queuedOffline
                  ? 'Dose saved offline (${widget.medicationName}). It will sync when back online.'
                  : 'Could not save dose for ${widget.medicationName}. Please retry.'),
              backgroundColor:
                  queuedOffline ? statusColors.taken : statusColors.missed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }());
  }

  Future<void> _handleSnoozeModal() async {
    if (_currentSnoozeCount >= DoseStateMachine.maxSnoozeLimit) {
      final statusColors =
          Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Maximum 3 snoozes reached for this dose.'),
          backgroundColor: statusColors.lowStock,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final settingsVm = context.read<SettingsViewModel>();
    final chosen = await AlarmModals.showSnoozeSheet(
      context: context,
      initialMinutes: settingsVm.snoozeMinutes,
      currentSnoozeCount: _currentSnoozeCount,
    );

    if (chosen == null || !mounted) return;
    await _executeSnooze(chosen);
  }

  Future<void> _executeSnooze(int chosen) async {
    if (_currentSnoozeCount >= DoseStateMachine.maxSnoozeLimit) {
      final statusColors =
          Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Maximum 3 snoozes reached for this dose.'),
          backgroundColor: statusColors.lowStock,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await HapticFeedback.mediumImpact();

    if (!mounted) {
      _isProcessing = false;
      return;
    }
    final alarmScheduler = context.read<AlarmScheduler>();
    final medVm = context.read<MedicationViewModel>();
    final intakeVm = context.read<IntakeViewModel>();
    final authVm = context.read<AuthViewModel>();

    final med = medVm.medications.cast<Medication?>().firstWhere(
          (m) => m?.id == widget.medicationId,
          orElse: () => null,
        );

    final formEnum = med?.form ??
        MedicationForm.values.firstWhere(
          (f) => f.name.toLowerCase() == widget.formName.toLowerCase(),
          orElse: () => MedicationForm.tablet,
        );

    // 1. Immediately silence current alarm audio and notifications (slot stays non-terminal for snooze)
    await _silenceNotification();
    if (!mounted) return;

    String effectiveUserId = widget.userId;
    if (effectiveUserId.isEmpty) {
      effectiveUserId = authVm.currentUserId;
    }
    if (effectiveUserId.isEmpty) {
      effectiveUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    }
    if (effectiveUserId.isEmpty && med != null) {
      effectiveUserId = med.userId;
    }

    final activeMed = med ??
        Medication(
          id: widget.medicationId,
          userId: effectiveUserId,
          name: widget.medicationName,
          doseAmount: widget.doseAmount,
          strength: widget.strength,
          form: formEnum,
          colorTag: widget.colorTag,
          instructions: widget.instructions,
          alarmSoundId: _resolvedSoundId ?? AppConstants.defaultAlarmSound,
          customSoundPath: _resolvedCustomPath,
          vibrationEnabled: _resolvedVibration,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

    final nextSnoozeCount = _currentSnoozeCount + 1;
    final snoozeLog = IntakeLog(
      id: DoseStateMachine.generateLogId(
          widget.medicationId, widget.scheduledTime),
      userId: effectiveUserId,
      medicationId: widget.medicationId,
      medicationName: widget.medicationName,
      doseAmount: widget.doseAmount,
      scheduledTime: widget.scheduledTime,
      recordedTime: DateTime.now(),
      status: DoseStatus.snoozed,
      snoozeUntil: DateTime.now().add(Duration(minutes: chosen)),
      snoozeCount: nextSnoozeCount,
      isPrn: false,
      notes:
          'Snoozed for ${chosen}m ($nextSnoozeCount/${DoseStateMachine.maxSnoozeLimit})',
    );

    await alarmScheduler.scheduleSnoozeAlarm(
      notificationId: widget.notificationId,
      medication: activeMed,
      originalScheduledTime: widget.scheduledTime,
      snoozeMinutes: chosen,
      snoozeCount: nextSnoozeCount,
    );

    _isProcessing = false;
    _exitScreen();

    unawaited(() async {
      try {
        await intakeVm
            .recordIntakeAtomic(
              intakeLog: snoozeLog,
              decrementInventory: false,
            )
            .timeout(const Duration(seconds: 12));

        final rootCtx = AppRouter.rootNavigatorKey.currentContext;
        if (rootCtx != null && rootCtx.mounted) {
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              content: Text(
                  'Snoozed for $chosen mins ($nextSnoozeCount/${DoseStateMachine.maxSnoozeLimit})'),
              backgroundColor: Theme.of(rootCtx).colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e, s) {
        AppLogger.w('Snooze sync failed, queuing offline: $e',
            tag: 'AlarmRinging', error: e, stackTrace: s);
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
          AppLogger.e('Failed to queue offline intake log',
              tag: 'AlarmRinging', error: cacheErr, stackTrace: cacheStack);
          unawaited(CrashlyticsService.recordError(cacheErr, cacheStack));
        }

        final rootCtx = AppRouter.rootNavigatorKey.currentContext;
        if (rootCtx != null && rootCtx.mounted) {
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              content: Text(
                  'Snoozed for $chosen mins ($nextSnoozeCount/${DoseStateMachine.maxSnoozeLimit})'),
              backgroundColor: Theme.of(rootCtx).colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }());
  }

  Future<void> _handleSkipModal() async {
    await HapticFeedback.mediumImpact();
    if (!mounted) return;

    final confirmedReason = await AlarmModals.showSkipSheet(
      context: context,
      medicationName: widget.medicationName,
    );

    if (confirmedReason == null || !mounted) return;
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    _syncDialMotion(MediaQuery.disableAnimationsOf(context));

    final intakeVm = context.read<IntakeViewModel>();
    final authVm = context.read<AuthViewModel>();
    final medVm = context.read<MedicationViewModel>();

    // 1. Mark dose terminally skipped & immediately silence current alarm audio and notifications
    await AlarmScheduler.markDoseAcknowledged(
      widget.medicationId,
      widget.scheduledTime,
      terminal: true,
    );
    await _silenceNotification();
    if (!mounted) return;

    final med = medVm.medications.cast<Medication?>().firstWhere(
          (m) => m?.id == widget.medicationId,
          orElse: () => null,
        );

    String effectiveUserId = widget.userId;
    if (effectiveUserId.isEmpty) {
      effectiveUserId = authVm.currentUserId;
    }
    if (effectiveUserId.isEmpty) {
      effectiveUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    }
    if (effectiveUserId.isEmpty && med != null) {
      effectiveUserId = med.userId;
    }

    final skipLog = IntakeLog(
      id: DoseStateMachine.generateLogId(
          widget.medicationId, widget.scheduledTime),
      userId: effectiveUserId,
      medicationId: widget.medicationId,
      medicationName: widget.medicationName,
      doseAmount: widget.doseAmount,
      scheduledTime: widget.scheduledTime,
      recordedTime: DateTime.now(),
      status: DoseStatus.skipped,
      isPrn: false,
      notes: confirmedReason,
    );

    _isProcessing = false;
    _exitScreen();

    unawaited(() async {
      try {
        await intakeVm
            .recordIntakeAtomic(
              intakeLog: skipLog,
              decrementInventory: false,
            )
            .timeout(const Duration(seconds: 12));

        final rootCtx = AppRouter.rootNavigatorKey.currentContext;
        if (rootCtx != null && rootCtx.mounted) {
          final statusColors =
              Theme.of(rootCtx).extension<StatusColors>() ?? StatusColors.light;
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              content: Text('Dose skipped: ${widget.medicationName}'),
              backgroundColor: statusColors.missed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e, s) {
        AppLogger.w('Skip sync failed, queuing offline: $e',
            tag: 'AlarmRinging', error: e, stackTrace: s);
        try {
          final prefs = await SharedPreferences.getInstance();
          final pendingList =
              prefs.getStringList('pending_background_intakes') ?? [];
          pendingList.add(jsonEncode({
            'log': skipLog.toJson(),
            'decrementInventory': false,
            'timestamp': DateTime.now().toIso8601String(),
          }));
          await prefs.setStringList('pending_background_intakes', pendingList);
        } catch (cacheErr, cacheStack) {
          AppLogger.e('Failed to queue offline intake log',
              tag: 'AlarmRinging', error: cacheErr, stackTrace: cacheStack);
          unawaited(CrashlyticsService.recordError(cacheErr, cacheStack));
        }

        final rootCtx = AppRouter.rootNavigatorKey.currentContext;
        if (rootCtx != null && rootCtx.mounted) {
          final statusColors =
              Theme.of(rootCtx).extension<StatusColors>() ?? StatusColors.light;
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              content: Text('Dose skipped: ${widget.medicationName}'),
              backgroundColor: statusColors.missed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }());
  }

  void _handleTimeout() {
    // Stop local audio/vibration but preserve scheduled follow-up reminder
    AlarmSoundService().stopAlarm();
    if (!mounted) return;
    _syncDialMotion(MediaQuery.disableAnimationsOf(context));
    final notifService = context.read<NotificationService>();
    notifService.cancelNotification(widget.notificationId);

    if (mounted) {
      final statusColors =
          Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Reminder paused for ${widget.medicationName}. Follow-up alert remains scheduled.'),
          backgroundColor: statusColors.lowStock,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _exitScreen();
    }
  }

  void _exitScreen() {
    AlarmScheduler.activeRingingNotificationIds.remove(widget.notificationId);
    try {
      const MethodChannel('com.remedytrack.app/alarm_window')
          .invokeMethod('dismissAlarmScreen');
    } catch (e, s) {
      AppLogger.w('Failed to dismiss native alarm window',
          tag: 'AlarmRinging', error: e, stackTrace: s);
    }

    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    }
    AppRouter.onAlarmScreenDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settingsVm = context.watch<SettingsViewModel?>();
    final isHighContrast = settingsVm?.isHighContrast ?? false;
    final is24h = settingsVm?.is24HourFormat ?? false;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final statusColors = theme.extension<StatusColors>() ??
        (isDark ? StatusColors.dark : StatusColors.light);

    const brandPaleBg = Color(0xFFF4FAFE);
    const brandSoftBlue = Color(0xFFDDF2FC);
    const brandBabyBlue = Color(0xFFA7D8F0);
    const brandDeepNavy = Color(0xFF24445C);
    const brandDarkBg = Color(0xFF163247);

    final bgColor = isHighContrast
        ? (isDark ? Colors.black : Colors.white)
        : (isDark ? brandDarkBg : brandPaleBg);
    final cardColor = isHighContrast
        ? (isDark ? const Color(0xFF161616) : Colors.white)
        : (isDark ? const Color(0xFF1E3E57) : Colors.white);
    final primaryText = isHighContrast
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? Colors.white : brandDeepNavy);
    final secondaryText = isHighContrast
        ? (isDark ? Colors.white70 : Colors.black87)
        : (isDark ? brandSoftBlue : const Color(0xFF4E6678));
    final accentBlue = isHighContrast
        ? theme.colorScheme.primary
        : (isDark ? brandBabyBlue : const Color(0xFF1557B0));

    final formEnum = MedicationForm.values.firstWhere(
      (f) => f.name.toLowerCase() == widget.formName.toLowerCase(),
      orElse: () => MedicationForm.tablet,
    );
    final formattedDose = MedicationValidator.formatQuantity(widget.doseAmount);
    final unitLabel = MedicationValidator.formatUnit(formEnum, widget.doseAmount);

    final timeStr = is24h
        ? DateFormat('HH:mm').format(_currentTime)
        : DateFormat('h:mm').format(_currentTime);
    final amPmStr = is24h ? '' : DateFormat('a').format(_currentTime);
    final secStr = DateFormat('ss').format(_currentTime);
    final dateStr = DateFormat('EEEE, MMM d').format(_currentTime);
    final schedTimeFormatted = is24h
        ? DateFormat('HH:mm').format(widget.scheduledTime)
        : DateFormat('h:mm a').format(widget.scheduledTime);

    final remainingSnoozes =
        DoseStateMachine.maxSnoozeLimit - _currentSnoozeCount;
    final countdownMins = _secondsRemaining ~/ 60;
    final countdownSecs = (_secondsRemaining % 60).toString().padLeft(2, '0');
    final ringProgress =
        (_secondsRemaining / _ringDurationSeconds).clamp(0.0, 1.0);
    final isDialActive = !reduceMotion && !_isMuted && !_isProcessing;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            return SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    minHeight: (viewportConstraints.maxHeight - 32)
                        .clamp(0.0, double.infinity),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Top utility bar: calm reminder status + sound/timer/close controls
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: accentBlue.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.notifications_active_rounded,
                                    size: 16,
                                    color: accentBlue,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Medication Reminder',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: primaryText,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              backgroundColor: cardColor,
                              foregroundColor: _isMuted
                                  ? statusColors.lowStock
                                  : statusColors.taken,
                              side: BorderSide(
                                color: (_isMuted
                                        ? statusColors.lowStock
                                        : statusColors.taken)
                                    .withValues(alpha: 0.55),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: _toggleMute,
                            icon: Icon(
                              _isMuted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              size: 16,
                            ),
                            label: Text(
                              _isMuted ? 'Muted' : 'Sound',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 7),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: accentBlue.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              '$countdownMins:$countdownSecs',
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Silence and close',
                            style: IconButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: cardColor,
                              foregroundColor: statusColors.missed,
                              side: BorderSide(
                                color:
                                    statusColors.missed.withValues(alpha: 0.45),
                              ),
                            ),
                            onPressed: () async {
                              await _silenceNotification();
                              if (mounted) _exitScreen();
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // 2. Hero clock + custom-painted live countdown dial + dose card
                      Column(
                        children: [
                          _buildStaggeredEntry(
                            start: 0.0,
                            end: 0.45,
                            child: Column(
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          color: primaryText,
                                          fontSize: 54,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -1.6,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        ':$secStr',
                                        style: TextStyle(
                                          color: secondaryText,
                                          fontSize: 21,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      if (amPmStr.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          amPmStr,
                                          style: TextStyle(
                                            color: accentBlue,
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$dateStr • Scheduled $schedTimeFormatted',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: 132,
                                  height: 132,
                                  child: AnimatedBuilder(
                                    animation: _dialSweepController,
                                    builder: (context, _) {
                                      final frameIdx = (!isDialActive || reduceMotion)
                                          ? 0
                                          : ((_dialSweepController.value * 24)
                                                  .floor() %
                                              alarmFrameAssets.length);
                                      return CustomPaint(
                                        painter: _AlarmDialPainter(
                                          progress: ringProgress,
                                          sweepPhase: _dialSweepController.value,
                                          isActive: isDialActive,
                                          trackColor: accentBlue.withValues(
                                              alpha: 0.22),
                                          progressColor: accentBlue,
                                        ),
                                        child: Center(
                                          child: Container(
                                            width: 96,
                                            height: 96,
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isDark
                                                  ? brandSoftBlue
                                                  : Colors.white,
                                              border: Border.all(
                                                color: accentBlue.withValues(
                                                    alpha: 0.45),
                                                width: 2,
                                              ),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: Image.asset(
                                              alarmFrameAssets[frameIdx],
                                              key: const ValueKey(
                                                  'alarm_frame_sequence_icon'),
                                              gaplessPlayback: true,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) => Icon(
                                                Icons.alarm_on_rounded,
                                                size: 48,
                                                color: accentBlue,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Medication Details Card
                          _buildStaggeredEntry(
                            start: 0.2,
                            end: 0.72,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: isHighContrast
                                      ? primaryText
                                      : accentBlue.withValues(
                                          alpha: isDark ? 0.35 : 0.65),
                                  width: isHighContrast ? 2.0 : 1.4,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      PillAvatar(
                                        form: formEnum,
                                        color: accentBlue,
                                        size: 48,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.medicationName,
                                              style: TextStyle(
                                                color: primaryText,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: isDark
                                                        ? accentBlue.withValues(
                                                            alpha: 0.18)
                                                        : brandSoftBlue,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: Text(
                                                    '$formattedDose $unitLabel',
                                                    style: TextStyle(
                                                      color: primaryText,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                if (widget.strength
                                                    .trim()
                                                    .isNotEmpty)
                                                  Text(
                                                    widget.strength.trim(),
                                                    style: TextStyle(
                                                      color: secondaryText,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            Builder(
                                              builder: (ctx) {
                                                final medVm = ctx.watch<
                                                    MedicationViewModel?>();
                                                final med = medVm?.medications
                                                    .cast<Medication?>()
                                                    .firstWhere(
                                                      (m) =>
                                                          m?.id ==
                                                          widget.medicationId,
                                                      orElse: () => null,
                                                    );
                                                final fallbackInst =
                                                    widget.instructions.trim();
                                                final instructions = (med
                                                                ?.instructions
                                                                .trim()
                                                                .isNotEmpty ==
                                                            true
                                                        ? med!.instructions
                                                            .trim()
                                                        : (fallbackInst !=
                                                                'Take as prescribed with water.'
                                                            ? fallbackInst
                                                            : ''))
                                                    .trim();
                                                if (instructions.isEmpty) {
                                                  return const SizedBox
                                                      .shrink();
                                                }
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .info_outline_rounded,
                                                        size: 14,
                                                        color: secondaryText,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          instructions,
                                                          style: TextStyle(
                                                            color:
                                                                secondaryText,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // 3. Action Dock: single primary confirmation CTA + quick snooze chips + Snooze/Skip row
                      _buildStaggeredEntry(
                        start: 0.42,
                        end: 1.0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              button: true,
                              label:
                                  'Take ${widget.medicationName} now. Confirms dose taken.',
                              child: SizedBox(
                                height: 58,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: statusColors.taken,
                                    foregroundColor: statusColors.onTaken,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  onPressed:
                                      _isProcessing ? null : _handleTaken,
                                  icon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: _isProcessing
                                        ? SizedBox(
                                            key: const ValueKey('saving'),
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: statusColors.onTaken,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.check_circle_rounded,
                                            key: ValueKey('check'),
                                            size: 24,
                                          ),
                                  ),
                                  label: Text(
                                    _isProcessing
                                        ? 'Saving Dose...'
                                        : 'Take Dose Now',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            if (remainingSnoozes > 0) ...[
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 14,
                                        color: secondaryText,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Quick snooze:',
                                        style: TextStyle(
                                          color: secondaryText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ...[5, 10, 15].map((mins) {
                                    return ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: cardColor,
                                      side: BorderSide(
                                        color:
                                            accentBlue.withValues(alpha: 0.45),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      label: Text(
                                        '+${mins}m',
                                        style: TextStyle(
                                          color: primaryText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onPressed: _isProcessing
                                          ? null
                                          : () => _executeSnooze(mins),
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],

                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(50),
                                      backgroundColor: cardColor,
                                      foregroundColor: accentBlue,
                                      side: BorderSide(
                                        color: remainingSnoozes > 0
                                            ? accentBlue
                                            : secondaryText.withValues(
                                                alpha: 0.35),
                                        width: 1.4,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed:
                                        (remainingSnoozes > 0 && !_isProcessing)
                                            ? _handleSnoozeModal
                                            : null,
                                    icon: const Icon(Icons.snooze_rounded,
                                        size: 20),
                                    label: Text(
                                      remainingSnoozes > 0
                                          ? 'Snooze ($remainingSnoozes left)'
                                          : 'Max Snoozes',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(50),
                                      backgroundColor: cardColor,
                                      foregroundColor: statusColors.missed,
                                      side: BorderSide(
                                        color: statusColors.missed
                                            .withValues(alpha: 0.6),
                                        width: 1.4,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed:
                                        _isProcessing ? null : _handleSkipModal,
                                    icon: const Icon(Icons.fast_forward_rounded,
                                        size: 20),
                                    label: const Text(
                                      'Skip Dose',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStaggeredEntry({
    required double start,
    required double end,
    required Widget child,
  }) {
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, innerChild) {
        final t = anim.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1.0 - t)),
            child: innerChild,
          ),
        );
      },
      child: child,
    );
  }
}

class _AlarmDialPainter extends CustomPainter {
  final double progress;
  final double sweepPhase;
  final bool isActive;
  final Color trackColor;
  final Color progressColor;

  const _AlarmDialPainter({
    required this.progress,
    required this.sweepPhase,
    required this.isActive,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = (math.min(size.width, size.height) / 2) - 8;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, ringRadius, trackPaint);

    if (progress > 0) {
      final arcPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arcPaint,
      );
    }

    if (isActive) {
      final outerRadius = ringRadius + 5.5;
      final baseAngle = sweepPhase * 2 * math.pi;
      final tickPaint = Paint()
        ..color = progressColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius),
        baseAngle,
        math.pi * 0.22,
        false,
        tickPaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius),
        baseAngle + math.pi,
        math.pi * 0.22,
        false,
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AlarmDialPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.sweepPhase != sweepPhase ||
        oldDelegate.isActive != isActive ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}
