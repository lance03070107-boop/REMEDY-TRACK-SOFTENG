# RemedyTrack Production Pre-Launch Checklist & Verification Guide

**Application ID:** `com.remedytrack.app`  
**Bundle ID:** `com.remedytrack.app`  
**Target Stores:** Google Play Store & Apple App Store  
**Last Audited:** October 12, 2026

---

## 1. Master Readiness Status Table

| Domain | Checklist Item | Status | Verification Detail / Path |
| :--- | :--- | :---: | :--- |
| **Android** | Package / Namespace Migration | ✅ **READY** | `namespace = "com.remedytrack.app"` in `build.gradle.kts` & `MainActivity.kt`. |
| **Android** | Release Signing Config | ✅ **READY** | `android/key.properties` dynamic loading wired in `build.gradle.kts`. |
| **Android** | R8 Shrinking & Obfuscation | ✅ **READY** | `isMinifyEnabled = true`, `isShrinkResources = true`, `proguard-rules.pro` verified. |
| **Android** | Permissions & Security Flags | ✅ **READY** | `android:allowBackup="false"`, `usesCleartextTraffic="false"`, unnecessary perms removed. |
| **iOS** | Bundle ID Migration | ✅ **READY** | `PRODUCT_BUNDLE_IDENTIFIER = com.remedytrack.app` in `project.pbxproj`. |
| **iOS** | Privacy Manifest | ✅ **READY** | `ios/Runner/PrivacyInfo.xcprivacy` with Required Reason APIs & data declarations. |
| **iOS** | Encryption Exemption | ✅ **READY** | `ITSAppUsesNonExemptEncryption = false` in `Info.plist`. |
| **Branding** | App Icons & Adaptive Drawables | ✅ **READY** | Generated via `flutter_launcher_icons` (no alpha on iOS; adaptive on Android). |
| **Branding** | Native Splash Screens | ✅ **READY** | Generated via `flutter_native_splash` (Light/Dark mode & Android 12 Splash API). |
| **Compliance** | Privacy Policy (RA 10173) | ✅ **READY** | `docs/compliance/privacy_policy.md` and `privacy_policy.html`. |
| **Compliance** | Terms of Service & Disclaimer | ✅ **READY** | `docs/compliance/terms_of_service.md` and `terms_of_service.html`. |
| **Compliance** | Store Data Safety & IARC | ✅ **READY** | `docs/compliance/store_declarations.md`. |
| **Store Pack** | Store Listing & ASO Copy | ✅ **READY** | `docs/store_listing/store_listing_pack.md`. |
| **CI/CD** | GitHub Actions Workflows | ✅ **READY** | `.github/workflows/flutter_ci.yml` & `functions_ci.yml`. |
| **Firebase** | Project Re-Registration | ⚠️ **ACTION REQ.** | Re-register Android app with `com.remedytrack.app` in Firebase Console. |
| **Google Cloud**| API Key Restrictions | ⚠️ **ACTION REQ.** | Restrict Android & iOS API keys to package SHA-1 and Bundle ID in Cloud Console. |
| **Google Cloud**| Email Enumeration Protection | ⚠️ **ACTION REQ.** | Enable toggle in Firebase Console &rarr; Auth Settings. |
| **Google Cloud**| Cloud Billing Budget Alert | ⚠️ **ACTION REQ.** | Set up $5 / $10 budget alert in Google Cloud Console. |
| **Play Console**| 14-Day Closed Testing Track | ⚠️ **ACTION REQ.** | Recruit 12 / 20 opted-in testers for 14 continuous days. |

---

## 2. Release Keystore Generation & Firebase Fingerprints

### Step 1: Generate the Production Upload Key
Execute the following command in PowerShell / Terminal (replace placeholders with your strong password):

```powershell
keytool -genkey -v -keystore android/app/upload-keystore.jks `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 `
  -alias upload-key `
  -dname "CN=Lance Aclan, OU=RemedyTrack Team, O=Laguna University, L=Santa Cruz, ST=Laguna, C=PH"
```

> **CRITICAL:** Back up `android/app/upload-keystore.jks` in a secure password manager. If you lose this key before enrolling in Google Play App Signing, you cannot update your application.

### Step 2: Extract SHA-1 and SHA-256 Fingerprints
Run:
```powershell
keytool -list -v -keystore android/app/upload-keystore.jks -alias upload-key
```
You will receive output formatted as:
* **SHA-1:** `AA:BB:CC:...`
* **SHA-256:** `11:22:33:...`

### Step 3: Configure `android/key.properties`
Create the file `android/key.properties` (this file is excluded by `.gitignore`):
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload-key
storeFile=upload-keystore.jks
```

