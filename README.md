# RemedyTrack: Your Personal Health and Dosage Companion

A production-quality Flutter mobile health application engineered for Android, iOS, Web, and Desktop. Built with Material 3, exact Catppuccin Latte and Mocha palettes, offline-first Cloud Firestore persistence, atomic intake and inventory transactions, and battery-resilient background alarms.

---

## 🚀 Production Deployment & Real Authentication

RemedyTrack is configured for production deployment:
- **Clean Authentication**: Register real accounts directly on `/register` or sign in on `/login`.
- **Firebase Connection**: Automatically initialized across Web, Android, iOS, Windows, and macOS via `DefaultFirebaseOptions.currentPlatform`.
- **Cloud Firestore Persistence**: Offline cache enabled for seamless offline-first capability.
- **Dual-Mode Architecture**: Connected to live Firebase backend when configured; seamlessly provides secure local sessions during offline travel or development.
- **Material 3 Expressive**: 20dp cards, 16dp rounded buttons, 28dp dialogs, 76dp navigation bar with 16dp pill indicators, and adaptive responsive shell (`NavigationBar` on mobile < 640px vs `NavigationRail` on tablet/desktop >= 640px).

---

## 🏗 Architectural Blueprint

```
lib/
  core/
    constants/
      app_constants.dart          # Timing thresholds, storage keys, channel IDs
      app_strings.dart            # Centralized strings (RA 10173 consent & UI)
    errors/
      app_exception.dart          # Domain exception hierarchy
    router/
      app_router.dart             # GoRouter declaration with type-safe routing
    theme/
      catppuccin_colors.dart      # Raw Latte and Mocha hex color constants
      status_colors.dart          # ThemeExtension<StatusColors> for dose states
      app_theme.dart              # Explicit Material 3 ThemeData (Light, Dark, High-Contrast)
    utils/
      date_time_utils.dart        # Safe-interval math, countdown, bucket groups
  models/
    user_profile.dart             # Patient & caregiver metadata + FCM token
    medication.dart               # Prescription entity with PRN constraints
    dose_schedule.dart            # Complex frequencies (daily, intervals, cycles)
    intake_log.dart               # Immutable dose log with status classification
    inventory_item.dart           # Stock depletion, thresholds, and refill metadata
    appointment.dart              # Clinical appointments and doctor consultations
    emergency_info.dart           # Emergency card (blood type, allergies, physician)
  repositories/
    medication_repository.dart    # Abstract contract + Firestore implementation
    intake_repository.dart        # ACID atomic transaction for intake + inventory
    inventory_repository.dart     # Stock updates and refill transactions
    user_repository.dart          # User profiles & Section 16 RA 10173 data erasure
    mock_repositories.dart        # Zero-config synthetic patient repositories for offline development
  services/
    permission_service.dart       # Notification, exact alarm, battery saver, OEM guides
    biometric_service.dart        # Local authentication (Face ID / Fingerprint / PIN)
    notification_service.dart     # flutter_local_notifications channel configuration
    alarm_scheduler.dart          # Exact alarms, lock-screen actions, snooze escalation
    fcm_service.dart              # Firebase Cloud Messaging for caregiver alerts
    pdf_report_service.dart       # Doctor-ready PDF generation & print/share export
  viewmodels/
    auth_viewmodel.dart           # Authentication, RA 10173 consent, account erasure
    settings_viewmodel.dart       # Theme mode, high-contrast, snooze & escalation
    medication_viewmodel.dart     # Registry CRUD, alarm rescheduling, PRN checks
    intake_viewmodel.dart         # Atomic intake recording, late grace, duplicate guards
    inventory_viewmodel.dart      # Stock counts, Peach low-stock alerts, refills
    adherence_viewmodel.dart      # Adherence %, streaks, fl_chart data, PDF triggers
    caregiver_viewmodel.dart      # Multi-profile switching & caregiver FCM triggers
    emergency_viewmodel.dart      # Emergency card persistence
  views/
    splash/
      splash_view.dart            # Animated Mocha splash with auth/biometric gate
    onboarding/
      onboarding_view.dart        # 4 slides with contextual permission requests
    auth/
      login_view.dart             # Email/password authentication & reset dialog
      register_view.dart          # Account creation with RA 10173 consent gate
      privacy_consent_dialog.dart # Statutory RA 10173 consent dialog
    home/
      dashboard_view.dart         # Time-bucket grouped schedule & quick take/skip
    medications/
      medication_list_view.dart   # Registry, search, filtering, and PRN launcher
      add_edit_medication_view.dart # Progressive disclosure medication form
      prn_medication_dialog.dart  # On-demand dose logger with safety warnings
    schedule/
      schedule_view.dart          # Horizontal week calendar and routine inspector
    intake_log/
      intake_history_view.dart    # Filterable chronological dose history
    inventory/
      inventory_view.dart         # Pill counters, Peach low-stock alert, refills
    reports/
      adherence_report_view.dart  # fl_chart analytics, streaks, and PDF export
    profile/
      emergency_card_view.dart    # Rapid emergency medical identification
      caregiver_view.dart         # Multi-profile manager and dependent linking
    settings/
      settings_view.dart          # Theme, snooze, escalation, biometric, erasure
      theme_preview_view.dart     # Catppuccin Latte/Mocha palette showcase
      reliability_check_view.dart # Alarm reliability health check & OEM guides
    widgets/
      status_badge.dart           # Accessible StatusColors paired with icon + text
      custom_text_field.dart      # Material 3 inputs with 48dp touch targets
      action_card.dart            # Accessible card with high-contrast borders
      state_views.dart            # LoadingView, EmptyStateView, and ErrorStateView
  main.dart                       # MultiProvider DI, Firestore persistence, MaterialApp
```

