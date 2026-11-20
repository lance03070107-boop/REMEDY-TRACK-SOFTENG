import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/inventory_item.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthViewModel Security & Authentication Tests', () {
    late MockUserRepository mockUserRepo;
    late AuthViewModel authVm;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockUserRepo = MockUserRepository();
      authVm = AuthViewModel(
        userRepository: mockUserRepo,
      );
    });

    test('initial state is unauthenticated with empty user identifiers', () {
      expect(authVm.isAuthenticated, isFalse);
      expect(authVm.currentUserId, isEmpty);
      expect(authVm.currentUserEmail, isEmpty);
      expect(authVm.isLoading, isFalse);
      expect(authVm.errorMessage, isNull);
    });

    test('password policy correctly validates compliance', () {
      // Too short (< 8 chars)
      expect(AuthViewModel.isPasswordCompliant('Ab1!'), isFalse);
      expect(AuthViewModel.isPasswordCompliant('Pass12'), isFalse);

      // 8+ chars but only letters
      expect(AuthViewModel.isPasswordCompliant('PasswordOnly'), isFalse);

      // 8+ chars but only numbers
      expect(AuthViewModel.isPasswordCompliant('12345678'), isFalse);

      // Valid: >=8 chars with both letter and number
      expect(AuthViewModel.isPasswordCompliant('Pass1234'), isTrue);
      expect(AuthViewModel.isPasswordCompliant('ClaraPass2026!'), isTrue);
    });

    test('password strength categorization evaluates correctly', () {
      expect(AuthViewModel.evaluatePasswordStrength('short'),
          PasswordStrength.weak);
      expect(AuthViewModel.evaluatePasswordStrength('onlylettershere'),
          PasswordStrength.weak);
      expect(AuthViewModel.evaluatePasswordStrength('Pass1234'),
          PasswordStrength.fair);
      expect(AuthViewModel.evaluatePasswordStrength('SecurePass2026!'),
          PasswordStrength.strong);
    });

    test('registerWithEmail rejects non-compliant passwords', () async {
      final success = await authVm.registerWithEmail(
        'test@example.com',
        'weak',
        'Test User',
      );
      expect(success, isFalse);
      expect(authVm.errorMessage, contains('at least 8 characters'));
      expect(authVm.isAuthenticated, isFalse);
    });

    test(
        'signInWithEmail gracefully reports unavailable connection when Firebase is uninitialized',
        () async {
      final success = await authVm.signInWithEmail(
          'test.patient@example.com', 'SecurePass123!');

      expect(success, isFalse);
      expect(authVm.isAuthenticated, isFalse);
      expect(
          authVm.errorMessage, contains('Firebase connection is unavailable'));
    });

    test(
        'registerWithEmail gracefully reports unavailable connection when Firebase is uninitialized',
        () async {
      final success = await authVm.registerWithEmail(
        'clara.oswald@example.ph',
        'ClaraPass2026!',
        'Clara Oswald',
      );

      expect(success, isFalse);
      expect(authVm.isAuthenticated, isFalse);
      expect(
          authVm.errorMessage, contains('Firebase connection is unavailable'));
    });

    test('signOut terminates session and resets all user states to empty',
        () async {
      await authVm.signOut();
      expect(authVm.isAuthenticated, isFalse);
      expect(authVm.currentUserId, isEmpty);
      expect(authVm.currentUserEmail, isEmpty);
      expect(authVm.userProfile, isNull);
    });

    test('acceptPrivacyConsent stores RA 10173 consent correctly', () async {
      expect(authVm.isPrivacyConsentGiven, isFalse);

      await authVm.acceptPrivacyConsent();
      expect(authVm.isPrivacyConsentGiven, isTrue);

      final newVm = AuthViewModel(userRepository: mockUserRepo);
      await newVm.checkStoredConsent();
      expect(newVm.isPrivacyConsentGiven, isTrue);
    });

    test(
        'social sign-in provider detection properties return false for unauthenticated session',
        () {
      expect(authVm.isGoogleLinked, isFalse);
      expect(authVm.isAppleLinked, isFalse);
      expect(authVm.isPasswordLinked, isFalse);
      expect(authVm.isEmailOtpVerified, isFalse);
    });

    test(
        'signOut removes pending_background_intakes and remedy_active_dose_alarm_ids from SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'pending_background_intakes': ['{"id":"log_1"}'],
        'remedy_active_dose_alarm_ids': ['101', '102'],
      });
      await authVm.signOut();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pending_background_intakes'), isNull);
      expect(prefs.getStringList('remedy_active_dose_alarm_ids'), isNull);
    });

    test(
        'MedicationViewModel.saveMedicationOnlyResult saves medication without creating dummy stock and preserves existing stock on edit',
        () async {
      final medRepo = MockMedicationRepository();
      final invRepo = MockInventoryRepository();
      final medVm = MedicationViewModel(
        medicationRepository: medRepo,
        inventoryRepository: invRepo,
      );

      final now = DateTime(2026, 11, 14, 8, 0);
      final newMed = Medication(
        id: 'med_new_no_stock',
        userId: 'user_01',
        name: 'Metformin',
        strength: '500 mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        colorTag: 0xFF1E66F5,
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00'],
          startDate: now,
        ),
        createdAt: now,
        updatedAt: now,
      );

      final createRes = await medVm.saveMedicationOnlyResult(
        medication: newMed,
        isEditing: false,
      );
      expect(createRes.isSuccess, isTrue);

      final invAfterCreate = await invRepo.getInventoryByMedicationId(
          'user_01', 'med_new_no_stock');
      expect(invAfterCreate, isNull);

      // Now seed existing stock and edit medication
      await invRepo.setInventoryItem(
        const InventoryItem(
          id: 'inv_med_new_no_stock',
          medicationId: 'med_new_no_stock',
          userId: 'user_01',
          currentStock: 42.0,
          lowStockThreshold: 10.0,
          unit: 'tablets',
        ),
      );

      final editRes = await medVm.saveMedicationOnlyResult(
        medication: newMed.copyWith(strength: '850 mg'),
        isEditing: true,
      );
      expect(editRes.isSuccess, isTrue);

      final invAfterEdit = await invRepo.getInventoryByMedicationId(
          'user_01', 'med_new_no_stock');
      expect(invAfterEdit, isNotNull);
      expect(invAfterEdit!.currentStock, 42.0);
    });
  });
}
