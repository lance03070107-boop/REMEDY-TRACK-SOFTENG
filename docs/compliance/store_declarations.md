# Store Declarations & Compliance Guide

**Application ID:** `com.remedytrack.app`  
**App Name:** RemedyTrack: Medicine Reminder  
**Target Platforms:** Google Play Console & Apple App Store Connect

---

## 1. Google Play Data Safety Questionnaire (Exact Copy-Paste Answers)

### Section 1: Data Collection & Sharing Overview
* **Does your app collect or share any of the required user data types?**  
  &rarr; **Yes**
* **Is all of the user data collected by your app encrypted in transit?**  
  &rarr; **Yes** (All cloud traffic is transmitted over TLS 1.3 / HTTPS).
* **Do you provide a way for users to request that their data be deleted?**  
  &rarr; **Yes** (Directly in-app via Settings &rarr; Account &rarr; Delete Account, and via email).

---

### Section 2: Data Types Breakdown

#### Category: Personal Info
1. **Name**
   * **Collected?** Yes | **Shared?** No
   * **Ephemeral?** No (Stored in Firestore profile)
   * **Required or Optional?** Optional (User display name)
   * **Purpose:** App functionality, Personalization, Caregiver identification.

2. **Email Address**
   * **Collected?** Yes | **Shared?** No
   * **Ephemeral?** No
   * **Required or Optional?** Required (Account login & OTP verification)
   * **Purpose:** App functionality, Account management.

3. **User IDs**
   * **Collected?** Yes | **Shared?** No
   * **Ephemeral?** No (Firebase Auth UID)
   * **Required or Optional?** Required
   * **Purpose:** App functionality, Account management, Security.

---

#### Category: Health and Fitness
1. **Health Info**
   * **Collected?** Yes | **Shared?** No (Shared with third parties: No. Shared with authorized caregiver chosen by user: Yes, strictly read-only)
   * **Ephemeral?** No (Medication names, dosage schedules, intake logs, inventory counts)
   * **Required or Optional?** Required for core app functionality
   * **Purpose:** App functionality (Medication reminders, adherence logs, inventory refill alerts).

---

#### Category: App Info and Performance
1. **Crash Logs**
   * **Collected?** Yes | **Shared?** No
   * **Ephemeral?** No (Processed by Firebase Crashlytics)
   * **Required or Optional?** Required
   * **Purpose:** Analytics, Diagnostics (PII is stripped prior to sending).

2. **Device or Other IDs**
   * **Collected?** Yes | **Shared?** No
   * **Ephemeral?** No (Firebase Cloud Messaging push notification token)
   * **Required or Optional?** Required
   * **Purpose:** App functionality (Delivering medication reminder push notifications).

---

## 2. Google Play Health Apps Declaration

* **Does your app fall under the Health Apps policy?**  
  &rarr; **Yes**
* **Select relevant health app categories:**  
  &rarr; Select: **"Health management and services" &rarr; "Medication management"** (or **"Disease and condition management / Medication adherence"**).
* **Is your app a regulated Medical Device (SaMD)?**  
  &rarr; **No.** RemedyTrack is a non-clinical schedule reminder and adherence logging tool. It does not calculate custom clinical dosages, diagnose disease, or assess drug interactions.
* **Clinical Trials / Human Subjects:**  
  &rarr; **No** (Academic capstone software evaluation).
* **Public Health Authority declaration:**  
  &rarr; **Not applicable** (Independent academic adherence utility).

---

## 3. Google Play Content Rating (IARC Questionnaire)

* **Category:** Consumer / Utility / Health & Fitness
* **Violence:** No
* **Sexuality / Nudity:** No
* **Language:** No profanity
* **Controlled Substances:**  
  * *Question: Does the app reference drugs, alcohol, or tobacco?*  
  * &rarr; **Answer:** **Yes (References prescription and OTC medications solely in an informational/reminder tracking context)**.  
  * *Question: Does the app facilitate the sale of illegal drugs or prescription medication?*  
  * &rarr; **Answer:** **No** (RemedyTrack has no e-commerce, shopping cart, or pharmacy sales).
* **Location Sharing:** No
* **Digital Purchases / In-App Purchases:** No
* **Resulting Rating:** Typically **PEGI 3 / ESRB Everyone / Everyone** (Clean utility).

---

## 4. Account Deletion Path (Apple Guideline 5.1.1(v) & Google Play Policy)

Both Apple and Google require an obvious in-app account deletion mechanism AND a publicly accessible web deletion URL:

1. **In-App Deletion Path:**  
   * **Navigation:** `Open RemedyTrack` &rarr; `Tap Settings (bottom nav)` &rarr; `Scroll to Account` &rarr; `Tap "Delete Account"` &rarr; `Confirm Warning Dialog`.  
   * **Behavior:** Atomically purges user profile, emergency card, medication definitions, intake history, inventory records, and unlinks caregivers, followed by immediate Firebase Auth user record deletion.
2. **Public Deletion Request URL:**  
   * URL: `https://remedy-track.web.app/privacy_policy.html#deletion`  
   * **Privacy Policy URL:** `https://remedy-track.web.app/privacy_policy.html`  
   * **Terms of Service URL:** `https://remedy-track.web.app/terms_of_service.html`  
   * **Email Contact:** `dpo@remedytrack.app`  
   * **Data Deleted:** Entire user account record, all medication schedules, intake history, and inventory balance logs.  
   * **Retention:** Complete zero-retention purge within 30 calendar days.

---

## 5. Apple App Privacy "Nutrition Label" Declarations

On Apple App Store Connect:

| Data Type | Collected? | Linked to User Identity? | Used for Tracking? | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Health & Fitness** (Medications, Intake Logs) | Yes | **Yes** | **No** | App Functionality |
| **Contact Info** (Email Address) | Yes | **Yes** | **No** | App Functionality, Account Management |
| **Identifiers** (User ID, Device FCM Token) | Yes | **Yes** | **No** | App Functionality |
| **Diagnostics** (Crash Data, Performance) | Yes | **No** (PII stripped) | **No** | App Functionality, Analytics |

* **Third-Party Tracking:** Check **"No, we do not track users across other companies' apps or websites."**

