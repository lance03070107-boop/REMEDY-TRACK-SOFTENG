/// Global technical constants, storage keys, and business rule thresholds.
class AppConstants {
  const AppConstants._();

  // Shared Preferences Keys (Non-sensitive preferences)
  static const String keyThemeMode = 'remedy_theme_mode';
  static const String keyHighContrast = 'remedy_high_contrast';
  static const String keyOnboardingComplete = 'remedy_onboarding_complete';
  static const String keyTimeFormat24h = 'remedy_time_format_24h';
  static const String keySnoozeMinutes = 'remedy_snooze_minutes';
  static const String keyEscalationMinutes = 'remedy_escalation_minutes';
  static const String keyActiveProfileId = 'remedy_active_profile_id';
  static const String keyPrivacyAccepted = 'remedy_privacy_accepted';
  static const String keyAlarmSound = 'remedy_alarm_sound';
  static const String keyCustomSounds = 'remedy_custom_alarm_sounds';
  static const String keyTaglishPrompts = 'remedy_taglish_prompts';
  static const String keyNotifiedLowStockIds = 'remedy_notified_low_stock_ids';

  // Validation & Clinical Bounds (Single Source of Truth)
  static const double minStock = 0.0;
  static const double maxStock = 9999.0;
  static const double minDoseAmount = 0.01;
  static const double maxDoseAmount = 100.0;
  static const double minLowStockThreshold = 0.0;
  static const double maxLowStockThreshold = 9999.0;
  static const int defaultLowStockDaysSupply = 7;

  static const int minMedicationNameLength = 1;
  static const int maxMedicationNameLength = 60;
  static const int maxGenericNameLength = 60;
  static const int minStrengthLength = 1;
  static const int maxStrengthLength = 7;
  static const int maxInstructionsLength = 200;
  static const int maxNotesLength = 300;
  static const int maxSkipReasonLength = 200;

  static const int minDisplayNameLength = 2;
  static const int maxDisplayNameLength = 60;
  static const int maxEmailLength = 120;
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 72;
  static const int otpLength = 6;
  static const int caregiverInviteCodeLength = 6;

  static const int minPrnIntervalHours = 1;
  static const int maxPrnIntervalHours = 72;
  static const double maxPrnDailyDose = 100.0;

  static const int minScheduleIntervalDays = 1;
  static const int maxScheduleIntervalDays = 365;
  static const int minScheduleIntervalHours = 1;
  static const int maxScheduleIntervalHours = 24;
  static const int minCycleDays = 1;
  static const int maxCycleDays = 365;
  static const int minTimeSlots = 1;
  static const int maxTimeSlots = 12;

  // Timing & Interval Defaults
  static const int defaultSnoozeDurationMinutes = 10;
  static const int defaultEscalationMinutes = 15;
  static const int lateGracePeriodMinutes =
      60; // Doses within 60 mins are 'Late', not 'Missed'
  static const int duplicateDoseThresholdMinutes =
      30; // Warn if intake logged < 30 mins ago

  // Notification Channel Constants (V3: Urgent looping alarm on STREAM_ALARM with dedicated per-tone audio binding)
  static const String alarmChannelIdV3Prefix = 'remedy_alarm_channel_v3';
  static const String alarmChannelNameV3 = 'Medication Alarms (Urgent)';
  static const String alarmChannelDescriptionV3 =
      'Audible, persistent alarm-clock alerts for prescribed medication doses.';

  /// Resolves the dedicated Android notification channel ID for a specific acoustic tone.
  static String getAlarmChannelId(String tone) {
    final validTone =
        availableAlarmSounds.contains(tone) ? tone : defaultAlarmSound;
    return '${alarmChannelIdV3Prefix}_$validTone';
  }

  // Legacy channels preserved for backward compatibility and deletion migrations
  static const String alarmChannelIdV2 = 'remedy_alarm_channel_v2';
  static const String alarmChannelNameV2 = 'Medication Alarms (Urgent)';
  static const String alarmChannelDescriptionV2 =
      'Audible, persistent alarm-clock alerts for prescribed medication doses.';
  static const String alarmChannelId = 'remedy_alarm_channel_v1';
  static const String alarmChannelName = 'Medication Reminders';
  static const String alarmChannelDescription =
      'Critical exact-alarm alerts for prescribed medication doses.';
  static const String refillChannelId = 'remedy_refill_channel_v1';
  static const String refillChannelName = 'Refill & Inventory Alerts';
  static const String refillChannelDescription =
      'Alerts when medication inventory falls below safe thresholds.';

  // Alarm Audio Tones & Rolling Window Limits
  static const String defaultAlarmSound = 'remedy_alarm_classic';
  static const List<String> availableAlarmSounds = [
    'remedy_alarm_classic',
    'remedy_alarm_gentle',
    'remedy_alarm_beep',
    'remedy_alarm_bell',
    'remedy_alarm_digital',
    'remedy_alarm_harp',
  ];
  static const int maxRollingWindowAlarms =
      30; // 30 primary + 30 escalation = 60 <= 64 iOS ceiling

  // Notification Actions
  static const String actionTaken = 'ACTION_TAKEN';
  static const String actionSnooze = 'ACTION_SNOOZE';
  static const String actionSkip = 'ACTION_SKIP';

  // Cloud Functions Region (Single Source of Truth)
  static const String cloudFunctionsRegion = 'asia-southeast1';

  // OTP Verification Settings
  static const int otpCodeLength = 6;
  static const int otpResendCooldownSeconds = 60;
  static const int otpExpiryMinutes = 10;
  static const int otpMaxAttempts = 5;

  // Collection Names (Firestore)
  static const String colUsers = 'users';
  static const String colMedications = 'medications';
  static const String colIntakeLogs = 'intake_logs';
  static const String colInventory = 'inventory';
  static const String colCaregivers = 'caregivers';
  static const String colOtpChallenges = 'otp_challenges';

  // Google Sign-In Web Client ID (serverClientId for Credential Manager on Android)
  static const String googleServerClientId =
      '468984717069-0okrnfi98n8qeoge4fivlaf8tq544meu.apps.googleusercontent.com';
}
