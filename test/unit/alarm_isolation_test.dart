import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/services/alarm_scheduler.dart';
import 'package:remedy_track/services/local_medication_cache.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';
import '../mocks/test_mock_repositories.dart';

class _SpyAlarmScheduler extends AlarmScheduler {
  final List<List<Medication>> rescheduleCalls = [];
  int cancelAllCount = 0;

  @override
  Future<void> rescheduleAllAlarms(List<Medication> activeMedications) async {
    rescheduleCalls.add(List<Medication>.from(activeMedications));
  }

  @override
  Future<void> cancelAllAlarms({bool clearAcknowledged = true}) async {
    cancelAllCount++;
    if (clearAcknowledged) {
      await AlarmScheduler.clearAcknowledgedDoses();
    }
  }
}

class _PerUserMedicationRepo extends MockMedicationRepository {
  final Map<String, List<Medication>> byUser;

  _PerUserMedicationRepo(this.byUser);

  @override
  Stream<List<Medication>> streamMedications(String userId) {
    return Stream<List<Medication>>.value(byUser[userId] ?? const []);
  }

  @override
  Future<List<Medication>> getMedications(String userId) async {
    return byUser[userId] ?? const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Alarm Isolation & Acknowledged Dose Deduplication', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AlarmScheduler.clearAcknowledgedDoses();
    });

    test(
        'markDoseAcknowledged tracks slot-handled (snooze) vs terminal (taken/skip) states cleanly',
        () async {
      final now = DateTime.now();
      final sched = DateTime(now.year, now.month, now.day, now.hour)
          .add(const Duration(hours: 2));
      const medId = 'med_isolation_1';

      expect(AlarmScheduler.isDoseSlotHandled(medId, sched), isFalse);
      expect(AlarmScheduler.isDoseTerminal(medId, sched), isFalse);

      // Snooze marks original slot handled while staying non-terminal
      await AlarmScheduler.markDoseAcknowledged(medId, sched, terminal: false);
      expect(AlarmScheduler.isDoseSlotHandled(medId, sched), isTrue);
      expect(AlarmScheduler.isDoseTerminal(medId, sched), isFalse);

      // Re-hydrating from SharedPreferences preserves state across restarts
      await AlarmScheduler.refreshAcknowledgedDosesFromPrefs(
        reloadPrefs: false,
      );
      expect(AlarmScheduler.isDoseSlotHandled(medId, sched), isTrue);
      expect(AlarmScheduler.isDoseTerminal(medId, sched), isFalse);

      // Marking taken/skipped elevates state to terminal
      await AlarmScheduler.markDoseAcknowledged(medId, sched, terminal: true);
      expect(AlarmScheduler.isDoseSlotHandled(medId, sched), isTrue);
      expect(AlarmScheduler.isDoseTerminal(medId, sched), isTrue);

      // Clearing resets both flags cleanly
      await AlarmScheduler.clearAcknowledgedDoses();
      expect(AlarmScheduler.isDoseSlotHandled(medId, sched), isFalse);
      expect(AlarmScheduler.isDoseTerminal(medId, sched), isFalse);
    });

    test(
        'Caregiver Mode (isOwnProfile: false) never schedules dependent alarms onto caregiver phone',
        () async {
      final caregiverMed = Medication(
        id: 'med_caregiver_own',
        userId: 'caregiver_uid',
        name: 'Vitamin D3',
        strength: '1000 IU',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: DateTime(2026, 11, 14),
        updatedAt: DateTime(2026, 11, 14),
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['09:00'],
          startDate: DateTime(2026, 11, 14),
        ),
      );
      final patientMed = Medication(
        id: 'med_patient_dependent',
        userId: 'patient_uid',
        name: 'Metformin',
        strength: '500 mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: DateTime(2026, 11, 14),
        updatedAt: DateTime(2026, 11, 14),
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00'],
          startDate: DateTime(2026, 11, 14),
        ),
      );

      final medRepo = _PerUserMedicationRepo({
        'caregiver_uid': [caregiverMed],
        'patient_uid': [patientMed],
      });
      final invRepo = MockInventoryRepository();
      final spyScheduler = _SpyAlarmScheduler();

      final vm = MedicationViewModel(
        medicationRepository: medRepo,
        inventoryRepository: invRepo,
        alarmScheduler: spyScheduler,
      );
      addTearDown(vm.dispose);

      // 1. Watching patient profile must NOT touch LocalMedicationCache or AlarmScheduler
      vm.listenToMedications('patient_uid', isOwnProfile: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.medications.map((m) => m.id), contains('med_patient_dependent'));
      expect(spyScheduler.rescheduleCalls, isEmpty);
      expect(await LocalMedicationCache.loadMedications(), isEmpty);

      // 2. Switching back to own profile MUST reschedule own alarms and update cache
      vm.listenToMedications('caregiver_uid', isOwnProfile: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.medications.map((m) => m.id), contains('med_caregiver_own'));
      expect(spyScheduler.rescheduleCalls, hasLength(1));
      expect(spyScheduler.rescheduleCalls.first.map((m) => m.id),
          equals(['med_caregiver_own']));
    });
  });
}
