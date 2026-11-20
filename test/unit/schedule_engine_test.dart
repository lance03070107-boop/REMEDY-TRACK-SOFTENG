import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/models/dose_schedule.dart';

void main() {
  group('ScheduleEngine and Safe-Interval Tests', () {
    test('DoseSchedule correctly serializes and deserializes daily frequency',
        () {
      final schedule = DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['08:00', '20:00'],
        startDate: DateTime(2026, 1, 1),
      );

      final json = schedule.toJson();
      final reconstructed = DoseSchedule.fromJson(json);

      expect(reconstructed.frequency, ScheduleFrequency.daily);
      expect(reconstructed.timesOfDay.length, 2);
      expect(reconstructed.timesOfDay.first, '08:00');
    });

    test(
        'DoseSchedule correctly stores cycle-based parameters (21 days on, 7 days off)',
        () {
      final schedule = DoseSchedule(
        frequency: ScheduleFrequency.cycleBased,
        timesOfDay: const ['09:00'],
        cycleActiveDays: 21,
        cycleRestDays: 7,
        startDate: DateTime(2026, 1, 1),
      );

      expect(schedule.cycleActiveDays, 21);
      expect(schedule.cycleRestDays, 7);
      expect(schedule.frequency, ScheduleFrequency.cycleBased);
    });
  });
}
