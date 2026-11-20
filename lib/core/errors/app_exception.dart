export 'clinical_safety_exception.dart';

/// Typed application exceptions for structured error handling across repositories and ViewModels.
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const AppException(this.message, {this.code, this.details});

  @override
  String toString() => message;
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code, super.details});
}

class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.code, super.details});
}

class PermissionException extends AppException {
  const PermissionException(super.message, {super.code, super.details});
}

class InventoryException extends AppException {
  const InventoryException(super.message, {super.code, super.details});
}

class OtpException extends AppException {
  const OtpException(super.message, {super.code, super.details});
}

class RateLimitException extends AppException {
  const RateLimitException(super.message, {super.code, super.details});
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.code, super.details});
}

class ValidationException extends AppException {
  const ValidationException(super.message, {super.code, super.details});
}

class UnknownException extends AppException {
  const UnknownException(super.message, {super.code, super.details});
}
