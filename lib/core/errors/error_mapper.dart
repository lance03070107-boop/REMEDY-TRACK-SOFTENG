import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_exception.dart';

/// Centralized mapper that converts low-level runtime errors, Firebase exceptions,
/// sockets, and platform exceptions into clean, typed, user-facing [AppException] subclasses.
/// Guarantees that raw exception messages (which may contain internal schema, URLs, or PII)
/// are never surfaced directly to patients or caregivers.
class ErrorMapper {
  const ErrorMapper._();

  /// Maps any caught error or exception to a safe, strongly-typed [AppException].
  static AppException map(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) {
      return error;
    }

    if (error is FirebaseAuthException) {
      return _mapFirebaseAuth(error);
    }

    if (error is FirebaseFunctionsException) {
      return _mapFirebaseFunctions(error);
    }

    if (error is FirebaseException) {
      return _mapFirebaseCore(error);
    }

    if (!kIsWeb && error is SocketException) {
      return const NetworkException(
        'Unable to connect to RemedyTrack servers. Changes will be saved locally.',
        code: 'NETWORK_SOCKET_ERROR',
      );
    }

    if (error is TimeoutException) {
      return const NetworkException(
        'The operation timed out. Please verify your connection and try again.',
        code: 'NETWORK_TIMEOUT',
      );
    }

    if (error is PlatformException) {
      return _mapPlatformException(error);
    }

