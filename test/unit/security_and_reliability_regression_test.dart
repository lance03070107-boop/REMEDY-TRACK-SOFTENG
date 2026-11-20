import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedy_track/core/constants/app_constants.dart';
import 'package:remedy_track/models/caregiver_relationship.dart';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/models/user_profile.dart';
import 'package:remedy_track/services/alarm_id_generator.dart';
import 'package:remedy_track/services/alarm_scheduler.dart';
import 'package:remedy_track/services/missed_dose_reconciler.dart';
import 'package:remedy_track/viewmodels/adherence_viewmodel.dart';
import 'package:remedy_track/viewmodels/caregiver_viewmodel.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';

import '../mocks/test_mock_repositories.dart';

class _FailingIntakeRepository extends MockIntakeRepository {
  bool shouldThrowOnWrite = false;

  _FailingIntakeRepository(super.inventoryRepo);

  @override
  Future<void> recordIntakeAtomic({
    required IntakeLog intakeLog,
    required bool decrementInventory,
  }) async {
    if (shouldThrowOnWrite) {
      throw Exception('Simulated Firestore write failure');
    }
    return super.recordIntakeAtomic(
      intakeLog: intakeLog,
      decrementInventory: decrementInventory,
    );
  }

  @override
  Future<void> undoTakeDoseAtomic({
    required IntakeLog intakeLog,
    required bool restoreInventory,
  }) async {
    if (shouldThrowOnWrite) {
      throw Exception('Simulated Firestore undo failure');
    }
    return super.undoTakeDoseAtomic(
      intakeLog: intakeLog,
      restoreInventory: restoreInventory,
    );
  }
}

