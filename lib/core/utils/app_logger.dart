import 'package:flutter/foundation.dart';

/// Structured, PII-safe application logger.
/// Suppresses output in release builds; in debug mode, sanitizes sensitive medical data
/// and credentials before printing to the developer console.
class AppLogger {
  const AppLogger._();

  // Common PII patterns to sanitize
  static final RegExp _emailRegex =
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,7}\b');
  static final RegExp _phPhoneRegex = RegExp(r'(\+?63|0)9\d{9}');
  static final RegExp _passwordRegex =
      RegExp(r'(password|pass|secret|token)=([^\s&]+)', caseSensitive: false);

  /// Sanitizes text to remove any accidentally interpolated sensitive personal information.
  static String scrubPii(String message) {
    var clean = message;
    clean = clean.replaceAllMapped(_emailRegex, (m) {
      final email = m.group(0)!;
      final parts = email.split('@');
      if (parts.first.length > 2) {
        return '${parts.first.substring(0, 2)}***@${parts.last}';
      }
      return '***@${parts.last}';
    });
    clean = clean.replaceAllMapped(_phPhoneRegex, (m) => '+639******');
    clean = clean.replaceAllMapped(
        _passwordRegex, (m) => '${m.group(1)}=[REDACTED]');
    return clean;
  }

  /// Logs a debug-level message (only printed in debug mode).
  static void d(String message, {String tag = 'RemedyTrack'}) {
    if (!kDebugMode) return;
    final sanitized = scrubPii(message);
    debugPrint('[$tag] [DEBUG] $sanitized');
  }

  /// Logs an info-level message.
  static void i(String message, {String tag = 'RemedyTrack'}) {
    if (!kDebugMode) return;
    final sanitized = scrubPii(message);
    debugPrint('[$tag] [INFO] $sanitized');
  }

  /// Logs a warning-level message with optional sanitized error and stack trace.
  static void w(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String tag = 'RemedyTrack',
  }) {
    if (!kDebugMode) return;
    final sanitized = scrubPii(message);
    debugPrint('[$tag] [WARN] $sanitized');
    if (error != null) {
      debugPrint('[$tag] [WARN_DETAILS] ${scrubPii(error.toString())}');
    }
    if (stackTrace != null) {
      debugPrint('[$tag] [WARN_STACK] $stackTrace');
    }
  }

  /// Logs an error-level message with optional sanitized error and stack trace.
  static void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String tag = 'RemedyTrack',
  }) {
    if (!kDebugMode) return;
    final sanitizedMessage = scrubPii(message);
    final sanitizedError = error != null ? scrubPii(error.toString()) : null;
    debugPrint('[$tag] [ERROR] $sanitizedMessage');
    if (sanitizedError != null) {
      debugPrint('[$tag] [ERROR_DETAILS] $sanitizedError');
    }
    if (stackTrace != null) {
      debugPrint('[$tag] [STACK] $stackTrace');
    }
  }
}
