# RemedyTrack Data Model & Entity-Relationship Diagram (ERD)

## Overview
RemedyTrack utilizes **Cloud Firestore** as a NoSQL document database. To guarantee multi-tenant security, strict user isolation, and role-based caregiver access, each document in the patient domain carries an immutable `userId` reference.

All data structures comply with the **Philippine Data Privacy Act of 2012 (RA 10173)**, treating health regimens and intake logs as Sensitive Personal Information (SPI).

---

## Entity-Relationship Diagram (ERD)

```mermaid
erDiagram
    USERS ||--o{ MEDICATIONS : "configures"
    USERS ||--o{ INTAKE_LOGS : "records"
    USERS ||--o{ INVENTORY : "tracks"
    USERS ||--o{ APPOINTMENTS : "schedules"
    USERS ||--o| EMERGENCY_CARD : "maintains"
    USERS ||--o{ CAREGIVERS : "authorizes"
    CAREGIVER_INVITES ||--|| USERS : "generated_by"
    MEDICATIONS ||--o{ INTAKE_LOGS : "logs_for"
    MEDICATIONS ||--o| INVENTORY : "monitors_supply"

    USERS {
        string id PK "Unique Auth UID"
        string email "Patient Email"
        string displayName "Full Name"
        string fcmToken "FCM Push Token"
        list caregiverIds "Authorized Caregiver UIDs"
        timestamp createdAt "Registration Timestamp"
    }

    MEDICATIONS {
        string id PK "Medication ID"
        string userId FK "Owner UID"
        string name "Brand or Common Name"
        string genericName "Generic Active Ingredient"
        string strength "Strength (e.g., 5mg, 500mg)"
        string form "tablet, capsule, syrup, etc."
        float doseAmount "Prescribed Unit Dose"
        string instructions "Clinical instructions"
        map schedule "Frequency & timesOfDay"
        boolean isPrn "As-Needed Flag"
        int minIntervalHours "PRN Min Gap"
        float dailyMaxDose "PRN 24h Cap"
        boolean isActive "Active Regimen Flag"
        timestamp createdAt "Creation Timestamp"
        timestamp updatedAt "Last Update Timestamp"
    }

    INTAKE_LOGS {
        string id PK "Deterministic: medId_timestampMinute"
        string userId FK "Owner UID"
        string medicationId FK "Associated Medication"
        string medicationName "Snapshot of Med Name"
        timestamp scheduledTime "Prescribed Dose Time"
        timestamp recordedTime "Actual User Action Time"
        string status "taken, skipped, snoozed, missed"
        float doseAmount "Units consumed"
        string notes "Patient notes or reasons"
    }

    INVENTORY {
        string id PK "Inventory Record ID"
        string userId FK "Owner UID"
        string medicationId FK "Associated Medication"
        float currentStock "Remaining Balance"
        float lowStockThreshold "Refill Reserve Alert Point"
        string unit "tablets, capsules, mL, puffs"
        timestamp lastRefillDate "Date of Last Restock"
        string notes "Notes"
    }

    CAREGIVERS {
        string id PK "caregiverId_patientId"
        string patientId FK "Patient UID (Owner)"
        string caregiverId FK "Caregiver UID (Viewer)"
        string status "active, revoked"
        map permissions "canViewMedications, canViewLogs, canViewInventory"
        timestamp createdAt "Pairing Timestamp"
    }

    CAREGIVER_INVITES {
        string code PK "6-character alphanumeric pairing code"
        string patientId FK "Inviting Patient UID"
        string patientName "Inviting Patient Name"
        timestamp expiresAt "24-Hour Expiration"
        string status "pending, redeemed, expired"
    }

    EMERGENCY_CARD {
        string id PK "users/{uid}/emergency/card"
        string bloodType "ABO/Rh Blood Type"
        list allergies "Known Drug/Food Allergies"
        list emergencyContacts "ICE Phone Numbers"
        string physicianContact "Doctor Contact"
    }
```

---

## Firestore Collection Schema Dictionary

### 1. `users/{userId}`
- **Purpose**: Core patient identity document.
- **Security**: Readable/writable only by authenticated owner. Active caregivers in `caregiverIds` have read permissions.
- **Fields**:
  - `id`: `String` (Firebase Auth UID)
  - `email`: `String` (RFC 5322 formatted email)
  - `displayName`: `String` (Max 100 characters)
  - `caregiverIds`: `List<String>` (UIDs of authorized active caregivers)
  - `createdAt`: `Timestamp`

### 2. `medications/{medicationId}`
- **Purpose**: Prescribed medication regimens and dosage rules.
- **Security**: Owner read/write. Active caregivers read-only.
- **Key Fields**:
  - `form`: `String` (`tablet`, `capsule`, `syrup`, `inhaler`, `injection`, `drops`, `topical`).
  - `schedule`: `Map` containing `frequency` (`daily`, `specificWeekdays`, `everyXDays`, `cycleBased`), `timesOfDay` (`List<String>` HH:mm), and `startDate`.
  - `isPrn`: `Boolean` flag enabling PRN safe-guard arithmetic (`minIntervalHours` and `dailyMaxDose`).

### 3. `intake_logs/{logId}`
- **Purpose**: Immutable and reconcilable historical audit trail of doses.
- **Deterministic ID Formula**: `${medicationId}_${scheduledTime.millisecondsSinceEpoch ~/ 60000}`.
- **Status Enum**: `taken`, `skipped`, `snoozed`, `missed`.

### 4. `inventory/{itemId}`
- **Purpose**: Medication stock balance and refill reserve tracking.
- **Arithmetic Invariant**: Decremented atomically ONLY for dosage forms `tablet` and `capsule` upon `taken` doses. Skipped and missed doses never alter stock.

### 5. `caregivers/{relationshipId}`
- **Purpose**: Bi-directional, revocable link establishing caregiver authorization.
- **Document ID**: `${caregiverUid}_${patientUid}`.
- **Status**: `active` or `revoked`. Revocation immediately disables caregiver Firestore access.

### 6. `caregiver_invites/{code}`
- **Purpose**: Ephemeral 24-hour pairing challenge for caregiver onboarding.
- **Code Format**: 6-character cryptographically secure uppercase alphanumeric string. Single-use only.

