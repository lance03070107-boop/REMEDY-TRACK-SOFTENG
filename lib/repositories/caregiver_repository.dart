import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_mapper.dart';
import '../core/utils/app_logger.dart';
import '../models/caregiver_relationship.dart';
import '../services/crashlytics_service.dart';

abstract class CaregiverRepository {
  Future<CaregiverInvite> createPairingInvite({
    required String patientId,
    required String patientName,
  });

  Future<CaregiverInvite?> getActiveInvite(String patientId);

  Future<CaregiverRelationship> acceptPairingInvite({
    required String code,
    required String caregiverId,
    required String caregiverName,
  });

  Future<void> revokeRelationship({
    required String patientId,
    required String caregiverId,
    required String revokedBy,
  });

  Future<List<CaregiverRelationship>> getCaregiversForPatient(String patientId);

  Future<List<CaregiverRelationship>> getDependentsForCaregiver(
      String caregiverId);
}

class FirebaseCaregiverRepository implements CaregiverRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _functions;
  final bool _useCloudFunctions;

  FirebaseCaregiverRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions,
        _useCloudFunctions = firestore == null;

  FirebaseFunctions? _resolveFunctions() {
    if (_functions != null) return _functions;
    if (!_useCloudFunctions || Firebase.apps.isEmpty) return null;
    try {
      return FirebaseFunctions.instanceFor(region: 'asia-southeast1');
    } catch (_) {
      return null;
    }
  }

  static const Duration _networkTimeout = Duration(seconds: 10);
  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String generateInviteCode([int length = 6]) {
    final rand = Random.secure();
    return List.generate(length, (_) => _chars[rand.nextInt(_chars.length)])
        .join();
  }

  String _sanitizeDisplayName(String raw, String fallback) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;
    if (trimmed.length > AppConstants.maxDisplayNameLength) {
      return trimmed.substring(0, AppConstants.maxDisplayNameLength);
    }
    return trimmed;
  }

  @override
  Future<CaregiverInvite> createPairingInvite({
    required String patientId,
    required String patientName,
  }) async {
    if (patientId.trim().isEmpty) {
      throw const AuthException(
        'Please sign in again before generating a pairing code.',
        code: 'UNAUTHENTICATED',
      );
    }

    try {
      final safePatientName = _sanitizeDisplayName(patientName, 'Patient');
      final fns = _resolveFunctions();
      if (fns != null) {
        try {
          final callable = fns.httpsCallable('generateCaregiverInvite');
          final result = await callable
              .call<Map<String, dynamic>>(<String, dynamic>{})
              .timeout(_networkTimeout);
          final data = result.data;
          final serverCode = data['inviteCode']?.toString().trim() ?? '';
          final serverExpires =
              DateTime.tryParse(data['expiresAt']?.toString() ?? '');
          if (serverCode.isNotEmpty) {
            return CaregiverInvite(
              code: serverCode,
              patientId: patientId,
              patientName: safePatientName,
              status: 'pending',
              createdAt: DateTime.now(),
              expiresAt:
                  serverExpires ?? DateTime.now().add(const Duration(hours: 24)),
            );
          }
        } catch (fnErr) {
          AppLogger.d(
            'generateCaregiverInvite callable fallback to Firestore: $fnErr',
            tag: 'CaregiverRepository',
          );
        }
      }

      final invitesCol = _firestore.collection('caregiver_invites');

      // Generate a fresh 6-character code that is not currently colliding in Firestore.
      String code = generateInviteCode(AppConstants.caregiverInviteCodeLength);
      for (var attempt = 0; attempt < 5; attempt++) {
        final candidateSnap =
            await invitesCol.doc(code).get().timeout(_networkTimeout);
        if (!candidateSnap.exists) {
          break;
        }
        code = generateInviteCode(AppConstants.caregiverInviteCodeLength);
      }

      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24));
      final batch = _firestore.batch();

      // Expire any older pending invites from this patient so only the newest code stays active.
      final existingSnap = await invitesCol
          .where('patientId', isEqualTo: patientId)
          .limit(20)
          .get()
          .timeout(_networkTimeout);
      for (final doc in existingSnap.docs) {
        if (doc.id != code && doc.data()['status'] == 'pending') {
          batch.update(doc.reference, {
            'status': 'expired',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      batch.set(invitesCol.doc(code), {
        'code': code,
        'patientId': patientId,
        'patientName': safePatientName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });

      await batch.commit().timeout(_networkTimeout);

      return CaregiverInvite(
        code: code,
        patientId: patientId,
        patientName: safePatientName,
        status: 'pending',
        createdAt: now,
        expiresAt: expiresAt,
      );
    } on AppException {
      rethrow;
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'CaregiverRepository.createPairingInvite'));
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<CaregiverInvite?> getActiveInvite(String patientId) async {
    if (patientId.trim().isEmpty) return null;
    try {
      // Query by single equality field so zero composite index is required.
      final snap = await _firestore
          .collection('caregiver_invites')
          .where('patientId', isEqualTo: patientId)
          .limit(20)
          .get()
          .timeout(_networkTimeout);

      if (snap.docs.isEmpty) return null;

      final activeInvites = snap.docs
          .map((doc) => CaregiverInvite.fromJson(doc.data()))
          .where((invite) => invite.status == 'pending' && !invite.isExpired)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return activeInvites.isEmpty ? null : activeInvites.first;
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'CaregiverRepository.getActiveInvite'));
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<CaregiverRelationship> acceptPairingInvite({
    required String code,
    required String caregiverId,
    required String caregiverName,
  }) async {
    if (caregiverId.trim().isEmpty) {
      throw const AuthException(
        'Please sign in again before linking a patient.',
        code: 'UNAUTHENTICATED',
      );
    }

    final normalizedCode =
        code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizedCode)) {
      throw const ValidationException(
        'Please enter a valid 6-character pairing code.',
        code: 'INVALID_INVITE_CODE',
      );
    }

    try {
      final safeCaregiverName = _sanitizeDisplayName(caregiverName, 'Caregiver');
      final fns = _resolveFunctions();
      if (fns != null) {
        try {
          final callable = fns.httpsCallable('acceptCaregiverInvite');
          final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
            'code': normalizedCode,
            'caregiverName': safeCaregiverName,
          }).timeout(_networkTimeout);
          final data = result.data;
          if (data['success'] == true) {
            final patientIdFromFn = data['patientId']?.toString().trim() ?? '';
            final patientNameFromRes =
                data['patientName']?.toString() ?? 'Patient';
            if (patientIdFromFn.isEmpty) {
              // Backward-compatible lookup if an older Cloud Function did not return patientId
              final relQuery = await _firestore
                  .collection(AppConstants.colCaregivers)
                  .where('caregiverId', isEqualTo: caregiverId)
                  .where('status', isEqualTo: 'active')
                  .get()
                  .timeout(_networkTimeout);
              final matched = relQuery.docs
                  .map((d) => CaregiverRelationship.fromJson(d.data()))
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              if (matched.isNotEmpty) {
                return matched.first;
              }
            }
            if (patientIdFromFn.isNotEmpty) {
              final relId = '${patientIdFromFn}_$caregiverId';
              final now = DateTime.now();
              return CaregiverRelationship(
                id: relId,
                patientId: patientIdFromFn,
                patientName: _sanitizeDisplayName(patientNameFromRes, 'Patient'),
                caregiverId: caregiverId,
                caregiverName: safeCaregiverName,
                status: 'active',
                permissions: const ['view_adherence', 'receive_alerts'],
                createdAt: now,
                updatedAt: now,
              );
            }
          }
        } on FirebaseFunctionsException catch (fnEx) {
          // Only short-circuit explicit business-rule rejections from a deployed callable.
          // Do NOT short-circuit 'not-found' because undeployed / 404 Cloud Functions also
          // return FirebaseFunctionsException(code: 'not-found') even when the invite exists in Firestore!
          if (fnEx.code == 'failed-precondition' ||
              fnEx.code == 'deadline-exceeded' ||
              fnEx.code == 'invalid-argument') {
            throw ValidationException(
              fnEx.message ?? 'Invalid or expired pairing code.',
              code: fnEx.code.toUpperCase(),
            );
          }
          AppLogger.d(
            'acceptCaregiverInvite callable fallback to Firestore (${fnEx.code}): $fnEx',
            tag: 'CaregiverRepository',
          );
        } catch (fnErr) {
          AppLogger.d(
            'acceptCaregiverInvite callable fallback to Firestore: $fnErr',
            tag: 'CaregiverRepository',
          );
        }
      }

      final inviteRef =
          _firestore.collection('caregiver_invites').doc(normalizedCode);
      DocumentSnapshot<Map<String, dynamic>> inviteSnap;
      try {
        inviteSnap = await inviteRef
            .get(const GetOptions(source: Source.server))
            .timeout(_networkTimeout);
      } catch (_) {
        inviteSnap = await inviteRef.get().timeout(_networkTimeout);
      }

      if (!inviteSnap.exists || inviteSnap.data() == null) {
        throw const ValidationException(
          'Pairing code not found or has expired.',
          code: 'INVITE_NOT_FOUND',
        );
      }

      final invite = CaregiverInvite.fromJson(inviteSnap.data()!);
      if (invite.status != 'pending') {
        throw const ValidationException(
          'This pairing code has already been used.',
          code: 'INVITE_ALREADY_USED',
        );
      }
      if (invite.isExpired) {
        throw const ValidationException(
          'This pairing code has expired (24-hour limit).',
          code: 'INVITE_EXPIRED',
        );
      }
      if (invite.patientId == caregiverId) {
        throw const ValidationException(
          'You cannot link yourself as your own caregiver.',
          code: 'SELF_LINK_NOT_ALLOWED',
        );
      }

      final safePatientName =
          _sanitizeDisplayName(invite.patientName, 'Patient');
      final rawAllowedMedIds = inviteSnap.data()!['allowedMedicationIds'];
      final List<String>? allowedMedIds = rawAllowedMedIds is List
          ? rawAllowedMedIds
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : null;
      final relationshipId = '${invite.patientId}_$caregiverId';
      final relRef =
          _firestore.collection(AppConstants.colCaregivers).doc(relationshipId);
      // Safely check whether an active relationship already exists; ignore permission-denied
      // on non-existent docs (firestore.rules requires resource.data.caregiverId == uid on read).
      try {
        final existingRelSnap = await relRef.get().timeout(_networkTimeout);
        if (existingRelSnap.exists &&
            existingRelSnap.data()?['status'] == 'active') {
          throw const ValidationException(
            'You are already linked as a caregiver for this patient.',
            code: 'ALREADY_LINKED',
          );
        }
      } on ValidationException {
        rethrow;
      } catch (_) {}
      final now = DateTime.now();

      final batch = _firestore.batch();
      batch.update(inviteRef, {
        'status': 'accepted',
        'usedBy': caregiverId,
        'usedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(relRef, {
        'id': relationshipId,
        'patientId': invite.patientId,
        'patientName': safePatientName,
        'caregiverId': caregiverId,
        'caregiverName': safeCaregiverName,
        'status': 'active',
        'permissions': const ['view_adherence', 'receive_alerts'],
        if (allowedMedIds != null) 'allowedMedicationIds': allowedMedIds,
        'inviteCode': normalizedCode,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit().timeout(_networkTimeout);

      return CaregiverRelationship(
        id: relationshipId,
        patientId: invite.patientId,
        patientName: safePatientName,
        caregiverId: caregiverId,
        caregiverName: safeCaregiverName,
        status: 'active',
        permissions: const ['view_adherence', 'receive_alerts'],
        createdAt: now,
        updatedAt: now,
      );
    } on AppException {
      rethrow;
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'CaregiverRepository.acceptPairingInvite'));
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<void> revokeRelationship({
    required String patientId,
    required String caregiverId,
    required String revokedBy,
  }) async {
    try {
      final fns = _resolveFunctions();
      if (fns != null) {
        try {
          final callable = fns.httpsCallable('revokeCaregiverAccess');
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
            'patientId': patientId,
            'caregiverId': caregiverId,
          }).timeout(_networkTimeout);
          return;
        } catch (fnErr) {
          AppLogger.d(
            'revokeCaregiverAccess callable fallback to Firestore: $fnErr',
            tag: 'CaregiverRepository',
          );
        }
      }

      final caregiversCol = _firestore.collection(AppConstants.colCaregivers);
      final docRef = caregiversCol.doc('${patientId}_$caregiverId');
      final docSnap = await docRef.get().timeout(_networkTimeout);

      if (docSnap.exists) {
        await docRef.update({
          'status': 'revoked',
          'updatedAt': FieldValue.serverTimestamp(),
        }).timeout(_networkTimeout);
        return;
      }

      // Fallback for legacy relationship document IDs
      final matching = await caregiversCol
          .where('patientId', isEqualTo: patientId)
          .where('caregiverId', isEqualTo: caregiverId)
          .get()
          .timeout(_networkTimeout);
      if (matching.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in matching.docs) {
          batch.update(doc.reference, {
            'status': 'revoked',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit().timeout(_networkTimeout);
      }
    } catch (e, stack) {
      AppLogger.w('Failed to revoke caregiver link: $e',
          tag: 'CaregiverRepository');
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'CaregiverRepository.revokeRelationship'));
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<List<CaregiverRelationship>> getCaregiversForPatient(
      String patientId) async {
    if (patientId.trim().isEmpty) return const [];
    try {
      final snap = await _firestore
          .collection(AppConstants.colCaregivers)
          .where('patientId', isEqualTo: patientId)
          .get()
          .timeout(_networkTimeout);

      return snap.docs
          .map((d) => CaregiverRelationship.fromJson(d.data()))
          .where((rel) => rel.isActive)
          .toList();
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'CaregiverRepository.getCaregiversForPatient'));
      throw ErrorMapper.map(e, stack);
    }
  }

  @override
  Future<List<CaregiverRelationship>> getDependentsForCaregiver(
      String caregiverId) async {
    if (caregiverId.trim().isEmpty) return const [];
    try {
      final snap = await _firestore
          .collection(AppConstants.colCaregivers)
          .where('caregiverId', isEqualTo: caregiverId)
          .get()
          .timeout(_networkTimeout);

      return snap.docs
          .map((d) => CaregiverRelationship.fromJson(d.data()))
          .where((rel) => rel.isActive)
          .toList();
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack,
          reason: 'CaregiverRepository.getDependentsForCaregiver'));
      throw ErrorMapper.map(e, stack);
    }
  }
}
