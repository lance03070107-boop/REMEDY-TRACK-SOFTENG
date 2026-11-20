import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_mapper.dart';
import '../core/utils/app_logger.dart';
import '../core/utils/result.dart';
import '../core/validation/medication_validator.dart';
import '../models/intake_log.dart';
import '../models/inventory_item.dart';
import '../models/medication.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/medication_repository.dart';
import '../services/alarm_scheduler.dart';
import '../services/crashlytics_service.dart';
import '../services/local_medication_cache.dart';

class PrnValidationResult {
  final bool isSafe;
  final String? warningMessage;

  const PrnValidationResult({required this.isSafe, this.warningMessage});
}

class MedicationViewModel extends ChangeNotifier {
  final MedicationRepository _medicationRepository;
  final InventoryRepository _inventoryRepository;
  final AlarmScheduler _alarmScheduler;

  StreamSubscription<List<Medication>>? _medSubscription;
  String? _activeUserId;
  bool _isOwnProfile = true;
  List<Medication> _medications = [];
  bool _isLoading = false;
  String? _errorMessage;

  MedicationViewModel({
    required MedicationRepository medicationRepository,
    required InventoryRepository inventoryRepository,
    AlarmScheduler? alarmScheduler,
  })  : _medicationRepository = medicationRepository,
        _inventoryRepository = inventoryRepository,
        _alarmScheduler = alarmScheduler ?? AlarmScheduler();

