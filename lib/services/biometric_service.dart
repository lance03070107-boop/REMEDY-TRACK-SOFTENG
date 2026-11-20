import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'crashlytics_service.dart';

enum BiometricAuthStatus {
  success,
  cancelled,
  notEnrolled,
  lockedOut,
  failed,
  unsupported,
}

class BiometricAuthResult {
  final BiometricAuthStatus status;
  final String? message;

  const BiometricAuthResult(this.status, {this.message});

  bool get isSuccess => status == BiometricAuthStatus.success;
}

/// Service protecting sensitive medical data using device biometric sensors or fallback PIN.
/// Explicitly disables biometrics on Web to prevent false unlock bypasses.
class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return const [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
      return const [];
    }
  }

  /// Full authentication returning detailed status for user feedback and error recovery.
  Future<BiometricAuthResult> authenticateDetailed({
    String reason =
        'Authenticate to unlock your confidential medical schedule and intake logs.',
  }) async {
    if (kIsWeb) {
      return const BiometricAuthResult(
        BiometricAuthStatus.unsupported,
        message: 'Biometric lock is disabled on Web.',
      );
    }

    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return const BiometricAuthResult(
          BiometricAuthStatus.notEnrolled,
          message: 'No biometric credentials or device lock configured.',
        );
      }

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allows device PIN/passcode fallback
        ),
      );

      if (authenticated) {
        return const BiometricAuthResult(BiometricAuthStatus.success);
      } else {
        return const BiometricAuthResult(
          BiometricAuthStatus.cancelled,
          message: 'Authentication was cancelled.',
        );
      }
    } on PlatformException catch (e) {
      switch (e.code) {
        case auth_error.notEnrolled:
        case auth_error.passcodeNotSet:
          return const BiometricAuthResult(
            BiometricAuthStatus.notEnrolled,
            message: 'Biometrics or passcode are not set up on this device.',
          );
        case auth_error.lockedOut:
        case auth_error.permanentlyLockedOut:
          return const BiometricAuthResult(
            BiometricAuthStatus.lockedOut,
            message:
                'Biometrics temporarily locked due to too many failed attempts.',
          );
        default:
          return BiometricAuthResult(
            BiometricAuthStatus.failed,
            message: e.message ?? 'Biometric authentication failed.',
          );
      }
    } catch (e) {
      return const BiometricAuthResult(
        BiometricAuthStatus.failed,
        message: 'An unexpected biometric error occurred.',
      );
    }
  }

  /// Simplified boolean check for legacy calls. On Web, strictly returns false.
  Future<bool> authenticate() async {
    final result = await authenticateDetailed();
    return result.isSuccess;
  }
}
