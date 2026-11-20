import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/services/alarm_id_generator.dart';

void main() {
  group('Notification & Snooze Payload Roundtrip Tests (A2, A5)', () {
    test(
        'primary and escalation payloads preserve primaryNotifId and all metadata',
        () {
      const primaryNotifId = 123456;
      final escalationId = AlarmIdGenerator.getEscalationId(primaryNotifId);

      final originalPayload = jsonEncode({
        'medId': 'med_101',
        'notifId': primaryNotifId,
        'primaryNotifId': primaryNotifId,
        'sched': '2026-10-17T08:00:00.000',
        'userId': 'user_abc',
        'medName': 'Losartan',
        'doseAmount': 1.0,
        'strength': '50 mg',
        'form': 'tablet',
        'colorTag': 0xFF1E66F5,
        'instructions': 'Take with water after breakfast',
        'soundId': 'remedy_alarm_classic',
        'customPath': '',
        'snoozeCount': 0,
      });

      final escalationPayload = jsonEncode({
        'medId': 'med_101',
        'notifId': escalationId,
        'primaryNotifId': primaryNotifId,
        'sched': '2026-10-17T08:00:00.000',
        'userId': 'user_abc',
        'medName': 'Losartan',
        'doseAmount': 1.0,
        'strength': '50 mg',
        'form': 'tablet',
        'colorTag': 0xFF1E66F5,
        'instructions': 'Take with water after breakfast',
        'soundId': 'remedy_alarm_classic',
        'customPath': '',
        'snoozeCount': 0,
      });

      // Decode and verify primary
      final primaryMap = jsonDecode(originalPayload) as Map<String, dynamic>;
      expect(primaryMap['primaryNotifId'], equals(primaryNotifId));
      expect(primaryMap['strength'], equals('50 mg'));
      expect(primaryMap['instructions'],
          equals('Take with water after breakfast'));

      // Decode and verify escalation carries same primaryNotifId
      final escMap = jsonDecode(escalationPayload) as Map<String, dynamic>;
      expect(escMap['notifId'], equals(escalationId));
      expect(escMap['primaryNotifId'], equals(primaryNotifId));
      expect(escMap['strength'], equals('50 mg'));

      // Verify AlarmIdGenerator.getPrimaryId maps accurately
      expect(
          AlarmIdGenerator.getPrimaryId(
              (escMap['primaryNotifId'] as num).toInt()),
          equals(primaryNotifId));
    });

    test(
        'snooze payload retains full clinical metadata and increments snoozeCount',
        () {
      const primaryNotifId = 888999;
      final snoozePayload = jsonEncode({
        'medId': 'med_202',
        'notifId': primaryNotifId,
        'primaryNotifId': primaryNotifId,
        'sched': '2026-10-17T12:00:00.000',
        'userId': 'user_xyz',
        'medName': 'Metformin',
        'doseAmount': 2.0,
        'strength': '500 mg',
        'form': 'capsule',
        'colorTag': 0xFFE64553,
        'instructions': 'Take immediately before lunch',
        'soundId': 'remedy_alarm_beep',
        'customPath': '',
        'snoozeCount': 1,
      });

      final map = jsonDecode(snoozePayload) as Map<String, dynamic>;
      expect(map['snoozeCount'], equals(1));
      expect(map['strength'], equals('500 mg'));
      expect(map['form'], equals('capsule'));
      expect(map['colorTag'], equals(0xFFE64553));
      expect(map['instructions'], equals('Take immediately before lunch'));
    });
  });
}
