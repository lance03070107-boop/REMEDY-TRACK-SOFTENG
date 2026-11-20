import 'dart:async';
import 'app_logger.dart';

/// Executes an idempotent read or network operation with exponential backoff and timeout.
/// Non-idempotent operations must NOT use this without an idempotency key.
Future<T> retryWithBackoff<T>(
  Future<T> Function() operation, {
  int maxRetries = 3,
  Duration initialDelay = const Duration(milliseconds: 350),
  Duration timeout = const Duration(seconds: 10),
  double backoffMultiplier = 2.0,
}) async {
  int attempts = 0;
  Duration currentDelay = initialDelay;

  while (true) {
    attempts++;
    try {
      return await operation().timeout(timeout);
    } catch (e) {
      if (attempts >= maxRetries) {
        rethrow;
      }
      AppLogger.w(
        'Idempotent read failed (attempt $attempts/$maxRetries), retrying in ${currentDelay.inMilliseconds}ms: $e',
        tag: 'RetryHelper',
      );
      await Future<void>.delayed(currentDelay);
      currentDelay = Duration(
        milliseconds: (currentDelay.inMilliseconds * backoffMultiplier).round(),
      );
    }
  }
}
