import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/error_mapper.dart';
import '../core/utils/app_logger.dart';
import '../core/validation/medication_validator.dart';
import '../models/inventory_item.dart';
import '../models/medication.dart';

abstract class MedicationRepository {
  Stream<List<Medication>> streamMedications(String userId);
  Future<List<Medication>> getMedications(String userId);
  Future<Medication?> getMedicationById(String id);
  Future<void> addMedication(Medication medication);
  Future<void> updateMedication(Medication medication);
  Future<void> saveMedicationWithInventory({
    required Medication medication,
    required InventoryItem inventoryItem,
  });
  Future<void> deleteMedication(String id);
}

class FirebaseMedicationRepository implements MedicationRepository {
  final FirebaseFirestore _firestore;
  final bool Function() _isOnline;

  FirebaseMedicationRepository({
    FirebaseFirestore? firestore,
    bool Function()? isOnline,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _isOnline = isOnline ?? _alwaysOnline;

  static bool _alwaysOnline() => true;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(AppConstants.colMedications);

  CollectionReference<Map<String, dynamic>> get _inventoryCollection =>
      _firestore.collection(AppConstants.colInventory);

  @override
  Stream<List<Medication>> streamMedications(String userId) {
    return _collection
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Medication.fromJson(doc.data()))
          .toList();
    });
  }

  static const Duration _readTimeout = Duration(seconds: 8);
  static const Duration _writeTimeout = Duration(seconds: 12);
  static const Duration _offlineWriteTimeout = Duration(milliseconds: 1500);

  Future<void> _commitWrite(Future<void> writeFuture) async {
    final effectiveTimeout =
        _isOnline() ? _writeTimeout : _offlineWriteTimeout;
    // Offline persistence on mobile and web commits to local cache and queues remote sync
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
  Future<List<Medication>> getMedications(String userId) async {
    try {
      QuerySnapshot<Map<String, dynamic>>? snapshot;
      try {
        snapshot = await _collection
            .where('userId', isEqualTo: userId)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(_readTimeout);
      } catch (e) {
        if (!_shouldFallbackToCache(e)) rethrow;
        AppLogger.d('getMedications falling back to cache: $e',
            tag: 'MedicationRepository');
        snapshot = await _collection
            .where('userId', isEqualTo: userId)
            .get(const GetOptions(source: Source.cache));
      }
      return snapshot.docs
          .map((doc) => Medication.fromJson(doc.data()))
          .toList();
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<Medication?> getMedicationById(String id) async {
    try {
      final docRef = _collection.doc(id);
      DocumentSnapshot<Map<String, dynamic>>? doc;
      try {
        doc = await docRef
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(_readTimeout);
      } catch (e) {
        if (!_shouldFallbackToCache(e)) rethrow;
        AppLogger.d('getMedicationById falling back to cache: $e',
            tag: 'MedicationRepository');
        doc = await docRef.get(const GetOptions(source: Source.cache));
      }
      if (!doc.exists || doc.data() == null) return null;
      return Medication.fromJson(doc.data()!);
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> addMedication(Medication medication) async {
    final validation = MedicationValidator.validateMedicationModel(medication);
    if (validation.isFailure) {
      throw validation.errorOrNull!;
    }
    try {
      await _commitWrite(
        _collection.doc(medication.id).set(medication.toJson()),
      );
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> updateMedication(Medication medication) async {
    final validation = MedicationValidator.validateMedicationModel(medication);
    if (validation.isFailure) {
      throw validation.errorOrNull!;
    }
    try {
      await _commitWrite(
        _collection
            .doc(medication.id)
            .set(medication.toJson(), SetOptions(merge: true)),
      );
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> saveMedicationWithInventory({
    required Medication medication,
    required InventoryItem inventoryItem,
  }) async {
    final medValidation =
        MedicationValidator.validateMedicationModel(medication);
    if (medValidation.isFailure) {
      throw medValidation.errorOrNull!;
    }
    final invValidation = MedicationValidator.validateInventoryItemModel(
      inventoryItem,
      form: medication.form,
    );
    if (invValidation.isFailure) {
      throw invValidation.errorOrNull!;
    }

    try {
      final batch = _firestore.batch();
      batch.set(
        _collection.doc(medication.id),
        medication.toJson(),
        SetOptions(merge: true),
      );
      batch.set(
        _inventoryCollection.doc(inventoryItem.id),
        inventoryItem.toJson(),
        SetOptions(merge: true),
      );
      await _commitWrite(batch.commit());
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> deleteMedication(String id) async {
    try {
      final batch = _firestore.batch();
      batch.delete(_collection.doc(id));
      batch.delete(_inventoryCollection.doc('inv_$id'));
      await _commitWrite(batch.commit());
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }
}