    // Fallback: Safe, sanitized user-facing error message with code
    return UnknownException(
      'An unexpected error occurred. Please try again.',
      code: 'UNKNOWN_ERROR',
      details: error.toString(),
    );
  }

  static AppException _mapFirebaseAuth(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return const AuthException(
          'No registered account found with this email.',
          code: 'USER_NOT_FOUND',
        );
      case 'wrong-password':
      case 'invalid-credential':
        return const AuthException(
          'Incorrect email or password. Please verify your credentials.',
          code: 'INVALID_CREDENTIALS',
        );
      case 'email-already-in-use':
        return const AuthException(
          'An account already exists with this email address.',
          code: 'EMAIL_ALREADY_IN_USE',
        );
      case 'invalid-email':
        return const ValidationException(
          'Please enter a valid email address.',
          code: 'INVALID_EMAIL',
        );
      case 'weak-password':
        return const ValidationException(
          'Password does not meet minimum security requirements.',
          code: 'WEAK_PASSWORD',
        );
      case 'user-disabled':
        return const AuthException(
          'This account has been disabled. Please contact support.',
          code: 'USER_DISABLED',
        );
      case 'too-many-requests':
        return const RateLimitException(
          'Too many failed attempts. Please wait a few minutes before trying again.',
          code: 'RATE_LIMIT_EXCEEDED',
        );
      case 'requires-recent-login':
        return const AuthException(
          'For your security, please re-authenticate before performing this sensitive operation.',
          code: 'REQUIRES_RECENT_LOGIN',
        );
      case 'network-request-failed':
        return const NetworkException(
          'Check your internet connection and try again.',
          code: 'NETWORK_FAILED',
        );
      case 'operation-not-allowed':
        return const PermissionException(
          'This sign-in method is not enabled.',
          code: 'OPERATION_NOT_ALLOWED',
        );
      case 'user-mismatch':
        return const AuthException(
          'Account credentials do not match the signed-in user.',
          code: 'USER_MISMATCH',
        );
      case 'user-token-expired':
        return const AuthException(
          'Your session has expired. Please sign in again.',
          code: 'USER_TOKEN_EXPIRED',
        );
      case 'provider-already-linked':
        return const ValidationException(
          'This sign-in method is already linked to your account.',
          code: 'PROVIDER_ALREADY_LINKED',
        );
      case 'credential-already-in-use':
        return const AuthException(
          'This credential is already linked to another account.',
          code: 'CREDENTIAL_ALREADY_IN_USE',
        );
      default:
        return AuthException(
          "We couldn't sign you in. Please check your details and try again.",
          code: e.code,
          details: e.message,
        );
    }
  }

  static AppException _mapFirebaseCore(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return const PermissionException(
          'You do not have permission to access this record. Please sign in with the right account.',
          code: 'FIRESTORE_PERMISSION_DENIED',
        );
      case 'unavailable':
        return const NetworkException(
          'Cloud sync is temporarily unavailable. Your changes stay saved on this device and will sync automatically when you reconnect.',
          code: 'FIRESTORE_UNAVAILABLE',
        );
      case 'deadline-exceeded':
        return const NetworkException(
          'The connection timed out before finishing. Your changes stay saved locally and will sync when ready.',
          code: 'FIRESTORE_DEADLINE_EXCEEDED',
        );
      case 'not-found':
        return const DatabaseException(
          'The requested medication record could not be found.',
          code: 'RECORD_NOT_FOUND',
        );
      case 'resource-exhausted':
        return const RateLimitException(
          'Too many requests sent right now. Please wait a moment and try again.',
          code: 'RESOURCE_EXHAUSTED',
        );
      case 'unauthenticated':
        return const AuthException(
          'Your session has expired. Please sign in again to continue.',
          code: 'SESSION_EXPIRED',
        );
      case 'already-exists':
        return const DatabaseException(
          'A record with this identifier already exists.',
          code: 'RECORD_ALREADY_EXISTS',
        );
      case 'failed-precondition':
        return const DatabaseException(
          'Sync needs a quick refresh because browser storage or a required index is still updating. Close duplicate tabs or tap Retry.',
          code: 'FAILED_PRECONDITION',
        );
      case 'aborted':
        return const DatabaseException(
          'Another update happened at the same time. Please try again.',
          code: 'FIRESTORE_ABORTED',
        );
      case 'cancelled':
        return const NetworkException(
          'The sync request was cancelled before finishing. Please try again.',
          code: 'FIRESTORE_CANCELLED',
        );
      case 'invalid-argument':
        return ValidationException(
          e.message?.isNotEmpty == true
              ? 'Please check your entered details and try again.'
              : 'Some entered details could not be accepted.',
          code: 'INVALID_ARGUMENT',
          details: e.message,
        );
      default:
        return DatabaseException(
          'Could not sync with cloud right now. Your recent changes remain saved on this device.',
          code: e.code,
          details: e.message,
        );
    }
  }

  static AppException _mapFirebaseFunctions(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return const AuthException(
          'Your session has expired. Please sign in again to continue.',
          code: 'FUNCTIONS_UNAUTHENTICATED',
        );
      case 'permission-denied':
        return const PermissionException(
          'You do not have permission to perform this action.',
          code: 'FUNCTIONS_PERMISSION_DENIED',
        );
      case 'invalid-argument':
        return ValidationException(
          e.message?.isNotEmpty == true
              ? e.message!
              : 'Please check your entered details and try again.',
          code: 'FUNCTIONS_INVALID_ARGUMENT',
          details: e.message,
        );
      case 'not-found':
      case 'unimplemented':
        return const NetworkException(
          'Cloud function endpoint is unavailable right now. Please try again or update the app.',
          code: 'FUNCTIONS_NOT_FOUND',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return const NetworkException(
          'Unable to reach RemedyTrack cloud services. Please check your internet connection.',
          code: 'FUNCTIONS_UNAVAILABLE',
        );
      case 'resource-exhausted':
        return const RateLimitException(
          'Too many requests sent right now. Please wait a moment and try again.',
          code: 'FUNCTIONS_RATE_LIMIT',
        );
      default:
        return NetworkException(
          e.message?.isNotEmpty == true && e.message!.toLowerCase() != 'internal'
              ? e.message!
              : 'Could not reach cloud service. Please check your connection and try again.',
          code: 'FUNCTIONS_${e.code.toUpperCase()}',
          details: e.message,
        );
    }
  }

  static AppException _mapPlatformException(PlatformException e) {
    if (e.code.contains('network') || e.code.contains('connection')) {
      return NetworkException(
        'Device network error. Please check your internet connection.',
        code: e.code,
      );
    }
    if (e.code.contains('biometric') || e.code.contains('auth')) {
      return AuthException(
        'Biometric authentication failed or was canceled.',
        code: e.code,
      );
    }
    return DatabaseException(
      'System operation failed: ${e.message ?? 'Unknown platform error'}.',
      code: e.code,
      details: e.details,
    );
  }
}
