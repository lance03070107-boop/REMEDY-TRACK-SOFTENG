import '../errors/app_exception.dart';

/// Sealed Result type enforcing explicit success and failure branches
/// across repository and service boundaries.
sealed class Result<T> {
  const Result();

  /// Returns true if the result represents a successful operation.
  bool get isSuccess => this is Success<T>;

  /// Returns true if the result represents a failed operation.
  bool get isFailure => this is Failure<T>;

  /// Returns the wrapped data if successful, or null on failure.
  T? get dataOrNull => switch (this) {
        Success(data: final d) => d,
        Failure() => null,
      };

  /// Returns the wrapped exception if failed, or null on success.
  AppException? get errorOrNull => switch (this) {
        Success() => null,
        Failure(exception: final e) => e,
      };

  /// Pattern-matches over both cases.
  R when<R>({
    required R Function(T data) success,
    required R Function(AppException exception) failure,
  }) =>
      switch (this) {
        Success(data: final d) => success(d),
        Failure(exception: final e) => failure(e),
      };

  /// Transforms the successful data value using [mapper].
  Result<R> map<R>(R Function(T data) mapper) => switch (this) {
        Success(data: final d) => Success(mapper(d)),
        Failure(exception: final e) => Failure(e),
      };
}

/// Represents a successful computation returning [data].
final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);

  @override
  String toString() => 'Success($data)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Success<T> && other.data == data);

  @override
  int get hashCode => data.hashCode;
}

/// Represents a failed computation returning [exception].
final class Failure<T> extends Result<T> {
  final AppException exception;
  const Failure(this.exception);

  @override
  String toString() => 'Failure($exception)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Failure<T> && other.exception == exception);

  @override
  int get hashCode => exception.hashCode;
}
