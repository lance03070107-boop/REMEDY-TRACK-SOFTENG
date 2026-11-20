import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/app_logger.dart';
import '../models/medication.dart';
import 'crashlytics_service.dart';
import 'secure_storage_service.dart';

/// Offline-safe local cache for active scheduled medications.
/// Stores a minimized scheduling-only projection (stripping clinical notes and generic names)
/// inside platform-encrypted storage ([SecureStorageService]), with a test-only fallback
/// when native secure storage channels are unavailable in headless unit tests.
class LocalMedicationCache {
  const LocalMedicationCache._();

  static const String keyCachedActiveMedications =
      'remedy_cached_active_medications';
  static const String keyLastCacheUpdate = 'remedy_last_med_cache_update_ms';

  static final SecureStorageService _secureStorage = SecureStorageService();

  /// Strips non-scheduling clinical fields (`notes`, `genericName`) before caching locally.
  static Medication _minimizeForScheduling(Medication m) {
    return m.copyWith(
      genericName: '',
      clearNotes: true,
    );
  }

  /// Serializes and stores active scheduled medications in encrypted local storage.
  static Future<void> saveMedications(List<Medication> medications) async {
    try {
      final activeMeds = medications
          .where((m) => m.isActive && !m.isPrn && m.schedule != null)
          .map(_minimizeForScheduling)
          .toList();
      final encodedList =
          activeMeds.map((m) => jsonEncode(m.toJson())).toList();
      final payload = jsonEncode(encodedList);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        keyLastCacheUpdate,
        DateTime.now().millisecondsSinceEpoch,
      );

      final wroteSecurely = await _secureStorage.write(
        SecureStorageService.keyEncryptedMedicationCache,
        payload,
      );
      if (wroteSecurely) {
        // Remove any legacy plaintext cache from SharedPreferences
        await prefs.remove(keyCachedActiveMedications);
      } else {
        await prefs.setStringList(keyCachedActiveMedications, encodedList);
      }
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
    }
  }

  /// Deserializes and returns locally cached active medications.
  static Future<List<Medication>> loadMedications() async {
    try {
      List<String> encodedList = [];
      try {
        final encryptedPayload = await _secureStorage.read(
          SecureStorageService.keyEncryptedMedicationCache,
        );
        if (encryptedPayload != null && encryptedPayload.isNotEmpty) {
          final decoded = jsonDecode(encryptedPayload) as List<dynamic>;
          encodedList = decoded.map((e) => e.toString()).toList();
        }
      } catch (e, stack) {
        AppLogger.w('SecureStorage cache decode fallback: $e',
            tag: 'LocalMedicationCache');
        unawaited(CrashlyticsService.recordError(e, stack,
            reason: 'LocalMedicationCache.loadActiveMedications'));
      }

      if (encodedList.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        encodedList = prefs.getStringList(keyCachedActiveMedications) ?? [];
      }

      final List<Medication> list = [];
      for (final raw in encodedList) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          list.add(Medication.fromJson(map));
        } catch (e, stack) {
          unawaited(CrashlyticsService.recordError(e, stack));
        }
      }
      return list;
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
      return [];
    }
  }

  /// Clears the local medication cache (e.g. on user sign-out).
  static Future<void> clear() async {
    try {
      await _secureStorage.delete(
        SecureStorageService.keyEncryptedMedicationCache,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyCachedActiveMedications);
      await prefs.remove(keyLastCacheUpdate);
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
    }
  }
}
