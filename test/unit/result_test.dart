import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/errors/app_exception.dart';
import 'package:remedy_track/core/utils/result.dart';

void main() {
  group('Result<T> Sealed Class & Pattern Matching Tests', () {
    test('Success holds value and exposes expected properties', () {
      const Result<int> result = Success(42);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.dataOrNull, equals(42));
      expect(result.errorOrNull, isNull);
    });

    test('Failure holds exception and exposes expected properties', () {
      const exception =
          NetworkException('Offline mode active', code: 'OFFLINE');
      const Result<int> result = Failure(exception);

      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.errorOrNull, equals(exception));
    });

    test('when pattern matching executes correct branch', () {
      const Result<String> success = Success('Medication saved');
      final successMsg = success.when(
        success: (data) => 'OK: $data',
        failure: (err) => 'FAIL: ${err.message}',
      );
      expect(successMsg, equals('OK: Medication saved'));

      const Result<String> failure =
          Failure(ValidationException('Invalid dosage'));
      final failureMsg = failure.when(
        success: (data) => 'OK: $data',
        failure: (err) => 'FAIL: ${err.message}',
      );
      expect(failureMsg, equals('FAIL: Invalid dosage'));
    });

    test('map transforms value on Success and preserves Failure', () {
      const Result<int> success = Success(5);
      final mappedSuccess = success.map((x) => x * 10);
      expect(mappedSuccess, isA<Success<int>>());
      expect(mappedSuccess.dataOrNull, equals(50));

      const Result<int> failure = Failure(DatabaseException('DB write locked'));
      final mappedFailure = failure.map((x) => x * 10);
      expect(mappedFailure, isA<Failure<int>>());
      expect(mappedFailure.errorOrNull?.message, equals('DB write locked'));
    });

    test('equality and hashCode contracts for Success and Failure', () {
      expect(const Success(100), equals(const Success(100)));
      expect(const Success(100), isNot(equals(const Success(200))));

      const ex1 = AuthException('Invalid PIN');
      const ex2 = AuthException('Invalid PIN');
      expect(const Failure<void>(ex1), equals(const Failure<void>(ex2)));
    });
  });
}
