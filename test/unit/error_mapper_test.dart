import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/errors/app_exception.dart';
import 'package:remedy_track/core/errors/error_mapper.dart';

void main() {
  group('ErrorMapper Exception Mapping Tests', () {
    test('returns existing AppException instances without modification', () {
      const original =
          NetworkException('Custom offline message', code: 'CUSTOM_OFFLINE');
      final mapped = ErrorMapper.map(original);
      expect(mapped, same(original));
      expect(mapped.message, equals('Custom offline message'));
      expect(mapped.code, equals('CUSTOM_OFFLINE'));
    });

    test('maps FirebaseAuthException codes to friendly AppExceptions', () {
      final userNotFound = FirebaseAuthException(code: 'user-not-found');
      final mapped1 = ErrorMapper.map(userNotFound);
      expect(mapped1, isA<AuthException>());
      expect(mapped1.code, equals('USER_NOT_FOUND'));
      expect(mapped1.message, contains('No registered account found'));

      final wrongPassword = FirebaseAuthException(code: 'wrong-password');
      final mapped2 = ErrorMapper.map(wrongPassword);
      expect(mapped2, isA<AuthException>());
      expect(mapped2.code, equals('INVALID_CREDENTIALS'));

      final emailInUse = FirebaseAuthException(code: 'email-already-in-use');
      final mapped3 = ErrorMapper.map(emailInUse);
      expect(mapped3, isA<AuthException>());
      expect(mapped3.code, equals('EMAIL_ALREADY_IN_USE'));

      final invalidEmail = FirebaseAuthException(code: 'invalid-email');
      final mapped4 = ErrorMapper.map(invalidEmail);
      expect(mapped4, isA<ValidationException>());
      expect(mapped4.code, equals('INVALID_EMAIL'));

      final weakPassword = FirebaseAuthException(code: 'weak-password');
      final mapped5 = ErrorMapper.map(weakPassword);
      expect(mapped5, isA<ValidationException>());
      expect(mapped5.code, equals('WEAK_PASSWORD'));

      final tooManyRequests = FirebaseAuthException(code: 'too-many-requests');
      final mapped6 = ErrorMapper.map(tooManyRequests);
      expect(mapped6, isA<RateLimitException>());
      expect(mapped6.code, equals('RATE_LIMIT_EXCEEDED'));

      final requiresRecentLogin =
          FirebaseAuthException(code: 'requires-recent-login');
      final mapped7 = ErrorMapper.map(requiresRecentLogin);
      expect(mapped7, isA<AuthException>());
      expect(mapped7.code, equals('REQUIRES_RECENT_LOGIN'));
    });

    test('maps FirebaseException (Firestore) codes to safe AppExceptions', () {
      final permissionDenied = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions for users/secret_123',
      );
      final mapped1 = ErrorMapper.map(permissionDenied);
      expect(mapped1, isA<PermissionException>());
      expect(mapped1.code, equals('FIRESTORE_PERMISSION_DENIED'));
      // Raw internal schema and paths must not leak into patient message
      expect(mapped1.message, isNot(contains('secret_123')));

      final unavailable =
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      final mapped2 = ErrorMapper.map(unavailable);
      expect(mapped2, isA<NetworkException>());
      expect(mapped2.code, equals('FIRESTORE_UNAVAILABLE'));

      final notFound =
          FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
      final mapped3 = ErrorMapper.map(notFound);
      expect(mapped3, isA<DatabaseException>());
      expect(mapped3.code, equals('RECORD_NOT_FOUND'));

      final deadlineExceeded = FirebaseException(
          plugin: 'cloud_firestore', code: 'deadline-exceeded');
      final mapped4 = ErrorMapper.map(deadlineExceeded);
      expect(mapped4, isA<NetworkException>());
      expect(mapped4.code, equals('FIRESTORE_DEADLINE_EXCEEDED'));
    });

    test('maps low-level network failures (SocketException & TimeoutException)',
        () {
      const socket =
          SocketException('Failed host lookup: remedytrack.firebaseio.com');
      final mappedSocket = ErrorMapper.map(socket);
      expect(mappedSocket, isA<NetworkException>());
      expect(mappedSocket.code, equals('NETWORK_SOCKET_ERROR'));
      expect(mappedSocket.message,
          contains('Unable to connect to RemedyTrack servers'));

      final timeout = TimeoutException('Connection timed out');
      final mappedTimeout = ErrorMapper.map(timeout);
      expect(mappedTimeout, isA<NetworkException>());
      expect(mappedTimeout.code, equals('NETWORK_TIMEOUT'));
    });

    test(
        'maps PlatformException to safe AppException without leaking platform internal strings',
        () {
      final platform = PlatformException(
          code: 'SIGN_IN_FAILED', message: 'Google Play Services outdated');
      final mappedPlatform = ErrorMapper.map(platform);
      expect(mappedPlatform, isA<AppException>());
      expect(mappedPlatform.code, equals('SIGN_IN_FAILED'));
    });

    test('maps unknown runtime exceptions to safe UnknownException fallback',
        () {
      final runtimeError =
          StateError('Unexpected internal memory assertion failed');
      final mapped = ErrorMapper.map(runtimeError);
      expect(mapped, isA<UnknownException>());
      expect(mapped.code, equals('UNKNOWN_ERROR'));
      expect(mapped.message,
          equals('An unexpected error occurred. Please try again.'));
      expect(mapped.details, contains('Unexpected internal memory assertion'));
    });

    test(
        'ClinicalSafetyException extends AppException and formats clean messages',
        () {
      const safety = ClinicalSafetyException(
        risk: ClinicalSafetyRisk.prnMinInterval,
        message: 'Too soon for another dose.',
        clinicalRecommendation: 'Wait another 30 minutes.',
      );

      expect(safety, isA<AppException>());
      expect(safety.code, equals('DOSAGE_SAFETY_CHECK'));
      expect(safety.toString(),
          equals('Too soon for another dose.\nWait another 30 minutes.'));
      expect(safety.toString(), isNot(contains('ClinicalSafetyException:')));
      expect(ErrorMapper.map(safety), same(safety));
    });

    test('maps aborted, cancelled, and invalid-argument FirebaseException codes',
        () {
      final aborted =
          FirebaseException(plugin: 'cloud_firestore', code: 'aborted');
      final mappedAborted = ErrorMapper.map(aborted);
      expect(mappedAborted, isA<DatabaseException>());
      expect(mappedAborted.code, equals('FIRESTORE_ABORTED'));

      final cancelled =
          FirebaseException(plugin: 'cloud_firestore', code: 'cancelled');
      final mappedCancelled = ErrorMapper.map(cancelled);
      expect(mappedCancelled, isA<NetworkException>());
      expect(mappedCancelled.code, equals('FIRESTORE_CANCELLED'));

      final invalidArg = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-argument',
        message: 'Field notes exceeded internal schema limit',
      );
      final mappedInvalid = ErrorMapper.map(invalidArg);
      expect(mappedInvalid, isA<ValidationException>());
      expect(mappedInvalid.code, equals('INVALID_ARGUMENT'));
      expect(mappedInvalid.message,
          isNot(contains('internal schema limit')));
    });
  });
}
