import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/utils/app_logger.dart';

void main() {
  group('AppLogger RA 10173 PII Scrubbing Tests', () {
    test('scrubs email addresses while retaining domain structure', () {
      const input =
          'Patient registered with email maria.santos@gmail.com for dosage alert';
      final output = AppLogger.scrubPii(input);

      expect(output, isNot(contains('maria.santos@gmail.com')));
      expect(output, contains('ma***@gmail.com'));
      expect(output, contains('dosage alert'));
    });

    test('scrubs short email prefixes safely', () {
      const input = 'Contact: a@remedytrack.ph';
      final output = AppLogger.scrubPii(input);

      expect(output, isNot(contains('a@remedytrack.ph')));
      expect(output, contains('***@remedytrack.ph'));
    });

    test('scrubs Philippine mobile numbers (+63 and 09 formats)', () {
      const input1 =
          'Emergency SMS sent to +639171234567 regarding missed dose';
      final output1 = AppLogger.scrubPii(input1);

      expect(output1, isNot(contains('9171234567')));
      expect(output1, contains('+639******'));

      const input2 = 'Caregiver contact: 09181234567';
      final output2 = AppLogger.scrubPii(input2);

      expect(output2, isNot(contains('09181234567')));
      expect(output2, contains('+639******'));
    });

    test('scrubs passwords, secrets, and auth tokens from query or log strings',
        () {
      const input =
          'Attempting auth with password=SecretPassword!123&user=juan and token=eyJhbGciOi';
      final output = AppLogger.scrubPii(input);

      expect(output, isNot(contains('SecretPassword!123')));
      expect(output, isNot(contains('eyJhbGciOi')));
      expect(output, contains('password=[REDACTED]'));
      expect(output, contains('token=[REDACTED]'));
    });

    test('leaves non-sensitive clinical terms and numbers unredacted', () {
      const input = 'Scheduled dose: Amoxicillin 500mg at 08:00 AM';
      final output = AppLogger.scrubPii(input);

      expect(output, equals(input));
    });
  });
}
