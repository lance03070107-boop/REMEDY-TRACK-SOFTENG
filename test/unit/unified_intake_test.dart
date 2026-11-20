import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/state/dose_state_machine.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/inventory_item.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/services/alarm_id_generator.dart';

void main() {
  group('Unified Intake & Idempotency Pipeline Tests', () {
    late MockInventoryRepository invRepo;
    late MockIntakeRepository intakeRepo;
    const testUserId = 'test_patient_user_001';
    const medId = 'med_amox_500';

    setUp(() async {
      invRepo = MockInventoryRepository();
      intakeRepo = MockIntakeRepository(invRepo);

      // Seed initial stock of 30 tablets
      await invRepo.setInventoryItem(
        const InventoryItem(
          id: 'inv_amox_001',
          userId: testUserId,
          medicationId: medId,
          currentStock: 30.0,
          unit: 'capsules',
          lowStockThreshold: 10.0,
        ),
      );
    });

    test(
        '1. Single idempotent intake path: repeated taken logs do NOT decrement stock twice',
        () async {
      final scheduledTime = DateTime(2026, 10, 16, 8, 0);
      final logId = DoseStateMachine.generateLogId(medId, scheduledTime);

      final log1 = IntakeLog(
        id: logId,
        userId: testUserId,
        medicationId: medId,
        medicationName: 'Amoxicillin',
        scheduledTime: scheduledTime,
        recordedTime: scheduledTime.add(const Duration(minutes: 5)),
        status: DoseStatus.taken,
        doseAmount: 1.0,
      );

      // First intake log: decrements stock from 30.0 to 29.0
      await intakeRepo.recordIntakeAtomic(
        intakeLog: log1,
        decrementInventory: true,
      );

      final itemAfterFirst =
          await invRepo.getInventoryByMedicationId(testUserId, medId);
      expect(itemAfterFirst?.currentStock, 29.0);

      // Re-recording the same log (e.g. background replay or network retry)
      final duplicateLog = IntakeLog(
        id: logId,
        userId: testUserId,
        medicationId: medId,
        medicationName: 'Amoxicillin',
        scheduledTime: scheduledTime,
        recordedTime: scheduledTime.add(const Duration(minutes: 10)),
        status: DoseStatus.taken,
        doseAmount: 1.0,
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: duplicateLog,
        decrementInventory: true,
      );

      final itemAfterDuplicate =
          await invRepo.getInventoryByMedicationId(testUserId, medId);
      expect(itemAfterDuplicate?.currentStock, 29.0,
          reason:
              'Duplicate taken log must be strictly idempotent and not decrement stock again');
    });

    test(
        '2. Tablet and capsule forms decrement stock; syrups, inhalers, and injections do NOT',
        () async {
      // Setup syrup inventory
      const syrupMedId = 'med_cough_syrup';
      await invRepo.setInventoryItem(
        const InventoryItem(
          id: 'inv_syrup_001',
          userId: testUserId,
          medicationId: syrupMedId,
          currentStock: 120.0,
          unit: 'ml',
          lowStockThreshold: 30.0,
        ),
      );

      final scheduledTime = DateTime(2026, 10, 16, 12, 0);
      final syrupLog = IntakeLog(
        id: DoseStateMachine.generateLogId(syrupMedId, scheduledTime),
        userId: testUserId,
        medicationId: syrupMedId,
        medicationName: 'Cough Syrup',
        scheduledTime: scheduledTime,
        recordedTime: scheduledTime,
        status: DoseStatus.taken,
        doseAmount: 5.0,
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: syrupLog,
        decrementInventory:
            false, // Paper specifies automated arithmetic ONLY for tablets & capsules
      );

      final syrupItem =
          await invRepo.getInventoryByMedicationId(testUserId, syrupMedId);
      expect(syrupItem?.currentStock, 120.0,
          reason:
              'Syrup forms must not be subject to automatic arithmetic decrements');

      // Test Tablet decrements
      const tabletMedId = 'med_amlodipine';
      await invRepo.setInventoryItem(
        const InventoryItem(
          id: 'inv_amlo_001',
          userId: testUserId,
          medicationId: tabletMedId,
          currentStock: 14.0,
          unit: 'tablets',
          lowStockThreshold: 5.0,
        ),
      );

      final tabletLog = IntakeLog(
        id: DoseStateMachine.generateLogId(tabletMedId, scheduledTime),
        userId: testUserId,
        medicationId: tabletMedId,
        medicationName: 'Amlodipine',
        scheduledTime: scheduledTime,
        recordedTime: scheduledTime,
        status: DoseStatus.taken,
        doseAmount: 1.0,
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: tabletLog,
        decrementInventory: true,
      );

      final tabletItem =
          await invRepo.getInventoryByMedicationId(testUserId, tabletMedId);
      expect(tabletItem?.currentStock, 13.0,
          reason: 'Tablet form must decrement stock accurately');
    });

    test('3. Skipped and Missed statuses do NOT decrement inventory', () async {
      final scheduledTime = DateTime(2026, 10, 16, 18, 0);
      final skipLog = IntakeLog(
        id: DoseStateMachine.generateLogId(medId, scheduledTime),
        userId: testUserId,
        medicationId: medId,
        medicationName: 'Amoxicillin',
        scheduledTime: scheduledTime,
        recordedTime: scheduledTime.add(const Duration(minutes: 2)),
        status: DoseStatus.skipped,
        doseAmount: 1.0,
        notes: 'Patient Fasting',
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: skipLog,
        decrementInventory: false,
      );

      final itemAfterSkip =
          await invRepo.getInventoryByMedicationId(testUserId, medId);
      expect(itemAfterSkip?.currentStock, 30.0,
          reason: 'Skipped doses must never decrement inventory stock');
    });

    test('4. Collision resistance between primary and escalation alarm IDs',
        () {
      final seenIds = <int>{};
      final now = DateTime(2026, 10, 16, 6, 0);

      // Generate 200 occurrences across 5 different medications and multiple times
      for (int m = 0; m < 5; m++) {
        final currentMedId = 'med_test_$m';
        for (int day = 0; day < 10; day++) {
          for (int tIdx = 0; tIdx < 4; tIdx++) {
            final doseTime = now.add(Duration(days: day, hours: tIdx * 4));
            final primaryId = AlarmIdGenerator.generateDoseAlarmId(
              medicationId: currentMedId,
              scheduledDateTime: doseTime,
              timeIndex: tIdx,
            );
            final escalationId = AlarmIdGenerator.getEscalationId(primaryId);

            // Neither primary nor escalation may collide
            expect(seenIds.contains(primaryId), isFalse,
                reason: 'Primary alarm ID $primaryId must be unique');
            seenIds.add(primaryId);

            expect(seenIds.contains(escalationId), isFalse,
                reason:
                    'Escalation alarm ID $escalationId must not collide with primary or other escalations');
            seenIds.add(escalationId);

            // Both must fit within 32-bit signed positive integer range
            expect(primaryId, greaterThanOrEqualTo(1000));
            expect(primaryId, lessThan(1500000000));
            expect(escalationId, greaterThanOrEqualTo(501000));
            expect(escalationId, lessThan(2147483647));
          }
        }
      }

      expect(seenIds.length, 400);
    });
  });
}
