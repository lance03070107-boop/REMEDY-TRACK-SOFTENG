import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/inventory_item.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import 'package:remedy_track/viewmodels/adherence_viewmodel.dart';
import '../mocks/test_mock_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockIntakeRepository intakeRepo;
  late MockInventoryRepository inventoryRepo;

  setUp(() {
    inventoryRepo = MockInventoryRepository();
    intakeRepo = MockIntakeRepository(inventoryRepo);
    SharedPreferences.setMockInitialValues({});
  });

  group(
      'Phase 2 - B1: Dose State Machine Enforcement & Terminal State Protection',
      () {
    test('Reconciler missed cannot overwrite an already taken dose', () async {
      final scheduled = DateTime.now().subtract(const Duration(hours: 2));
      final takenLog = IntakeLog(
        id: 'med_test_sched_1',
        userId: 'patient_1',
        medicationId: 'med_test',
        medicationName: 'Amlodipine',
        doseAmount: 1.0,
        scheduledTime: scheduled,
        recordedTime: scheduled.add(const Duration(minutes: 5)),
        status: DoseStatus.taken,
      );

      // Record taken dose
      await intakeRepo.recordIntakeAtomic(
        intakeLog: takenLog,
        decrementInventory: true,
      );

      // Concurrently or subsequently, reconciler attempts to mark missed
      final missedLog = takenLog.copyWith(
        status: DoseStatus.missed,
        notes:
            'Auto-reconciled: Unacknowledged 60 minutes after scheduled alarm.',
      );
      await intakeRepo.recordIntakeAtomic(
        intakeLog: missedLog,
        decrementInventory: false,
      );

      // Verify the log in the repository is STILL taken
      final logs = await intakeRepo.getIntakeLogs('patient_1');
      expect(logs.length, 1);
      expect(logs.first.status, DoseStatus.taken);
    });

    test('Reconciler missed cannot overwrite an already late dose', () async {
      final scheduled = DateTime.now().subtract(const Duration(hours: 3));
      final lateLog = IntakeLog(
        id: 'med_test_sched_2',
        userId: 'patient_1',
        medicationId: 'med_test',
        medicationName: 'Amlodipine',
        doseAmount: 1.0,
        scheduledTime: scheduled,
        recordedTime: scheduled.add(const Duration(hours: 2)),
        status: DoseStatus.late,
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: lateLog,
        decrementInventory: true,
      );

      final missedLog = lateLog.copyWith(status: DoseStatus.missed);
      await intakeRepo.recordIntakeAtomic(
        intakeLog: missedLog,
        decrementInventory: false,
      );

      final logs = await intakeRepo.getIntakeLogs('patient_1');
      expect(logs.first.status, DoseStatus.late);
    });

    test('Concurrent skip cannot overwrite an already taken dose', () async {
      final scheduled = DateTime.now().subtract(const Duration(minutes: 30));
      final takenLog = IntakeLog(
        id: 'med_test_sched_3',
        userId: 'patient_1',
        medicationId: 'med_test',
        medicationName: 'Metformin',
        doseAmount: 1.0,
        scheduledTime: scheduled,
        recordedTime: scheduled.add(const Duration(minutes: 2)),
        status: DoseStatus.taken,
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: takenLog,
        decrementInventory: true,
      );

      final skippedLog = takenLog.copyWith(status: DoseStatus.skipped);
      await intakeRepo.recordIntakeAtomic(
        intakeLog: skippedLog,
        decrementInventory: false,
      );

      final logs = await intakeRepo.getIntakeLogs('patient_1');
      expect(logs.first.status, DoseStatus.taken);
    });

    test('Missed cannot overwrite an already skipped dose', () async {
      final scheduled = DateTime.now().subtract(const Duration(hours: 2));
      final skippedLog = IntakeLog(
        id: 'med_test_sched_4',
        userId: 'patient_1',
        medicationId: 'med_test',
        medicationName: 'Metformin',
        doseAmount: 1.0,
        scheduledTime: scheduled,
        status: DoseStatus.skipped,
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: skippedLog,
        decrementInventory: false,
      );

      final missedLog = skippedLog.copyWith(status: DoseStatus.missed);
      await intakeRepo.recordIntakeAtomic(
        intakeLog: missedLog,
        decrementInventory: false,
      );

      final logs = await intakeRepo.getIntakeLogs('patient_1');
      expect(logs.first.status, DoseStatus.skipped);
    });
  });

  group('Phase 2 - B2: Idempotent Inventory Decrement', () {
    test('Repeated taken writes decrement inventory exactly once', () async {
      await inventoryRepo.setInventoryItem(
        InventoryItem(
          id: 'inv_med_1',
          userId: 'patient_1',
          medicationId: 'med_1',
          currentStock: 30.0,
          unit: 'tablets',
          lowStockThreshold: 5.0,
          refillQuantity: 30.0,
          lastRefillDate: DateTime.now(),
        ),
      );

      final log = IntakeLog(
        id: 'med_1_sched_100',
        userId: 'patient_1',
        medicationId: 'med_1',
        medicationName: 'Losartan',
        doseAmount: 1.0,
        scheduledTime: DateTime.now(),
        status: DoseStatus.taken,
      );

      // First write
      await intakeRepo.recordIntakeAtomic(
          intakeLog: log, decrementInventory: true);
      var inv =
          await inventoryRepo.getInventoryByMedicationId('patient_1', 'med_1');
      expect(inv!.currentStock, 29.0);

      // Duplicate write (e.g. offline retry or repeated sync)
      await intakeRepo.recordIntakeAtomic(
          intakeLog: log, decrementInventory: true);
      inv =
          await inventoryRepo.getInventoryByMedicationId('patient_1', 'med_1');
      expect(inv!.currentStock, 29.0); // Stock must NOT be decremented again
    });
  });

  group('Phase 2 - B3: Inventory Inflation Prevention on Undo', () {
    test('Undoing a skipped dose does NOT inflate inventory', () async {
      await inventoryRepo.setInventoryItem(
        InventoryItem(
          id: 'inv_med_2',
          userId: 'patient_1',
          medicationId: 'med_2',
          currentStock: 25.0,
          unit: 'tablets',
          lowStockThreshold: 5.0,
          refillQuantity: 30.0,
          lastRefillDate: DateTime.now(),
        ),
      );

      final skippedLog = IntakeLog(
        id: 'med_2_sched_101',
        userId: 'patient_1',
        medicationId: 'med_2',
        medicationName: 'Metformin',
        doseAmount: 1.0,
        scheduledTime: DateTime.now(),
        status: DoseStatus.skipped,
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: skippedLog,
        decrementInventory: false,
      );

      // Undo the skipped dose
      await intakeRepo.undoTakeDoseAtomic(
        intakeLog: skippedLog,
        restoreInventory: true,
      );

      final inv =
          await inventoryRepo.getInventoryByMedicationId('patient_1', 'med_2');
      expect(inv!.currentStock, 25.0); // Stock must remain 25.0, NOT 26.0!
    });

    test('Undoing a missed dose does NOT inflate inventory', () async {
      await inventoryRepo.setInventoryItem(
        InventoryItem(
          id: 'inv_med_3',
          userId: 'patient_1',
          medicationId: 'med_3',
          currentStock: 20.0,
          unit: 'tablets',
          lowStockThreshold: 5.0,
          refillQuantity: 30.0,
          lastRefillDate: DateTime.now(),
        ),
      );

      final missedLog = IntakeLog(
        id: 'med_3_sched_102',
        userId: 'patient_1',
        medicationId: 'med_3',
        medicationName: 'Aspirin',
        doseAmount: 1.0,
        scheduledTime: DateTime.now(),
        status: DoseStatus.missed,
      );

      await intakeRepo.recordIntakeAtomic(
        intakeLog: missedLog,
        decrementInventory: false,
      );

      // Undo the missed dose
      await intakeRepo.undoTakeDoseAtomic(
        intakeLog: missedLog,
        restoreInventory: true,
      );

      final inv =
          await inventoryRepo.getInventoryByMedicationId('patient_1', 'med_3');
      expect(inv!.currentStock, 20.0); // Stock must remain 20.0!
    });

    test('Undoing a taken dose DOES restore inventory', () async {
      await inventoryRepo.setInventoryItem(
        InventoryItem(
          id: 'inv_med_4',
          userId: 'patient_1',
          medicationId: 'med_4',
          currentStock: 15.0,
          unit: 'tablets',
          lowStockThreshold: 5.0,
          refillQuantity: 30.0,
          lastRefillDate: DateTime.now(),
        ),
      );

      final takenLog = IntakeLog(
        id: 'med_4_sched_103',
        userId: 'patient_1',
        medicationId: 'med_4',
        medicationName: 'Atorvastatin',
        doseAmount: 2.0,
        scheduledTime: DateTime.now(),
        status: DoseStatus.taken,
      );

      // Take dose -> stock drops to 13.0
      await intakeRepo.recordIntakeAtomic(
        intakeLog: takenLog,
        decrementInventory: true,
      );
      var inv =
          await inventoryRepo.getInventoryByMedicationId('patient_1', 'med_4');
      expect(inv!.currentStock, 13.0);

      // Undo taken dose -> stock restored to 15.0
      await intakeRepo.undoTakeDoseAtomic(
        intakeLog: takenLog,
        restoreInventory: true,
      );
      inv =
          await inventoryRepo.getInventoryByMedicationId('patient_1', 'med_4');
      expect(inv!.currentStock, 15.0);
    });
  });

  group('Phase 2 - B6: Loss Prevention in flushPendingBackgroundIntakes', () {
    test(
        'failed items are retained in pending_background_intakes while successes are removed',
        () async {
      final validItem = {
        'id': 'log_valid_1',
        'userId': 'patient_1',
        'medicationId': 'med_valid',
        'medicationName': 'Paracetamol',
        'doseAmount': 1.0,
        'scheduledTime': DateTime.now().toIso8601String(),
        'recordedTime': DateTime.now().toIso8601String(),
        'status': 'taken',
        'form': 'tablet',
        'isPrn': false,
      };

      // Corrupted item missing scheduledTime that fails to parse
      final corruptedItem = {
        'id': 'log_corrupt_2',
        'userId': 'patient_1',
        'medicationId': 'med_bad',
        'medicationName': 'BrokenMed',
        'doseAmount': 1.0,
        'scheduledTime': 'invalid-timestamp-xyz',
        'recordedTime': DateTime.now().toIso8601String(),
        'status': 'taken',
        'form': 'tablet',
        'isPrn': false,
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pending_background_intakes', [
        jsonEncode(validItem),
        jsonEncode(corruptedItem),
      ]);

      final viewModel = IntakeViewModel(intakeRepository: intakeRepo);
      await viewModel.flushPendingBackgroundIntakes('patient_1');

      // Check SharedPreferences: validItem was processed and removed, corruptedItem was retained!
      final remaining = prefs.getStringList('pending_background_intakes');
      expect(remaining, isNotNull);
      expect(remaining!.length, 1);
      final remainingMap = jsonDecode(remaining.first) as Map<String, dynamic>;
      expect(remainingMap['id'], 'log_corrupt_2');

      // Verify valid item was recorded
      final logs = await intakeRepo.getIntakeLogs('patient_1');
      expect(logs.any((IntakeLog l) => l.id == 'log_valid_1'), isTrue);
    });
  });

  group('Phase 2 - B7: Date Range Queries & 30-Day Adherence Limit Protection',
      () {
    test('getLogsForDateRange returns all 120 doses without 100-log truncation',
        () async {
      final now = DateTime.now();
      final seeded = <IntakeLog>[];

      // Seed 120 doses across 30 days (4 doses per day)
      for (int i = 0; i < 120; i++) {
        seeded.add(
          IntakeLog(
            id: 'dose_$i',
            userId: 'heavy_user',
            medicationId: 'med_heavy',
            medicationName: 'MaintenanceMed',
            doseAmount: 1.0,
            scheduledTime: now.subtract(Duration(hours: i * 6)),
            recordedTime: now.subtract(Duration(hours: i * 6)),
            status: DoseStatus.taken,
          ),
        );
      }

      intakeRepo.seedLogs(seeded);

      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final logsInRange = await intakeRepo.getLogsForDateRange(
        'heavy_user',
        thirtyDaysAgo,
        now.add(const Duration(minutes: 5)),
      );

      // Must return full 120 logs without being capped at 100!
      expect(logsInRange.length, 120);

      // Verify AdherenceViewModel.loadLogsForDateRange
      final adherenceVm = AdherenceViewModel(intakeRepository: intakeRepo);
      final vmLogs = await adherenceVm.loadLogsForDateRange(
        'heavy_user',
        thirtyDaysAgo,
        now.add(const Duration(minutes: 5)),
      );
      expect(vmLogs.length, 120);
    });
  });

  group('Phase 2 - B8: ISO-8601 UTC Serialization & Fail-Fast Deserialization',
      () {
    test('toJson outputs UTC ISO-8601 strings ending in Z', () {
      final localTime = DateTime(2026, 10, 18, 8, 30);
      final log = IntakeLog(
        id: 'utc_test_1',
        userId: 'u1',
        medicationId: 'm1',
        medicationName: 'TestMed',
        doseAmount: 1.0,
        scheduledTime: localTime,
        recordedTime: localTime.add(const Duration(minutes: 5)),
        status: DoseStatus.taken,
      );

      final json = log.toJson();
      expect(json['scheduledTime'], endsWith('Z'));
      expect(json['recordedTime'], endsWith('Z'));
    });

    test('fromJson normalizes parsed timestamp to local timezone', () {
      final json = {
        'id': 'log_local_test',
        'userId': 'u1',
        'medicationId': 'm1',
        'medicationName': 'TestMed',
        'doseAmount': 1.0,
        'scheduledTime': '2026-10-18T00:30:00.000Z',
        'status': 'taken',
      };

      final log = IntakeLog.fromJson(json);
      expect(log.scheduledTime.isUtc, isFalse);
    });

    test('fromJson throws FormatException when scheduledTime is missing', () {
      final json = {
        'id': 'log_missing_sched',
        'userId': 'u1',
        'medicationId': 'm1',
        'medicationName': 'TestMed',
        'status': 'taken',
      };

      expect(() => IntakeLog.fromJson(json), throwsFormatException);
    });

    test('fromJson throws FormatException when scheduledTime is corrupted', () {
      final json = {
        'id': 'log_bad_sched',
        'userId': 'u1',
        'medicationId': 'm1',
        'medicationName': 'TestMed',
        'scheduledTime': 'this-is-not-a-date',
        'status': 'taken',
      };

      expect(() => IntakeLog.fromJson(json), throwsFormatException);
    });
  });
}
