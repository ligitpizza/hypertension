# 09 — Decisions, Conflicts & Open Questions

The sources disagree in places. **Order of authority:** Chapter 4 (design) > Chapter 3 (requirements) > Chapter 1 (scope) > `source/hypertension_app_reference.md` (early planning notes).

The code must match the report, because Chapter 5 (Implementation) is assessed against Chapters 3–4. Anything marked **Needs Ch4 update** adds something the report doesn't have yet. Implement the default, and record it in `IMPLEMENTATION_LOG.md` so the report can be updated.

## Decisions (defaults applied)

| ID | Topic | Conflict | Decision | Report impact |
|---|---|---|---|---|
| D-01 | Firestore layout | Ref md: nested `patients/{id}/bp_readings`, `doctors/{id}/clinical_notes`, `family_links`. Ch4: 20 flat top-level collections with `patientId` | **Ch4 flat collections**, names exactly as in `04-data-model.md` (`vital_readings`, not `bp_readings`) | None |
| D-02 | Profile data | Ch4 ERD: PatientProfile/DoctorProfile/FamilyMemberProfile satellite tables. Ch4 §4.2.3 dictionary: role fields merged into `users` | **Merged `users`** (physical design) + separate `health_profiles` | None (Ch4 already explains this) |
| D-03 | Risk score document | Ref md: flat floats + `overallLevel`. Ch4: `scores` map `{value, level}` per complication + `modelUsed` | **Ch4 map.** Overall level = max of the 5 levels, computed at read time. A reduced-confidence flag is returned in the API response only | None. If you'd rather store `overallLevel` / `lowConfidence`: Needs Ch4 update |
| D-04 | ML input features | Ref md: 13 features (incl. alcohol, activity, diet, hypertension years). Ch4 §4.5.1: 12 variables (incl. existing conditions, medication count, days since last reading). Each Kaggle dataset has different columns | **Ch4's 12 variables** are the platform input. `ml/feature_map.json` maps them to each model's dataset columns, with documented defaults for missing ones | Explain the mapping in Ch5 |
| D-05 | Refill alerts | UC5.2 needs remaining supply; `medications` has no quantity | Add `medications.quantityOnHand` (Number) and `refillThresholdDays` (Number, default 7) | **Needs Ch4 update** |
| D-05b | Mobile login role selector | Fig 4.3.1.1 shows Patient/Doctor/Admin selector; Fig 4.3.14.8 has a separate staff login; agreed design separates them | Patient/Family apps: **no role selector**. Staff portal: role from custom claim | Fix the Fig 4.3.1.1 caption/mockup later |
| D-06 | Family linking | Fig 4.3.16.1: family enters the patient's link code, patient approves. Ch4 dictionary only has `users.patientId` (null while pending), with nowhere to store the code or pending request | Add `users.linkCode` (patient, 6-char, regenerable) and a `family_link_requests` collection (`familyMemberId`, `patientId`, `status: pending/approved/rejected`, `createdAt`) | **Needs Ch4 update** |
| D-07 | Device data | FCM tokens and E2E public keys are needed but not modelled | `users/{uid}/fcmTokens/{token}` sub-collection; `users.publicKey` (String) | **Needs Ch4 update** (minor) |
| D-08 | Background jobs | Ref md uses Firebase Cloud Functions; Ch4 deployment has only Cloud Run | **Cloud Scheduler → FastAPI `/internal/jobs/*`** (single backend, matches Ch4; available because of D-19) | Add Cloud Scheduler to deployment diagram (minor) |
| D-09 | E2E encryption vs NLP scan | NFR-2.1 (E2E) means the server can't read messages, but UC10.3 says "the system scans" | **Client-side scan before encryption** (sender) + re-scan after decryption (doctor client). Server stores only ciphertext + `isFlagged` | Clarify in Ch5 |
| D-10 | Triage / alert thresholds | Ch4 says "fixed clinical thresholds" without listing them; ref md gives Mild/Moderate/Emergency bands | Use the ref md bands + red-flag symptom rules (`06-algorithms-and-flows.md` §D, §E). Add `symptom_catalog.isRedFlag` (Boolean) | **Needs Ch4 update** (one field) |
| D-11 | Grab API | Sandbox access requires business onboarding and may not be obtainable | `GrabClient` interface with real + **fake simulator** (timed status webhooks). Demo with whichever works | State it in Ch5 |
| D-12 | NFR-6.1 min Android API | Report placeholder | **minSdk 24 (Android 7.0).** Originally 23; raised at setup (2026-10-12) because Flutter 3.44's own minimum is API 24 | Fill NFR-6.1 placeholder later |
| D-13 | Platform | Ref md says Android/iOS; Ch1 scope says Android only | **Android only** for mobile. Don't configure iOS | None |
| D-14 | Client surfaces | Ref md: one app with role routing. Ch4 sitemap/§4.3.16: Patient app, separate Family app, Staff web portal | **One Flutter codebase, three entrypoints** (`main_patient`, `main_family`, `main_staff`) | None |
| D-15 | AI chat history | Ref md: `patients/{id}/ai_sessions`. Ch4: top-level `agent_messages` | **Ch4 `agent_messages`** | None |
| D-16 | Data export | DataExport entity exists in diagrams but has no ERD table/collection | Generate the export on demand (JSON + PDF), no persistence; log to `audit_logs` | None |
| D-17 | Emergency number | Mockups say "911" | **999** (Malaysia) | Fix mockup text later |
| D-18 | Overall triage/alert naming | Alert levels Mild/Moderate/Emergency (FR-9.1) vs triage outcomes monitor/contact/emergency (FR-14.3) | Keep both as separate enums; don't merge | None |
| D-19 | Cloud plan | Cloud Run, Cloud Storage and Cloud Scheduler all require billing; Spark alternatives (Render, Supabase) would break the Ch4 deployment design | **Firebase Blaze plan** (pay-as-you-go, $300 trial credit if eligible), budget alert, `max-instances=2` | None (matches Ch4) |
| D-20 | Region | Not specified in the report | **asia-southeast1** for all regional services (Firestore/Storage regions are permanent) | Can mention in Ch5 |
| D-21 | Deployment cadence | Report doesn't say when to deploy | Walking-skeleton deploy at end of Increment 0, redeploy at the end of every increment; daily dev on emulators | Ch5 describes it |
| D-22 | Email provider | Ch1 scope names SendGrid; its free tier is reportedly discontinued | `EmailClient` adapter with a console fake in dev. **Agreed with Ping (2026-10-12): Brevo** (free transactional tier) is the real provider. Staff accounts get a Firebase password-setup link by email (UC1.5 step 5) | Update the Ch1 scope wording if the provider changes |
| D-23 | Android application IDs | docs/00 suggested `my.edu.tarumt.careflow.*` | **Agreed with Ping (2026-10-12):** patient flavor `fyp.hypertension.patient`, family flavor `fyp.hypertension.family` (Android namespace `fyp.hypertension`). Dart package name `hypertension` (`flutter create --org fyp --project-name hypertension`) | Mention in Ch5 (build config) |
| D-24 | Task runner | docs/08 says `make test/lint/emulators`; docs/10 lists `.sh` deploy scripts. `make` is not installed on Ping's Windows machine | **Agreed with Ping (2026-10-12):** one cross-platform `tasks.py` at the repo root (`python tasks.py test|lint|emulators|deploy-backend|deploy-web|deploy-rules|create-scheduler-jobs|...`) replaces the Makefile and `.sh` scripts | None |
| D-25 | Onboarding data shape | `health_profiles` has three String fields, but the Inc 2 risk model needs specific values (BMI, smoking, family history, conditions) | **Agreed with Ping (2026-10-12):** each field stores a **JSON object** (Ch4: "Structured/free-text"). `personalInfo` = {heightCm, weightKg, phone, emergencyContact{name, phone, relationship}}; `medicalHistory` = {hypertensionDiagnosedYear, conditions[], familyHistory[], allergies, notes}; `lifestyleFactors` = {smokingStatus, alcohol, exerciseDaysPerWeek, saltIntake}. `dateOfBirth` and `gender` are collected at onboarding and stored on `users` (Ch4 dictionary). Partial progress (UC1.4 A1) is kept on the device until submit | Describe the JSON shape in Ch5 |
| D-26 | Mobile login role toggle | Fig 4.3.1.1 shows a Patient/Family toggle; D-05b said no selector on mobile | **Agreed with Ping (2026-10-12): keep the toggle as in the mockup** (supersedes D-05b for mobile). The selected role must match the account's `role` claim **and** the app (Patient app = patient, Family app = family_member); otherwise sign-in is refused with "Please use the CareFlow Family app" / "Please use the CareFlow app". Staff portal toggle (Fig 4.3.14.8) works the same way | None (matches mockup) |
| D-27 | Failed-login auditing | FR-1.5 + audit-log mockup show failed logins, but Firebase sign-in happens on the device | **Agreed with Ping (2026-10-12):** audit LOGIN and LOGOUT through authenticated endpoints; failed attempts go to an unauthenticated, rate-limited endpoint that stores only the email **domain** and the failure reason (no full email, no password) | Mention in Ch5 |
| D-28 | Minimum patient age | The report sets no age limit | **Requested by Ping (2026-10-13):** patients must be **at least 13**. Onboarding's date picker only offers dates 13+ years ago and the backend rejects younger dates of birth (`422`, "You must be at least 13 years old") | Mention in Ch5 |
| D-29 | ML training data | Planning notes listed Framingham (CAD), Pima (T2D), fedesoriano (stroke), UCI heart-failure records and UCI CKD. Chapters 1–4 only require public datasets, the 12 inputs and AUC ≥ 0.80. Pima relies on blood glucose; the UCI HF set predicts death in existing HF patients; the UCI CKD set diagnoses CKD from kidney labs; none of those inputs exist in the app | **Agreed with Ping (2026-10-13):** **NHANES 2011–2018** (US CDC, public domain; measured BP, pulse, BMI, smoking, BP medication, medication count, family history) as the main source for all five complications (stroke, CAD, heart failure, CKD, T2D), with **Framingham** as a true future-risk CAD cross-check. Lab values may define outcomes (e.g. CKD = eGFR < 60 or ACR ≥ 30) but are never model inputs. NHANES is cross-sectional (association with having the condition, not 10-year incidence); stated as a limitation. Final model selection waits for honest AUC results | **Ch1 wording** "Kaggle datasets" → "public datasets (CDC NHANES, Framingham)"; explain in Ch5 |

