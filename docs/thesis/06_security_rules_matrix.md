# RemedyTrack Cloud Firestore Security Rules Matrix (RBAC & RA 10173)

## Overview
RemedyTrack enforces a strict **Least-Privilege Role-Based Access Control (RBAC)** model in `firestore.rules`.
In compliance with the **Philippine Data Privacy Act of 2012 (RA 10173)**, unauthenticated users have zero access to the database, and patients retain complete data sovereignty with instantaneous caregiver revocation rights.

---

## Security Rules Matrix

| Target Collection / Document | Operation | Unauthenticated | Resource Owner (Patient) | Active Caregiver | Revoked Caregiver | Other Authenticated User |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **`users/{userId}`** | `read` | ❌ Deny | ✅ Allow | ✅ Allow | ❌ Deny | ❌ Deny |
| | `create` | ❌ Deny | ✅ Allow (`uid == userId`) | ❌ Deny | ❌ Deny | ❌ Deny |
| | `update` | ❌ Deny | ✅ Allow (`uid == userId`) | ❌ Deny | ❌ Deny | ❌ Deny |
| | `delete` | ❌ Deny | ✅ Allow (`uid == userId`) | ❌ Deny | ❌ Deny | ❌ Deny |
| **`users/{userId}/emergency/card`** | `read` | ❌ Deny | ✅ Allow | ✅ Allow | ❌ Deny | ❌ Deny |
| | `write` | ❌ Deny | ✅ Allow (`uid == userId`) | ❌ Deny | ❌ Deny | ❌ Deny |
| **`medications/{medId}`** | `read` | ❌ Deny | ✅ Allow | ✅ Allow | ❌ Deny | ❌ Deny |
| | `create` | ❌ Deny | ✅ Allow (Schema Validated) | ❌ Deny | ❌ Deny | ❌ Deny |
| | `update` | ❌ Deny | ✅ Allow (Immutable `userId`) | ❌ Deny | ❌ Deny | ❌ Deny |
| | `delete` | ❌ Deny | ✅ Allow | ❌ Deny | ❌ Deny | ❌ Deny |
| **`intake_logs/{logId}`** | `read` | ❌ Deny | ✅ Allow | ✅ Allow | ❌ Deny | ❌ Deny |
| | `create` | ❌ Deny | ✅ Allow (Schema Validated) | ❌ Deny | ❌ Deny | ❌ Deny |
| | `update` | ❌ Deny | ✅ Allow | ❌ Deny | ❌ Deny | ❌ Deny |
| | `delete` | ❌ Deny | ✅ Allow | ❌ Deny | ❌ Deny | ❌ Deny |
| **`inventory/{itemId}`** | `read` | ❌ Deny | ✅ Allow | ✅ Allow | ❌ Deny | ❌ Deny |
| | `create` | ❌ Deny | ✅ Allow (Schema Validated) | ❌ Deny | ❌ Deny | ❌ Deny |
| | `update` | ❌ Deny | ✅ Allow (Immutable `userId`) | ❌ Deny | ❌ Deny | ❌ Deny |
| | `delete` | ❌ Deny | ✅ Allow | ❌ Deny | ❌ Deny | ❌ Deny |
| **`caregivers/{relId}`** | `read` | ❌ Deny | ✅ Allow | ✅ Allow | ❌ Deny | ❌ Deny |
| | `create` | ❌ Deny | ✅ Allow (Either Party) | ✅ Allow | ❌ Deny | ❌ Deny |
| | `update` | ❌ Deny | ✅ Allow (Patient or Caregiver)| ❌ Deny | ❌ Deny | ❌ Deny |
| | `delete` | ❌ Deny | ✅ Allow (Patient or Caregiver)| ❌ Deny | ❌ Deny | ❌ Deny |
| **`caregiver_invites/{code}`** | `read` | ❌ Deny | ✅ Allow (Pending or Owner)| ✅ Allow (Pending Code) | ❌ Deny | ❌ Deny |
| | `create` | ❌ Deny | ✅ Allow (`uid == patientId`) | ❌ Deny | ❌ Deny | ❌ Deny |
| | `update` | ❌ Deny | ✅ Allow (Redemption) | ✅ Allow (Redemption) | ❌ Deny | ❌ Deny |
| **All Other Collections** | `*` | ❌ Deny | ❌ Deny | ❌ Deny | ❌ Deny | ❌ Deny |

---

## Core Security Rule Logic (`firestore.rules`)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isAuthenticated() {
      return request.auth != null;
    }

    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }

    function isCaregiverOf(patientId) {
      return isAuthenticated() && (
        (exists(/databases/$(database)/documents/users/$(patientId)) &&
         request.auth.uid in get(/databases/$(database)/documents/users/$(patientId)).data.get('caregiverIds', [])) ||
        exists(/databases/$(database)/documents/caregivers/$(request.auth.uid + '_' + patientId)) &&
        get(/databases/$(database)/documents/caregivers/$(request.auth.uid + '_' + patientId)).data.status == 'active'
      );
    }

    // Default deny all unknown paths
    match /{document=**} {
      allow read, write: false;
    }
  }
}
```

---

## Schema Invariants & Anti-Tampering Protections

1. **User ID Immutability**:
   On every document `update`, the rules evaluate `request.resource.data.userId == resource.data.userId`. A malicious user cannot hijack or re-assign an existing medication or log to another account.
2. **String Bounds & Length Clamping**:
   - Medication and User Names: Limited to `<= 100` characters.
   - Clinical Notes: Limited to `<= 500` characters.
   This prevents database abuse, storage bloating, and Denial-of-Service through oversized JSON payloads.
3. **Numeric Type Validation**:
   - `doseAmount`, `currentStock`, and `lowStockThreshold` must be valid `number` types greater than or equal to `0`.
   - Negative inventory balances are strictly rejected at the database boundary.