---

## 🔒 Philippine Data Privacy Act (RA 10173) Compliance

1. **Section 12 (Criteria for Lawful Processing):** Explicit, informed consent is obtained at registration via `PrivacyConsentDialog` before clinical data ingestion.
2. **Section 16 (Right to Erasure):** Patients can trigger complete, permanent erasure of their account, prescriptions, logs, and emergency profile in `SettingsView -> Delete Account & All Data`.
3. **Data Minimization & Confidentiality:** Clinical data is strictly bound to the authenticated user's Firebase UID. Zero third-party analytics SDKs are incorporated.

---

## 🎨 Design System: Catppuccin Palette

- **Latte (Light Mode):**
  - Primary: `#1e66f5` (Blue)
  - Secondary: `#179299` (Teal)
  - Tertiary: `#8839ef` (Mauve)
  - Surface: `#eff1f5` (Base)
  - Text: `#4c4f69` (Text)
- **Mocha (Dark Mode):**
  - Primary: `#89b4fa` (Blue)
  - Secondary: `#94e2d5` (Teal)
  - Tertiary: `#cba6f7` (Mauve)
  - Surface: `#1e1e2e` (Base)
  - Text: `#cdd6f4` (Text)
- **Status Colors (ThemeExtension):**
  - Taken: `#40a02b` / `#a6e3a1`
  - Late: `#df8e1d` / `#f9e2af`
  - Missed: `#d20f39` / `#f38ba8` (Red reserved for missed/critical only)
  - Skipped: `#8c8fa1` / `#7f849c`
  - Snoozed: `#04a5e5` / `#89dceb`
  - Low Stock: `#fe640b` / `#fab387` (Peach used, never red)
- **High-Contrast Variant:**
  - Crust (`#11111b`) dark background with high-contrast foreground and 2dp outlines.

---

## ⚡ Setup & Run Instructions

### Prerequisites
- Flutter 3.19+ / Dart 3.3+
- Android Studio / Xcode configured
- Firebase project created with Authentication and Cloud Firestore enabled

### 1. Dependencies Installation
```bash
flutter pub get
```

### 2. Firebase Configuration
Place your downloaded `google-services.json` in `android/app/` and `GoogleService-Info.plist` in `ios/Runner/`.
Deploy the security rules:
```bash
firebase deploy --only firestore:rules
```

### 3. Run Automated Tests
```bash
flutter test
```

### 4. Launch Application
```bash
flutter run
```

---

## 📋 Manual Real-Device Notification Test Checklist

| # | Test Scenario | Steps | Expected Outcome |
|---|---------------|-------|------------------|
| 1 | Exact Scheduled Alarm | Schedule a dose for 2 minutes in future; lock phone screen. | Notification appears on lock screen with sound and full screen intent at exact minute. |
| 2 | Lock Screen "Taken" Action | Tap "Taken" button directly on lock screen notification banner. | Dose logs as "Taken", inventory stock decrements by prescribed units without app launch. |
| 3 | Snooze Action | Tap "Snooze" action on notification. | Notification dismisses; follow-up alarm triggers precisely after configured snooze minutes. |
| 4 | Escalation Re-Alert | Ignore notification for 15 minutes. | Secondary escalation notification triggers: "URGENT REMINDER: Unconfirmed dose". |
| 5 | Device Reboot Rescheduling | Schedule dose for tomorrow. Reboot device. | `BOOT_COMPLETED` receiver catches broadcast; alarm remains scheduled and fires on time. |
| 6 | Late Grace Window | Take dose 75 minutes after scheduled time. | Dose is logged with status `Late` (orange badge), rather than `Missed`. |
| 7 | Duplicate Dose Guard | Log a dose, then immediately attempt to log the same dose within 30 minutes. | Warning dialog pops up warning against accidental duplicate administration. |
| 8 | PRN Safety Gate | Log PRN dose, then attempt another before configured minimum interval. | Safety warning dialog blocks intake, stating remaining minutes required before next safe dose. |

---

## ⚠️ Known Limitations
1. **Aggressive OEM Task Killers:** Certain Xiaomi (MIUI) and Huawei (EMUI) OS builds terminate exact alarm broadcasts if "Autostart" and "No restrictions" are not manually granted in OS Settings. The in-app **Reliability Check Screen** provides one-tap guides for these vendors.
2. **FCM Caregiver Push Delivery:** Pushes dispatched across devices require an active Firebase Cloud Function or server backend with FCM Admin SDK credentials. The mobile client implements the token handshake and delivery interface.