## Open questions for Ping (Claude Code: ask before implementing these)

1. **Grab:** do you have Grab Express sandbox credentials? If not, the fake simulator is the default (D-11).
2. **Stripe amounts:** where do medication prices come from? Default: a static `price` per prescription item entered by the pharmacist/admin. This would need a field (Needs Ch4 update).
3. **Appointment slots:** what are the doctor working hours / slot length? Default: Mon–Fri, 09:00–17:00, 30-min slots, configurable in code.
4. **Family visibility:** FR-14.2 says real-time BP for linked family. The interview respondent wanted emergency-only, and the survey supports tiered sharing. Default: FR-14.2 as written (always visible). Add a patient toggle "share everyday readings" only if you approve (Needs Ch3/Ch4 update).
5. **Doctor auto-assign** (Fig 4.3.14.2): is auto-assign by lowest caseload OK? (Default: yes.)
6. ~~**Email provider** (D-22)~~ — resolved 2026-10-12: Brevo.

## Report fixes noted (for Ping, not for Claude Code)

- Ch3 §3.8: change "26 functional requirements" to **52**.
- Ch3 NFR-6.1: fill in the Android API level (D-12).
- Ch4 additions from D-05, D-06, D-07, D-08, D-10 once implemented.
- Ch4 open diagram items:
  - stale frame numbers in the Module 10–13 sequence images
  - Module 13 diagram doesn't write `payment_transactions` / `delivery_tracking_events`
  - Module 9 never creates EmergencyAlert
  - AI Health Agent diagram uses `profile:User` instead of `profile:PatientProfile`
  - DataExport has no table
  - Doctor sitemap missing Calendar + Prescription screens
