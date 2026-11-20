import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/constants/app_constants.dart';
import '../core/errors/error_mapper.dart';
import '../core/utils/app_logger.dart';
import '../models/user_profile.dart';
import '../services/crashlytics_service.dart';

abstract class UserRepository {
  Future<UserProfile?> getUserProfile(String userId);
  Future<void> saveUserProfile(UserProfile profile);
  Future<void> deleteAllUserData(String userId); // RA 10173 Right to Erasure
}

class FirebaseUserRepository implements UserRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _functions;

  FirebaseUserRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? _resolveFunctions();

  static FirebaseFunctions? _resolveFunctions() {
    try {
      if (FirebaseFirestore.instance.app.options.projectId.isNotEmpty) {
        return FirebaseFunctions.instanceFor(
          region: AppConstants.cloudFunctionsRegion,
        );
      }
    } catch (e, stack) {
      AppLogger.w('UserRepository: Cloud Functions unavailable: $e',
          tag: 'UserRepository');
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'UserRepository._resolveFunctions'));
    }
    return null;
  }

  static const Duration _readTimeout = Duration(seconds: 8);
  static const Duration _writeTimeout = Duration(seconds: 12);

  Future<void> _commitWrite(Future<void> writeFuture) async {
    if (kIsWeb) {
      await writeFuture.timeout(_writeTimeout);
    } else {
      await writeFuture.timeout(_writeTimeout, onTimeout: () {
        // Offline persistence on mobile commits to local cache and queues sync
        return;
      });
    }
  }

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      final docRef = _firestore.collection(AppConstants.colUsers).doc(userId);
      DocumentSnapshot<Map<String, dynamic>>? doc;
      try {
        doc = await docRef
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(_readTimeout);
      } catch (e) {
        AppLogger.d(
            'UserRepository.getUserProfile falling back to local cache: $e',
            tag: 'UserRepository');
        try {
          doc = await docRef.get(const GetOptions(source: Source.cache));
        } catch (cacheErr, cacheStack) {
          AppLogger.w(
              'UserRepository.getUserProfile cache miss/error: $cacheErr',
              tag: 'UserRepository');
          unawaited(CrashlyticsService.recordError(cacheErr, cacheStack,
              reason: 'UserRepository.getUserProfile.cache'));
          doc = null;
        }
      }
      if (doc == null || !doc.exists || doc.data() == null) return null;
      return UserProfile.fromJson(doc.data()!);
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      final docRef = _firestore.collection(AppConstants.colUsers).doc(profile.id);
      DocumentSnapshot<Map<String, dynamic>>? existing;
      try {
        existing = await docRef
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(_readTimeout);
      } catch (e) {
        AppLogger.d('saveUserProfile server check fell back to cache: $e',
            tag: 'UserRepository');
        try {
          existing = await docRef.get(const GetOptions(source: Source.cache));
        } catch (cacheErr, cacheStack) {
          AppLogger.w('saveUserProfile cache lookup failed: $cacheErr',
              tag: 'UserRepository', error: cacheErr, stackTrace: cacheStack);
        }
      }

      final existingData = existing?.data();
      final existingVerified = existingData?['emailOtpVerified'] == true;
      final effectiveVerified = profile.emailOtpVerified || existingVerified;

      final updatePayload = <String, dynamic>{
        'displayName': profile.displayName,
        'isCaregiver': profile.isCaregiver,
        'fcmToken': profile.fcmToken,
        'caregiverNotificationEnabled': profile.caregiverNotificationEnabled,
        'caregiverEmail': profile.caregiverEmail,
        'emailOtpVerified': effectiveVerified,
        if (profile.phoneNumber != null) 'phoneNumber': profile.phoneNumber,
        if (existingData != null && !existingData.containsKey('id'))
          'id': profile.id,
        if (existingData != null && !existingData.containsKey('email'))
          'email': profile.email,
        if (existingData != null && !existingData.containsKey('createdAt'))
          'createdAt': profile.createdAt.toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

      if (existing != null && existing.exists) {
        await _commitWrite(docRef.update(updatePayload));
      } else {
        final createPayload = profile
            .copyWith(emailOtpVerified: effectiveVerified)
            .toJson();
        await _commitWrite(
          docRef.set(createPayload, SetOptions(merge: true)),
        );
      }
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }

  /// RA 10173 Section 16 (Right to Erasure / Blocking):
  /// Permanently deletes all personal and medical records belonging to the patient across collections.
  /// Batches operations into chunks <= 400 to strictly observe Firestore's safe transaction limits.
  @override
  Future<void> deleteAllUserData(String userId) async {
    // 1. Try atomic Cloud Functions recursiveDelete if available
    try {
      final functions = _functions;
      if (functions != null) {
        final callable = functions.httpsCallable('deleteUserData');
        await callable.call<Map<String, dynamic>>();
        return;
      }
    } on FirebaseFunctionsException catch (e, stack) {
      if (e.code != 'not-found' && e.code != 'unimplemented') {
        unawaited(
          CrashlyticsService.recordError(
            e,
            stack,
            reason: 'deleteUserData callable failed (${e.code})',
          ),
        );
        throw ErrorMapper.map(e, stack);
      }
      AppLogger.w(
        'deleteUserData Cloud Function unavailable (${e.code}); using client fallback.',
        tag: 'UserRepository',
      );
    } catch (e, stack) {
      unawaited(
        CrashlyticsService.recordError(
          e,
          stack,
          reason: 'deleteUserData callable unexpected error',
        ),
      );
      throw ErrorMapper.map(e, stack);
    }

    try {
      final List<DocumentReference> refsToDelete = [];

      // 1. Delete medications
      final meds = await _firestore
          .collection(AppConstants.colMedications)
          .where('userId', isEqualTo: userId)
          .get();
      refsToDelete.addAll(meds.docs.map((d) => d.reference));

      // 2. Delete intake logs
      final logs = await _firestore
          .collection(AppConstants.colIntakeLogs)
          .where('userId', isEqualTo: userId)
          .get();
      refsToDelete.addAll(logs.docs.map((d) => d.reference));

      // 3. Delete inventory
      final inv = await _firestore
          .collection(AppConstants.colInventory)
          .where('userId', isEqualTo: userId)
          .get();
      refsToDelete.addAll(inv.docs.map((d) => d.reference));

      // 4. Delete caregiver associations where user is patient or caregiver
      final patientCaregivers = await _firestore
          .collection(AppConstants.colCaregivers)
          .where('patientId', isEqualTo: userId)
          .get();
      refsToDelete.addAll(patientCaregivers.docs.map((d) => d.reference));

      final asCaregiver = await _firestore
          .collection(AppConstants.colCaregivers)
          .where('caregiverId', isEqualTo: userId)
          .get();
      refsToDelete.addAll(asCaregiver.docs.map((d) => d.reference));

      // Clean up caregiverIds / dependentIds references on linked user documents
      for (final doc in patientCaregivers.docs) {
        final cgId = doc.data()['caregiverId']?.toString() ?? '';
        if (cgId.isNotEmpty && cgId != userId) {
          try {
            await _firestore.collection(AppConstants.colUsers).doc(cgId).update({
              'dependentIds': FieldValue.arrayRemove([userId]),
            });
          } catch (_) {}
        }
      }
      for (final doc in asCaregiver.docs) {
        final patId = doc.data()['patientId']?.toString() ?? '';
        if (patId.isNotEmpty && patId != userId) {
          try {
            await _firestore
                .collection(AppConstants.colUsers)
                .doc(patId)
                .update({
              'caregiverIds': FieldValue.arrayRemove([userId]),
            });
          } catch (_) {}
        }
      }

      // 5. Delete caregiver invites and caregiver alerts (RA 10173 right to erasure)
      final invites = await _firestore
          .collection('caregiver_invites')
          .where('patientId', isEqualTo: userId)
          .get();
      refsToDelete.addAll(invites.docs.map((d) => d.reference));

      final patientAlerts = await _firestore
          .collection('caregiver_alerts')
          .where('patientId', isEqualTo: userId)
          .get();
      refsToDelete.addAll(patientAlerts.docs.map((d) => d.reference));

      final caregiverAlerts = await _firestore
          .collection('caregiver_alerts')
          .where('caregiverId', isEqualTo: userId)
          .get();
      refsToDelete.addAll(caregiverAlerts.docs.map((d) => d.reference));

      // 6. Delete emergency card (otp_challenges is server-only per firestore.rules)
      final emergRef = _firestore
          .collection(AppConstants.colUsers)
          .doc(userId)
          .collection('emergency')
          .doc('card');
      refsToDelete.add(emergRef);

      // 8. Delete user profile doc
      final userRef = _firestore.collection(AppConstants.colUsers).doc(userId);
      refsToDelete.add(userRef);

      // Deduplicate refs
      final uniqueRefs = refsToDelete.toSet().toList();

      // Chunk in batches of <= 400
      const int batchChunkSize = 400;
      for (var i = 0; i < uniqueRefs.length; i += batchChunkSize) {
        final end = (i + batchChunkSize < uniqueRefs.length)
            ? i + batchChunkSize
            : uniqueRefs.length;
        final chunk = uniqueRefs.sublist(i, end);
        final batch = _firestore.batch();
        for (final ref in chunk) {
          batch.delete(ref);
        }
        await batch.commit();
      }
    } catch (e, stack) {
      throw ErrorMapper.map(e, stack);
    }
  }
}
