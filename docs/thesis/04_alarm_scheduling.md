# RemedyTrack Alarm Scheduling & Notification Architecture

## Overview
Reliable medication adherence requires alarms to sound at the exact second scheduled, regardless of Android Doze mode, iOS background execution restrictions, app updates, or device reboot.

RemedyTrack implements a fault-tolerant alarm architecture compliant with **Google Play Exact Alarm Policies** and **Philippine RA 10173 (Privacy by Design)**.

---

## Alarm Scheduling & Firing Sequence

```mermaid
sequenceDiagram
    autonumber
    actor User as Patient
    participant UI as Dashboard / ViewModel
    participant Scheduler as AlarmScheduler
    participant FLN as flutter_local_notifications
    participant OS as Android / iOS Alarm Manager
    participant Receiver as Boot & Timezone Receiver
    participant BgWorker as BackgroundWorker (WorkManager)

    User->>UI: Creates or Updates Medication Regimen
    UI->>Scheduler: scheduleAllMedicationAlarms(medications)
    Scheduler->>FLN: zonedSchedule(ExactAllowWhileIdle)
    FLN->>OS: Registers AlarmManager / UNUserNotificationCenter

    Note over OS: System reboots OR Timezone changes
    OS->>Receiver: RECEIVE_BOOT_COMPLETED / TIMEZONE_CHANGED
    Receiver->>Scheduler: rescheduleAllAlarms()
    Scheduler->>FLN: Re-registers all active medication alarms

    Note over OS: Scheduled Alarm Time Arrives (e.g. 08:00 AM)
    OS->>FLN: Fires Exact Notification (High Priority, Insistent)
    FLN->>User: Displays Full-Screen / Lock-Screen Notification Actions<br/>[Taken] [Snooze (+10m)] [Skip]

    alt Patient taps [Taken] from Lock Screen
        User->>FLN: Taps [Taken] Action
        FLN->>Scheduler: notificationTapBackground(Isolate)
        Scheduler->>UI: Flushes Atomic Intake & Decrements Inventory
    else Patient does not acknowledge within 60 minutes
        BgWorker->>BgWorker: Periodic 15m Reconciler executes
        BgWorker->>UI: Reconciles unacknowledged dose to 'missed'
    end
```

---

## Operating System & Policy Declarations

### 1. Google Play Exact Alarm Policy (Android 12, 13, 14+)
- **Selected Permission**: `android.permission.SCHEDULE_EXACT_ALARM`.
- **Policy Justification**: RemedyTrack is classified under **Health & Medication Tracking / Reminders**.
- **Play Console Declaration**: Under Google Play's Exact Alarm Policy, medication reminders are an approved use case because missing a timely dose represents a direct health risk to patients managing chronic conditions (e.g., hypertension, diabetes).
- **Graceful Degradation**: If the user revokes exact alarm permission in Android settings, RemedyTrack detects the state via `Permission.scheduleExactAlarm.isGranted`, activates inexact windowed alarms, and displays a yellow diagnostic banner in the app prompting the user to re-enable exact alarms.

### 2. Device Reboot & Battery Optimization Rescheduling
- **`RECEIVE_BOOT_COMPLETED`**: Android automatically clears alarms when the device powers down. The app registers a broadcast receiver in `AndroidManifest.xml` that catches boot completion and automatically re-populates the exact alarm table from local persistence.
- **Battery Saver / Doze Mode**: All alarms are registered using `androidAllowWhileIdle: true` and `AlarmClock` mode where applicable, ensuring alarms break through Android Doze mode.

### 3. iOS 14+ Rolling Window Scheduler
- **iOS 64-Notification Limit**: iOS enforces a strict operating system limit of 64 scheduled local notifications per application.
- **Rolling Window Architecture**: RemedyTrack generates notifications only for a rolling 7-day window. Whenever the user opens the application or an intake is logged, the window advances forward, guaranteeing the app never exhausts iOS's 64-notification threshold.

### 4. RA 10173 Privacy Compliance for Notifications
- **Default Notification Body**: To prevent sensitive health disclosures to bystanders viewing the patient's lock screen, notification titles and bodies default to:
  - *Title*: "RemedyTrack Reminder"
  - *Body*: "It is time to take your scheduled medication."
- Medication names and strengths are excluded by default unless the patient explicitly toggles "Display Medication Names on Lock Screen" in Privacy Settings.

