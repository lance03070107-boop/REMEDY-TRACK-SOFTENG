import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/core/errors/clinical_safety_exception.dart';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/medication.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/services/alarm_scheduler.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Clinical Safety Invariants & Reliability Unit Tests', () {
    late MockInventoryRepository inventoryRepo;
    late MockIntakeRepository intakeRepo;
    late AlarmScheduler alarmScheduler;
    late IntakeViewModel intakeVm;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      inventoryRepo = MockInventoryRepository();
      intakeRepo = MockIntakeRepository(inventoryRepo);
      alarmScheduler = AlarmScheduler();
      intakeVm = IntakeViewModel(
        intakeRepository: intakeRepo,
        alarmScheduler: alarmScheduler,
      );
    });

    final testMed = Medication(
      id: 'med_paracetamol_500',
      userId: 'patient_maria_101',
      name: 'Paracetamol',
      genericName: 'Acetaminophen',
      strength: '500mg',
      form: MedicationForm.tablet,
      doseAmount: 1.0,
      instructions: 'Take 1 tablet with water',
      schedule: DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['08:00', '16:00', '23:00'],
        startDate: DateTime(2026, 1, 1),
      ),
      isPrn: false,
      dailyMaxDose: 4.0,
      minIntervalHours: 4,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final testPrnMed = Medication(
      id: 'med_tramadol_50',
      userId: 'patient_maria_101',
      name: 'Tramadol',
      genericName: 'Tramadol HCl',
      strength: '50mg',
      form: MedicationForm.capsule,
      doseAmount: 1.0,
      instructions: 'Take as needed for severe pain',
      schedule: null,
      isPrn: true,
      dailyMaxDose: 4.0,
      minIntervalHours: 6,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    // =========================================================================
    // 1. DUPLICATE DOSE PROTECTION (< 30 MINUTES)
    // =========================================================================
    group('Duplicate Dose Protection (<30m threshold)', () {
      final now = DateTime(2026, 10, 11, 14, 0, 0);

      test('flags duplicate dose if logged within 30 minutes', () {
        final recentLog = IntakeLog(
          id: 'log_dup_1',
          userId: testMed.userId,
          medicationId: testMed.id,
          medicationName: testMed.name,
          doseAmount: 1.0,
          scheduledTime: now.subtract(const Duration(minutes: 15)),
          recordedTime: now.subtract(const Duration(minutes: 15)),
          status: DoseStatus.taken,
        );
        intakeVm.setLogsForTesting([recentLog]);

        expect(intakeVm.checkIsDuplicateDose(testMed.id, atTime: now), isTrue);
      });

      test('does not flag duplicate dose if logged beyond 30 minutes', () {
        final olderLog = IntakeLog(
          id: 'log_dup_2',
          userId: testMed.userId,
          medicationId: testMed.id,
          medicationName: testMed.name,
          doseAmount: 1.0,
          scheduledTime: now.subtract(const Duration(minutes: 35)),
          recordedTime: now.subtract(const Duration(minutes: 35)),
          status: DoseStatus.taken,
        );
        intakeVm.setLogsForTesting([olderLog]);

        expect(intakeVm.checkIsDuplicateDose(testMed.id, atTime: now), isFalse);
      });

      test('does not flag duplicate dose if previous log was skipped', () {
        final skippedLog = IntakeLog(
          id: 'log_dup_3',
          userId: testMed.userId,
          medicationId: testMed.id,
          medicationName: testMed.name,
          doseAmount: 1.0,
          scheduledTime: now.subtract(const Duration(minutes: 10)),
          recordedTime: now.subtract(const Duration(minutes: 10)),
          status: DoseStatus.skipped,
        );
        intakeVm.setLogsForTesting([skippedLog]);

        expect(intakeVm.checkIsDuplicateDose(testMed.id, atTime: now), isFalse);
      });

      test(
          'validateScheduledDoseSafety throws ClinicalSafetyException on duplicate dose',
          () {
        final recentLog = IntakeLog(
          id: 'log_dup_4',
          userId: testMed.userId,
          medicationId: testMed.id,
          medicationName: testMed.name,
          doseAmount: 1.0,
          scheduledTime: now.subtract(const Duration(minutes: 12)),
          recordedTime: now.subtract(const Duration(minutes: 12)),
          status: DoseStatus.taken,
        );
        intakeVm.setLogsForTesting([recentLog]);

        expect(
          () => intakeVm.validateScheduledDoseSafety(
            medication: testMed,
            scheduledTime: now,
            nextScheduledTime: now.add(const Duration(hours: 6)),
            currentTime: now,
          ),
          throwsA(
            isA<ClinicalSafetyException>().having(
              (e) => e.risk,
              'risk',
              ClinicalSafetyRisk.duplicateDose,
            ),
          ),
        );
      });
    });

    // =========================================================================
    // 2. LATE DOSE GRACE PERIOD (60 MINUTES)
    // =========================================================================
    group('Late Dose Grace Period (60m window)', () {
      final scheduled = DateTime(2026, 10, 11, 8, 0, 0);

      test('dose taken within 60 minutes is marked as taken', () async {
        final takenTime = scheduled.add(const Duration(minutes: 45));
        await intakeVm.takeDose(
          medication: testMed,
          scheduledTime: scheduled,
          atTime: takenTime,
        );

        final logs = await intakeRepo.getIntakeLogs(testMed.userId);
        expect(logs.length, 1);
        expect(logs.first.status, DoseStatus.taken);
      });

      test('dose taken exactly at 60 minutes is marked as taken', () async {
        final takenTime = scheduled.add(const Duration(minutes: 60));
        await intakeVm.takeDose(
          medication: testMed,
          scheduledTime: scheduled,
          atTime: takenTime,
        );

        final logs = await intakeRepo.getIntakeLogs(testMed.userId);
        expect(logs.first.status, DoseStatus.taken);
      });

      test('dose taken past 60 minutes is marked as late', () async {
        final lateTime = scheduled.add(const Duration(minutes: 75));
        await intakeVm.takeDose(
          medication: testMed,
          scheduledTime: scheduled,
          atTime: lateTime,
        );

        final logs = await intakeRepo.getIntakeLogs(testMed.userId);
        expect(logs.first.status, DoseStatus.late);
      });
    });

    // =========================================================================
    // 3. SAFE-INTERVAL FRACTION (0.5) & DOSE STACKING PREVENTION
    // =========================================================================
    group('Safe-Interval Fraction (0.5) & Dose Stacking Guard', () {
      final scheduled = DateTime(2026, 10, 11, 8, 0, 0);
      final nextScheduled =
          DateTime(2026, 10, 11, 16, 0, 0); // 8-hour gap (480 mins)

      test('allows taking dose when within grace window', () {
        // At 08:30 (30 mins after scheduled, within 60 min late grace period)
        final at830 = DateTime(2026, 10, 11, 8, 30, 0);
        expect(
          () => intakeVm.validateScheduledDoseSafety(
            medication: testMed,
            scheduledTime: scheduled,
            nextScheduledTime: nextScheduled,
            currentTime: at830,
          ),
          returnsNormally,
        );
      });

      test(
          'prohibits taking dose when past missed window and provides neutral advice',
          () {
        // At 13:00 (5 hours after scheduled, past 60 min late grace period)
        final at13 = DateTime(2026, 10, 11, 13, 0, 0);

        // Throws ClinicalSafetyException with risk doseStacking and neutral advice
        expect(
          () => intakeVm.validateScheduledDoseSafety(
            medication: testMed,
            scheduledTime: scheduled,
            nextScheduledTime: nextScheduled,
            currentTime: at13,
          ),
          throwsA(
            isA<ClinicalSafetyException>()
                .having((e) => e.risk, 'risk', ClinicalSafetyRisk.doseStacking)
                .having(
                  (e) => e.clinicalRecommendation,
                  'clinicalRecommendation',
                  'Missed dose. Ask your doctor or pharmacist what to do.',
                ),
          ),
        );
      });
    });

    // =========================================================================
    // 4. PRN MINIMUM INTERVAL SAFEGUARDS (minIntervalHours)
    // =========================================================================
    group('PRN Minimum Interval Safeguards (minIntervalHours)', () {
      final now = DateTime(2026, 10, 11, 15, 0, 0);

      test('throws ClinicalSafetyException if PRN interval is violated', () {
        // Tramadol minIntervalHours = 6. Taken 3 hours ago at 12:00.
        final pastDose = IntakeLog(
          id: 'log_prn_1',
          userId: testPrnMed.userId,
          medicationId: testPrnMed.id,
          medicationName: testPrnMed.name,
          doseAmount: 1.0,
          scheduledTime: DateTime(2026, 10, 11, 12, 0, 0),
          recordedTime: DateTime(2026, 10, 11, 12, 0, 0),
          status: DoseStatus.taken,
          isPrn: true,
        );
        intakeVm.setLogsForTesting([pastDose]);

        expect(
          () => intakeVm.validatePrnSafety(testPrnMed, atTime: now),
          throwsA(
            isA<ClinicalSafetyException>()
                .having(
                    (e) => e.risk, 'risk', ClinicalSafetyRisk.prnMinInterval)
                .having((e) => e.clinicalRecommendation, 'recommendation',
                    contains('Wait another 180 minutes')),
          ),
        );
      });

      test('permits PRN dose once minimum interval has elapsed', () {
        // Taken 6 hours and 15 mins ago at 08:45
        final pastDose = IntakeLog(
          id: 'log_prn_2',
          userId: testPrnMed.userId,
          medicationId: testPrnMed.id,
          medicationName: testPrnMed.name,
          doseAmount: 1.0,
          scheduledTime: DateTime(2026, 10, 11, 8, 45, 0),
          recordedTime: DateTime(2026, 10, 11, 8, 45, 0),
          status: DoseStatus.taken,
          isPrn: true,
        );
        intakeVm.setLogsForTesting([pastDose]);

        expect(() => intakeVm.validatePrnSafety(testPrnMed, atTime: now),
            returnsNormally);
      });
    });

    // =========================================================================
    // 5. PRN ROLLING 24-HOUR MAXIMUM DOSE (dailyMaxDose)
    // =========================================================================
    group('PRN Rolling 24-Hour Daily Maximum Dose (dailyMaxDose)', () {
      final now = DateTime(2026, 10, 11, 20, 0, 0);

      test('permits doses within rolling 24-hour limit', () {
        // Daily max dose is 4.0 tablets. Three doses taken in the last 24h (total: 3.0)
        final logs = [
          IntakeLog(
            id: 'log_max_1',
            userId: testPrnMed.userId,
            medicationId: testPrnMed.id,
            medicationName: testPrnMed.name,
            doseAmount: 1.0,
            scheduledTime: now.subtract(const Duration(hours: 18)),
            recordedTime: now.subtract(const Duration(hours: 18)),
            status: DoseStatus.taken,
          ),
          IntakeLog(
            id: 'log_max_2',
            userId: testPrnMed.userId,
            medicationId: testPrnMed.id,
            medicationName: testPrnMed.name,
            doseAmount: 1.0,
            scheduledTime: now.subtract(const Duration(hours: 12)),
            recordedTime: now.subtract(const Duration(hours: 12)),
            status: DoseStatus.taken,
          ),
          IntakeLog(
            id: 'log_max_3',
            userId: testPrnMed.userId,
            medicationId: testPrnMed.id,
            medicationName: testPrnMed.name,
            doseAmount: 1.0,
            scheduledTime: now.subtract(const Duration(hours: 7)),
            recordedTime: now.subtract(const Duration(hours: 7)),
            status: DoseStatus.taken,
          ),
        ];
        intakeVm.setLogsForTesting(logs);

        // Attempting 4th dose (3.0 + 1.0 = 4.0 <= 4.0 max): should pass!
        expect(() => intakeVm.validatePrnSafety(testPrnMed, atTime: now),
            returnsNormally);
      });

      test(
          'throws ClinicalSafetyException when 24h rolling max dose is exceeded',
          () {
        // Four doses already taken in last 24h (total 4.0)
        final logs = List.generate(
          4,
          (i) => IntakeLog(
            id: 'log_max_full_$i',
            userId: testPrnMed.userId,
            medicationId: testPrnMed.id,
            medicationName: testPrnMed.name,
            doseAmount: 1.0,
            scheduledTime: now.subtract(Duration(hours: 20 - i * 4)),
            recordedTime: now.subtract(Duration(hours: 20 - i * 4)),
            status: DoseStatus.taken,
          ),
        );
        intakeVm.setLogsForTesting(logs);

        // Attempting 5th dose (4.0 + 1.0 = 5.0 > 4.0): must throw!
        expect(
          () => intakeVm.validatePrnSafety(testPrnMed, atTime: now),
          throwsA(
            isA<ClinicalSafetyException>()
                .having(
                    (e) => e.risk, 'risk', ClinicalSafetyRisk.prnMaxDailyDose)
                .having((e) => e.message, 'message',
                    contains('above the 24-hour maximum of 4')),
          ),
        );
      });

      test('ignores doses older than 24 hours in the rolling window', () {
        // Dose from 26 hours ago should NOT count toward current 24-hour limit
        final logs = [
          IntakeLog(
            id: 'log_old_1',
            userId: testPrnMed.userId,
            medicationId: testPrnMed.id,
            medicationName: testPrnMed.name,
            doseAmount: 3.0,
            scheduledTime: now.subtract(const Duration(hours: 26)),
            recordedTime: now.subtract(const Duration(hours: 26)),
            status: DoseStatus.taken,
          ),
          IntakeLog(
            id: 'log_recent_1',
            userId: testPrnMed.userId,
            medicationId: testPrnMed.id,
            medicationName: testPrnMed.name,
            doseAmount: 1.0,
            scheduledTime: now.subtract(const Duration(hours: 8)),
            recordedTime: now.subtract(const Duration(hours: 8)),
            status: DoseStatus.taken,
          ),
        ];
        intakeVm.setLogsForTesting(logs);

        // Only 1.0 tablet is in the rolling 24h window; adding 1.0 gives 2.0 <= 4.0
        expect(() => intakeVm.validatePrnSafety(testPrnMed, atTime: now),
            returnsNormally);
      });
    });

    // =========================================================================
    // 6. MIDNIGHT ROLLOVER EDGE CASES
    // =========================================================================
    group('Midnight Rollover Edge Cases', () {
      test('enforces PRN interval across midnight correctly', () {
        // Dose taken at 23:30 (Day 1)
        final nightDose = IntakeLog(
          id: 'log_midnight_1',
          userId: testPrnMed.userId,
          medicationId: testPrnMed.id,
          medicationName: testPrnMed.name,
          doseAmount: 1.0,
          scheduledTime: DateTime(2026, 10, 11, 23, 30, 0),
          recordedTime: DateTime(2026, 10, 11, 23, 30, 0),
          status: DoseStatus.taken,
          isPrn: true,
        );
        intakeVm.setLogsForTesting([nightDose]);

        // Attempting dose at 00:30 (Day 2) -> elapsed only 60 mins vs 6 hours required
        final earlyMorning = DateTime(2026, 10, 12, 0, 30, 0);

        expect(
          () => intakeVm.validatePrnSafety(testPrnMed, atTime: earlyMorning),
          throwsA(
            isA<ClinicalSafetyException>()
                .having(
                    (e) => e.risk, 'risk', ClinicalSafetyRisk.prnMinInterval)
                .having((e) => e.clinicalRecommendation, 'recommendation',
                    contains('Wait another 300 minutes')),
          ),
        );
      });
    });

    // =========================================================================
    // 7. OFFLINE QUEUE & LOCK-SCREEN BACKGROUND INTAKE FLUSH
    // =========================================================================
    group('Lock-Screen Action Background Queue & Flush', () {
      test(
          'flushes pending background intakes to repository and clears SharedPreferences',
          () async {
        final prefs = await SharedPreferences.getInstance();
        final rawQueue = [
          jsonEncode({
            'id': 'bg_intake_101',
            'userId': 'patient_maria_101',
            'medicationId': testMed.id,
            'medicationName': testMed.name,
            'doseAmount': 1.0,
            'scheduledTime': DateTime(2026, 10, 11, 8, 0, 0).toIso8601String(),
            'recordedTime': DateTime(2026, 10, 11, 8, 2, 0).toIso8601String(),
            'status': 'taken',
            'isPrn': false,
            'notes': 'Recorded from lock screen action',
          }),
        ];
        await prefs.setStringList('pending_background_intakes', rawQueue);

        // Call flush on app launch
        await intakeVm.flushPendingBackgroundIntakes('patient_maria_101');

        // Verify repository received the intake log
        final flushedLogs = await intakeRepo.getIntakeLogs('patient_maria_101');
        expect(flushedLogs.length, 1);
        expect(flushedLogs.first.id, 'bg_intake_101');
        expect(flushedLogs.first.status, DoseStatus.taken);
        expect(flushedLogs.first.notes, 'Recorded from lock screen action');

        // Verify SharedPreferences queue is emptied
        final remaining = prefs.getStringList('pending_background_intakes');
        expect(remaining, isNull);
      });
    });

    group('PRN Rounding, Sorting, and Float Tolerance Safeguards', () {
      test(
          'validatePrnSafety rounds sub-minute waits up to 1 minute and picks latest unsorted log',
          () {
        final now = DateTime(2026, 11, 13, 12, 0, 0);
        final olderLog = IntakeLog(
          id: 'log_older',
          userId: testPrnMed.userId,
          medicationId: testPrnMed.id,
          medicationName: testPrnMed.name,
          doseAmount: 1.0,
          scheduledTime: now.subtract(const Duration(hours: 10)),
          recordedTime: now.subtract(const Duration(hours: 10)),
          status: DoseStatus.taken,
          isPrn: true,
        );
        // 5h 59m 40s ago -> 20s remaining before 6h interval -> must show 1 minute, not 0.
        final newerLog = IntakeLog(
          id: 'log_newer',
          userId: testPrnMed.userId,
          medicationId: testPrnMed.id,
          medicationName: testPrnMed.name,
          doseAmount: 1.0,
          scheduledTime:
              now.subtract(const Duration(hours: 5, minutes: 59, seconds: 40)),
          recordedTime:
              now.subtract(const Duration(hours: 5, minutes: 59, seconds: 40)),
          status: DoseStatus.taken,
          isPrn: true,
        );

        // Intentionally unsorted: newer before older and older after newer
        intakeVm.setLogsForTesting([olderLog, newerLog]);

        expect(
          () => intakeVm.validatePrnSafety(testPrnMed, atTime: now),
          throwsA(
            isA<ClinicalSafetyException>()
                .having(
                    (e) => e.risk, 'risk', ClinicalSafetyRisk.prnMinInterval)
                .having((e) => e.clinicalRecommendation, 'recommendation',
                    contains('Wait another 1 minutes')),
          ),
        );
      });

      test('validatePrnSafety applies 1e-6 float tolerance on 24h daily max',
          () {
        final now = DateTime(2026, 11, 13, 20, 0, 0);
        final decimalMed = testMed.copyWith(
          id: 'med_syrup_prn',
          form: MedicationForm.syrup,
          doseAmount: 0.1,
          isPrn: true,
          minIntervalHours: 1,
          dailyMaxDose: 0.4,
        );

        // 0.1 + 0.2 = 0.30000000000000004 in IEEE 754; adding 0.1 gives ~0.4000000000000001
        intakeVm.setLogsForTesting([
          IntakeLog(
            id: 'f1',
            userId: decimalMed.userId,
            medicationId: decimalMed.id,
            medicationName: decimalMed.name,
            doseAmount: 0.1,
            scheduledTime: now.subtract(const Duration(hours: 6)),
            recordedTime: now.subtract(const Duration(hours: 6)),
            status: DoseStatus.taken,
            isPrn: true,
          ),
          IntakeLog(
            id: 'f2',
            userId: decimalMed.userId,
            medicationId: decimalMed.id,
            medicationName: decimalMed.name,
            doseAmount: 0.2,
            scheduledTime: now.subtract(const Duration(hours: 3)),
            recordedTime: now.subtract(const Duration(hours: 3)),
            status: DoseStatus.taken,
            isPrn: true,
          ),
        ]);

        expect(() => intakeVm.validatePrnSafety(decimalMed, atTime: now),
            returnsNormally);
      });

      test(
          'MedicationViewModel.validatePrnIntake enforces >= 1 minute wait and daily max',
          () {
        final medVm = MedicationViewModel(
          medicationRepository: MockMedicationRepository(),
          inventoryRepository: inventoryRepo,
          alarmScheduler: alarmScheduler,
        );
        final now = DateTime.now();

        final subMinuteWaitResult = medVm.validatePrnIntake(
          testPrnMed,
          [
            IntakeLog(
              id: 'log_sub_min',
              userId: testPrnMed.userId,
              medicationId: testPrnMed.id,
              medicationName: testPrnMed.name,
              doseAmount: 1.0,
              scheduledTime: now.subtract(
                  const Duration(hours: 5, minutes: 59, seconds: 40)),
              recordedTime: now.subtract(
                  const Duration(hours: 5, minutes: 59, seconds: 40)),
              status: DoseStatus.taken,
              isPrn: true,
            ),
          ],
        );

        expect(subMinuteWaitResult.isSafe, isFalse);
        expect(subMinuteWaitResult.warningMessage, contains('1 more minute'));

        final overDailyResult = medVm.validatePrnIntake(
          testPrnMed,
          List.generate(
            4,
            (i) => IntakeLog(
              id: 'log_vm_max_$i',
              userId: testPrnMed.userId,
              medicationId: testPrnMed.id,
              medicationName: testPrnMed.name,
              doseAmount: 1.0,
              scheduledTime: now.subtract(Duration(hours: 18 - i * 2)),
              recordedTime: now.subtract(Duration(hours: 18 - i * 2)),
              status: DoseStatus.taken,
              isPrn: true,
            ),
          ),
        );

        expect(overDailyResult.isSafe, isFalse);
        expect(overDailyResult.warningMessage, contains('24-hour safe limit'));
      });
    });
  });
}
