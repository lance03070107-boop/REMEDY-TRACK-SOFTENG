import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedy_track/core/constants/app_constants.dart';
import 'package:remedy_track/core/errors/app_exception.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/inventory_item.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/repositories/caregiver_repository.dart';
import 'package:remedy_track/services/alarm_scheduler.dart';
import 'package:remedy_track/viewmodels/adherence_viewmodel.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/caregiver_viewmodel.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import 'package:remedy_track/viewmodels/inventory_viewmodel.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';
import '../mocks/test_mock_repositories.dart';

class _FakeUserInfo extends Fake implements UserInfo {
  @override
  final String providerId;
  _FakeUserInfo(this.providerId);
}

class _FakeUserCredential extends Fake implements UserCredential {
  @override
  final User? user;
  _FakeUserCredential(this.user);
}

class _FakeUser extends Fake implements User {
  @override
  final String uid;
  @override
  final String? email = 'patient@example.com';
  @override
  final String? displayName = 'Patient Test';
  @override
  final bool emailVerified = true;
  @override
  final List<UserInfo> providerData;

  Future<UserCredential> Function(AuthCredential)? onReauthenticate;
  Future<void> Function(String)? onUpdatePassword;
  Future<UserCredential> Function(AuthCredential)? onLinkWithCredential;
  int getIdTokenCalls = 0;

  _FakeUser({
    required this.uid,
    required this.providerData,
  });

  @override
  Future<UserCredential> reauthenticateWithCredential(
      AuthCredential credential) async {
    if (onReauthenticate != null) return onReauthenticate!(credential);
    return _FakeUserCredential(this);
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    if (onUpdatePassword != null) return onUpdatePassword!(newPassword);
  }

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    if (onLinkWithCredential != null) return onLinkWithCredential!(credential);
    return _FakeUserCredential(this);
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    getIdTokenCalls++;
    return 'refreshed-token';
  }

  @override
  Future<void> reload() async {}
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  final StreamController<User?> _authController =
      StreamController<User?>.broadcast();
  User? _user;
  int signOutCalls = 0;

  _FakeFirebaseAuth({User? initialUser}) : _user = initialUser;

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> authStateChanges() => _authController.stream;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _user = null;
    _authController.add(null);
  }

  void dispose() {
    _authController.close();
  }
}

