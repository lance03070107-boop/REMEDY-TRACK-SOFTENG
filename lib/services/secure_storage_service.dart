import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/utils/app_logger.dart';

/// Production secure storage service wrapping platform-native secure enclaves:
/// - Android Keystore (EncryptedSharedPreferences)
/// - iOS / macOS Keychain (first_unlock access)
/// - Web encrypted WebCrypto / IndexedDB fallback
class SecureStorageService {
  final FlutterSecureStorage _storage;

  // Sensitive storage keys
  static const String keyUserToken = 'rt_sec_user_token';
  static const String keyUserId = 'rt_sec_user_id';
  static const String keyUserEmail = 'rt_sec_user_email';
  static const String keyBiometricEnrolled = 'rt_sec_biometric_enrolled';
  static const String keyFcmToken = 'rt_sec_fcm_token';
  static const String keyEncryptedMedicationCache = 'rt_sec_med_cache_v2';

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              wOptions: WindowsOptions(),
              webOptions: WebOptions(
                dbName: 'remedy_track_sec_vault',
                publicKey: 'remedy_track_key',
              ),
            );

  Future<bool> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (e, s) {
      AppLogger.w('SecureStorage write error for $key: $e',
          tag: 'SecureStorage', error: e, stackTrace: s);
      return false;
    }
  }

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e, s) {
      AppLogger.w('SecureStorage read error for $key: $e',
          tag: 'SecureStorage', error: e, stackTrace: s);
      return null;
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e, s) {
      AppLogger.w('SecureStorage delete error for $key: $e',
          tag: 'SecureStorage', error: e, stackTrace: s);
    }
  }

  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e, s) {
      AppLogger.w('SecureStorage deleteAll error: $e',
          tag: 'SecureStorage', error: e, stackTrace: s);
    }
  }
}
