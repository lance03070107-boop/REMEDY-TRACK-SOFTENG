import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/repositories/caregiver_repository.dart';
import 'package:remedy_track/viewmodels/adherence_viewmodel.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/caregiver_viewmodel.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';
import 'package:remedy_track/viewmodels/settings_viewmodel.dart';
import 'package:remedy_track/views/reports/insights_view.dart';
import '../mocks/test_mock_repositories.dart';

class _FakeCaregiverRepo extends Fake implements CaregiverRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  List<IntakeLog> sampleLogs() {
    final now = DateTime.now();
    return [
      IntakeLog(
        id: 'log_1',
        userId: 'user_1',
        medicationId: 'med_1',
        medicationName: 'Metformin',
        doseAmount: 1,
        scheduledTime: now.subtract(const Duration(hours: 4)),
        recordedTime: now.subtract(const Duration(hours: 4)),
        status: DoseStatus.taken,
      ),
      IntakeLog(
        id: 'log_2',
        userId: 'user_1',
        medicationId: 'med_2',
        medicationName: 'Amlodipine',
        doseAmount: 1,
        scheduledTime: now.subtract(const Duration(hours: 2)),
        recordedTime: now.subtract(const Duration(hours: 2)),
        status: DoseStatus.missed,
      ),
    ];
  }

  Widget buildHarness({
    required IntakeViewModel intakeVm,
    required CaregiverViewModel caregiverVm,
  }) {
    final invRepo = MockInventoryRepository();
    final medRepo = MockMedicationRepository();
    final userRepo = MockUserRepository();
    final authVm = AuthViewModel(userRepository: userRepo);
    final medVm = MedicationViewModel(
      medicationRepository: medRepo,
      inventoryRepository: invRepo,
    );
    final adherenceVm = AdherenceViewModel();
    final settingsVm = SettingsViewModel();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
        ChangeNotifierProvider<MedicationViewModel>.value(value: medVm),
        ChangeNotifierProvider<IntakeViewModel>.value(value: intakeVm),
        ChangeNotifierProvider<AdherenceViewModel>.value(value: adherenceVm),
        ChangeNotifierProvider<CaregiverViewModel>.value(value: caregiverVm),
        ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const InsightsView(initialTabIndex: 1),
      ),
    );
  }

  group('Dosage History Delete (One-by-One & Delete All)', () {
    testWidgets('deletes a single dosage history record after confirmation',
        (tester) async {
      final invRepo = MockInventoryRepository();
      final intakeRepo = MockIntakeRepository(invRepo);
      final intakeVm = IntakeViewModel(intakeRepository: intakeRepo);
      final logs = sampleLogs();
      for (final log in logs) {
        await intakeRepo.recordIntakeAtomic(
            intakeLog: log, decrementInventory: false);
      }
      intakeVm.setLogsForTesting(logs);

      final caregiverVm = CaregiverViewModel(
        caregiverRepository: _FakeCaregiverRepo(),
        userRepository: MockUserRepository(),
      );

      await tester.pumpWidget(
        buildHarness(intakeVm: intakeVm, caregiverVm: caregiverVm),
      );
      await tester.pumpAndSettle();

      expect(find.text('Metformin'), findsOneWidget);
      expect(find.text('Amlodipine'), findsOneWidget);
      expect(find.text('Delete All'), findsOneWidget);

      // Tap first per-item delete button
      await tester.tap(find.byTooltip('Delete record').first);
      await tester.pumpAndSettle();

      expect(find.text('Delete Dose Record?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(intakeVm.allLogs.length, equals(1));
      expect(find.text('Metformin'), findsNothing);
      expect(find.text('Amlodipine'), findsOneWidget);
    });

    testWidgets('deletes all dosage history records after confirmation',
        (tester) async {
      final invRepo = MockInventoryRepository();
      final intakeRepo = MockIntakeRepository(invRepo);
      final intakeVm = IntakeViewModel(intakeRepository: intakeRepo);
      final logs = sampleLogs();
      for (final log in logs) {
        await intakeRepo.recordIntakeAtomic(
            intakeLog: log, decrementInventory: false);
      }
      intakeVm.setLogsForTesting(logs);

      final caregiverVm = CaregiverViewModel(
        caregiverRepository: _FakeCaregiverRepo(),
        userRepository: MockUserRepository(),
      );

      await tester.pumpWidget(
        buildHarness(intakeVm: intakeVm, caregiverVm: caregiverVm),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete All'));
      await tester.pumpAndSettle();

      expect(find.text('Delete All Dosage History?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete All'));
      await tester.pumpAndSettle();

      expect(intakeVm.allLogs, isEmpty);
      expect(find.text('No Logs Found'), findsOneWidget);
    });

    testWidgets('hides delete controls in Caregiver Read-Only Mode',
        (tester) async {
      final invRepo = MockInventoryRepository();
      final intakeRepo = MockIntakeRepository(invRepo);
      final intakeVm = IntakeViewModel(intakeRepository: intakeRepo);
      intakeVm.setLogsForTesting(sampleLogs());

      final caregiverVm = CaregiverViewModel(
        caregiverRepository: _FakeCaregiverRepo(),
        userRepository: MockUserRepository(),
      )..setActiveProfile('patient_1', 'Patient One');

      await tester.pumpWidget(
        buildHarness(intakeVm: intakeVm, caregiverVm: caregiverVm),
      );
      await tester.pumpAndSettle();

      expect(find.text('Metformin'), findsOneWidget);
      expect(find.text('Delete All'), findsNothing);
      expect(find.byTooltip('Delete record'), findsNothing);
    });
  });
}
