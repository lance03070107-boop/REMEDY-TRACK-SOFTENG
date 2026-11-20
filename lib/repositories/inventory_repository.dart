import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_mapper.dart';
import '../core/utils/app_logger.dart';
import '../core/validation/medication_validator.dart';
import '../models/inventory_item.dart';

abstract class InventoryRepository {
  Stream<List<InventoryItem>> streamInventory(String userId);
  Future<List<InventoryItem>> getInventory(String userId);
  Future<InventoryItem?> getInventoryByMedicationId(
      String userId, String medicationId);
  Future<void> setInventoryItem(InventoryItem item);
  Future<void> refillStock(
    String itemId,
    double additionalAmount, {
    String? requestId,
  });
  Future<void> deleteInventoryItem(String itemId);
}

class FirebaseInventoryRepository implements InventoryRepository {
  final FirebaseFirestore _firestore;
  final bool Function() _isOnline;
  final Set<String> _appliedRefillRequestIds = <String>{};

  FirebaseInventoryRepository({
    FirebaseFirestore? firestore,
    bool Function()? isOnline,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _isOnline = isOnline ?? _alwaysOnline;

  static bool _alwaysOnline() => true;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(AppConstants.colInventory);

  @override
  Stream<List<InventoryItem>> streamInventory(String userId) {
    return _collection
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => InventoryItem.fromJson(doc.data()))
          .toList();
    });
  }

  static const Duration _readTimeout = Duration(seconds: 8);
  static const Duration _writeTimeout = Duration(seconds: 12);
  static const Duration _offlineWriteTimeout = Duration(milliseconds: 1500);

  Future<void> _commitWrite(Future<void> writeFuture) async {
    final effectiveTimeout =
        _isOnline() ? _writeTimeout : _offlineWriteTimeout;
    // Offline persistence on mobile and web commits locally and queues remote sync
    await writeFuture.timeout(effectiveTimeout, onTimeout: () {
      return;
    });
  }

  bool _shouldFallbackToCache(Object error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      return code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code == 'network-request-failed' ||
          code == 'failed-precondition' ||
          code == 'aborted' ||
          code == 'cancelled';
    }
    return false;
  }

  @override
  Future<List<InventoryItem>> getInventory(String userId) async {
    try {
      QuerySnapshot<Map<String, dynamic>>? snapshot;
      try {
        snapshot = await _collection
            .where('userId', isEqualTo: userId)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(_readTimeout);
      } catch (e) {
        if (!_shouldFallbackToCache(e)) rethrow;
        AppLogger.d('getInventory falling back to cache: $e',
            tag: 'InventoryRepository');
        snapshot = await _collection
            .where('userId', isEqualTo: userId)
            .get(const GetOptions(source: Source.cache));
      }
      return snapshot.docs
          .map((doc) => InventoryItem.fromJson(doc.data()))
          .toList();
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<InventoryItem?> getInventoryByMedicationId(
      String userId, String medicationId) async {
    try {
      QuerySnapshot<Map<String, dynamic>>? snapshot;
      try {
        snapshot = await _collection
            .where('userId', isEqualTo: userId)
            .where('medicationId', isEqualTo: medicationId)
            .limit(1)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(_readTimeout);
      } catch (e) {
        if (!_shouldFallbackToCache(e)) rethrow;
        AppLogger.d('getInventoryByMedicationId falling back to cache: $e',
            tag: 'InventoryRepository');
        snapshot = await _collection
            .where('userId', isEqualTo: userId)
            .where('medicationId', isEqualTo: medicationId)
            .limit(1)
            .get(const GetOptions(source: Source.cache));
      }
      if (snapshot.docs.isEmpty) return null;
      return InventoryItem.fromJson(snapshot.docs.first.data());
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> setInventoryItem(InventoryItem item) async {
    final validation = MedicationValidator.validateInventoryItemModel(item);
    if (validation.isFailure) {
      throw validation.errorOrNull!;
    }
    try {
      await _commitWrite(
        _collection.doc(item.id).set(item.toJson(), SetOptions(merge: true)),
      );
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> refillStock(
    String itemId,
    double additionalAmount, {
    String? requestId,
  }) async {
    if (requestId != null &&
        requestId.isNotEmpty &&
        _appliedRefillRequestIds.contains(requestId)) {
      AppLogger.d('Skipping duplicate refill request $requestId',
          tag: 'InventoryRepository');
      return;
    }
    if (additionalAmount.isNaN ||
        additionalAmount.isInfinite ||
        additionalAmount <= 0 ||
        additionalAmount > AppConstants.maxStock) {
      throw ValidationException(
        'Refill amount must be greater than 0 and at most ${AppConstants.maxStock.toInt()}.',
      );
    }

    try {
      final docRef = _collection.doc(itemId);
      DocumentSnapshot<Map<String, dynamic>>? snapshot;
      if (!_isOnline()) {
        snapshot = await docRef.get(const GetOptions(source: Source.cache));
      } else {
        try {
          snapshot = await docRef
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(_readTimeout);
        } catch (e) {
          if (!_shouldFallbackToCache(e)) rethrow;
          AppLogger.d('refillStock falling back to cache: $e',
              tag: 'InventoryRepository');
          snapshot = await docRef.get(const GetOptions(source: Source.cache));
        }
      }

      if (!snapshot.exists || snapshot.data() == null) {
        throw const InventoryException(
          'Inventory record not found. Set up initial stock first.',
        );
      }

      final existingData = snapshot.data()!;
      final currentStock =
          (existingData['currentStock'] as num?)?.toDouble() ?? 0.0;
      if (currentStock + additionalAmount > AppConstants.maxStock + 1e-6) {
        throw ValidationException(
          'Total stock cannot exceed ${AppConstants.maxStock.toInt()} units.',
        );
      }

      final newStock = (currentStock + additionalAmount)
          .clamp(AppConstants.minStock, AppConstants.maxStock);

      await _commitWrite(
        docRef.update({
          'currentStock': newStock,
          'lastRefillDate': DateTime.now().toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
      if (requestId != null && requestId.isNotEmpty) {
        _appliedRefillRequestIds.add(requestId);
      }
    } on AppException {
      rethrow;
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> deleteInventoryItem(String itemId) async {
    try {
      await _commitWrite(_collection.doc(itemId).delete());
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }
}
