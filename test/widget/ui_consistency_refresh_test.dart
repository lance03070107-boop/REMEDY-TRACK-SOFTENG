import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';
import 'package:remedy_track/viewmodels/settings_viewmodel.dart';
import 'package:remedy_track/views/medications/add_edit_medication_view.dart';
import 'package:remedy_track/views/schedule/schedule_view.dart';
import 'package:remedy_track/views/widgets/pill_avatar.dart';
import '../mocks/test_mock_repositories.dart';

class _TestAuthViewModel extends AuthViewModel {
  _TestAuthViewModel({required super.userRepository});

  @override
  bool get isAuthenticated => true;

  @override
  String get currentUserId => 'patient_ui_refresh_01';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'ScheduleView renders PillAvatar dosage form icon, InkWell date strip, and no overflow at 320dp 1.3x',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockInvRepo = MockInventoryRepository();
    final mockIntakeRepo = MockIntakeRepository(mockInvRepo);
    final mockMedRepo = MockMedicationRepository();

    final syrupMed = Medication(
      id: 'med_syrup_1',
      userId: 'patient_ui_refresh_01',
      name: 'Cetirizine Syrup',
      genericName: 'Cetirizine',
      strength: '5mg/mL',
      form: MedicationForm.syrup,
      doseAmount: 5.0,
      colorTag: 0xFF1E66F5,
      schedule: DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['08:00'],
        startDate: DateTime.now().subtract(const Duration(days: 1)),
      ),
      isPrn: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final medVm = MedicationViewModel(
      medicationRepository: mockMedRepo,
      inventoryRepository: mockInvRepo,
    );
    final intakeVm = IntakeViewModel(intakeRepository: mockIntakeRepo);
    final settingsVm = SettingsViewModel();

    medVm.listenToMedications('patient_ui_refresh_01');
    intakeVm.listenToIntakeLogs('patient_ui_refresh_01');
    mockMedRepo.seedMedications([syrupMed]);
    mockIntakeRepo.seedLogs([]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MedicationViewModel>.value(value: medVm),
          ChangeNotifierProvider<IntakeViewModel>.value(value: intakeVm),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const ScheduleView(),
        ),
      ),
    );

    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byType(InkWell), findsWidgets);
    expect(find.byType(PillAvatar), findsOneWidget);
    final pillImg = tester.widget<Image>(
      find.descendant(
        of: find.byType(PillAvatar),
        matching: find.byType(Image),
      ),
    );
    expect(
      (pillImg.image as AssetImage).assetName,
      'assets/branding/med_forms/syrup.png',
    );
    expect(find.byIcon(Icons.medication_rounded), findsNothing);
  });

  testWidgets(
      'AddEditMedicationView renders dosage-form asset icons in dropdown at 320dp 1.3x',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockInvRepo = MockInventoryRepository();
    final mockMedRepo = MockMedicationRepository();
    final mockUserRepo = MockUserRepository();

    final authVm = _TestAuthViewModel(userRepository: mockUserRepo);
    final medVm = MedicationViewModel(
      medicationRepository: mockMedRepo,
      inventoryRepository: mockInvRepo,
    );
    final settingsVm = SettingsViewModel();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
          ChangeNotifierProvider<MedicationViewModel>.value(value: medVm),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const AddEditMedicationView(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final formDropdown =
        find.byKey(const ValueKey<String>('form_dropdown_tablet'));
    expect(formDropdown, findsOneWidget);
    final selectedImg = tester.widget<Image>(
      find.descendant(of: formDropdown, matching: find.byType(Image)).first,
    );
    expect(
      (selectedImg.image as AssetImage).assetName,
      'assets/branding/med_forms/tablet.png',
    );

    await tester.ensureVisible(formDropdown);
    await tester.tap(formDropdown);
    await tester.pumpAndSettle();

    expect(find.text('Liquid / Syrup (mL)'), findsWidgets);
    await tester.tap(find.text('Liquid / Syrup (mL)').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('form_dropdown_syrup')),
      findsOneWidget,
    );
  });
}
