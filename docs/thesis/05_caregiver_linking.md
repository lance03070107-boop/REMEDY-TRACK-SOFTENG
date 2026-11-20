# RemedyTrack Caregiver Linking & RBAC Architecture

## Overview
RemedyTrack features a secure, **Role-Based Access Control (RBAC)** caregiver delegation flow designed to allow family members and professional caregivers to monitor patient adherence and supply levels without compromising data integrity.

The system enforces:
1. **Single-Use 6-Digit Pairing Codes** expiring in 24 hours.
2. **Bi-Directional Relationship Verification**.
3. **Strict Read-Only Enforcement** both at the presentation layer and the database layer (Firestore Security Rules).
4. **Immediate Revocation** at any time by the patient.

---

## Caregiver Pairing Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    actor Patient as Patient (Owner)
    participant PatientApp as Patient RemedyTrack App
    participant Firestore as Cloud Firestore
    participant CaregiverApp as Caregiver RemedyTrack App
    actor Caregiver as Caregiver (Viewer)

    Note over Patient,PatientApp: 1. Generate Invite Code
    Patient->>PatientApp: Navigates to Caregivers & Taps "Generate Pairing Code"
    PatientApp->>Firestore: Writes doc to caregiver_invites/{CODE}<br/>(code, patientId, expiresAt: now + 24h, status: 'pending')
    Firestore-->>PatientApp: Confirmation
    PatientApp->>Patient: Displays 6-character monospace code with 24h countdown timer

    Note over Patient,Caregiver: 2. Out-of-band Share (SMS / In-person)
    Patient->>Caregiver: Shares Pairing Code (e.g., "RT-8924")

    Note over Caregiver,CaregiverApp: 3. Redeem Pairing Code
    Caregiver->>CaregiverApp: Opens Caregiver View & Taps "Enter Code"
    Caregiver->>CaregiverApp: Enters "RT-8924"
    CaregiverApp->>Firestore: Reads caregiver_invites/RT-8924 & validates:<br/>(status == 'pending' && now < expiresAt)
    CaregiverApp->>Firestore: Creates caregivers/{caregiverUid}_{patientUid}<br/>(status: 'active', permissions: ['read_only'])
    CaregiverApp->>Firestore: Updates users/{patientUid}.caregiverIds.add(caregiverUid)
    CaregiverApp->>Firestore: Updates caregiver_invites/RT-8924 (status: 'redeemed')
    Firestore-->>CaregiverApp: Link confirmed

    Note over CaregiverApp: 4. Dependent Profile Switch
    Caregiver->>CaregiverApp: Switches Active Profile to Patient
    CaregiverApp->>PatientApp: Enforces Read-Only Mode:<br/>- Hides "Take / Skip / Snooze" buttons<br/>- Hides "+ Add Medication" & Inventory Refill FABs<br/>- Shows prominent Caregiver Read-Only Banner

    Note over Patient,Firestore: 5. Revocation (Anytime)
    Patient->>PatientApp: Taps "Revoke Access" for Caregiver
    PatientApp->>Firestore: Updates caregivers/{relId} status = 'revoked'
    PatientApp->>Firestore: Removes caregiverUid from users/{patientUid}.caregiverIds
    Firestore-->>CaregiverApp: Real-time listener immediately blocks access (Permission Denied)
```

---

## Role-Based Access Control (RBAC) Guarantees

| Capability | Patient (Owner) | Active Caregiver (Viewer) | Revoked Caregiver |
| :--- | :---: | :---: | :---: |
| **View Medication Regimens** | Allowed | **Allowed (Read-Only)** | Denied |
| **Add / Edit / Delete Medications** | Allowed | **Denied** | Denied |
| **View Intake Logs & Adherence Charts** | Allowed | **Allowed (Read-Only)** | Denied |
| **Log Intake (Taken / Skipped / Snooze)** | Allowed | **Denied** | Denied |
| **View Inventory Balances & Refill Dates**| Allowed | **Allowed (Read-Only)** | Denied |
| **Restock / Refill Inventory** | Allowed | **Denied** | Denied |
| **View Emergency Card** | Allowed | **Allowed (Read-Only)** | Denied |
| **Revoke Caregiver Relationship** | Allowed | Denied | Denied |

---

## UI Enforcement vs Database Enforcement

1. **Client-Side UI Enforcement**:
   - When a caregiver switches their active profile to a dependent, `CaregiverViewModel.isCaregiverMode` evaluates to `true`.
   - All action buttons on `DashboardView` (Take, Skip, Snooze), `MedicationListView` (Add, Edit, Delete), and `InventoryView` (Refill, Restock) are dynamically hidden.
   - A persistent peach-accented banner informs the caregiver: *"Caregiver Read-Only Mode: Viewing [Patient Name]. Intake logging is disabled."*

2. **Server-Side Security Rules Enforcement**:
   - Even if client code is modified, Cloud Firestore security rules strictly evaluate `isCaregiverOf(patientId)`.
   - Write operations (`create`, `update`, `delete`) on medications, logs, and inventory require `request.auth.uid == resource.data.userId`.
   - A caregiver attempting to write directly receives an immediate Firestore permission denial (`PERMISSION_DENIED`).

