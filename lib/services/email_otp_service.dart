import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/app_logger.dart';
import 'crashlytics_service.dart';

/// Client-side service calling 2nd Gen Cloud Functions `requestEmailOtp` and `verifyEmailOtp`.
/// Enforces typed error mapping to OtpException and RateLimitException.
class EmailOtpService {
  final FirebaseFunctions? _functions;

  EmailOtpService({FirebaseFunctions? functions})
      : _functions = functions ?? _resolveFunctions();

  static FirebaseFunctions? _resolveFunctions() {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseFunctions.instanceFor(
        region: AppConstants.cloudFunctionsRegion,
      );
    } catch (e, stack) {
      AppLogger.w('EmailOtpService: Cloud Functions unavailable: $e',
          tag: 'EmailOtpService');
      CrashlyticsService.recordError(e, stack,
          reason: 'EmailOtpService._resolveFunctions');
      return null;
    }
  }

  /// Requests a 6-digit email OTP challenge from the Cloud Functions backend.
  Future<Map<String, dynamic>> requestEmailOtp({
    required String purpose,
    String? email,
  }) async {
    final functions = _functions;

    if (functions == null || Firebase.apps.isEmpty) {
      throw const OtpException(
        'Cloud Functions service is unavailable. Please verify your connection.',
      );
    }

    try {
      final callable = functions.httpsCallable('requestEmailOtp');
      final result = await callable.call<Map<String, dynamic>>({
        'purpose': purpose,
        if (email != null && email.isNotEmpty) 'email': email,
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw RateLimitException(e.message ?? 'Rate limit exceeded.');
      }
      throw OtpException(e.message ?? 'Failed to send verification code.');
    } catch (e, stack) {
      await CrashlyticsService.recordError(e, stack,
          reason: 'EmailOtpService.requestEmailOtp');
      throw const OtpException(
          'Failed to request verification code. Please check your connection and try again.');
    }
  }

  /// Verifies a 6-digit email OTP against the server-side salted HMAC challenge.
  Future<bool> verifyEmailOtp({
    required String code,
    required String purpose,
  }) async {
    final cleanCode = code.trim();
    if (cleanCode.length != AppConstants.otpCodeLength ||
        !RegExp(r'^\d{6}$').hasMatch(cleanCode)) {
      throw const OtpException(
          'Please enter a valid 6-digit verification code.');
    }

    final functions = _functions;

    if (functions == null || Firebase.apps.isEmpty) {
      throw const OtpException(
        'Cloud Functions service is unavailable. Cannot verify code.',
      );
    }

    try {
      final callable = functions.httpsCallable('verifyEmailOtp');
      final result = await callable.call<Map<String, dynamic>>({
        'code': cleanCode,
        'purpose': purpose,
      });
      final data = Map<String, dynamic>.from(result.data);
      return data['verified'] == true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw RateLimitException(
            e.message ?? 'Too many verification attempts.');
      }
      throw OtpException(e.message ?? 'Verification failed.');
    } catch (e, stack) {
      await CrashlyticsService.recordError(e, stack,
          reason: 'EmailOtpService.verifyEmailOtp');
      throw const OtpException(
          'Verification failed. Please check your network and try again.');
    }
  }
}
