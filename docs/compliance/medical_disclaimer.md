# Medical Disclaimer Specification

**Project:** RemedyTrack (Laguna University Capstone)  
**Application ID:** `com.remedytrack.app`  
**Governing Standard:** ISO/IEC 25010 Quality Model (Safety, Reliability, Regulatory Transparency)

---

## 1. Master Medical Disclaimer Text

> **REMEDYTRACK IS NOT A MEDICAL DEVICE AND DOES NOT PROVIDE MEDICAL ADVICE, DIAGNOSIS, OR TREATMENT.**  
> 
> RemedyTrack is an informational schedule reminder and medication adherence logging tool developed as an academic capstone research project at Laguna University.
> 
> * **No Clinical Assessment:** RemedyTrack does not assess, verify, or calculate clinical dosages.
> * **No Interaction Checks:** RemedyTrack does not evaluate drug-drug interactions, contraindications, or adverse food-drug interactions.
> * **User Responsibility:** All schedules and quantities entered must conform to the instructions provided by your licensed healthcare provider or pharmacist.
> * **Emergency Situations:** In case of a medical emergency, adverse side effect, or accidental double dosage, immediately call the Philippine Emergency Hotline (**911**) or proceed to the nearest emergency medical facility. Never disregard professional medical advice or delay seeking care because of notifications received from this application.

---

## 2. In-App Surfaces Inventory

The medical disclaimer is surfaced at multiple critical checkpoints across the application journey to ensure complete user informed consent and liability mitigation:

| Surface / Screen | Location & Widget | Enforcement Mode |
| :--- | :--- | :--- |
| **1. First Launch Consent** | `lib/views/onboarding/privacy_consent_view.dart` | **Blocking Gate:** User must explicitly check acknowledgment checkbox before account creation. |
| **2. Login / Register** | `lib/views/auth/register_view.dart` | Clickable hyperlink to Terms of Service & Medical Disclaimer under submit button. |
| **3. App Settings** | `lib/views/settings/settings_view.dart` &rarr; "Medical Disclaimer" | Dedicated list tile opening full scrollable modal dialog (`showDialog`). |
| **4. About Screen** | `lib/views/settings/about_view.dart` | Prominent informational alert box highlighting non-clinical utility. |
| **5. Add Medication Flow** | `lib/views/medications/add_edit_medication_view.dart` | Subtitle notice reminding users to copy dosages strictly from prescription packaging. |
| **6. Store Listings** | Google Play Store & Apple App Store Descriptions | Explicit disclaimer in top 300 words of public store description. |
| **7. Web Landing & Policies** | `docs/compliance/terms_of_service.html` & `docs/compliance/privacy_policy.html` | High-visibility warning box at top of document. |

---

## 3. Regulatory Scope & Boundary

RemedyTrack is strictly scoped as an **Adherence Support Tool** and not as Software as a Medical Device (SaMD):
1. **US FDA Policy on Device Software Functions:** Fits under enforcement discretion for general health and wellness / medication adherence reminders that do not perform automated diagnosis or personalized clinical dosage calculation.
2. **Philippine Food and Drug Administration (FDA) & DOH Guidelines:** Fits non-device digital mobile logging utilities.
3. **Data Integrity:** Dose decrement arithmetic is restricted strictly to solid oral dosage units (tablets and capsules). Liquids, inhalers, and insulin units are excluded from automatic balance reduction to prevent inaccurate dosage assumptions.