class _FakeCaregiverRepository extends Fake implements CaregiverRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthViewModel.changePassword validation & FirebaseAuth error mapping',
      () {
    test('fails with AuthException when no active session exists', () async {
      final authVm = AuthViewModel(
        firebaseAuth: _FakeFirebaseAuth(initialUser: null),
        userRepository: MockUserRepository(),
      );

      final result = await authVm.changePassword(
        currentPassword: 'OldPassword1',
        newPassword: 'NewPassword2',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<AuthException>());
      expect(result.errorOrNull!.message,
          contains('Your session has expired'));
      authVm.dispose();
    });

    test('fails with ValidationException for Google-only accounts', () async {
      final user = _FakeUser(
        uid: 'google-uid',
        providerData: [_FakeUserInfo(GoogleAuthProvider.PROVIDER_ID)],
      );
      final fakeAuth = _FakeFirebaseAuth(initialUser: user);
      final authVm = AuthViewModel(
        firebaseAuth: fakeAuth,
        userRepository: MockUserRepository(),
      );

      expect(authVm.hasPasswordProvider, isFalse);
      final result = await authVm.changePassword(
        currentPassword: 'OldPassword1',
        newPassword: 'NewPassword2',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ValidationException>());
      expect(result.errorOrNull!.code, equals('NO_PASSWORD_PROVIDER'));
      authVm.dispose();
      fakeAuth.dispose();
    });

    test('validates empty, whitespace, length, compliance, and unchanged',
        () async {
      final user = _FakeUser(
        uid: 'pw-uid',
        providerData: [_FakeUserInfo(EmailAuthProvider.PROVIDER_ID)],
      );
      final fakeAuth = _FakeFirebaseAuth(initialUser: user);
      final authVm = AuthViewModel(
        firebaseAuth: fakeAuth,
        userRepository: MockUserRepository(),
      );

      expect(authVm.hasPasswordProvider, isTrue);

      final rEmptyCurr = await authVm.changePassword(
          currentPassword: '', newPassword: 'ValidPass1');
      expect(rEmptyCurr.errorOrNull?.code, equals('CURRENT_PASSWORD_REQUIRED'));

      final rEmptyNew = await authVm.changePassword(
          currentPassword: 'OldPassword1', newPassword: '');
      expect(rEmptyNew.errorOrNull?.code, equals('NEW_PASSWORD_REQUIRED'));

      final rSpace = await authVm.changePassword(
          currentPassword: 'OldPassword1', newPassword: ' ValidPass1');
      expect(rSpace.errorOrNull?.code, equals('PASSWORD_WHITESPACE'));

      final rShort = await authVm.changePassword(
          currentPassword: 'OldPassword1', newPassword: 'Abc1');
      expect(rShort.errorOrNull?.code, equals('PASSWORD_LENGTH'));

      final rTooLong = await authVm.changePassword(
          currentPassword: 'OldPassword1', newPassword: '${'a' * 72}1');
      expect(rTooLong.errorOrNull?.code, equals('PASSWORD_LENGTH'));

      final rNoNumber = await authVm.changePassword(
          currentPassword: 'OldPassword1', newPassword: 'OnlyLetters');
      expect(rNoNumber.errorOrNull?.code, equals('WEAK_PASSWORD'));

      final rSame = await authVm.changePassword(
          currentPassword: 'OldPassword1', newPassword: 'OldPassword1');
      expect(rSame.errorOrNull?.code, equals('PASSWORD_UNCHANGED'));

      authVm.dispose();
      fakeAuth.dispose();
    });

    test('fails immediately with NetworkException when offline', () async {
      bool reauthCalled = false;
      final user = _FakeUser(
        uid: 'pw-uid',
        providerData: [_FakeUserInfo(EmailAuthProvider.PROVIDER_ID)],
      )..onReauthenticate = (_) async {
          reauthCalled = true;
          throw Exception('should not be called');
        };
      final fakeAuth = _FakeFirebaseAuth(initialUser: user);
      final authVm = AuthViewModel(
        firebaseAuth: fakeAuth,
        userRepository: MockUserRepository(),
        isOnline: () => false,
      );

      final result = await authVm.changePassword(
        currentPassword: 'OldPassword1',
        newPassword: 'NewPassword2',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<NetworkException>());
      expect(reauthCalled, isFalse);
      authVm.dispose();
      fakeAuth.dispose();
    });

    test('maps every FirebaseAuthException code to friendly message', () async {
      final expectedMappings = <String, String>{
        'wrong-password': 'Current password is incorrect.',
        'invalid-credential': 'Current password is incorrect.',
        'weak-password':
            'New password is too weak. Use at least 8 characters with letters and numbers.',
        'requires-recent-login': 'For security, please sign in again and retry.',
        'too-many-requests':
            'Too many attempts. Please wait a few minutes and try again.',
        'network-request-failed':
            'Network error. Check your connection and try again.',
        'user-mismatch':
            'Account credentials do not match the signed-in user.',
        'user-not-found': 'Your session has expired. Please sign in again.',
        'user-token-expired': 'Your session has expired. Please sign in again.',
        'user-disabled':
            'This account has been disabled. Please contact support.',
        'unexpected-code': 'Could not change password. Please try again.',
      };

      for (final entry in expectedMappings.entries) {
        final user = _FakeUser(
          uid: 'pw-uid',
          providerData: [_FakeUserInfo(EmailAuthProvider.PROVIDER_ID)],
        )..onReauthenticate = (_) async {
            throw FirebaseAuthException(code: entry.key);
          };
        final fakeAuth = _FakeFirebaseAuth(initialUser: user);
        final authVm = AuthViewModel(
          firebaseAuth: fakeAuth,
          userRepository: MockUserRepository(),
          isOnline: () => true,
        );

        final result = await authVm.changePassword(
          currentPassword: 'OldPassword1',
          newPassword: 'NewPassword2',
        );

        expect(result.isFailure, isTrue, reason: 'Failed for code ${entry.key}');
        expect(
          result.errorOrNull!.message,
          equals(entry.value),
          reason: 'Unexpected message for code ${entry.key}',
        );
        authVm.dispose();
        fakeAuth.dispose();
      }
    });

    test('succeeds, refreshes ID token, and guards double submission', () async {
      final completer = Completer<UserCredential>();
      String? capturedNewPassword;
      final user = _FakeUser(
        uid: 'pw-uid',
        providerData: [_FakeUserInfo(EmailAuthProvider.PROVIDER_ID)],
      );
      user.onReauthenticate = (_) => completer.future;
      user.onUpdatePassword = (String np) async {
        capturedNewPassword = np;
      };
      final fakeAuth = _FakeFirebaseAuth(initialUser: user);
      final authVm = AuthViewModel(
        firebaseAuth: fakeAuth,
        userRepository: MockUserRepository(),
        isOnline: () => true,
      );

      final firstCall = authVm.changePassword(
        currentPassword: 'OldPassword1',
        newPassword: 'NewPassword2',
      );
      final secondCall = await authVm.changePassword(
        currentPassword: 'OldPassword1',
        newPassword: 'NewPassword2',
      );
      expect(secondCall.isFailure, isTrue);

      completer.complete(_FakeUserCredential(user));
      final firstResult = await firstCall;
      expect(firstResult.isSuccess, isTrue);
      expect(capturedNewPassword, equals('NewPassword2'));
      expect(user.getIdTokenCalls, equals(1));
      authVm.dispose();
      fakeAuth.dispose();
    });

    test('setPassword links credential for Google-only account', () async {
      bool linked = false;
      final user = _FakeUser(
        uid: 'google-uid',
        providerData: [_FakeUserInfo(GoogleAuthProvider.PROVIDER_ID)],
      )..onLinkWithCredential = (_) async {
          linked = true;
          return _FakeUserCredential(
            _FakeUser(
              uid: 'google-uid',
              providerData: [
                _FakeUserInfo(GoogleAuthProvider.PROVIDER_ID),
                _FakeUserInfo(EmailAuthProvider.PROVIDER_ID),
              ],
            ),
          );
        };
      final fakeAuth = _FakeFirebaseAuth(initialUser: user);
      final authVm = AuthViewModel(
        firebaseAuth: fakeAuth,
        userRepository: MockUserRepository(),
        isOnline: () => true,
      );

      final res = await authVm.setPassword(newPassword: 'NewPassword2');
      expect(res.isSuccess, isTrue);
      expect(linked, isTrue);
      authVm.dispose();
      fakeAuth.dispose();
    });
  });

  group('Adherence deduplication & offline queue preservation', () {
    test('deduplicateLogs prefers taken/late over legacy server missed duplicate',
        () {
      final sched = DateTime(2026, 11, 20, 8, 0);
      final serverMissed = IntakeLog(
        id: 'med1_${sched.millisecondsSinceEpoch}',
        userId: 'u1',
        medicationId: 'med1',
        medicationName: 'Metformin',
        doseAmount: 1,
        scheduledTime: sched,
        recordedTime: sched.add(const Duration(minutes: 65)),
        status: DoseStatus.missed,
      );
      final clientTaken = IntakeLog(
        id: 'med1_${sched.millisecondsSinceEpoch ~/ 60000}',
        userId: 'u1',
        medicationId: 'med1',
        medicationName: 'Metformin',
        doseAmount: 1,
        scheduledTime: sched,
        recordedTime: sched.add(const Duration(minutes: 5)),
        status: DoseStatus.taken,
      );

      final preferred =
          AdherenceViewModel.selectPreferredLog([serverMissed, clientTaken]);
      expect(preferred?.status, equals(DoseStatus.taken));

      final adherenceVm = AdherenceViewModel();
      expect(
        adherenceVm.calculateAdherenceRate([serverMissed, clientTaken]),
        equals(100.0),
      );
    });

    test(
        'flushPendingBackgroundIntakes preserves concurrent entries and removes only flushed ones',
        () async {
      final sched1 = DateTime(2026, 11, 20, 8, 0);
      final sched2 = DateTime(2026, 11, 20, 20, 0);
      final entry1 = jsonEncode({
        'log': IntakeLog(
          id: 'med1_${sched1.millisecondsSinceEpoch ~/ 60000}',
          userId: 'u1',
          medicationId: 'med1',
          medicationName: 'Aspirin',
          doseAmount: 1,
          scheduledTime: sched1,
          recordedTime: sched1,
          status: DoseStatus.taken,
        ).toJson(),
        'decrementInventory': true,
        'timestamp': '2026-11-20T08:00:00.000Z',
      });
      final entry2 = jsonEncode({
        'log': IntakeLog(
          id: 'med1_${sched2.millisecondsSinceEpoch ~/ 60000}',
          userId: 'u2', // Different user -> must NOT be flushed or deleted
          medicationId: 'med1',
          medicationName: 'Aspirin',
          doseAmount: 1,
          scheduledTime: sched2,
          recordedTime: sched2,
          status: DoseStatus.taken,
        ).toJson(),
        'decrementInventory': true,
        'timestamp': '2026-11-20T20:00:00.000Z',
      });

      SharedPreferences.setMockInitialValues({
        'pending_background_intakes': [entry1, entry2],
      });

      final invRepo = MockInventoryRepository();
      final intakeRepo = MockIntakeRepository(invRepo);
      final intakeVm = IntakeViewModel(intakeRepository: intakeRepo);

      expect(
        await IntakeViewModel.getPendingBackgroundIntakeCount('u1'),
        equals(1),
      );

      await intakeVm.flushPendingBackgroundIntakes('u1');

      final prefs = await SharedPreferences.getInstance();
      final remaining = prefs.getStringList('pending_background_intakes') ?? [];
      expect(remaining.length, equals(1));
      expect(remaining.first, equals(entry2));
      intakeVm.dispose();
    });

    test('AlarmScheduler.unmarkDoseAcknowledged clears terminal & handled flags',
        () async {
      final sched = DateTime.now().add(const Duration(hours: 2));
      await AlarmScheduler.markDoseAcknowledged('med_undo', sched,
          terminal: true);
      expect(AlarmScheduler.isDoseTerminal('med_undo', sched), isTrue);
      expect(AlarmScheduler.isDoseSlotHandled('med_undo', sched), isTrue);

      await AlarmScheduler.unmarkDoseAcknowledged('med_undo', sched);
      expect(AlarmScheduler.isDoseTerminal('med_undo', sched), isFalse);
      expect(AlarmScheduler.isDoseSlotHandled('med_undo', sched), isFalse);
    });

    test('ViewModel resetState clears state cleanly across account switch',
        () async {
      final medRepo = MockMedicationRepository();
      final invRepo = MockInventoryRepository();
      final intakeRepo = MockIntakeRepository(invRepo);
      final userRepo = MockUserRepository();

      final medVm = MedicationViewModel(
        medicationRepository: medRepo,
        inventoryRepository: invRepo,
      );
      final invVm = InventoryViewModel(inventoryRepository: invRepo);
      final intakeVm = IntakeViewModel(intakeRepository: intakeRepo);
      final cgVm = CaregiverViewModel(
        caregiverRepository: _FakeCaregiverRepository(),
        userRepository: userRepo,
      );

      await invVm.setupInventoryItem(
        const InventoryItem(
          id: 'inv_m1',
          userId: 'u1',
          medicationId: 'm1',
          currentStock: 10,
          lowStockThreshold: 5,
        ),
      );
      expect(invVm.inventoryItems.length, equals(1));
      cgVm.setActiveProfile('dep_1', 'Dependent One');
      expect(cgVm.isCaregiverMode, isTrue);

      medVm.resetState();
      invVm.resetState();
      intakeVm.resetState();
      cgVm.resetState();

      expect(medVm.medications, isEmpty);
      expect(invVm.inventoryItems, isEmpty);
      expect(intakeVm.allLogs, isEmpty);
      expect(cgVm.isCaregiverMode, isFalse);

      medVm.dispose();
      invVm.dispose();
      intakeVm.dispose();
      cgVm.dispose();
    });

    test('InventoryViewModel.refillItem prevents duplicate concurrent refills',
        () async {
      final invRepo = MockInventoryRepository();
      final invVm = InventoryViewModel(inventoryRepository: invRepo);
      await invVm.setupInventoryItem(
        const InventoryItem(
          id: 'inv_m1',
          userId: 'u1',
          medicationId: 'm1',
          currentStock: 10,
          lowStockThreshold: 5,
        ),
      );
      final med = Medication(
        id: 'm1',
        userId: 'u1',
        name: 'Metformin',
        strength: '500 mg',
        form: MedicationForm.tablet,
        doseAmount: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final f1 = invVm.refillItem('inv_m1', 10, form: med.form);
      final f2 = invVm.refillItem('inv_m1', 10, form: med.form);
      await Future.wait([f1, f2]);

      expect(invVm.inventoryItems.first.currentStock, equals(20));
      invVm.dispose();
    });

    test('Constants check for password length bounds', () {
      expect(AppConstants.minPasswordLength, equals(8));
      expect(AppConstants.maxPasswordLength, equals(72));
    });
  });
}
