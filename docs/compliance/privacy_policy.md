# Privacy Policy for RemedyTrack

**Effective Date:** October 12, 2026  
**Last Updated:** October 12, 2026  
**Status:** **[DRAFT FOR LEGAL COUNSEL REVIEW - COMPLIANT WITH PHILIPPINE REPUBLIC ACT NO. 10173 (DATA PRIVACY ACT OF 2012)]**

---

## 1. Introduction

RemedyTrack ("we", "our", or "the Application") is an academic capstone mobile application developed at Laguna University (Santa Cruz, Laguna, Philippines) designed to assist individuals in managing their medication schedules, adherence logs, and inventory replenishment.

We recognize the sensitive nature of health-related data and are dedicated to safeguarding your personal and health-sensitive information in strict compliance with the **Data Privacy Act of 2012 (Republic Act No. 10173)**, its Implementing Rules and Regulations (IRR), and issuance circulars of the **National Privacy Commission (NPC)** of the Philippines.

---

## 2. Data We Collect (Data Inventory)

In order to provide medication schedule alerts, inventory tracking, and optional caregiver observation, RemedyTrack collects the following categories of data:

### A. Personal Information & Identity Data
* **Account Credentials:** Email address, display name, account creation timestamp, and unique system user identifier (`UID`).
* **Optional Emergency Contact Data:** Designated emergency contact name, phone number, and relationship.

### B. Health-Related Sensitive Personal Information
Under Section 3(l) of RA 10173, medication and medical history constitute Sensitive Personal Information. We process:
* **Medication Profiles:** Medication brand name, generic name, dosage strength (e.g., 500 mg), dosage form (tablet, capsule, syrup, inhaler, etc.), daily frequency, intake instructions, and color tags.
* **Intake & Adherence Logs:** Scheduled dosage times, actual logged timestamp, dose acknowledgement status (`taken`, `skipped`, `snoozed`, `missed`), and optional user notes.
* **Supply & Inventory Balances:** Current medication counts, refill reserve thresholds, projected refill dates, and transaction logs.

### C. Technical & Diagnostic Information
* **Device Identifiers & Push Tokens:** Firebase Cloud Messaging (FCM) device registration tokens utilized solely for delivering notification reminders.
* **Crash & Performance Diagnostics:** Automated crash reports via Firebase Crashlytics. **PII Scrubbing Policy:** Crash logs are scrubbed to eliminate names, email addresses, specific medication names, and dosages; crash reports are linked solely to an opaque alphanumeric user ID for debugging.
* **Biometric Authentication Data:** RemedyTrack does **not** collect, store, or transmit biometric data (fingerprint or facial geometry). Biometric authentication is handled strictly on-device through the operating system's secure biometric hardware APIs (`Android BiometricPrompt` and Apple `LocalAuthentication`).

---

## 3. Purpose and Legal Basis for Processing

We process your data strictly under the legal grounds provided by Section 12 and Section 13 of RA 10173:
1. **Explicit Consent (Section 13(a)):** You provide unambiguous, informed consent upon account creation and privacy agreement to process your health schedule.
2. **Core Functionality (Contractual Necessity):** Delivering exact medication alarms, tracking dose logs, and managing low-stock alerts.
3. **Caregiver Delegation:** If you choose to link a caregiver, you initiate and approve explicit, single-use authorization to share read-only adherence data.

---

## 4. Caregiver Sharing & Access Control

RemedyTrack includes an optional caregiver observation mechanism:
* Access is granted exclusively through patient-initiated single-use pairing codes.
* Caregiver access is **read-only** and covers schedules, intake history, and inventory levels.
* Caregivers cannot alter, edit, or delete the patient's schedule, prescriptions, or inventory.
* Patients retain absolute control and may revoke caregiver access at any time with immediate effect.

---

## 5. Data Storage, Security & International Transfers

* **Hosting Infrastructure:** Backend database and serverless cloud functions are hosted on Google Cloud Platform / Firebase in the Southeast Asia region (`asia-southeast1` - Singapore).
* **Encryption in Transit:** All network traffic between your mobile device and cloud servers is enforced via Transport Layer Security (TLS 1.3 / HTTPS).
* **Encryption at Rest:** All data stored within Google Cloud Firestore is encrypted at rest using AES-256.
* **Access Rules & Least Privilege:** Role-based access rules enforce strict isolation: no user can access another user's health data unless explicitly authorized via verified caregiver relationship documents.
* **Application Security:** The application disables cleartext HTTP traffic, disables unencrypted OS cloud backups (`android:allowBackup="false"`), and uses ProGuard/R8 code obfuscation.

---

## 6. Data Retention and Account Erasure (Right to Erasure)

In compliance with the Data Privacy Act of 2012 and Google Play / Apple App Store account deletion mandates:
1. **Retention Period:** We retain your data only for as long as your account remains active.
2. **In-App Account Deletion:** You may permanently erase your account at any time directly within the application:
   * Navigate to **Settings** > **Account** > **Delete Account**.
   * Confirm deletion.
   * RemedyTrack permanently and irrevocably deletes your user profile, emergency card, medications, intake logs, inventory, caregiver connections, and Firebase Auth account from all cloud servers.
3. **Web / External Deletion Request:** If you have uninstalled the app or cannot log in, you may request deletion by emailing the Data Protection Officer at `dpo@remedytrack.app`. Erasure requests are completed within thirty (30) calendar days.

---

## 7. Your Rights Under RA 10173

As a data subject under Philippine law, you are entitled to:
1. **Right to Be Informed:** To know what personal data is being processed, why, and how.
2. **Right to Access:** To obtain a copy of your personal data held by RemedyTrack.
3. **Right to Rectification:** To dispute inaccuracies or rectify errors in your medication logs or profile.
4. **Right to Erasure or Blocking:** To withdraw consent and demand the removal and destruction of your data.
5. **Right to Damages:** To be indemnified for any damages sustained due to inaccurate, false, unlawfully obtained, or unauthorized use of personal data.
6. **Right to File a Complaint:** You have the right to file a complaint with the National Privacy Commission (NPC) at https://privacy.gov.ph if your privacy rights have been violated.

---

## 8. Third-Party Service Providers

We utilize trusted third-party cloud services that meet strict industry security standards (ISO/IEC 27001, SOC 2):
* **Google Firebase (Google LLC):** Cloud Firestore (database), Firebase Authentication (identity verification), Firebase Cloud Messaging (notifications), and Firebase Crashlytics (crash reporting).
* **Transactional Email Infrastructure:** Dedicated cloud transactional mail API utilized solely for sending one-time account verification OTP codes and security notices.

We do not sell, rent, monetize, or disclose your health data to advertising brokers, insurers, pharmaceutical marketers, or analytics brokers.

---

## 9. Contact Our Data Protection Officer (DPO)

For inquiries, privacy concerns, or to exercise your statutory rights under the Data Privacy Act of 2012, please reach out to our designated Data Protection Officer:

* **Attn:** Data Protection Officer (DPO)
* **Project:** RemedyTrack Capstone Research Team
* **Affiliation:** College of Computer Studies, Laguna University
* **Address:** Laguna Sports Complex, Brgy. Bubukal, Santa Cruz, Laguna, 4009, Philippines
* **Email:** `dpo@remedytrack.app` / `lance.aclan@remedytrack.app`

---

*Notice: This document is a draft prepared for academic capstone deployment and store publishing compliance. Prior to formal commercial deployment, formal endorsement by an accredited Philippine privacy practitioner is advised.*

