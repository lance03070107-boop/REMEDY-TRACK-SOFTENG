import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_mapper.dart';
import '../core/utils/app_logger.dart';
import '../models/intake_log.dart';
import '../services/crashlytics_service.dart';

abstract class IntakeRepository {
  Stream<List<IntakeLog>> streamIntakeLogs(String userId, {int limit = 2000});
  Future<List<IntakeLog>> getIntakeLogs(String userId, {int limit = 2000});
  Future<List<IntakeLog>> getLogsForDateRange(
      String userId, DateTime start, DateTime end);
  Future<void> recordIntakeAtomic({
    required IntakeLog intakeLog,
    required bool decrementInventory,
  });
  Future<void> undoTakeDoseAtomic({
    required IntakeLog intakeLog,
    required bool restoreInventory,
  });
  Future<void> updateLogStatus(String logId, DoseStatus status);
  Future<void> deleteIntakeLog(String logId);
}

class FirebaseIntakeRepository implements IntakeRepository {
  final FirebaseFirestore _firestore;
  final bool Function() _isOnline;

  FirebaseIntakeRepository({
    FirebaseFirestore? firestore,
    bool Function()? isOnline,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _isOnline = isOnline ?? _alwaysOnline;

  static bool _alwaysOnline() => true;

  CollectionReference<Map<String, dynamic>> get _logsCollection =>
      _firestore.collection(AppConstants.colIntakeLogs);

  CollectionReference<Map<String, dynamic>> get _inventoryCollection =>
      _firestore.collection(AppConstants.colInventory);

  List<IntakeLog> _parseDocsSafely(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final parsed = <IntakeLog>[];
    for (final doc in docs) {
      try {
        parsed.add(IntakeLog.fromJson(doc.data()));
      } catch (e, stack) {
        AppLogger.w(
          'Skipping malformed intake_log document ${doc.id}: $e',
          tag: 'IntakeRepository',
          error: e,
          stackTrace: stack,
        );
        unawaited(CrashlyticsService.recordError(
          e,
          stack,
          reason: 'Malformed intake_log skipped: ${doc.id}',
        ));
      }
    }
    return parsed;
  }

  @override
  Stream<List<IntakeLog>> streamIntakeLogs(String userId, {int limit = 2000}) {
    return _logsCollection
        .where('userId', isEqualTo: userId)
        .orderBy('scheduledTime', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => _parseDocsSafely(snapshot.docs));
  }

  static const Duration _readTimeout = Duration(seconds: 8);
  static const Duration _transactionTimeout = Duration(seconds: 6);
  static const Duration _writeTimeout = Duration(seconds: 12);
  static const Duration _offlineWriteTimeout = Duration(milliseconds: 1500);

  Future<void> _commitWrite(
    Future<void> writeFuture, {
    bool offlineFast = false,
  }) async {
    final effectiveTimeout =
        (offlineFast || !_isOnline()) ? _offlineWriteTimeout : _writeTimeout;
    // Firestore applies local writes synchronously to cache before committing remotely.
    // On both mobile and web, treat a commit timeout as locally queued for sync.
    await writeFuture.timeout(effectiveTimeout, onTimeout: () {
      return;
    });
  }

  /// Tracks log IDs whose inventory was already decremented in this session to prevent
  /// duplicate stock deduction if a slow transaction times out and triggers the cache fallback.
  final Set<String> _decrementedLogIds = <String>{};

  /// Tracks log IDs currently executing an online transaction with inventory decrement
  /// so concurrent/fallback invocations do not double-deduct.
  final Set<String> _pendingDecrementLogIds = <String>{};

  @override
  Future<List<IntakeLog>> getIntakeLogs(String userId,
      {int limit = 2000}) async {
    try {
      QuerySnapshot<Map<String, dynamic>>? snapshot;
      if (!_isOnline()) {
        snapshot = await _logsCollection
            .where('userId', isEqualTo: userId)
            .orderBy('scheduledTime', descending: true)
            .limit(limit)
            .get(const GetOptions(source: Source.cache));
      } else {
        try {
          snapshot = await _logsCollection
              .where('userId', isEqualTo: userId)
              .orderBy('scheduledTime', descending: true)
              .limit(limit)
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(_readTimeout);
        } catch (e) {
          if (!_isOfflineError(e)) rethrow;
          AppLogger.d('getIntakeLogs falling back to cache: $e',
              tag: 'IntakeRepository');
          snapshot = await _logsCollection
              .where('userId', isEqualTo: userId)
              .orderBy('scheduledTime', descending: true)
              .limit(limit)
              .get(const GetOptions(source: Source.cache));
        }
      }
      return _parseDocsSafely(snapshot.docs);
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<List<IntakeLog>> getLogsForDateRange(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      QuerySnapshot<Map<String, dynamic>>? snapshot;
      if (!_isOnline()) {
        snapshot = await _logsCollection
            .where('userId', isEqualTo: userId)
            .where('scheduledTime',
                isGreaterThanOrEqualTo: start.toUtc().toIso8601String())
            .where('scheduledTime',
                isLessThanOrEqualTo: end.toUtc().toIso8601String())
            .get(const GetOptions(source: Source.cache));
      } else {
        try {
          snapshot = await _logsCollection
              .where('userId', isEqualTo: userId)
              .where('scheduledTime',
                  isGreaterThanOrEqualTo: start.toUtc().toIso8601String())
              .where('scheduledTime',
                  isLessThanOrEqualTo: end.toUtc().toIso8601String())
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(_readTimeout);
        } catch (e) {
          if (!_isOfflineError(e)) rethrow;
          AppLogger.d('getLogsForDateRange falling back to cache: $e',
              tag: 'IntakeRepository');
          snapshot = await _logsCollection
              .where('userId', isEqualTo: userId)
              .where('scheduledTime',
                  isGreaterThanOrEqualTo: start.toUtc().toIso8601String())
              .where('scheduledTime',
                  isLessThanOrEqualTo: end.toUtc().toIso8601String())
              .get(const GetOptions(source: Source.cache));
        }
      }
      return _parseDocsSafely(snapshot.docs);
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  bool _isOfflineError(Object error) {
    if (error is TimeoutException || error is NetworkException) return true;
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      return code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code == 'network-request-failed' ||
          code == 'failed-precondition' ||
          code == 'cancelled' ||
          code == 'aborted';
    }
    return false;
  }

  bool _shouldBlockTransition(
      DoseStatus? existingStatus, DoseStatus nextStatus) {
    if (existingStatus == DoseStatus.taken ||
        existingStatus == DoseStatus.late) {
      if (nextStatus == DoseStatus.missed ||
          nextStatus == DoseStatus.skipped ||
          nextStatus == DoseStatus.snoozed) {
        return true;
      }
    }
    if (existingStatus == DoseStatus.skipped) {
      if (nextStatus == DoseStatus.missed || nextStatus == DoseStatus.snoozed) {
        return true;
      }
    }
    return false;
  }

  /// Atomically writes intake log and decrements existing inventory in a single ACID transaction
  /// to eliminate race conditions, double deduction, or desynchronized stock counts.
  /// When offline, immediately uses the cache-backed WriteBatch path without waiting for a transaction timeout.
  @override
  Future<void> recordIntakeAtomic({
    required IntakeLog intakeLog,
    required bool decrementInventory,
  }) async {
    if (_isOnline()) {
      bool didDecrementInTx = false;
      final bool trackPending =
          decrementInventory && !_decrementedLogIds.contains(intakeLog.id);
      if (trackPending) {
        _pendingDecrementLogIds.add(intakeLog.id);
      }
      try {
        await _firestore.runTransaction((transaction) async {
          didDecrementInTx = false;
          final logDocRef = _logsCollection.doc(intakeLog.id);
          final existingLogDoc = await transaction.get(logDocRef);

          final existingStatusStr = existingLogDoc.data()?['status'] as String?;
          final existingStatus = existingStatusStr != null
              ? DoseStatus.values.firstWhere(
                  (s) => s.name == existingStatusStr,
                  orElse: () => DoseStatus.pending,
                )
              : null;

          final bool alreadyTaken = existingLogDoc.exists &&
              (existingStatus == DoseStatus.taken ||
                  existingStatus == DoseStatus.late);

          // B1: Dose State Machine guard:
          if (_shouldBlockTransition(existingStatus, intakeLog.status)) {
            return;
          }

          // B2: Transactional Inventory Read & Partial Update (never overwrite unrelated fields):
          if (decrementInventory &&
              !alreadyTaken &&
              !_decrementedLogIds.contains(intakeLog.id) &&
              intakeLog.medicationId.isNotEmpty) {
            final invRef =
                _inventoryCollection.doc('inv_${intakeLog.medicationId}');
            final invDoc = await transaction.get(invRef);

            if (invDoc.exists && invDoc.data() != null) {
              final invData = invDoc.data()!;
              final currentStock =
                  (invData['currentStock'] as num?)?.toDouble() ?? 0.0;
              final updatedStock = (currentStock - intakeLog.doseAmount)
                  .clamp(AppConstants.minStock, AppConstants.maxStock);

              transaction.update(invRef, {
                'currentStock': updatedStock,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              didDecrementInTx = true;
            }
          }

          final logPayload = Map<String, dynamic>.from(intakeLog.toJson())
            ..['updatedAt'] = FieldValue.serverTimestamp();
          transaction.set(logDocRef, logPayload, SetOptions(merge: true));
        }).timeout(_transactionTimeout);

        // Only mark decremented AFTER the transaction commit succeeds
        if (didDecrementInTx) {
          _decrementedLogIds.add(intakeLog.id);
        }
        _pendingDecrementLogIds.remove(intakeLog.id);
        return;
      } catch (e, stack) {
        final bool wasTimeout = e is TimeoutException;
        if (!wasTimeout) {
          _pendingDecrementLogIds.remove(intakeLog.id);
        }
        if (!_isOfflineError(e)) {
          _pendingDecrementLogIds.remove(intakeLog.id);
          throw ErrorMapper.map(e, stack);
        }
        await _recordIntakeOfflineFallback(
          intakeLog: intakeLog,
          decrementInventory: decrementInventory,
          originalError: e,
          originalStack: stack,
          skipDecrementIfPending: wasTimeout && didDecrementInTx,
        );
        return;
      }
    }

    // Device is known offline -> bypass transaction entirely and write immediately to cache/queue
    await _recordIntakeOfflineFallback(
      intakeLog: intakeLog,
      decrementInventory: decrementInventory,
    );
  }

  Future<void> _recordIntakeOfflineFallback({
    required IntakeLog intakeLog,
    required bool decrementInventory,
    Object? originalError,
    StackTrace? originalStack,
    bool skipDecrementIfPending = false,
  }) async {
    try {
      final logDocRef = _logsCollection.doc(intakeLog.id);
      DocumentSnapshot<Map<String, dynamic>>? cachedLog;
      try {
        cachedLog =
            await logDocRef.get(const GetOptions(source: Source.cache));
      } catch (cacheErr) {
        AppLogger.d('recordIntakeAtomic log cache miss: $cacheErr',
            tag: 'IntakeRepository');
        cachedLog = null;
      }

      final existingStatusStr = cachedLog?.data()?['status'] as String?;
      final existingStatus = existingStatusStr != null
          ? DoseStatus.values.firstWhere(
              (s) => s.name == existingStatusStr,
              orElse: () => DoseStatus.pending,
            )
          : null;

      if (_shouldBlockTransition(existingStatus, intakeLog.status)) {
        return;
      }

      final bool alreadyTaken = (cachedLog?.exists ?? false) &&
          (existingStatus == DoseStatus.taken ||
              existingStatus == DoseStatus.late);

      final batch = _firestore.batch();
      final logPayload = Map<String, dynamic>.from(intakeLog.toJson())
        ..['updatedAt'] = FieldValue.serverTimestamp();
      batch.set(logDocRef, logPayload, SetOptions(merge: true));

      bool didDecrementInBatch = false;
      final bool blockedByPending =
          skipDecrementIfPending && _pendingDecrementLogIds.contains(intakeLog.id);
      if (decrementInventory &&
          !alreadyTaken &&
          !blockedByPending &&
          !_decrementedLogIds.contains(intakeLog.id) &&
          intakeLog.medicationId.isNotEmpty) {
        final invRef =
            _inventoryCollection.doc('inv_${intakeLog.medicationId}');
        DocumentSnapshot<Map<String, dynamic>>? cachedInv;
        try {
          cachedInv = await invRef.get(const GetOptions(source: Source.cache));
        } catch (cacheErr) {
          AppLogger.d('recordIntakeAtomic inventory cache miss: $cacheErr',
              tag: 'IntakeRepository');
          cachedInv = null;
        }

        if (cachedInv != null && cachedInv.exists && cachedInv.data() != null) {
          final invData = cachedInv.data()!;
          final currentStock =
              (invData['currentStock'] as num?)?.toDouble() ?? 0.0;
          final updatedStock = (currentStock - intakeLog.doseAmount)
              .clamp(AppConstants.minStock, AppConstants.maxStock);
          batch.update(invRef, {
            'currentStock': updatedStock,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          didDecrementInBatch = true;
        }
      }

      await _commitWrite(batch.commit(), offlineFast: true);
      if (didDecrementInBatch) {
        _decrementedLogIds.add(intakeLog.id);
      }
      _pendingDecrementLogIds.remove(intakeLog.id);
    } catch (fallbackErr, fallbackStack) {
      _pendingDecrementLogIds.remove(intakeLog.id);
      unawaited(CrashlyticsService.recordError(fallbackErr, fallbackStack));
      throw ErrorMapper.map(
        originalError ?? fallbackErr,
        originalStack ?? fallbackStack,
      );
    }
  }

  DoseStatus _revertedStatusForUndo(IntakeLog intakeLog) {
    final now = DateTime.now();
    return now.difference(intakeLog.scheduledTime).inMinutes >
            AppConstants.lateGracePeriodMinutes
        ? DoseStatus.missed
        : DoseStatus.pending;
  }

  /// Atomically reverts a taken intake log back to pending/missed and restores inventory stock.
  /// Reverts status rather than deleting so server-reconciled documents are not resurrected as missed.
  @override
  Future<void> undoTakeDoseAtomic({
    required IntakeLog intakeLog,
    required bool restoreInventory,
  }) async {
    final revertedStatus = _revertedStatusForUndo(intakeLog);
    final revertedPayload = Map<String, dynamic>.from(
      intakeLog
          .copyWith(
            status: revertedStatus,
            notes: 'Undone by user',
          )
          .toJson(),
    )
      ..['recordedTime'] = null
      ..['updatedAt'] = FieldValue.serverTimestamp();

    if (_isOnline()) {
      try {
        await _firestore.runTransaction((transaction) async {
          final logDocRef = _logsCollection.doc(intakeLog.id);
          final existingDoc = await transaction.get(logDocRef);

          final existingStatus = existingDoc.data()?['status'] as String?;
          final wasActuallyTaken = existingDoc.exists &&
              (existingStatus == DoseStatus.taken.name ||
                  existingStatus == DoseStatus.late.name);

          // B3: Inventory Inflation Guard:
          if (restoreInventory &&
              wasActuallyTaken &&
              intakeLog.medicationId.isNotEmpty) {
            final invRef =
                _inventoryCollection.doc('inv_${intakeLog.medicationId}');
            final invDoc = await transaction.get(invRef);

            if (invDoc.exists && invDoc.data() != null) {
              final invData = invDoc.data()!;
              final currentStock =
                  (invData['currentStock'] as num?)?.toDouble() ?? 0.0;
              final updatedStock = (currentStock + intakeLog.doseAmount)
                  .clamp(AppConstants.minStock, AppConstants.maxStock);

              transaction.update(invRef, {
                'currentStock': updatedStock,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          }

          if (existingDoc.exists) {
            transaction.set(logDocRef, revertedPayload, SetOptions(merge: true));
          }
        }).timeout(_transactionTimeout);

        _decrementedLogIds.remove(intakeLog.id);
        _pendingDecrementLogIds.remove(intakeLog.id);
        return;
      } catch (e, stack) {
        if (!_isOfflineError(e)) {
          throw ErrorMapper.map(e, stack);
        }
        await _undoTakeDoseOfflineFallback(
          intakeLog: intakeLog,
          restoreInventory: restoreInventory,
          revertedPayload: revertedPayload,
          originalError: e,
          originalStack: stack,
        );
        return;
      }
    }

    await _undoTakeDoseOfflineFallback(
      intakeLog: intakeLog,
      restoreInventory: restoreInventory,
      revertedPayload: revertedPayload,
    );
  }

  Future<void> _undoTakeDoseOfflineFallback({
    required IntakeLog intakeLog,
    required bool restoreInventory,
    required Map<String, dynamic> revertedPayload,
    Object? originalError,
    StackTrace? originalStack,
  }) async {
    try {
      final logDocRef = _logsCollection.doc(intakeLog.id);
      DocumentSnapshot<Map<String, dynamic>>? cachedDoc;
      try {
        cachedDoc = await logDocRef.get(const GetOptions(source: Source.cache));
      } catch (cacheErr) {
        AppLogger.d('undoTakeDoseAtomic log cache miss: $cacheErr',
            tag: 'IntakeRepository');
        cachedDoc = null;
      }

      // Even if the log is not in cache yet, honor the caller's known taken/late log status
      // so offline undo never silently no-ops.
      final String? existingStatus = (cachedDoc != null && cachedDoc.exists)
          ? (cachedDoc.data()?['status'] as String?)
          : intakeLog.status.name;
      final wasActuallyTaken = existingStatus == DoseStatus.taken.name ||
          existingStatus == DoseStatus.late.name;

      final batch = _firestore.batch();
      if (restoreInventory &&
          wasActuallyTaken &&
          intakeLog.medicationId.isNotEmpty) {
        final invRef =
            _inventoryCollection.doc('inv_${intakeLog.medicationId}');
        DocumentSnapshot<Map<String, dynamic>>? cachedInv;
        try {
          cachedInv = await invRef.get(const GetOptions(source: Source.cache));
        } catch (cacheErr) {
          AppLogger.d('undoTakeDoseAtomic inventory cache miss: $cacheErr',
              tag: 'IntakeRepository');
          cachedInv = null;
        }
        if (cachedInv != null && cachedInv.exists && cachedInv.data() != null) {
          final invData = cachedInv.data()!;
          final currentStock =
              (invData['currentStock'] as num?)?.toDouble() ?? 0.0;
          final updatedStock = (currentStock + intakeLog.doseAmount)
              .clamp(AppConstants.minStock, AppConstants.maxStock);
          batch.update(invRef, {
            'currentStock': updatedStock,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      batch.set(logDocRef, revertedPayload, SetOptions(merge: true));
      await _commitWrite(batch.commit(), offlineFast: true);
      _decrementedLogIds.remove(intakeLog.id);
      _pendingDecrementLogIds.remove(intakeLog.id);
    } catch (fallbackErr, fallbackStack) {
      unawaited(CrashlyticsService.recordError(fallbackErr, fallbackStack));
      throw ErrorMapper.map(
        originalError ?? fallbackErr,
        originalStack ?? fallbackStack,
      );
    }
  }

  @override
  Future<void> updateLogStatus(String logId, DoseStatus status) async {
    try {
      await _commitWrite(
        _logsCollection.doc(logId).update({
          'status': status.name,
          'recordedTime': DateTime.now().toUtc().toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> deleteIntakeLog(String logId) async {
    try {
      await _commitWrite(_logsCollection.doc(logId).delete());
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }
}
