import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/models/caregiver_relationship.dart';
import 'package:remedy_track/models/user_profile.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/viewmodels/caregiver_viewmodel.dart';

void main() {
  late MockCaregiverRepository caregiverRepo;
  late MockUserRepository userRepo;
  late CaregiverViewModel viewModel;

  setUp(() {
    caregiverRepo = MockCaregiverRepository();
    userRepo = MockUserRepository();
    viewModel = CaregiverViewModel(
      caregiverRepository: caregiverRepo,
      userRepository: userRepo,
    );
  });

  group('CaregiverViewModel - Pairing Code & Linking', () {
    test(
        'generatePairingCode produces 6-character alphanumeric code with 24h expiry',
        () async {
      final invite = await viewModel.generatePairingCode(
        patientId: 'patient_alice',
        patientName: 'Alice Santos',
      );

      expect(invite, isNotNull);
      expect(invite!.code.length, 6);
      expect(invite.patientId, 'patient_alice');
      expect(invite.patientName, 'Alice Santos');
      expect(invite.isExpired, isFalse);
      expect(invite.timeRemaining.inHours, greaterThanOrEqualTo(23));

      expect(viewModel.activeInvite, isNotNull);
      expect(viewModel.activeInvite!.code, invite.code);
    });

    test('redeemPairingCode establishes bi-directional relationship', () async {
      // 1. Generate invite as patient
      final invite = await caregiverRepo.createPairingInvite(
        patientId: 'patient_alice',
        patientName: 'Alice Santos',
      );

      // Seed profiles
      userRepo.seedProfile(
        UserProfile(
          id: 'patient_alice',
          email: 'alice@test.com',
          displayName: 'Alice Santos',
          createdAt: DateTime.now(),
        ),
      );

      // 2. Redeem invite as caregiver
      final success = await viewModel.redeemPairingCode(
        code: invite.code,
        caregiverId: 'caregiver_bob',
        caregiverName: 'Bob Santos',
      );

      expect(success, isTrue);
      expect(viewModel.myDependents.length, 1);
      expect(viewModel.myDependents.first.patientId, 'patient_alice');
      expect(viewModel.myDependents.first.caregiverId, 'caregiver_bob');
      expect(viewModel.myDependents.first.isActive, isTrue);
    });

    test(
        'redeemPairingCode prevents patient from linking themselves as caregiver',
        () async {
      final invite = await caregiverRepo.createPairingInvite(
        patientId: 'user_self',
        patientName: 'Self User',
      );

      final success = await viewModel.redeemPairingCode(
        code: invite.code,
        caregiverId: 'user_self',
        caregiverName: 'Self User',
      );

      expect(success, isFalse);
      expect(viewModel.errorMessage, contains('cannot link yourself'));
    });

    test('redeemPairingCode rejects non-existent or invalid codes', () async {
      final success = await viewModel.redeemPairingCode(
        code: 'XXXXXX',
        caregiverId: 'caregiver_bob',
        caregiverName: 'Bob Santos',
      );

      expect(success, isFalse);
      expect(viewModel.errorMessage, contains('invalid or does not exist'));
    });

    test('redeemPairingCode rejects expired codes', () async {
      caregiverRepo.seedInvite(
        CaregiverInvite(
          code: 'EXP123',
          patientId: 'patient_old',
          patientName: 'Old Patient',
          status: 'pending',
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );

      final success = await viewModel.redeemPairingCode(
        code: 'EXP123',
        caregiverId: 'caregiver_bob',
        caregiverName: 'Bob Santos',
      );

      expect(success, isFalse);
      expect(viewModel.errorMessage, contains('expired'));
    });
  });

  group('CaregiverViewModel - Revocation & RBAC Mode Switching', () {
    test(
        'revokeCaregiverAccess revokes link and clears active profile if selected',
        () async {
      caregiverRepo.seedRelationship(
        CaregiverRelationship(
          id: 'patient_alice_caregiver_bob',
          patientId: 'patient_alice',
          patientName: 'Alice Santos',
          caregiverId: 'caregiver_bob',
          caregiverName: 'Bob Santos',
          status: 'active',
          createdAt: DateTime.now(),
        ),
      );

      // Caregiver views patient Alice
      viewModel.setActiveProfile('patient_alice', 'Alice Santos');
      expect(viewModel.isCaregiverMode, isTrue);

      // Caregiver revokes relationship
      await viewModel.revokeCaregiverAccess(
        patientId: 'patient_alice',
        caregiverId: 'caregiver_bob',
        currentUserId: 'caregiver_bob',
      );

      expect(viewModel.isCaregiverMode, isFalse);
      expect(viewModel.activeProfileId, isNull);
      expect(viewModel.myDependents, isEmpty);
    });

    test('setActiveProfile toggles isCaregiverMode correctly', () {
      expect(viewModel.isCaregiverMode, isFalse);
      expect(viewModel.activeProfileId, isNull);

      viewModel.setActiveProfile('dependent_123', 'Elderly Mother');
      expect(viewModel.isCaregiverMode, isTrue);
      expect(viewModel.activeProfileId, 'dependent_123');
      expect(viewModel.activeProfileName, 'Elderly Mother');

      viewModel.setActiveProfile(null);
      expect(viewModel.isCaregiverMode, isFalse);
      expect(viewModel.activeProfileId, isNull);
    });

    test('generatePairingCode rejects empty patientId with helpful error',
        () async {
      final invite = await viewModel.generatePairingCode(
        patientId: '',
        patientName: 'Alice Santos',
      );

      expect(invite, isNull);
      expect(viewModel.isMutating, isFalse);
      expect(viewModel.errorMessage, contains('sign in'));
    });

    test('generatePairingCode surfaces repository failures cleanly', () async {
      caregiverRepo.shouldFailInviteGeneration = true;

      final invite = await viewModel.generatePairingCode(
        patientId: 'patient_alice',
        patientName: 'Alice Santos',
      );

      expect(invite, isNull);
      expect(viewModel.isMutating, isFalse);
      expect(viewModel.errorMessage, isNotNull);
    });
  });
}
