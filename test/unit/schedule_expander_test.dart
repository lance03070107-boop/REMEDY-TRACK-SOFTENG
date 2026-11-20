import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/scheduling/schedule_expander.dart';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/medication.dart';

void main() {
  group('ScheduleExpander - parseTimeOfDay', () {
    test('parses standard 24h times correctly', () {
      expect(ScheduleExpander.parseTimeOfDay('08:00'), equals((8, 0)));
      expect(ScheduleExpander.parseTimeOfDay('13:45'), equals((13, 45)));
      expect(ScheduleExpander.parseTimeOfDay('00:00'), equals((0, 0)));
      expect(ScheduleExpander.parseTimeOfDay('23:59'), equals((23, 59)));
    });

    test('parses single digit hours/minutes safely', () {
      expect(ScheduleExpander.parseTimeOfDay('8:5'), equals((8, 5)));
    });

    test('returns null for invalid strings without throwing', () {
      expect(ScheduleExpander.parseTimeOfDay(''), isNull);
      expect(ScheduleExpander.parseTimeOfDay('24:00'), isNull);
      expect(ScheduleExpander.parseTimeOfDay('12:60'), isNull);
      expect(ScheduleExpander.parseTimeOfDay('-1:00'), isNull);
      expect(ScheduleExpander.parseTimeOfDay('abc:def'), isNull);
      expect(ScheduleExpander.parseTimeOfDay('08:00:00'), isNull);
      expect(ScheduleExpander.parseTimeOfDay('noon'), isNull);
    });
  });

  group('ScheduleExpander - isScheduledOnDate', () {
    final baseStart = DateTime(2026, 10, 1);

    test('daily frequency honors start and end dates', () {
      final schedule = DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['08:00'],
        startDate: baseStart,
        endDate: DateTime(2026, 10, 15),
      );

      // Before start date -> false
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 9, 30)),
          isFalse);
      // On start date -> true
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 1)),
          isTrue);
      // In middle -> true
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 10)),
          isTrue);
      // On end date -> true
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 15)),
          isTrue);
      // After end date -> false
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 16)),
          isFalse);
    });

    test('specificWeekdays matches specified days of week', () {
      // 2026-10-01 is Thursday (weekday 4)
      final schedule = DoseSchedule(
        frequency: ScheduleFrequency.specificWeekdays,
        timesOfDay: const ['09:00'],
        weekdays: const [DateTime.monday, DateTime.wednesday, DateTime.friday],
        startDate: baseStart,
      );

      // 2026-10-05 is Monday
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 5)),
          isTrue);
      // 2026-10-06 is Tuesday
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 6)),
          isFalse);
      // 2026-10-07 is Wednesday
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 7)),
          isTrue);
      // 2026-10-09 is Friday
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 9)),
          isTrue);
      // 2026-10-11 is Sunday
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 11)),
          isFalse);
    });

    test('everyXDays calculates days accurately without DST drift', () {
      final schedule = DoseSchedule(
        frequency: ScheduleFrequency.everyXDays,
        timesOfDay: const ['10:00'],
        startDate: baseStart,
        intervalValue: 3,
      );

      // Day 0 (Oct 1) -> true
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 1)),
          isTrue);
      // Day 1 (Oct 2) -> false
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 2)),
          isFalse);
      // Day 2 (Oct 3) -> false
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 3)),
          isFalse);
      // Day 3 (Oct 4) -> true
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 4)),
          isTrue);
      // Day 6 (Oct 7) -> true
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 7)),
          isTrue);
    });

    test('cycleBased accurately handles active and rest phases', () {
      final schedule = DoseSchedule(
        frequency: ScheduleFrequency.cycleBased,
        timesOfDay: const ['08:00'],
        startDate: baseStart,
        cycleActiveDays: 21,
        cycleRestDays: 7,
      );

      // Days 0..20 are active (Oct 1 to Oct 21)
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 1)),
          isTrue);
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 21)),
          isTrue);

      // Days 21..27 are rest (Oct 22 to Oct 28)
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 22)),
          isFalse);
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 28)),
          isFalse);

      // Day 28 starts next active cycle (Oct 29)
      expect(
          ScheduleExpander.isScheduledOnDate(schedule, DateTime(2026, 10, 29)),
          isTrue);
    });
  });

  group('ScheduleExpander - expandOccurrences', () {
    test(
        'expands ordered occurrences within window and computes deterministic IDs',
        () {
      final med = Medication(
        id: 'med_test_1',
        userId: 'user_1',
        name: 'Metformin',
        strength: '500 mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00', '20:00'],
          startDate: DateTime(2026, 10, 1),
        ),
      );

      final start = DateTime(2026, 10, 1, 0, 0);
      final end = DateTime(2026, 10, 2, 23, 59);

      final occurrences = ScheduleExpander.expandOccurrences(
        medication: med,
        start: start,
        end: end,
      );

      expect(occurrences.length, equals(4));
      expect(occurrences[0].scheduledDateTime,
          equals(DateTime(2026, 10, 1, 8, 0)));
      expect(occurrences[0].timeIndex, equals(0));
      expect(occurrences[0].notificationId, isPositive);

      expect(occurrences[1].scheduledDateTime,
          equals(DateTime(2026, 10, 1, 20, 0)));
      expect(occurrences[1].timeIndex, equals(1));
      expect(occurrences[1].notificationId, isPositive);
      expect(occurrences[1].notificationId,
          isNot(equals(occurrences[0].notificationId)));

      expect(occurrences[2].scheduledDateTime,
          equals(DateTime(2026, 10, 2, 8, 0)));
      expect(occurrences[3].scheduledDateTime,
          equals(DateTime(2026, 10, 2, 20, 0)));
    });

    test('excludes doses occurring before createdAfter anchor', () {
      final med = Medication(
        id: 'med_test_midday',
        userId: 'user_1',
        name: 'Amlodipine',
        strength: '5 mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        createdAt: DateTime(2026, 10, 1, 14, 30), // Created at 2:30 PM
        updatedAt: DateTime(2026, 10, 1, 14, 30),
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00', '18:00'],
          startDate: DateTime(2026, 10, 1),
        ),
      );

      final start = DateTime(2026, 10, 1, 0, 0);
      final end = DateTime(2026, 10, 1, 23, 59);

      final occurrences = ScheduleExpander.expandOccurrences(
        medication: med,
        start: start,
        end: end,
        createdAfter: med.createdAt,
      );

      // 8:00 AM was before creation (14:30), so only 18:00 (6 PM) should be returned
      expect(occurrences.length, equals(1));
      expect(occurrences.first.scheduledDateTime,
          equals(DateTime(2026, 10, 1, 18, 0)));
    });

    test(
        'everyXHours expands single anchor start time into 24-hour interval occurrences',
        () {
      final schedule = DoseSchedule(
        frequency: ScheduleFrequency.everyXHours,
        timesOfDay: const ['08:00'],
        intervalValue: 6,
        startDate: DateTime(2026, 10, 1),
      );

      final effectiveSlots = ScheduleExpander.effectiveTimesOfDay(schedule);
      expect(effectiveSlots, equals(['02:00', '08:00', '14:00', '20:00']));

      final med = Medication(
        id: 'med_every_6h',
        userId: 'user_1',
        name: 'Amoxicillin',
        genericName: 'Amoxicillin Trihydrate',
        strength: '500mg',
        form: MedicationForm.capsule,
        doseAmount: 1.0,
        instructions: 'Take with food',
        notes: '7-day antibiotic course',
        createdAt: DateTime(2026, 10, 1, 0, 0),
        updatedAt: DateTime(2026, 10, 1, 0, 0),
        schedule: schedule,
      );

      final occurrences = ScheduleExpander.expandOccurrences(
        medication: med,
        start: DateTime(2026, 10, 1, 0, 0),
        end: DateTime(2026, 10, 1, 23, 59),
      );
      expect(occurrences.length, equals(4));
      expect(
        occurrences.map((o) => o.scheduledDateTime.hour).toList(),
        equals([2, 8, 14, 20]),
      );

      final rangeTimes = ScheduleExpander.getOccurrencesInRange(
        schedule: schedule,
        start: DateTime(2026, 10, 1, 0, 0),
        end: DateTime(2026, 10, 1, 23, 59),
      );
      expect(rangeTimes.length, equals(4));
    });
  });
}
