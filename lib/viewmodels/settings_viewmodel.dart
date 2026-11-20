import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../services/analytics_service.dart';

/// ViewModel managing user preferences: theme, high contrast, snooze duration, and alarm formats.
class SettingsViewModel extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isHighContrast = false;
  bool _is24HourFormat = false;
  bool _isBiometricEnabled = false;
  bool _isAnalyticsConsentGiven = false;
  int _snoozeMinutes = AppConstants.defaultSnoozeDurationMinutes;
  int _escalationMinutes = AppConstants.defaultEscalationMinutes;
  int _lockTimeoutSeconds = AppConstants.defaultLockTimeoutSeconds;
  String _alarmSound = AppConstants.defaultAlarmSound;
  bool _taglishPromptsEnabled = true;
  AnalyticsService? _analyticsService;

  SettingsViewModel({AnalyticsService? analyticsService})
      : _analyticsService = analyticsService {
    loadSettings();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isHighContrast => _isHighContrast;
  bool get is24HourFormat => _is24HourFormat;
  bool get isBiometricEnabled => _isBiometricEnabled;
  bool get isAnalyticsConsentGiven => _isAnalyticsConsentGiven;
  int get snoozeMinutes => _snoozeMinutes;
  int get escalationMinutes => _escalationMinutes;
  int get lockTimeoutSeconds => _lockTimeoutSeconds;
  String get alarmSound => _alarmSound;
  bool get taglishPromptsEnabled => _taglishPromptsEnabled;

  void attachAnalyticsService(AnalyticsService service) {
    _analyticsService = service;
    _isAnalyticsConsentGiven = service.isConsented;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(AppConstants.keyThemeMode) ?? 0;
    _themeMode = ThemeMode.values[themeIndex];
    _isHighContrast = prefs.getBool(AppConstants.keyHighContrast) ?? false;
    _is24HourFormat = prefs.getBool(AppConstants.keyTimeFormat24h) ?? false;
    _isBiometricEnabled =
        prefs.getBool(AppConstants.keyBiometricEnabled) ?? false;
    _isAnalyticsConsentGiven =
        prefs.getBool(AnalyticsService.keyAnalyticsConsent) ?? false;
    _lockTimeoutSeconds = prefs.getInt(AppConstants.keyLockTimeoutSeconds) ??
        AppConstants.defaultLockTimeoutSeconds;
    _snoozeMinutes = prefs.getInt(AppConstants.keySnoozeMinutes) ??
        AppConstants.defaultSnoozeDurationMinutes;
    _escalationMinutes = prefs.getInt(AppConstants.keyEscalationMinutes) ??
        AppConstants.defaultEscalationMinutes;
    _alarmSound = prefs.getString(AppConstants.keyAlarmSound) ??
        AppConstants.defaultAlarmSound;
    _taglishPromptsEnabled =
        prefs.getBool(AppConstants.keyTaglishPrompts) ?? true;
    notifyListeners();
  }

  Future<void> setAnalyticsConsent(bool value) async {
    _isAnalyticsConsentGiven = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AnalyticsService.keyAnalyticsConsent, value);
    await _analyticsService?.setConsent(value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setHighContrast(bool value) async {
    _isHighContrast = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyHighContrast, value);
    notifyListeners();
  }

  Future<void> set24HourFormat(bool value) async {
    _is24HourFormat = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyTimeFormat24h, value);
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool value) async {
    _isBiometricEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyBiometricEnabled, value);
    notifyListeners();
  }

  Future<void> setSnoozeMinutes(int minutes) async {
    _snoozeMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keySnoozeMinutes, minutes);
    notifyListeners();
  }

  Future<void> setEscalationMinutes(int minutes) async {
    _escalationMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyEscalationMinutes, minutes);
    notifyListeners();
  }

  Future<void> setLockTimeoutSeconds(int seconds) async {
    _lockTimeoutSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyLockTimeoutSeconds, seconds);
    notifyListeners();
  }

  Future<void> setAlarmSound(String sound) async {
    _alarmSound = sound;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyAlarmSound, sound);
    notifyListeners();
  }

  Future<void> setTaglishPromptsEnabled(bool enabled) async {
    _taglishPromptsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyTaglishPrompts, enabled);
    notifyListeners();
  }
}
