import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/utils/retry_helper.dart';

void main() {
  group('retryWithBackoff Exponential Backoff Tests', () {
    test('succeeds immediately on first invocation without retries', () async {
      int calls = 0;
      final result = await retryWithBackoff(
        () async {
          calls++;
          return 'immediate_success';
        },
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 10),
      );

      expect(result, equals('immediate_success'));
      expect(calls, equals(1));
    });

    test('recovers after transient failures with backoff delay', () async {
      int calls = 0;
      final result = await retryWithBackoff(
        () async {
          calls++;
          if (calls < 3) {
            throw TimeoutException('Transient network timeout');
          }
          return 'recovered_data';
        },
        maxRetries: 4,
        initialDelay: const Duration(milliseconds: 10),
        backoffMultiplier: 1.5,
      );

      expect(result, equals('recovered_data'));
      expect(calls, equals(3));
    });

    test('rethrows exception when all retry attempts are exhausted', () async {
      int calls = 0;

      expect(
        () => retryWithBackoff(
          () async {
            calls++;
            throw StateError('Persistent backend failure');
          },
          maxRetries: 3,
          initialDelay: const Duration(milliseconds: 10),
        ),
        throwsA(isA<StateError>()),
      );

      // Verify attempts count after failure
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, equals(3));
    });

    test('times out operation exceeding configured per-attempt timeout',
        () async {
      expect(
        () => retryWithBackoff(
          () async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            return 'late';
          },
          maxRetries: 2,
          timeout: const Duration(milliseconds: 20),
          initialDelay: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
