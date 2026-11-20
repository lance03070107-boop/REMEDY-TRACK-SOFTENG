import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/app_logger.dart';

/// Service managing privacy-safe telemetry and usage statistics.
/// Strictly enforces Philippine RA 10173:
/// - Explicit opt-in consent required (default off)
/// - ZERO PII or health data in events (no medication names, no dosages, no user names, no emails)
class AnalyticsService {
  final FirebaseAnalytics? _analytics;
  bool _isConsented = false;

  static const String keyAnalyticsConsent = 'rt_analytics_consent_given';

  AnalyticsService({FirebaseAnalytics? analytics})
      : _analytics = analytics ?? _resolveAnalytics();

  static FirebaseAnalytics? _resolveAnalytics() {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseAnalytics.instance;
    } catch (e) {
      AppLogger.w('Analytics instance unavailable on this browser/platform: $e',
          tag: 'Analytics');
      return null;
    }
  }

  bool get isConsented => _isConsented;

  /// Initializes analytics state based on stored user privacy consent.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isConsented = prefs.getBool(keyAnalyticsConsent) ?? false;

    final analytics = _analytics;
    if (analytics != null && Firebase.apps.isNotEmpty) {
      try {
        await analytics.setAnalyticsCollectionEnabled(_isConsented);
        AppLogger.i('Analytics initialized (collection: $_isConsented)',
            tag: 'Analytics');
      } catch (e) {
        AppLogger.w('Failed to set analytics collection status: $e',
            tag: 'Analytics');
      }
    }
  }

  /// Updates user consent preference and toggles Firebase collection accordingly.
  Future<void> setConsent(bool consented) async {
    _isConsented = consented;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAnalyticsConsent, consented);

    final analytics = _analytics;
    if (analytics != null && Firebase.apps.isNotEmpty) {
      try {
        await analytics.setAnalyticsCollectionEnabled(consented);
        AppLogger.i('Analytics consent updated: $consented', tag: 'Analytics');
      } catch (e) {
        AppLogger.w('Error updating analytics consent: $e', tag: 'Analytics');
      }
    }
  }

  /// Logs a screen navigation event (without health parameters).
  Future<void> logScreenView(String screenName) async {
    if (!_isConsented || _analytics == null) return;
    try {
      await _analytics!.logScreenView(screenName: screenName);
    } catch (e) {
      AppLogger.w('Failed to log screen view: $e', tag: 'Analytics');
    }
  }

  /// Logs a general action event (without any medication names or dosages).
  Future<void> logAction(String actionName) async {
    if (!_isConsented || _analytics == null) return;
    try {
      await _analytics!.logEvent(
        name: actionName,
        parameters: {
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      AppLogger.w('Failed to log action event: $e', tag: 'Analytics');
    }
  }

  /// Logs adherence calculation action (only percentage bracket, no medicine name).
  Future<void> logAdherenceViewed(double rate) async {
    if (!_isConsented || _analytics == null) return;
    try {
      final bracket = rate >= 80 ? 'high' : (rate >= 50 ? 'moderate' : 'low');
      await _analytics!.logEvent(
        name: 'adherence_summary_viewed',
        parameters: {'bracket': bracket},
      );
    } catch (e) {
      AppLogger.w('Failed to log adherence viewed: $e', tag: 'Analytics');
    }
  }
}