Medication _buildTestMedication({
  String id = 'med_reg_1',
  String userId = 'patient_reg_1',
  bool vibrationEnabled = true,
  DoseSchedule? schedule,
  DateTime? createdAt,
}) {
  final ts = createdAt ?? DateTime(2026, 10, 1, 6, 0);
  return Medication(
    id: id,
    userId: userId,
    name: 'Amlodipine',
    strength: '5 mg',
    form: MedicationForm.tablet,
    doseAmount: 1.0,
    isPrn: schedule == null,
    schedule: schedule,
    alarmSoundId: AppConstants.defaultAlarmSound,
    vibrationEnabled: vibrationEnabled,
    createdAt: ts,
    updatedAt: ts,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Alarm payload and slot ID bounds regression', () {
    test('buildAlarmPayload preserves vibrate flag and snoozeCount', () {
      final schedTime = DateTime(2026, 10, 15, 8, 0);
      final silentMed = _buildTestMedication(vibrationEnabled: false);

      final encoded = AlarmScheduler.buildAlarmPayload(
        medication: silentMed,
        notificationId: 4201,
        primaryNotifId: 4200,
        scheduledDateTime: schedTime,
        soundId: 'gentle_chime',
        snoozeCount: 2,
        triggerDateTime: schedTime.add(const Duration(minutes: 20)),
      );
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['vibrate'], isFalse);
      expect(decoded['snoozeCount'], 2);
      expect(decoded['soundId'], 'gentle_chime');
      expect(decoded['primaryNotifId'], 4200);
    });

    test('AlarmIdGenerator generates unique valid IDs across all 12 time slots',
        () {
      final date = DateTime(2026, 10, 15, 8, 0);
      final ids = <int>{};
      for (int slot = 0; slot < AppConstants.maxTimeSlots; slot++) {
        final id = AlarmIdGenerator.generateDoseAlarmId(
          medicationId: 'med_12_slots',
          scheduledDateTime: date,
          timeIndex: slot,
        );
        expect(id, greaterThanOrEqualTo(1000));
        expect(
          AlarmIdGenerator.getEscalationId(id),
          lessThan(2147483647),
        );
        ids.add(id);
      }
      expect(ids.length, AppConstants.maxTimeSlots);
    });
  });

  group('AdherenceViewModel empty-state and partial-day streak regression', () {
    test('hasScheduledAdherenceData excludes PRN-only and snoozed-only logs',
        () {
      final vm = AdherenceViewModel();
      final now = DateTime.now();

      final prnOnly = [
        IntakeLog(
          id: 'prn_1',
          userId: 'u1',
          medicationId: 'm_prn',
          medicationName: 'Ibuprofen',
          doseAmount: 1.0,
          scheduledTime: now,
          recordedTime: now,
          status: DoseStatus.taken,
          isPrn: true,
        ),
      ];
      final snoozedOnly = [
        IntakeLog(
          id: 'snooze_1',
          userId: 'u1',
          medicationId: 'm_sched',
          medicationName: 'Losartan',
          doseAmount: 1.0,
          scheduledTime: now,
          recordedTime: now,
          status: DoseStatus.snoozed,
          snoozeCount: 1,
          isPrn: false,
        ),
      ];
      final withScheduledTaken = [
        ...prnOnly,
        ...snoozedOnly,
        IntakeLog(
          id: 'sched_taken_1',
          userId: 'u1',
          medicationId: 'm_sched',
          medicationName: 'Losartan',
          doseAmount: 1.0,
          scheduledTime: now,
          recordedTime: now,
          status: DoseStatus.taken,
          isPrn: false,
        ),
      ];

      expect(vm.hasScheduledAdherenceData(const []), isFalse);
      expect(vm.hasScheduledAdherenceData(prnOnly), isFalse);
      expect(vm.hasScheduledAdherenceData(snoozedOnly), isFalse);
      expect(vm.hasScheduledAdherenceData(withScheduledTaken), isTrue);
    });

    test(
        'calculateStreakDays does not credit incomplete today when todayExpectedCount exceeds logged doses',
        () {
      final vm = AdherenceViewModel();
      final now = DateTime.now();
      final day0 = DateTime(now.year, now.month, now.day, 8, 0);
      final day1 = DateTime(now.year, now.month, now.day - 1, 8, 0);
      final day2 = DateTime(now.year, now.month, now.day - 2, 8, 0);

      final logsPartialToday = [
        IntakeLog(
          id: 'd0_1',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Med',
          doseAmount: 1.0,
          scheduledTime: day0,
          recordedTime: day0,
          status: DoseStatus.taken,
        ),
        IntakeLog(
          id: 'd1_1',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Med',
          doseAmount: 1.0,
          scheduledTime: day1,
          recordedTime: day1,
          status: DoseStatus.taken,
        ),
        IntakeLog(
          id: 'd2_1',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Med',
          doseAmount: 1.0,
          scheduledTime: day2,
          recordedTime: day2,
          status: DoseStatus.taken,
        ),
      ];

      expect(
        vm.calculateStreakDays(logsPartialToday, todayExpectedCount: 3),
        2,
      );

      final logsCompleteToday = [
        ...logsPartialToday,
        IntakeLog(
          id: 'd0_2',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Med',
          doseAmount: 1.0,
          scheduledTime: day0.add(const Duration(hours: 4)),
          recordedTime: day0.add(const Duration(hours: 4)),
          status: DoseStatus.taken,
        ),
        IntakeLog(
          id: 'd0_3',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Med',
          doseAmount: 1.0,
          scheduledTime: day0.add(const Duration(hours: 8)),
          recordedTime: day0.add(const Duration(hours: 8)),
          status: DoseStatus.taken,
        ),
      ];

      expect(
        vm.calculateStreakDays(logsCompleteToday, todayExpectedCount: 3),
        3,
      );
    });
  });

  group('IntakeViewModel boolean mutation status regression', () {
    test('takeDose and undoTakenDose return false on repository failure',
        () async {
      final invRepo = MockInventoryRepository();
      final intakeRepo = _FailingIntakeRepository(invRepo);
      final vm = IntakeViewModel(intakeRepository: intakeRepo);
      final med = _buildTestMedication(
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00'],
          startDate: DateTime(2026, 10, 1),
        ),
      );
      final schedTime = DateTime(2026, 10, 15, 8, 0);

      // Successful write returns true
      final ok = await vm.takeDose(
        medication: med,
        scheduledTime: schedTime,
        atTime: schedTime,
      );
      expect(ok, isTrue);

      // Failed undo returns false and sets errorMessage
      intakeRepo.shouldThrowOnWrite = true;
      final recordedLog = (await intakeRepo.getIntakeLogs(med.userId)).first;
      final undoOk = await vm.undoTakenDose(
        medication: med,
        takenLog: recordedLog,
      );
      expect(undoOk, isFalse);
      expect(vm.errorMessage, isNotNull);

      // Failed takeDose returns false
      final failTake = await vm.takeDose(
        medication: med,
        scheduledTime: schedTime.add(const Duration(days: 1)),
        atTime: schedTime.add(const Duration(days: 1)),
      );
      expect(failTake, isFalse);
    });
  });

  group('CaregiverViewModel activeProfileEmail resolution', () {
    test('resolves active dependent email and clears when returning to self',
        () async {
      final caregiverRepo = MockCaregiverRepository();
      final userRepo = MockUserRepository();
      userRepo.seedProfile(UserProfile(
        id: 'patient_alice',
        email: 'alice@example.com',
        displayName: 'Alice Santos',
        createdAt: DateTime(2026, 1, 1),
      ));
      caregiverRepo.seedRelationship(CaregiverRelationship(
        id: 'patient_alice_caregiver_bob',
        patientId: 'patient_alice',
        patientName: 'Alice Santos',
        caregiverId: 'caregiver_bob',
        caregiverName: 'Bob Santos',
        status: 'active',
        createdAt: DateTime(2026, 1, 2),
      ));

      final vm = CaregiverViewModel(
        caregiverRepository: caregiverRepo,
        userRepository: userRepo,
      );
      await vm.loadCaregiverData('caregiver_bob');
      expect(vm.activeProfileEmail, isNull);

      vm.setActiveProfile('patient_alice', 'Alice Santos');
      expect(vm.isCaregiverMode, isTrue);
      expect(vm.activeProfileEmail, 'alice@example.com');

      vm.setActiveProfile(null, null);
      expect(vm.isCaregiverMode, isFalse);
      expect(vm.activeProfileEmail, isNull);
    });
  });

  group('MissedDoseReconciler updatedAt anchor and clean notes regression',
      () {
    test('skips backfill before newer DoseSchedule.updatedAt', () async {
      final medRepo = MockMedicationRepository();
      final invRepo = MockInventoryRepository();
      final intakeRepo = MockIntakeRepository(invRepo);
      final reconciler = MissedDoseReconciler(
        medicationRepository: medRepo,
        intakeRepository: intakeRepo,
      );

      final now = DateTime.now();
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      final hh = twoHoursAgo.hour.toString().padLeft(2, '0');
      final mm = twoHoursAgo.minute.toString().padLeft(2, '0');

      final editedMed = _buildTestMedication(
        createdAt: now.subtract(const Duration(days: 5)),
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: ['$hh:$mm'],
          startDate: now.subtract(const Duration(days: 5)),
          // Edited 10 minutes ago -> must not retroactively create missed logs
          updatedAt: now.subtract(const Duration(minutes: 10)),
        ),
      );
      medRepo.seedMedications([editedMed]);

      final count = await reconciler.reconcileMissedDoses(editedMed.userId);
      expect(count, 0);
      expect(await intakeRepo.getIntakeLogs(editedMed.userId), isEmpty);
    });

    test('reconciles overdue occurrence after anchor with null notes',
        () async {
      final medRepo = MockMedicationRepository();
      final invRepo = MockInventoryRepository();
      final intakeRepo = MockIntakeRepository(invRepo);
      final reconciler = MissedDoseReconciler(
        medicationRepository: medRepo,
        intakeRepository: intakeRepo,
      );

      final now = DateTime.now();
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      final hh = twoHoursAgo.hour.toString().padLeft(2, '0');
      final mm = twoHoursAgo.minute.toString().padLeft(2, '0');

      final overdueMed = _buildTestMedication(
        createdAt: now.subtract(const Duration(days: 5)),
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: ['$hh:$mm'],
          startDate: now.subtract(const Duration(days: 5)),
          updatedAt: now.subtract(const Duration(hours: 24)),
        ),
      );
      medRepo.seedMedications([overdueMed]);

      final count = await reconciler.reconcileMissedDoses(overdueMed.userId);
      expect(count, greaterThanOrEqualTo(1));

      final logs = await intakeRepo.getIntakeLogs(overdueMed.userId);
      expect(logs, isNotEmpty);
      expect(logs.every((l) => l.status == DoseStatus.missed), isTrue);
      expect(logs.every((l) => l.notes == null), isTrue);
    });
  });
}
