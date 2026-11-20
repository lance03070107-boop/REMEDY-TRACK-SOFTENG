import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/models/inventory_item.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/repositories/medication_repository.dart';
import 'package:remedy_track/services/alarm_scheduler.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/caregiver_viewmodel.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import 'package:remedy_track/viewmodels/inventory_viewmodel.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';
import 'package:remedy_track/viewmodels/settings_viewmodel.dart';
import 'package:remedy_track/views/home/dashboard_view.dart';
import 'package:remedy_track/views/widgets/pill_avatar.dart';
import '../mocks/test_mock_repositories.dart';

class _TestAuthViewModel extends AuthViewModel {
  _TestAuthViewModel({required super.userRepository});

  @override
  bool get isAuthenticated => true;

  @override
  String get currentUserId => 'patient_sync_test_01';

  @override
  String get currentUserDisplayName => 'Clara Reyes';
}

class _FailingMedicationRepository implements MedicationRepository {
  int streamCalls = 0;

  @override
  Stream<List<Medication>> streamMedications(String userId) {
    streamCalls++;
    return Stream<List<Medication>>.error(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
  }

  @override
  Future<List<Medication>> getMedications(String userId) async {
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }

  @override
  Future<Medication?> getMedicationById(String id) async => null;

  @override
  Future<void> addMedication(Medication medication) async {}

  @override
  Future<void> updateMedication(Medication medication) async {}

  @override
  Future<void> saveMedicationWithInventory({
    required Medication medication,
    required InventoryItem inventoryItem,
  }) async {}

  @override
  Future<void> deleteMedication(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'DashboardView renders non-blocking sync Retry banner instead of wiping out empty accounts on stream error',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final failingMedRepo = _FailingMedicationRepository();
    final mockInvRepo = MockInventoryRepository();
    final mockIntakeRepo = MockIntakeRepository(mockInvRepo);
    final mockUserRepo = MockUserRepository();
    final mockCaregiverRepo = MockCaregiverRepository();

    final authVm = _TestAuthViewModel(userRepository: mockUserRepo);
    final medVm = MedicationViewModel(
      medicationRepository: failingMedRepo,
      inventoryRepository: mockInvRepo,
    );
    final intakeVm = IntakeViewModel(intakeRepository: mockIntakeRepo);
    final invVm = InventoryViewModel(inventoryRepository: mockInvRepo);
    final caregiverVm = CaregiverViewModel(
      caregiverRepository: mockCaregiverRepo,
      userRepository: mockUserRepo,
    );
    final settingsVm = SettingsViewModel();
    final alarmScheduler = AlarmScheduler();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AlarmScheduler>.value(value: alarmScheduler),
          ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
          ChangeNotifierProvider<MedicationViewModel>.value(value: medVm),
          ChangeNotifierProvider<IntakeViewModel>.value(value: intakeVm),
          ChangeNotifierProvider<InventoryViewModel>.value(value: invVm),
          ChangeNotifierProvider<CaregiverViewModel>.value(value: caregiverVm),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardView(),
        ),
      ),
    );

    await tester.pump();
    mockIntakeRepo.seedLogs([]);
    mockInvRepo.seedInventory([]);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (int i = 0; i < 20 && (medVm.isLoading || intakeVm.isLoading); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(medVm.isLoading, isFalse,
        reason: 'medVm err=${medVm.errorMessage}, meds=${medVm.medications.length}');
    expect(intakeVm.isLoading, isFalse);

    // Dashboard chrome & summary cards stay rendered even with 0 meds + sync error
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Low Stock'), findsOneWidget);

    // Full-screen blocking fallback must NOT replace the dashboard
    expect(find.text('An Error Occurred'), findsNothing);

    // Non-blocking Retry banner appears and triggers stream reload when tapped
    final retryButton = find.widgetWithText(TextButton, 'Retry');
    expect(retryButton, findsOneWidget);
    final initialCalls = failingMedRepo.streamCalls;
    await tester.tap(retryButton);
    await tester.pump();
    mockIntakeRepo.seedLogs([]);
    mockInvRepo.seedInventory([]);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (int i = 0; i < 20 && (medVm.isLoading || intakeVm.isLoading); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(medVm.isLoading, isFalse,
        reason: 'medVm err=${medVm.errorMessage}, meds=${medVm.medications.length}');
    expect(intakeVm.isLoading, isFalse);
    expect(failingMedRepo.streamCalls, greaterThan(initialCalls));
  });

  testWidgets(
      'DashboardView As-Needed banner & modal use PillAvatar without dangling bullet at 320dp 1.3x',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockMedRepo = MockMedicationRepository();
    final mockInvRepo = MockInventoryRepository();
    final mockIntakeRepo = MockIntakeRepository(mockInvRepo);
    final mockUserRepo = MockUserRepository();
    final mockCaregiverRepo = MockCaregiverRepository();

    final prnMed = Medication(
      id: 'med_prn_1',
      userId: 'patient_sync_test_01',
      name: 'Paracetamol',
      genericName: 'Acetaminophen',
      strength: '500 mg',
      form: MedicationForm.tablet,
      doseAmount: 1.0,
      instructions: '',
      isPrn: true,
      minIntervalHours: 4,
      dailyMaxDose: 8.0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final authVm = _TestAuthViewModel(userRepository: mockUserRepo);
    final medVm = MedicationViewModel(
      medicationRepository: mockMedRepo,
      inventoryRepository: mockInvRepo,
    );
    final intakeVm = IntakeViewModel(intakeRepository: mockIntakeRepo);
    final invVm = InventoryViewModel(inventoryRepository: mockInvRepo);
    final caregiverVm = CaregiverViewModel(
      caregiverRepository: mockCaregiverRepo,
      userRepository: mockUserRepo,
    );
    final settingsVm = SettingsViewModel();
    final alarmScheduler = AlarmScheduler();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AlarmScheduler>.value(value: alarmScheduler),
          ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
          ChangeNotifierProvider<MedicationViewModel>.value(value: medVm),
          ChangeNotifierProvider<IntakeViewModel>.value(value: intakeVm),
          ChangeNotifierProvider<InventoryViewModel>.value(value: invVm),
          ChangeNotifierProvider<CaregiverViewModel>.value(value: caregiverVm),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const DashboardView(),
        ),
      ),
    );

    await tester.pump();
    mockMedRepo.seedMedications([prnMed]);
    mockIntakeRepo.seedLogs([]);
    mockInvRepo.seedInventory([]);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (int i = 0; i < 20 && (medVm.isLoading || intakeVm.isLoading); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    final prnBanner = find.text('As-Needed Medications');
    await tester.scrollUntilVisible(
      prnBanner,
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    expect(prnBanner, findsOneWidget);
    expect(find.byType(PillAvatar), findsOneWidget);

    await tester.ensureVisible(prnBanner);
    await tester.tap(prnBanner);
    await tester.pumpAndSettle();

    expect(find.text('Log As-Needed Dose'), findsOneWidget);
    expect(find.byIcon(Icons.healing_rounded), findsNothing);
    expect(find.text('500 mg • 1 tablet'), findsOneWidget);
    expect(find.text('500 mg • '), findsNothing);
  });
}
