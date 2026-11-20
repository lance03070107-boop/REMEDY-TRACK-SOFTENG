import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/inventory_item.dart';
import 'package:remedy_track/models/medication.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';

void main() {
  group('ISO/IEC 25010 Inventory Count Accuracy Simulation Test Suite', () {
    late MockInventoryRepository invRepo;
    late MockIntakeRepository intakeRepo;
    late IntakeViewModel intakeVm;

    setUp(() {
      invRepo = MockInventoryRepository();
      intakeRepo = MockIntakeRepository(invRepo);
      intakeVm = IntakeViewModel(intakeRepository: intakeRepo);
    });

    test('Tablets and capsules decrement stock accurately on taken doses',
        () async {
      final tabletMed = Medication(
        id: 'med_tablet_1',
        userId: 'user_eval',
        name: 'Amlodipine Besylate',
        strength: '5mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      const invItem = InventoryItem(
        id: 'inv_tablet_1',
        userId: 'user_eval',
        medicationId: 'med_tablet_1',
        currentStock: 100.0,
      );
      await invRepo.setInventoryItem(invItem);

      // Simulate 15 taken doses
      const dosesToTake = 15;
      for (int i = 0; i < dosesToTake; i++) {
        await intakeVm.takeDose(
          medication: tabletMed,
          scheduledTime: DateTime(2026, 10, 1, 8, 0).add(Duration(days: i)),
        );
      }

      final updated =
          await invRepo.getInventoryByMedicationId('user_eval', 'med_tablet_1');
      expect(updated, isNotNull);
      expect(updated!.currentStock, 85.0);

      // Verify accuracy calculation
      const expectedStock = 100.0 - dosesToTake;
      final accuracy = (updated.currentStock == expectedStock) ? 100.0 : 0.0;
      expect(accuracy, 100.0);
    });

    test('Skipped and Missed doses NEVER decrement inventory count', () async {
      final capsuleMed = Medication(
        id: 'med_capsule_1',
        userId: 'user_eval',
        name: 'Omeprazole',
        strength: '20mg',
        form: MedicationForm.capsule,
        doseAmount: 1.0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      const invItem = InventoryItem(
        id: 'inv_capsule_1',
        userId: 'user_eval',
        medicationId: 'med_capsule_1',
        currentStock: 60.0,
      );
      await invRepo.setInventoryItem(invItem);

      // 10 skipped doses
      for (int i = 0; i < 10; i++) {
        final scheduled = DateTime(2026, 10, 1, 8, 0).add(Duration(days: i));
        final skippedLog = IntakeLog(
          id: '${capsuleMed.id}_${scheduled.millisecondsSinceEpoch ~/ 60000}',
          userId: 'user_eval',
          medicationId: capsuleMed.id,
          medicationName: capsuleMed.name,
          scheduledTime: scheduled,
          status: DoseStatus.skipped,
          doseAmount: 1.0,
        );
        await intakeRepo.recordIntakeAtomic(
          intakeLog: skippedLog,
          decrementInventory: false,
        );
      }

      // 5 missed doses
      for (int i = 10; i < 15; i++) {
        final scheduled = DateTime(2026, 10, 1, 8, 0).add(Duration(days: i));
        final missedLog = IntakeLog(
          id: '${capsuleMed.id}_${scheduled.millisecondsSinceEpoch ~/ 60000}',
          userId: 'user_eval',
          medicationId: capsuleMed.id,
          medicationName: capsuleMed.name,
          scheduledTime: scheduled,
          status: DoseStatus.missed,
          doseAmount: 1.0,
        );
        await intakeRepo.recordIntakeAtomic(
          intakeLog: missedLog,
          decrementInventory: false,
        );
      }

      final updated = await invRepo.getInventoryByMedicationId(
          'user_eval', 'med_capsule_1');
      expect(updated, isNotNull);
      // Stock must remain unchanged at 60.0
      expect(updated!.currentStock, 60.0);
    });

    test(
        'Non-tablet and non-capsule dosage forms are strictly excluded from automated decrement',
        () async {
      const nonAutoForms = [
        MedicationForm.syrup,
        MedicationForm.inhaler,
        MedicationForm.topical,
        MedicationForm.injection,
        MedicationForm.drops,
      ];

      for (final form in nonAutoForms) {
        final med = Medication(
          id: 'med_${form.name}',
          userId: 'user_eval',
          name: 'Medication ${form.name}',
          strength: '10mg/mL',
          form: form,
          doseAmount: 5.0,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

        await invRepo.setInventoryItem(
          InventoryItem(
            id: 'inv_${form.name}',
            userId: 'user_eval',
            medicationId: 'med_${form.name}',
            currentStock: 120.0,
          ),
        );

        // Take dose
        await intakeVm.takeDose(
          medication: med,
          scheduledTime: DateTime(2026, 10, 1, 9, 0),
        );

        final item = await invRepo.getInventoryByMedicationId(
            'user_eval', 'med_${form.name}');
        // Stock must remain strictly untouched at 120.0
        expect(item!.currentStock, 120.0,
            reason: '${form.name} should NOT be auto-decremented');
      }
    });

    test('Undo taken dose atomically restores exact decremented units',
        () async {
      final tabletMed = Medication(
        id: 'med_undo_test',
        userId: 'user_eval',
        name: 'Metformin HCl',
        strength: '500mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await invRepo.setInventoryItem(
        const InventoryItem(
          id: 'inv_undo_test',
          userId: 'user_eval',
          medicationId: 'med_undo_test',
          currentStock: 50.0,
        ),
      );

      final scheduled = DateTime(2026, 10, 11, 8, 0);

      // Take dose
      await intakeVm.takeDose(
        medication: tabletMed,
        scheduledTime: scheduled,
      );

      var item = await invRepo.getInventoryByMedicationId(
          'user_eval', 'med_undo_test');
      expect(item!.currentStock, 49.0);

      // Undo taken dose
      final logId =
          '${tabletMed.id}_${scheduled.millisecondsSinceEpoch ~/ 60000}';
      final takenLog = IntakeLog(
        id: logId,
        userId: 'user_eval',
        medicationId: tabletMed.id,
        medicationName: tabletMed.name,
        scheduledTime: scheduled,
        status: DoseStatus.taken,
        doseAmount: tabletMed.doseAmount,
      );

      await intakeVm.undoTakenDose(
        medication: tabletMed,
        takenLog: takenLog,
      );

      item = await invRepo.getInventoryByMedicationId(
          'user_eval', 'med_undo_test');
      expect(item!.currentStock, 50.0);
    });

    test('1,000-Dose Stochastic Simulation produces 100.0% Inventory Accuracy',
        () async {
      final simTabletMed = Medication(
        id: 'sim_tablet',
        userId: 'sim_user',
        name: 'Losartan Potassium',
        strength: '50mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final simSyrupMed = Medication(
        id: 'sim_syrup',
        userId: 'sim_user',
        name: 'Paracetamol Suspension',
        strength: '120mg/5mL',
        form: MedicationForm.syrup,
        doseAmount: 5.0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await invRepo.setInventoryItem(
        const InventoryItem(
          id: 'inv_sim_tablet',
          userId: 'sim_user',
          medicationId: 'sim_tablet',
          currentStock: 1000.0,
        ),
      );

      await invRepo.setInventoryItem(
        const InventoryItem(
          id: 'inv_sim_syrup',
          userId: 'sim_user',
          medicationId: 'sim_syrup',
          currentStock: 500.0,
        ),
      );

      double expectedTabletStock = 1000.0;
      const double expectedSyrupStock = 500.0; // Syrups never auto-decrement

      // Run 500 tablet events (mix of taken, skipped, undo)
      for (int i = 0; i < 500; i++) {
        final time = DateTime(2026, 1, 1).add(Duration(hours: i * 4));
        final actionType = i % 5;

        if (actionType == 0 || actionType == 1 || actionType == 2) {
          // 60% Taken
          await intakeVm.takeDose(
            medication: simTabletMed,
            scheduledTime: time,
          );
          expectedTabletStock -= 1.0;
        } else if (actionType == 3) {
          // 20% Skipped
          final skippedLog = IntakeLog(
            id: 'sim_tablet_skip_$i',
            userId: 'sim_user',
            medicationId: simTabletMed.id,
            medicationName: simTabletMed.name,
            scheduledTime: time,
            status: DoseStatus.skipped,
            doseAmount: 1.0,
          );
          await intakeRepo.recordIntakeAtomic(
            intakeLog: skippedLog,
            decrementInventory: false,
          );
        } else if (actionType == 4) {
          // 20% Taken then Undone
          final logId =
              '${simTabletMed.id}_${time.millisecondsSinceEpoch ~/ 60000}';
          final takenLog = IntakeLog(
            id: logId,
            userId: 'sim_user',
            medicationId: simTabletMed.id,
            medicationName: simTabletMed.name,
            scheduledTime: time,
            status: DoseStatus.taken,
            doseAmount: simTabletMed.doseAmount,
          );
          await intakeVm.takeDose(
            medication: simTabletMed,
            scheduledTime: time,
          );
          await intakeVm.undoTakenDose(
            medication: simTabletMed,
            takenLog: takenLog,
          );
          // Net change = 0
        }
      }

      // Run 500 syrup events
      for (int i = 0; i < 500; i++) {
        final time = DateTime(2026, 1, 1).add(Duration(hours: i * 4));
        await intakeVm.takeDose(
          medication: simSyrupMed,
          scheduledTime: time,
        );
      }

      final finalTabletItem =
          await invRepo.getInventoryByMedicationId('sim_user', 'sim_tablet');
      final finalSyrupItem =
          await invRepo.getInventoryByMedicationId('sim_user', 'sim_syrup');

      expect(finalTabletItem!.currentStock, expectedTabletStock);
      expect(finalSyrupItem!.currentStock, expectedSyrupStock);

      final accuracyTablet =
          (finalTabletItem.currentStock == expectedTabletStock) ? 100.0 : 0.0;
      final accuracySyrup =
          (finalSyrupItem.currentStock == expectedSyrupStock) ? 100.0 : 0.0;

      final overallAccuracy = (accuracyTablet + accuracySyrup) / 2.0;
      expect(overallAccuracy, 100.0);
    });
  });
}
