import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/errors/app_exception.dart';
import 'package:remedy_track/services/email_otp_service.dart';

void main() {
  group('EmailOtpService Client-Side Validation & Guard Tests', () {
    late EmailOtpService service;

    setUp(() {
      service = EmailOtpService();
    });

    test('validates 6-digit formatting before sending to backend', () async {
      // Must reject code shorter than 6 digits
      expect(
        () => service.verifyEmailOtp(code: '123', purpose: 'signup'),
        throwsA(isA<OtpException>()),
      );

      // Must reject code longer than 6 digits
      expect(
        () => service.verifyEmailOtp(code: '1234567', purpose: 'signup'),
        throwsA(isA<OtpException>()),
      );

      // Must reject non-digit strings
      expect(
        () => service.verifyEmailOtp(code: 'abcdef', purpose: 'signup'),
        throwsA(isA<OtpException>()),
      );

      // Must reject empty code
      expect(
        () => service.verifyEmailOtp(code: '', purpose: 'signup'),
        throwsA(isA<OtpException>()),
      );
    });

    test(
        'throws OtpException when Cloud Functions instance is null or uninitialized',
        () async {
      expect(
        () => service.requestEmailOtp(
          purpose: 'signup',
          email: 'test@remedytrack.app',
        ),
        throwsA(isA<OtpException>()),
      );

      expect(
        () => service.verifyEmailOtp(
          code: '123456',
          purpose: 'signup',
        ),
        throwsA(isA<OtpException>()),
      );
    });
  });
}