  List<Medication> get medications => _medications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _medications.isEmpty;
  bool get hasError => _errorMessage != null;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Cancels active Firestore stream and clears in-memory state on sign-out or account switch.
  void resetState() {
    _medSubscription?.cancel();
    _medSubscription = null;
    _activeUserId = null;
    _isOwnProfile = true;
    _medications = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void retry(String userId) {
    _errorMessage = null;
    listenToMedications(
      userId,
      forceReload: true,
      isOwnProfile: _isOwnProfile,
    );
  }

  void listenToMedications(
    String userId, {
    bool forceReload = false,
    bool isOwnProfile = true,
  }) {
    if (userId.isEmpty) return;
    if (!forceReload &&
        _activeUserId == userId &&
        _isOwnProfile == isOwnProfile &&
        _medSubscription != null &&
        !_isLoading &&
        _errorMessage == null) {
      return;
    }

    if (_activeUserId != null && _activeUserId != userId) {
      _medications = [];
      _errorMessage = null;
    }

    _activeUserId = userId;
    _isOwnProfile = isOwnProfile;
    _medSubscription?.cancel();
    _setLoading(true);

    // Pre-populate from encrypted local cache only for the signed-in user's own profile
    if (_medications.isEmpty && isOwnProfile) {
      LocalMedicationCache.loadMedications().then((cached) {
        if (_medications.isEmpty && _isOwnProfile && cached.isNotEmpty) {
          _medications = cached.where((m) => m.userId == userId).toList();
          _isLoading = false;
          notifyListeners();
        }
      }).catchError((Object err, StackTrace stack) {
        AppLogger.w('LocalMedicationCache preload failed: $err',
            tag: 'MedicationVM', error: err, stackTrace: stack);
      });
    }

    _medSubscription = _medicationRepository.streamMedications(userId).listen(
      (list) {
        _medications = list;
        _isLoading = false;
        _errorMessage = null;
        if (_isOwnProfile) {
          unawaited(LocalMedicationCache.saveMedications(list));
          unawaited(_alarmScheduler.rescheduleAllAlarms(list));
        }
        notifyListeners();
      },
      onError: (Object e, StackTrace s) async {
        final mapped = ErrorMapper.map(e, s);
        if (mapped is! PermissionException && mapped is! AuthException) {
          // Offline resilience: try loading from Firestore local cache or LocalMedicationCache before showing error
          try {
            final cached = await _medicationRepository.getMedications(userId);
            _medications = cached;
            _isLoading = false;
            _errorMessage = null;
            notifyListeners();
            return;
          } catch (cacheErr, cacheStack) {
            AppLogger.w('Medication Firestore cache fallback failed: $cacheErr',
                tag: 'MedicationVM', error: cacheErr, stackTrace: cacheStack);
          }
          if (_isOwnProfile) {
            final localCached = await LocalMedicationCache.loadMedications();
            final userCached =
                localCached.where((m) => m.userId == userId).toList();
            if (userCached.isNotEmpty) {
              _medications = userCached;
              _isLoading = false;
              _errorMessage = null;
              notifyListeners();
              return;
            }
          }
        }
        _errorMessage = mapped.message;
        _isLoading = false;
        unawaited(CrashlyticsService.recordError(e, s));
        notifyListeners();
      },
    );
  }

  /// Validates and saves a [Medication] (create or update) without creating or overwriting
  /// its [InventoryItem], so stock remains managed exclusively in the Stock tab.
  Future<Result<void>> saveMedicationOnlyResult({
    required Medication medication,
    bool isEditing = false,
  }) async {
    final medCheck = MedicationValidator.validateMedicationModel(medication);
    if (medCheck.isFailure) {
      _errorMessage = medCheck.errorOrNull!.message;
      notifyListeners();
      return medCheck;
    }

    _setLoading(true);
    try {
      if (isEditing) {
        await _medicationRepository.updateMedication(medication);
      } else {
        await _medicationRepository.addMedication(medication);
      }

      final updatedList = [
        ..._medications.where((m) => m.id != medication.id),
        medication,
      ];
      _medications = updatedList;
      if (_isOwnProfile) {
        unawaited(LocalMedicationCache.saveMedications(updatedList));
        unawaited(_alarmScheduler.rescheduleAllAlarms(updatedList));
      }

      _errorMessage = null;
      return const Success(null);
    } catch (e, stack) {
      final mapped = ErrorMapper.map(e, stack);
      _errorMessage = mapped.message;
      unawaited(CrashlyticsService.recordError(e, stack));
      return Failure(mapped);
    } finally {
      _setLoading(false);
    }
  }

  /// Atomically validates and saves both a [Medication] and its [InventoryItem].
  Future<Result<void>> saveMedicationWithInventoryResult({
    required Medication medication,
    required InventoryItem inventoryItem,
  }) async {
    final medCheck = MedicationValidator.validateMedicationModel(medication);
    if (medCheck.isFailure) {
      _errorMessage = medCheck.errorOrNull!.message;
      notifyListeners();
      return medCheck;
    }
    final invCheck = MedicationValidator.validateInventoryItemModel(
      inventoryItem,
      form: medication.form,
    );
    if (invCheck.isFailure) {
      _errorMessage = invCheck.errorOrNull!.message;
      notifyListeners();
      return invCheck;
    }

    _setLoading(true);
    try {
      await _medicationRepository.saveMedicationWithInventory(
        medication: medication,
        inventoryItem: inventoryItem,
      );
      if (_medicationRepository is! FirebaseMedicationRepository) {
        await _inventoryRepository.setInventoryItem(inventoryItem);
      }

      final updatedList = [
        ..._medications.where((m) => m.id != medication.id),
        medication,
      ];
      _medications = updatedList;
      if (_isOwnProfile) {
        unawaited(LocalMedicationCache.saveMedications(updatedList));
        unawaited(_alarmScheduler.rescheduleAllAlarms(updatedList));
      }

      _errorMessage = null;
      return const Success(null);
    } catch (e, stack) {
      final mapped = ErrorMapper.map(e, stack);
      _errorMessage = mapped.message;
      unawaited(CrashlyticsService.recordError(e, stack));
      return Failure(mapped);
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addMedicationWithInventory({
    required Medication medication,
    required double initialStock,
    required double lowStockThreshold,
    required String unit,
  }) async {
    final inventoryItem = InventoryItem(
      id: 'inv_${medication.id}',
      userId: medication.userId,
      medicationId: medication.id,
      currentStock: initialStock,
      unit: unit,
      lowStockThreshold: lowStockThreshold,
      refillQuantity: initialStock > 0 ? initialStock : 30.0,
      lastRefillDate: DateTime.now(),
      notes: medication.name,
    );
    final result = await saveMedicationWithInventoryResult(
      medication: medication,
      inventoryItem: inventoryItem,
    );
    return result.isSuccess;
  }

  Future<bool> updateMedication(Medication medication) async {
    final medCheck = MedicationValidator.validateMedicationModel(medication);
    if (medCheck.isFailure) {
      _errorMessage = medCheck.errorOrNull!.message;
      notifyListeners();
      return false;
    }
    _setLoading(true);
    try {
      await _medicationRepository.updateMedication(medication);
      final updatedList = _medications
          .map((m) => m.id == medication.id ? medication : m)
          .toList();
      _medications = updatedList;
      if (_isOwnProfile) {
        unawaited(LocalMedicationCache.saveMedications(updatedList));
        unawaited(_alarmScheduler.rescheduleAllAlarms(updatedList));
      }
      _errorMessage = null;
      return true;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteMedication(String id) async {
    _setLoading(true);
    try {
      await _medicationRepository.deleteMedication(id);
      try {
        await _inventoryRepository.deleteInventoryItem('inv_$id');
      } catch (e, s) {
        AppLogger.d(
          'Optional inventory cleanup skipped or not found for inv_$id: $e',
          tag: 'MedicationViewModel',
        );
        unawaited(CrashlyticsService.recordError(e, s));
      }
      final remaining = _medications.where((m) => m.id != id).toList();
      _medications = remaining;
      if (_isOwnProfile) {
        unawaited(LocalMedicationCache.saveMedications(remaining));
        unawaited(_alarmScheduler.rescheduleAllAlarms(remaining));
      }
      _errorMessage = null;
      return true;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Applies a newly selected global default alarm tone across active medications
  /// and reschedules upcoming dose alarms.
  Future<void> applyGlobalDefaultAlarmTone({
    required String soundId,
    String? customSoundPath,
  }) async {
    final updatedList = <Medication>[];
    for (final med in _medications) {
      final updatedMed = med.copyWith(
        alarmSoundId: soundId,
        customSoundPath: customSoundPath,
        schedule: med.schedule?.copyWith(
          alarmSoundId: soundId,
          customSoundPath: customSoundPath,
        ),
        updatedAt: DateTime.now(),
      );
      updatedList.add(updatedMed);
      unawaited(
        _medicationRepository.updateMedication(updatedMed).catchError(
          (Object err, StackTrace stack) {
            AppLogger.w(
                'Failed syncing updated alarm tone for ${updatedMed.id}: $err',
                tag: 'MedicationVM',
                error: err,
                stackTrace: stack);
          },
        ),
      );
    }
    _medications = updatedList;
    if (_isOwnProfile) {
      unawaited(LocalMedicationCache.saveMedications(updatedList));
      await _alarmScheduler.rescheduleAllAlarms(updatedList);
    }
    notifyListeners();
  }

  PrnValidationResult validatePrnIntake(
    Medication medication,
    List<IntakeLog> todayLogs,
  ) {
    if (!medication.isPrn) {
      return const PrnValidationResult(isSafe: true);
    }

    final medLogs = todayLogs
        .where((l) =>
            l.medicationId == medication.id &&
            (l.status == DoseStatus.taken || l.status == DoseStatus.late) &&
            l.recordedTime != null)
        .toList()
      ..sort((a, b) => b.recordedTime!.compareTo(a.recordedTime!));

    final now = DateTime.now();

    if (medication.minIntervalHours != null && medLogs.isNotEmpty) {
      final lastTaken = medLogs.first.recordedTime!;
      final diff = now.difference(lastTaken);
      final minDuration = Duration(hours: medication.minIntervalHours!);

      if (diff < minDuration) {
        final remainingSeconds = (minDuration - diff).inSeconds;
        final remainingMinutes = remainingSeconds <= 0
            ? 1
            : ((remainingSeconds + 59) ~/ 60);
        return PrnValidationResult(
          isSafe: false,
          warningMessage:
              'It is too soon for another dose. Please wait $remainingMinutes more ${remainingMinutes == 1 ? 'minute' : 'minutes'} before taking this medicine again.',
        );
      }
    }

    if (medication.dailyMaxDose != null) {
      final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));
      final totalTakenLast24h = medLogs
          .where((l) => l.recordedTime!.isAfter(twentyFourHoursAgo))
          .fold<double>(0.0, (sum, item) => sum + item.doseAmount);

      if (totalDoseWouldExceedDailyMax(
        takenLast24h: totalTakenLast24h,
        nextDose: medication.doseAmount,
        dailyMaxDose: medication.dailyMaxDose!,
      )) {
        return PrnValidationResult(
          isSafe: false,
          warningMessage:
              'Taking this dose would go over your 24-hour safe limit (${medication.dailyMaxDose}). Ask your doctor or pharmacist before taking more.',
        );
      }
    }

    return const PrnValidationResult(isSafe: true);
  }

  static bool totalDoseWouldExceedDailyMax({
    required double takenLast24h,
    required double nextDose,
    required double dailyMaxDose,
  }) {
    return (takenLast24h + nextDose) > (dailyMaxDose + 1e-6);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _medSubscription?.cancel();
    super.dispose();
  }
}