---

## 3. Firebase Console Project Re-Registration Guide

Because the application ID changed from `com.example.remedy_track` to `com.remedytrack.app`:

1. Open the [Firebase Console](https://console.firebase.google.com/) and select your project `remedy-track`.
2. Click **Project Settings** (gear icon) &rarr; **General** tab.
3. Scroll down to **Your apps**:
   * Click **Add app** &rarr; select **Android**.
   * **Android package name:** Enter `com.remedytrack.app`.
   * **App nickname:** `RemedyTrack Android`.
   * **Debug signing certificate SHA-1:** Paste your debug SHA-1 (from `~/.android/debug.keystore`).
   * Click **Register app**.
   * Download the newly generated `google-services.json`.
   * Replace the existing file at `android/app/google-services.json`.
4. In Project Settings, under the new `com.remedytrack.app` entry:
   * Click **Add fingerprint**.
   * Add the **Upload Key SHA-1** extracted from `upload-keystore.jks`.
   * Add the **Upload Key SHA-256** extracted from `upload-keystore.jks`.
   *(Note: Once uploaded to Google Play, also copy the **Play App Signing** certificate SHA-1 into Firebase for Google Services and Phone Auth).*

---

## 4. Google Cloud Console API Key Restrictions

1. Navigate to [Google Cloud Console Credentials](https://console.cloud.google.com/apis/credentials).
2. Locate the Android API Key generated by Firebase:
   * **Application restrictions:** Select **Android apps**.
   * **Allowed applications:** Click **Add an item**:
     * Package name: `com.remedytrack.app`
     * SHA-1 fingerprint: Paste your Upload Key SHA-1 and Play App Signing SHA-1.
   * **API restrictions:** Select **Restrict key** &rarr; select:
     * *Firebase Installations API*
     * *Cloud Firestore API*
     * *Identity Toolkit API* (Firebase Auth)
     * *Firebase Cloud Messaging API*
     * *Cloud Functions API*
3. Locate the iOS API Key:
   * **Application restrictions:** Select **iOS apps**.
   * **Bundle identifier:** `com.remedytrack.app`.

---

## 5. Security & Billing Hardening

### A. Email Enumeration Protection
1. In Firebase Console, go to **Authentication** &rarr; **Settings** &rarr; **User actions**.
2. Enable **Email enumeration protection**. This prevents automated scanners from detecting whether an email address exists in your user database.

### B. Google Cloud Billing Budget Alert
1. In Google Cloud Console, navigate to **Billing** &rarr; **Budgets & alerts**.
2. Click **Create Budget**:
   * Name: `RemedyTrack Safety Budget`
   * Target amount: `$5.00` (or `$10.00`).
   * Thresholds: `50%`, `90%`, `100%`.
   * Actions: Enable **Email notifications to billing admins**.

---

## 6. OEM Device Reliability Testing Matrix

Due to aggressive custom battery optimization routines on Android manufacturer skins, test the notification and exact alarm delivery on the following physical device families:

| Manufacturer & OS | Optimization / Setting to Test | Test Procedure & Expected Result |
| :--- | :--- | :--- |
| **Samsung (One UI)** | Sleep & Deep Sleeping Apps | Ensure app is NOT in "Sleeping apps". Test 3 scheduled alarms while screen is locked for 30 minutes. Alarms must fire with sound/heads-up. |
| **Xiaomi (MIUI / HyperOS)** | Autostart & Battery Saver | Set Battery Saver to "No restrictions" and enable "Autostart". Reboot phone; verify scheduled alarms are rescheduled on `BOOT_COMPLETED`. |
| **Google Pixel (Stock Android 14/15)** | Standard Android Doze | Leave phone unplugged overnight. Morning alarm must fire exactly on time via `setExactAndAllowWhileIdle`. |
| **Apple (iOS 16 - 18)** | Focus Modes & Background App Refresh | Test notification category action buttons (`Taken`, `Snooze`, `Skip`) from locked screen and notification center. |

---

## 7. Google Play Console 14-Day Closed Testing Track

For personal Google Play developer accounts created after November 13, 2023, Google requires:
1. **Recruitment:** At least **20 opted-in testers** (or **12 testers** depending on account criteria) must opt into your closed test via email link / web link.
2. **Engagement Duration:** Testers must remain opted-in continuously for **14 consecutive days**.
3. **Application for Production:** After 14 days, complete the application questionnaire in Play Console explaining feedback gathered, bug fixes made, and readiness for production release.

