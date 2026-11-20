# RemedyTrack Physical Device Verification Matrix (Phase 1)

**Specification:** ISO/IEC 25010 Reliability, Fault Tolerance, and Time-Behavior Suite  
**Status:** All tests initialized to `NOT VERIFIED` pending physical hardware execution.

---

## 1. Test Devices

| Device Identifier | Hardware / Model | OS Version | OEM Skin / Battery Architecture | Status |
|---|---|---|---|---|
| **DEV-01** | Google Pixel 8 / 9 | Android 14 / 15 (AOSP) | Stock Android, Standard Doze | **NOT VERIFIED** |
| **DEV-02** | Samsung Galaxy A54 / S23 | Android 14 (One UI 6.x) | One UI, "Put unused apps to sleep", Adaptive Battery | **NOT VERIFIED** |
| **DEV-03** | Xiaomi Redmi Note 12 / 13 | HyperOS / MIUI 14 | MIUI Battery Saver, Autostart restrictions | **NOT VERIFIED** |
| **DEV-04** | Oppo Reno / Vivo V-series | ColorOS 13 / Funtouch OS | Background freeze, aggressive standby kill | **NOT VERIFIED** |
| **DEV-05** | iPhone 14 / 15 / 16 | iOS 17 / 18 | UNUserNotificationCenter, Focus Modes, Time Sensitive | **NOT VERIFIED** |

---

## 2. Test Execution Scenarios & Expected Outcomes

| Scenario ID | Test Condition | Action / Stimulus | Expected Behavior | Verification Status | Notes / Logs |
|---|---|---|---|---|---|
| **SC-01** | App killed / swiped away | Scheduled alarm triggers while app task is swiped from Recent Apps | Alarm rings on `STREAM_ALARM`, notification displays full-screen intent / heads-up banner with Taken, Snooze, Skip | **NOT VERIFIED** | Target: Pixel, Samsung, Xiaomi |
| **SC-02** | Device cold reboot | Device powered off and rebooted; app not opened after boot | Alarms re-arm after `BOOT_COMPLETED`; alarms ring on exact schedule without opening app | **NOT VERIFIED** | Target: All Android devices |
| **SC-03** | Airplane mode / Offline | Device placed in Airplane Mode for 24 hours | Alarms ring strictly offline from local hardware timers; Taken/Skip records to durable offline queue; syncs upon reconnect | **NOT VERIFIED** | Target: All devices |
| **SC-04** | Timezone change | System timezone shifted (e.g. Asia/Manila to UTC+0 or UTC+9) | `FlutterTimezone` and `tz.local` re-anchor; alarms ring at correct local clock time (e.g. 8:00 AM local time) | **NOT VERIFIED** | Target: Android & iOS |
| **SC-05** | DST Transition | System clock crosses Daylight Saving Time boundary | Date-only UTC arithmetic in `ScheduleExpander` prevents 1-hour drift or duplicate alarms | **NOT VERIFIED** | Target: Android & iOS |
| **SC-06** | 7+ days unopened | App remains killed and unopened for 7 consecutive days | WorkManager periodic task refuels rolling-window from `LocalMedicationCache`; alarms continue ringing past day 3 | **NOT VERIFIED** | Target: Pixel, Samsung |
| **SC-07** | Heavy regimen (5 meds × 4 doses) | 20 doses scheduled per day across 5 active maintenance prescriptions | Fair round-robin rolling window protects all 5 meds evenly; cap of 30 alarms respected without starving any medication | **NOT VERIFIED** | Target: All devices |
| **SC-08** | Lock-screen action "Taken" | User taps "Taken" directly from notification action button | In-app alarm and persistent notification silenced; intake atomically written to Firestore/local store; inventory decremented | **NOT VERIFIED** | Target: All devices |
| **SC-09** | Lock-screen action "Snooze" | User taps "Snooze" from notification action button | Dose snoozed for configured minutes; original metadata (`strength`, `instructions`, `colorTag`) preserved; max 3 snoozes enforced | **NOT VERIFIED** | Target: All devices |
| **SC-10** | Lock-screen action "Skip" | User taps "Skip" from notification action button | Alarm silenced; dose logged as skipped; inventory NOT decremented | **NOT VERIFIED** | Target: All devices |
| **SC-11** | Alarm timeout & escalation | Alarm rings continuously for countdown limit without user interaction | In-app audio and primary notification silence after timeout; scheduled escalation alert rings 10-15 minutes later | **NOT VERIFIED** | Target: All devices |
| **SC-12** | Interactive hold-to-confirm | User opens full-screen ringing screen and holds button for 1.2s | Circular hold indicator animates; heavy haptic feedback fires; atomic commit completes before screen dismisses | **NOT VERIFIED** | Target: Android & iOS |
| **SC-13** | Accessibility alternative | TalkBack / VoiceOver enabled or large text scaling active | Accessible action button available without requiring sustained multi-touch hold; text scales without RenderFlex overflow | **NOT VERIFIED** | Target: Android & iOS |
| **SC-14** | Dual audio stream elimination | Alarm fires while device is unlocked | Native notification tone and in-app `audioplayers` tone do not play simultaneously; zero acoustic echo | **NOT VERIFIED** | Target: Android devices |
| **SC-15** | iOS Focus Mode / DND | iPhone placed in "Do Not Disturb" Focus mode | Time Sensitive medication notification banner breaks through DND and delivers acoustic alert | **NOT VERIFIED** | Target: iPhone (DEV-05) |

---

## 3. Sign-off Criteria for Production Release

1. **Pass Rate:** 100% of P0 tests (SC-01, SC-02, SC-03, SC-06, SC-08, SC-11, SC-14) must pass on at least one stock Android (DEV-01) and one aggressive battery saver OEM (DEV-02 or DEV-03).
2. **Crash Count:** 0 crashes or ANRs (Application Not Responding) logged during test passes.
3. **Inventory Integrity:** Inventory count must match expected values with zero phantom decrements.

