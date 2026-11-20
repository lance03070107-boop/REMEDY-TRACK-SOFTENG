/// Centralized string constants for RemedyTrack.
/// Structured for effortless future localization (English / Filipino).
class AppStrings {
  const AppStrings._();

  // App Identity
  static const String appName = 'RemedyTrack';
  static const String appTagline = 'Your Personal Health and Dosage Companion';
  static const String medicalDisclaimer =
      'RemedyTrack is a reminder and tracking companion. It does NOT provide medical advice or replace consultation with a licensed healthcare provider.';

  // Auth & Privacy
  static const String loginTitle = 'Welcome back';
  static const String loginSubtitle =
      'Sign in to access your synchronized medication schedule.';
  static const String registerTitle = 'Create Account';
  static const String registerSubtitle =
      'Start managing your prescriptions with total confidence.';
  static const String emailLabel = 'Email Address';
  static const String passwordLabel = 'Password';
  static const String confirmPasswordLabel = 'Confirm Password';
  static const String forgotPassword = 'Forgot Password?';
  static const String signInButton = 'Sign In';
  static const String registerButton = 'Create Account';
  static const String googleSignIn = 'Continue with Google';
  static const String orDivider = 'OR';
  static const String noAccountPrompt = "Don't have an account? Sign Up";
  static const String alreadyHaveAccountPrompt =
      'Already have an account? Sign In';

  // RA 10173 Privacy Notice
  static const String privacyNoticeTitle =
      'Philippine Data Privacy Act (RA 10173) Consent';
  static const String privacyNoticeBody =
      'In compliance with Republic Act No. 10173 (Data Privacy Act of 2012), your personal and health information (prescriptions, intake times, and doctor notes) is stored privately on your device and in your encrypted cloud account. We never share, sell, or show your health data to advertisers. By continuing, you agree to use RemedyTrack to track your doses and reminders.';
  static const String privacyAccept = 'I Understand and Agree';
  static const String privacyDecline = 'Decline';

  // Navigation Labels
  static const String navHome = 'Today';
  static const String navMedications = 'Medications';
  static const String navHistory = 'Dose History';
  static const String navInventory = 'Stock';
  static const String navReports = 'Reports';
  static const String navInsights = 'Insights';
  static const String navSettings = 'Settings';

  // Dashboard & Schedule Groups
  static const String todaySchedule = "Today's Schedule";
  static const String morningGroup = 'Morning (5:00 AM - 11:59 AM)';
  static const String afternoonGroup = 'Afternoon (12:00 PM - 4:59 PM)';
  static const String eveningGroup = 'Evening (5:00 PM - 8:59 PM)';
  static const String nightGroup = 'Night (9:00 PM - 4:59 AM)';
  static const String noMedicationsScheduled =
      'No doses scheduled for this time.';
  static const String nextDoseLabel = 'Next Dose In';

  // Dose Status Labels
  static const String statusTaken = 'Taken';
  static const String statusLate = 'Late';
  static const String statusMissed = 'Missed';
  static const String statusSkipped = 'Skipped';
  static const String statusSnoozed = 'Snoozed';
  static const String statusLowStock = 'Low Stock';
  static const String statusPending = 'Upcoming';

  // Actions
  static const String actionTake = 'Take';
  static const String actionSkip = 'Skip';
  static const String actionSnooze = 'Snooze';
  static const String actionAddMedication = 'Add Medication';
  static const String actionEditMedication = 'Edit Medication';
  static const String actionDelete = 'Delete';
  static const String actionSave = 'Save';
  static const String actionRefill = 'Refill';
  static const String actionExportPdf = 'Export Doctor Report (PDF)';

  // Inventory & Warnings
  static const String inventoryTitle = 'Medication Stock';
  static const String remainingUnits = 'left';
  static const String lowStockAlert = 'Low Stock Alert';
  static const String refillProjectedDays = 'Estimated supply: ';
  static const String duplicateDoseWarningTitle = 'Potential Duplicate Dose';
  static const String duplicateDoseWarningBody =
      'You logged a dose of this medication recently (less than 30 minutes ago). Are you sure you want to record another dose?';

  // Missed Dose Smart Advice
  static const String missedDoseSmartTitle = 'Missed Dose Guidance';
  static const String missedDoseTakeNowAdvice =
      'More than half the time remains before your next scheduled dose. You may take this dose now. Never double up on your next dose.';
  static const String missedDoseSkipAdvice =
      'Your next scheduled dose is coming up soon (less than half the interval remaining). It is recommended to skip this missed dose to prevent stacking. Confirm with your pharmacist.';

  // As-Needed Medications
  static const String prnTitle = 'Log As-Needed Dose';
  static const String prnIntervalWarning =
      'It is too soon for another dose based on your minimum wait time.';
  static const String prnDailyMaxExceeded =
      'You have reached your safe daily limit for this medicine. Check with your doctor or pharmacist.';
}
