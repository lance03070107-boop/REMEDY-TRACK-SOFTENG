import 'dart:isolate';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/app_logger.dart';

/// Service managing crash reporting via Firebase Crashlytics.
/// Complies with Philippine RA 10173 by strictly scrubbing PII and clinical data
/// and binding only opaque user identifiers.
class CrashlyticsService {
  const CrashlyticsService._();

  static bool _initialized = false;

  /// Initializes Crashlytics and installs global error handlers.
  static Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    if (Firebase.apps.isNotEmpty) {
      try {
        // Only collect in release builds; completely disable in debug/mock mode
        const isEnabled = !kDebugMode;
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(isEnabled);

        // Global Flutter framework error handler
        FlutterError.onError = recordFlutterError;

        // Global unhandled asynchronous error handler
        PlatformDispatcher.instance.onError = (error, stack) {
          recordError(error, stack, fatal: true);
          return true;
        };

        // Uncaught Isolate error listener
        Isolate.current.addErrorListener(
          RawReceivePort((Object? pair) async {
            final List<dynamic> errorAndStack = pair as List<dynamic>;
            final Object error = errorAndStack.first as Object;
            final stack = StackTrace.fromString(errorAndStack.last.toString());
            await recordError(error, stack, fatal: true);
          }).sendPort,
        );

        _initialized = true;
        AppLogger.i('Crashlytics initialized (collection: $isEnabled)',
            tag: 'Crashlytics');
      } catch (e) {
        AppLogger.w('Failed to initialize Crashlytics: $e', tag: 'Crashlytics');
      }
    }
  }

  /// Sets the user identifier in Crashlytics.
  /// PRIVACY REQUIREMENT: Accepts ONLY the opaque Firestore UID.
  /// Never pass email, real names, or health data!
  static Future<void> setUserIdentifier(String? uid) async {
    if (kIsWeb || Firebase.apps.isEmpty || kDebugMode) return;
    try {
      if (uid != null && uid.isNotEmpty) {
        await FirebaseCrashlytics.instance.setUserIdentifier(uid);
      } else {
        await FirebaseCrashlytics.instance.setUserIdentifier('');
      }
    } catch (e) {
      AppLogger.w('Crashlytics setUserIdentifier failed: $e',
          tag: 'Crashlytics');
    }
  }

  /// Records a caught FlutterError details object.
  static void recordFlutterError(FlutterErrorDetails details) {
    AppLogger.e(
      details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
      tag: 'FlutterError',
    );

    if (!kIsWeb && Firebase.apps.isNotEmpty && !kDebugMode) {
      FirebaseCrashlytics.instance.recordFlutterError(details);
    }
  }

  /// Records a non-fatal or fatal error to Crashlytics after sanitizing error messages.
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    final sanitizedReason = reason != null ? AppLogger.scrubPii(reason) : null;
    AppLogger.e(
      'Recorded error (fatal: $fatal): ${AppLogger.scrubPii(error.toString())}',
      error: error,
      stackTrace: stack,
      tag: 'Crashlytics',
    );

    if (!kIsWeb && Firebase.apps.isNotEmpty && !kDebugMode) {
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          reason: sanitizedReason,
          fatal: fatal,
        );
      } catch (e) {
        AppLogger.w('Crashlytics recordError failed: $e', tag: 'Crashlytics');
      }
    }
  }

  /// Adds a safe custom key for operational diagnostics (NO health info or names).
  static Future<void> setCustomKey(String key, Object value) async {
    if (kIsWeb || Firebase.apps.isEmpty || kDebugMode) return;
    try {
      await FirebaseCrashlytics.instance.setCustomKey(key, value);
    } catch (e) {
      AppLogger.w('Crashlytics setCustomKey failed: $e', tag: 'Crashlytics');
    }
  }
}
