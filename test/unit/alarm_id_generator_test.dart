import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/services/alarm_id_generator.dart';

void main() {
  group('AlarmIdGenerator Tests', () {
    test(
        'generateDoseAlarmId produces positive ID within valid Android/iOS range',
        () {
      final scheduledTime = DateTime(2026, 10, 16, 8, 30);
      final id = AlarmIdGenerator.generateDoseAlarmId(
        medicationId: 'med_amlodipine_001',
        scheduledDateTime: scheduledTime,
        timeIndex: 0,
      );

      expect(id, isPositive);
      expect(id, greaterThanOrEqualTo(1000));
      expect(id, lessThanOrEqualTo(1500000000));
    });

    test('generateDoseAlarmId is strictly deterministic for identical inputs',
        () {
      final scheduledTime = DateTime(2026, 10, 16, 12, 0);
      final id1 = AlarmIdGenerator.generateDoseAlarmId(
        medicationId: 'med_metformin_500',
        scheduledDateTime: scheduledTime,
        timeIndex: 1,
      );
      final id2 = AlarmIdGenerator.generateDoseAlarmId(
        medicationId: 'med_metformin_500',
        scheduledDateTime: scheduledTime,
        timeIndex: 1,
      );

      expect(id1, equals(id2));
    });

    test(
        'Escalation ID does not exceed 32-bit signed integer maximum (2,147,483,647)',
        () {
      final scheduledTime = DateTime(2026, 12, 31, 23, 59);
      final primaryId = AlarmIdGenerator.generateDoseAlarmId(
        medicationId: 'med_losartan_100',
        scheduledDateTime: scheduledTime,
        timeIndex: 0,
      );
      final escalationId = AlarmIdGenerator.getEscalationId(primaryId);

      expect(
          escalationId, equals(primaryId + AlarmIdGenerator.escalationOffset));
      expect(escalationId, lessThan(0x7FFFFFFF)); // Under INT32_MAX
      expect(escalationId, isPositive);
    });

    test('NEW-5: 30-bit masking guarantees positive integer under Int32 max',
        () {
      // Test 100 diverse arbitrary strings, special characters, and boundary dates
      for (int i = 0; i < 100; i++) {
        final id = AlarmIdGenerator.generateDoseAlarmId(
          medicationId: 'med_unicode_💊_test_$i',
          scheduledDateTime: DateTime(2026, 1, 1).add(Duration(days: i * 17)),
          timeIndex: i % 5,
        );
        expect(id, isPositive);
        expect(id, lessThanOrEqualTo(1500000000));
        final escId = AlarmIdGenerator.getEscalationId(id);
        expect(escId, lessThan(2147483647)); // Strictly below Int32.MAX
        expect(escId, isPositive);
      }
    });

    test('getPrimaryId resolves primary ID correctly', () {
      const primaryId = 2500000;
      final escalationId = AlarmIdGenerator.getEscalationId(primaryId);
      expect(
          escalationId, equals(primaryId + AlarmIdGenerator.escalationOffset));
      expect(AlarmIdGenerator.isEscalationAlarmId(primaryId), isFalse);
      expect(AlarmIdGenerator.isEscalationAlarmId(escalationId), isTrue);
      expect(AlarmIdGenerator.getPrimaryId(escalationId, isEscalation: true),
          equals(primaryId));
      expect(AlarmIdGenerator.getPrimaryId(escalationId), equals(primaryId));
      expect(AlarmIdGenerator.getPrimaryId(primaryId), equals(primaryId));
    });

    test('Generates collision-free IDs across 250 realistic dose events', () {
      final seenIds = <int>{};
      final baseDate = DateTime(2026, 1, 1, 8, 0);

      for (int i = 0; i < 50; i++) {
        for (int hour = 6; hour <= 22; hour += 4) {
          final time = baseDate.add(Duration(days: i, hours: hour));
          final id = AlarmIdGenerator.generateDoseAlarmId(
            medicationId: 'med_patient_daily_$i',
            scheduledDateTime: time,
            timeIndex: hour,
          );
          expect(seenIds.contains(id), isFalse,
              reason:
                  'Collision detected for med_patient_daily_$i at $time (ID: $id)');
          seenIds.add(id);
        }
      }

      expect(seenIds.length, equals(250));
    });
  });
}
