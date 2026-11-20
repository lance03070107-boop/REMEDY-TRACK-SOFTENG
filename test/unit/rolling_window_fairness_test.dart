import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/scheduling/schedule_expander.dart';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/medication.dart';

void main() {
  group('Rolling Window Fairness Tests (A1)', () {
    test(
        'fair round-robin scheduling ensures low-frequency medications are not starved by high-frequency medications',
        () {
      final now = DateTime(2026, 10, 1, 0, 0);
      final windowEnd = now.add(const Duration(days: 7));

      // Med A: High frequency (4 doses/day = 28 doses across 7 days)
      final medA = Medication(
        id: 'med_high_freq',
        userId: 'user_test',
        name: 'Metformin',
        strength: '500 mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: now,
        updatedAt: now,
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00', '12:00', '16:00', '20:00'],
          startDate: now,
        ),
      );

      // Med B: Low frequency (1 dose/day in evening = 7 doses across 7 days)
      final medB = Medication(
        id: 'med_low_freq_1',
        userId: 'user_test',
        name: 'Atorvastatin',
        strength: '20 mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: now,
        updatedAt: now,
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['21:00'],
          startDate: now,
        ),
      );

      // Med C: Low frequency (1 dose/day in morning = 7 doses across 7 days)
      final medC = Medication(
        id: 'med_low_freq_2',
        userId: 'user_test',
        name: 'Amlodipine',
        strength: '5 mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: now,
        updatedAt: now,
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00'],
          startDate: now,
        ),
      );

      final medications = [medA, medB, medC];

      // 1. Gather all occurrences per medication using ScheduleExpander
      final Map<String, List<ScheduledDoseOccurrence>> medOccurrences = {};
      for (final med in medications) {
        final occurrences = ScheduleExpander.expandOccurrences(
          medication: med,
          start: now,
          end: windowEnd,
        );
        medOccurrences[med.id] = List.from(occurrences);
      }

      expect(medOccurrences['med_high_freq']!.length, equals(28));
      expect(medOccurrences['med_low_freq_1']!.length, equals(7));
      expect(medOccurrences['med_low_freq_2']!.length, equals(7));

      // 2. Perform fair round-robin scheduling capped at 30 alarms
      const maxAlarms = 30;
      final List<ScheduledDoseOccurrence> scheduled = [];
      final activeMedIds = medOccurrences.keys.toList();

      while (scheduled.length < maxAlarms &&
          medOccurrences.values.any((list) => list.isNotEmpty)) {
        bool addedAny = false;
        for (final medId in activeMedIds) {
          final list = medOccurrences[medId];
          if (list != null && list.isNotEmpty) {
            scheduled.add(list.removeAt(0));
            addedAny = true;
            if (scheduled.length >= maxAlarms) break;
          }
        }
        if (!addedAny) break;
      }

      expect(scheduled.length, equals(maxAlarms));

      // Count scheduled alarms per medication
      final countA =
          scheduled.where((o) => o.medication.id == 'med_high_freq').length;
      final countB =
          scheduled.where((o) => o.medication.id == 'med_low_freq_1').length;
      final countC =
          scheduled.where((o) => o.medication.id == 'med_low_freq_2').length;

      // In a purely chronological sort, med A would have taken 24 of the 30 slots in 6 days,
      // and med B & C would only have 3 slots each.
      // In fair round-robin:
      // Med B has 7 total doses -> receives all 7 doses (covered for full 7 days!)
      // Med C has 7 total doses -> receives all 7 doses (covered for full 7 days!)
      // Med A receives the remaining 16 slots!
      expect(countB, equals(7));
      expect(countC, equals(7));
      expect(countA, equals(16));

      // Verify that med B and med C are protected into day 7
      final medBLast =
          scheduled.where((o) => o.medication.id == 'med_low_freq_1').last;
      expect(medBLast.scheduledDateTime.day, equals(7));

      final medCLast =
          scheduled.where((o) => o.medication.id == 'med_low_freq_2').last;
      expect(medCLast.scheduledDateTime.day, equals(7));
    });
  });
}
