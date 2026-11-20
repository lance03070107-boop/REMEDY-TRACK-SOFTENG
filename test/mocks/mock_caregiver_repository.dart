import 'package:remedy_track/core/errors/app_exception.dart';
import 'package:remedy_track/models/caregiver_relationship.dart';
import 'package:remedy_track/repositories/caregiver_repository.dart';

class MockCaregiverRepository implements CaregiverRepository {
  final List<CaregiverInvite> _invites = [];
  final List<CaregiverRelationship> _relationships = [];
  bool shouldFailInviteGeneration = false;

  List<CaregiverRelationship> get relationships =>
      List.unmodifiable(_relationships);
  List<CaregiverInvite> get invites => List.unmodifiable(_invites);

  void seedRelationship(CaregiverRelationship rel) {
    _relationships.add(rel);
  }

  void seedInvite(CaregiverInvite invite) {
    _invites.add(invite);
  }

  @override
  Future<CaregiverInvite> createPairingInvite({
    required String patientId,
    required String patientName,
  }) async {
    if (shouldFailInviteGeneration) {
      throw const NetworkException(
        'Mock invite generation failed',
        code: 'MOCK_FAILED',
      );
    }
    final code = FirebaseCaregiverRepository.generateInviteCode(6);
    final invite = CaregiverInvite(
      code: code,
      patientId: patientId,
      patientName: patientName,
      status: 'pending',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
    _invites.add(invite);
    return invite;
  }

  @override
  Future<CaregiverInvite?> getActiveInvite(String patientId) async {
    final active = _invites.where((inv) =>
        inv.patientId == patientId &&
        inv.status == 'pending' &&
        !inv.isExpired);
    return active.isEmpty ? null : active.last;
  }

  @override
  Future<CaregiverRelationship> acceptPairingInvite({
    required String code,
    required String caregiverId,
    required String caregiverName,
  }) async {
    final normalized = code.trim().toUpperCase();
    final idx = _invites.indexWhere((inv) => inv.code == normalized);
    if (idx == -1) {
      throw const ValidationException(
        'The pairing code is invalid or does not exist.',
        code: 'INVITE_NOT_FOUND',
      );
    }

    final invite = _invites[idx];
    if (invite.status != 'pending') {
      throw const ValidationException(
        'This pairing code has already been redeemed.',
        code: 'INVITE_USED',
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
        code: 'CANNOT_PAIR_SELF',
      );
    }

    _invites[idx] = CaregiverInvite(
      code: invite.code,
      patientId: invite.patientId,
      patientName: invite.patientName,
      status: 'accepted',
      createdAt: invite.createdAt,
      expiresAt: invite.expiresAt,
    );

    final relationshipId = '${invite.patientId}_$caregiverId';
    final rel = CaregiverRelationship(
      id: relationshipId,
      patientId: invite.patientId,
      patientName: invite.patientName,
      caregiverId: caregiverId,
      caregiverName: caregiverName,
      status: 'active',
      permissions: const ['view_adherence', 'receive_alerts'],
      createdAt: DateTime.now(),
    );

    _relationships.removeWhere((r) => r.id == relationshipId);
    _relationships.add(rel);
    return rel;
  }

  @override
  Future<void> revokeRelationship({
    required String patientId,
    required String caregiverId,
    required String revokedBy,
  }) async {
    final relationshipId = '${patientId}_$caregiverId';
    _relationships.removeWhere((r) => r.id == relationshipId);
  }

  @override
  Future<List<CaregiverRelationship>> getCaregiversForPatient(
      String patientId) async {
    return _relationships
        .where((r) => r.patientId == patientId && r.isActive)
        .toList();
  }

  @override
  Future<List<CaregiverRelationship>> getDependentsForCaregiver(
      String caregiverId) async {
    return _relationships
        .where((r) => r.caregiverId == caregiverId && r.isActive)
        .toList();
  }
}
