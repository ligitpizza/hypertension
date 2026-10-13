# Implementation Log

Raw notes for FYP Chapter 5. Append one entry per completed module.

## Template

### YYYY-MM-DD — Increment N — Module X: <name>
- FRs implemented: FR-x.x, …
- Use-case exception flows handled: UCx.x E1, …
- Tests: N unit, N widget, N rules, N integration (all passing)
- Deviations / additions vs Chapter 4: (new fields/collections, changed flows — with reason)
- Known limitations:

---

### 2026-10-12 — Increment 0 — Project setup (walking skeleton)
- Scope: monorepo skeleton (app/, backend/, firebase/, tasks.py, .vscode/), Flutter app with
  `patient`/`family` flavors + `main_staff.dart` web entrypoint, Firebase apps registered via
  flutterfire, emulator wiring, FastAPI skeleton (auth dependency, audit logger, health,
  `/internal/jobs/heartbeat`), shared enums + `docs/fixtures/enums.json`, Firestore/Storage
  rules baseline + composite indexes, emulator seed (symptom_catalog + 1 demo account per role),
  deploy artefacts (Dockerfile, tasks.py deploy-*), commit-msg hook active.
- FRs touched (foundations only): FR-1.3 (role claim check + `require_roles`), FR-1.5 (audit
  logger), NFR-2.2 (deny-by-default rules), NFR-2.4 (debug-only cleartext), NFR-4.2 (offline
  persistence), NFR-3.1 (48 dp targets in theme).
- Tests: 23 Dart (20 unit enum-parity, 3 widget: loading/data/error), 42 pytest, 28 rules
  (Firestore + Storage, every role) — all passing. `flutter analyze`, ruff, ruff format, mypy
  --strict clean.
- Local verification: emulators + seed run; emulator sign-in as demo doctor -> FastAPI
  `/api/v1/health/auth` returns role `doctor`; heartbeat job writes `audit_logs` in the emulator.
  Staff portal web release build compiles.
- Deployed (walking skeleton, 2026-10-12):
  - Firestore rules + indexes, Storage rules.
  - Cloud Run `careflow-api` revision `careflow-api-00002-c5t` (asia-southeast1, min 0 / max 2,
    1 GiB): https://careflow-api-247793990377.asia-southeast1.run.app — `/api/v1/health` 200,
    `/api/v1/health/auth` 401 without token, `/internal/jobs/heartbeat` 401 without OIDC token.
  - Firebase Hosting (staff portal shell): https://hypertension-dd85f.web.app —
    `/api/v1/health` returns `ok` through the `/api/**` rewrite (exit test).
  - Cloud Scheduler job `careflow-heartbeat` (daily 03:00 Asia/Kuala_Lumpur, OIDC as
    `careflow-scheduler@…`, audience `careflow-internal-jobs`).
    Forced run 2026-10-12 11:42 UTC: Cloud Run returned 200 (OIDC accepted, heartbeat
    audit entry written).
  - Setup notes: Cloud Build on this project runs as the Compute default service account; the
    Cloud Scheduler API had to be enabled (was not on at project creation). Hosting serves
    `firebase/public/` (copied from `app/build/web`).
- Deviations / additions vs Chapter 4:
  - D-23 Android application IDs `fyp.hypertension.patient` / `.family`; Dart package `hypertension`.
  - D-24 `tasks.py` replaces `make` and `.sh` scripts (make not available on Windows).
  - D-12 minSdk raised 23 -> 24 (Flutter 3.44 minimum).
  - Risk level enum stored lowercase (`low|moderate|high|critical`) for consistency with the other
    snake/lower-case enums; Ch4 only names the levels.
  - `symptom_catalog` document IDs are stable slugs (e.g. `chest_pain`) instead of auto IDs, so
    seeding is idempotent and fixtures can reference them.
  - Scheduler OIDC audience is a fixed string (`careflow-internal-jobs`) verified by FastAPI;
    `/internal/jobs/*` is not under `/api`, so Hosting never exposes it.
  - Firebase emulators require JDK 21 (installed Temurin 21).
- Android exit test (2026-10-12): patient flavor debug build on a physical phone (MTN NX1,
  Android 16 / API 36) over USB with `adb reverse` (the documented alternative to the
  `10.0.2.2` emulator path, docs/10 §3) shows "API status: ok" from local FastAPI. PASSED.
  - Build fixes needed on Windows: enable `buildFeatures.resValues` (per-flavor app name) and
    `kotlin.incremental=false` (project on D:, pub cache on C:).
- Known limitations: on the MTN NX1 the phone's logcat output is obfuscated, so attaching the
  VS Code/`flutter run` debugger can fail ("log reader stopped"); the installed app still runs.
  No Android emulator (AVD) configured on the dev machine; the `10.0.2.2`
  path is configured but was verified with a physical phone instead.

---

### 2026-10-12 — Increment 1 — Module 1: User & Access Management
- FRs implemented: FR-1.1, FR-1.2, FR-1.3, FR-1.4, FR-1.5, FR-1.6 (Fig 4.1.1.1).
  - Backend: `POST /auth/register-profile`, `/auth/onboarding`, `/auth/session-events`,
    `/auth/login-failed`, `/admin/staff`; Brevo email adapter + console fake; rate limiter.
  - Rules: `users` (self / admin / assigned doctor read; self name-only update; admin may change
    `isActive`, `assignedDoctorId`; no client create/delete), `health_profiles` (owner, assigned
    doctor, admin read; server-only writes).
  - App: patient/family login with role toggle (Fig 4.3.1.1), register, forgot password, 3-step
    onboarding with device draft, Profile Complete (Fig 4.3.1.2), staff login (Fig 4.3.14.8),
    role-based staff shell, admin "Add staff account" (part of Fig 4.3.14.1), shared auth guard.
- Use-case exception flows handled: UC1.1 E1/E2, UC1.1 A1, UC1.2 E1/E2, UC1.2 A1, UC1.3 E1,
  UC1.4 E1, UC1.4 A1, UC1.5 E1.
- Tests: 97 pytest unit + 2 emulator integration (backend), 55 Firestore/Storage rules tests
  (27 new, all five roles), 78 Dart tests (unit: validators, redirect guard, error mapping,
  onboarding payload; widget: every new screen incl. loading/error states). End-to-end script
  against emulators + local FastAPI: 18/18 checks (register → claim → onboarding → rules →
  login audit → wrong app → staff creation → duplicate → deactivated block → failed-login audit).
- Deviations / additions vs Chapter 4:
  - D-25 onboarding fields stored as JSON objects inside the three `health_profiles` Strings;
    `dateOfBirth`/`gender` collected at onboarding.
  - D-26 mobile login keeps the Patient/Family toggle; it must match the account and the app.
  - D-27 failed logins audited with `userId = "anonymous"` and the email domain only; the
    scheduler uses `userId = "system:scheduler"`. `audit_logs.userId` is a users reference in
    Ch4, so these two sentinel values are an addition.
  - D-22 Brevo chosen as the email provider; staff get a Firebase password-setup link.
  - `health_profiles` document ID = patient UID (Ch4: auto-generated) to enforce the 1:1 rule.
  - `users.linkCode` (D-06) generated at patient registration.
  - Staff SSO button omitted (out of scope); biometric login deferred (no FR requires it).
  - Added `shared_preferences` (onboarding draft, UC1.4 A1).
  - Sign-out asks for confirmation (requested by Ping during phone testing); UC1.3 has no
    confirmation step, so this is a small UX addition.
  - Android: FlutterFire's automatic localhost→10.0.2.2 emulator mapping disabled so a physical
    phone works over `adb reverse`; `python tasks.py phone-install` added because this phone's
    obfuscated logcat prevents debugger attach.
- Bugs found and fixed during testing:
  - Flutter web: `useAuthEmulator` after `initializeApp` was silently ignored by
    firebase_auth_web, so a local staff build signed in against the live project (one failed
    attempt for a non-existent test account; no data touched). Fixed by registering the emulator
    before initialisation and failing closed if the JS Auth instance is not on the emulator.
  - Onboarding page could wait forever for the uid (Riverpod 3 pauses unlistened providers).
- Known limitations:
  - Deactivation is enforced through `users.isActive` (server LOGIN check + app guard); disabling
    the Firebase Auth account as well is added with the Admin "deactivate" action in Module 11.
  - Link-code uniqueness check is not transactional (collision chance negligible at 31^6).
  - Failed-login rate limit is per Cloud Run instance (max 2 instances).
  - Real Brevo sending not yet exercised (needs Ping's API key); console fake used.

---

### 2026-10-12 — Increment 1 — Module 2: Patient Health Overview
- FRs implemented: FR-2.1, FR-2.2 (Fig 4.1.1.2, Fig 4.3.2.1).
  - Dashboard: Today's Plan (medications + next booked/rescheduled appointment), latest BP
    reading (time ago, change vs. previous day, PPG heart rate labelled "estimate"), AI risk card
    (overall level = highest complication level, D-03), quick actions, patient bottom navigation.
  - Rules: read access for `vital_readings`, `risk_scores` (patient, assigned doctor, admin,
    linked family), `medications`, `appointments` (patient, assigned/appointment doctor, admin);
    all client writes closed until their modules.
- Use-case exception flows handled: UC2.1 E1 (per-card error + retry), UC2.2 E1, UC2.3 E1,
  UC2.4 E1 (empty states with prompts).
- Tests: 18 new Dart tests (98 total: unit for greeting, BP change, labels, model parsing,
  overall risk; widget for empty/data/error/loading and every quick action); 35 new rules tests
  (90 total).
- Deviations / additions vs Chapter 4:
  - Fig 4.1.1.2 reads today's doses from `dose_logs` (`findTodaysDoses(patientId)`), but
    `dose_logs` has no `patientId`, so Security Rules cannot authorise a patient's query on it.
    The dashboard lists today's medications from `medications`; dose "taken" ticks are deferred to
    Module 5, where a fix (e.g. denormalised `patientId` on `dose_logs`) will be proposed to Ping.
  - Dashboard reads go straight to Firestore (read/write split) rather than through a FastAPI
    "DashboardCtrl" endpoint; the controller role is played by Riverpod providers.
  - Riverpod 3 automatic retry disabled for dashboard streams so errors surface immediately.
- Known limitations: medication, appointment and risk cards stay in their empty states until
  Modules 5/7 (Increment 3) and Module 9 (Increment 2) write that data.

---

### 2026-10-13 — Increment 1 — Module 3: Vital Signs Tracking
- FRs implemented: FR-3.1, FR-3.2 (Fig 4.1.1.3; Figs 4.3.3.1-4.3.3.3; docs/06 algorithms B, E).
  - Backend `POST /api/v1/vitals` (patients only): plausible range, server timestamp, optional
    note and PPG heart rate, BP category + threshold alert level in the response, audit entry.
  - BP classifier + alert bands in Dart and Python, both driven by `docs/fixtures/bp_cases.json`.
  - Camera PPG: live preview + torch, finger-detected hint, 15 s capture, green channel →
    resample → zero-phase Butterworth band-pass 0.67–3.3 Hz → autocorrelation beat period →
    peak detection → bpm; weak/irregular signals rejected; processed in an isolate.
  - Screens: Log Vitals (note, manual HR fallback), Reading Saved (category badge, HR estimate,
    crisis 999 banner), Vitals tab (latest, risk unlock n/3, recent readings).
- Use-case exception flows handled: UC3.1 E1 (client and server), UC3.3 E1 (retry / skip /
  manual entry), camera unavailable / permission denied.
- Tests: 48 new pytest (145 total); Dart 169 total (BP fixture cases + boundaries, PPG accuracy
  at 50–150 bpm within ±3 bpm with noise/drift/jitter, failure cases, widget tests for all
  vitals screens). End-to-end on emulators + local FastAPI: 9/9 (log → stored with timestamp/HR/
  note, out-of-range rejected, crisis → emergency, doctor/family can read, pharmacist cannot,
  no direct client writes). Phone test (MTN NX1): PPG produced 56 bpm; reading saved.
- Deviations / additions vs Chapter 4:
  - Heart-rate plausible range 30–220 bpm (not specified in the report).
  - Heart rate is attached to a BP reading (`vital_readings` requires systolic/diastolic), so a
    heart rate cannot be saved on its own; manual heart-rate entry offered when the camera is
    unavailable (docs/05).
  - bpm uses the autocorrelation beat period to reject the dicrotic wave before peak counting
    (refines "peak count / duration" in algorithm B).
  - Live camera preview and finger-detected hint, and a light/dark/system theme toggle, added
    after Ping's phone testing.
  - Crisis readings show a 999 safety message on the Reading Saved screen; risk scoring and alert
    delivery to doctor/family hook into `POST /vitals` in Increment 2 (Module 9).
- Known limitations: PPG accuracy depends on torch brightness and frame rate per phone; the
  finger-detected hint uses fixed brightness/redness thresholds; validated on synthetic signals
  and one real phone only.

---

### 2026-10-13 — Increment 1 — Module 4: Health Data Visualisation
- FRs implemented: FR-4.1, FR-4.2, FR-4.3 (Fig 4.1.1.4; Figs 4.3.4.1, 4.3.4.2).
  - Health Trends: latest reading + category, fl_chart systolic/diastolic lines with 120/80 guide
    lines, ranges 7D/30D/3M/1Y (3M/1Y = daily averages), avg/min/max tiles, count, average heart
    rate, systolic change; "Compare heart rate" overlay; per-complication risk trend chart.
  - Readings queried with `patientId` + `timestamp >=` ordered by timestamp desc (existing index);
    chart/providers take a patient id for reuse in the doctor portal (Module 8).
- Use-case flows handled: UC4.1 A1 (switch in place), UC4.1 E1 (empty range), UC4.2 E1 (<2
  readings: no trend stats), UC4.3 E1 (no heart-rate data: BP only + note), UC4.4 E1 (single
  score, no line); Fig 4.3.4.2 empty state below three readings.
- Tests: 16 new Dart tests (185 total): range windows, daily averaging, stats, risk series, and
  widget tests for every flow above. Verified on the phone by Ping.
- Deviations / additions vs Chapter 4:
  - Fig 4.3.4.1 shows 7D/30D/3M; 1Y added because FR-4.1 requires it.
  - Fig 4.3.4.1's single "Cardiovascular Risk Score %" card is replaced by the per-complication
    risk trend (Ch4 stores five complication scores, D-03); it stays in its empty state until
    Module 9 writes risk scores.
  - 3M and 1Y plot daily averages for readability.

---

### 2026-10-13 — Increment 1 exit test
- Scenario (docs/08): new patient registers → onboards → logs three BP readings (two with PPG
  heart rate) → trend data readable via the app's query with correct avg/min/max inputs; demo
  doctor and admin sign in to the staff portal; patient refused by the staff portal.
  Result: **10/10 PASS** on emulators + local FastAPI.
- Rules suite 90/90; backend pytest + ruff + mypy clean; Flutter 185 tests + analyze clean.
- Real-device checks on MTN NX1 throughout Modules 1–4 (registration, onboarding, dashboard,
  BP logging, PPG 56 bpm, trends, back navigation, theme toggle).
- Deployment (2026-10-13, end-of-increment redeploy, docs/10 §4):
  - Firestore rules + indexes and Storage rules deployed.
  - Cloud Run `careflow-api` revision `careflow-api-00003-t78` (asia-southeast1); live
    `/api/v1/health` ok, `/api/v1/vitals` present (401 without token).
  - Staff portal redeployed to https://hypertension-dd85f.web.app.
  - First live admin created with `tasks.py bootstrap-admin`; admin signed in to the live portal
    and created a doctor account (setup link shown on screen, cloud email still "fake"); doctor
    signed in with the Doctor role.
  - Release APK (patient flavor, debug-signed, API → Cloud Run, live Firebase) installed on the
    MTN NX1: registration, onboarding, BP logging with camera heart rate, trends and sign-out /
    sign-in all worked against the live project.
  - Cloud email remains the console fake (Brevo secret to be added before the final deploy).
- **Increment 1 complete.**

---

### 2026-10-13 — Increment 2 — Module 9: Risk Assessment & Alerts (backend)
- FRs implemented: FR-9.1 (threshold alerts), FR-9.2 / FR-9.3 (risk scoring, earlier commits),
  FR-9.4 (rule-based recommendations), FR-9.5 (risk escalation), FR-9.6 (30-day deterioration),
  FR-8.4 delivery side (doctor alerts stored for the portal).
- Flow after `POST /api/v1/vitals`: classify → read the previous risk score → generate the new
  score (≥3 readings) → `plan_escalation` (pure rules, docs/06 §E/§F) → `Escalator.apply`:
  - mild: patient push; moderate: patient push + `clinical_alerts` (threshold, high) + doctor
    push + family push + booking prompt; emergency: same with severity critical, urgent pushes
    and 999 wording.
  - overall risk rises to High/Critical (vs previous score, or first score) → `risk_escalation`
    alert + patient "book an appointment" prompt; Critical also pushes family.
  - any complication up ≥2 levels → `medication_review` flag (UC9.3 step 4).
  - doctor alerts of the same type for the same patient are not repeated within 2 h.
  - response adds `recommendations` (always ends with the not-a-doctor disclaimer),
    `bookAppointmentPrompt`, and `risk.diagnosed` (conditions already diagnosed at onboarding).
- Deterioration: `POST /internal/jobs/deterioration`, Cloud Scheduler job
  `careflow-deterioration` daily 06:00 MYT. Least-squares slope of each complication's
  probability over 30 days; alert when slope ≥ 0.001/day (≈3 points per 30 days), latest >
  earliest, ≥3 scores spanning ≥7 days; one alert per patient per 7 days.
- Push: `PushClient` adapter (FCM via Admin SDK; `LogPushClient` when `FCM_ENABLED=false`),
  tokens via `POST`/`DELETE /api/v1/devices/fcm-token` into `users/{uid}/fcmTokens` (D-33);
  tokens FCM rejects are deleted. A push failure never fails the reading.
- Tests: 30 new pytest (tests/test_alerts.py, rule-by-rule + end-to-end through `/vitals` and
  the job), 18 new rules tests (firestore.alerts.test.js) → rules 108/108.
- Deviations / additions vs Chapter 4:
  - New collection `clinical_alerts` (D-32) and FCM token sub-collection (D-33).
  - Deterioration thresholds (0.001/day, 3 scores, 7-day span, 7-day dedupe) and the 2-hour
    alert dedupe are not specified in Ch3/Ch4; chosen as the simplest values that avoid alert
    spam.
  - The "escalate Moderate to Emergency if the doctor hasn't responded in 2 h" rule (docs/06 §E)
    and emergency auto-booking need Module 7 appointments → Increment 3.
  - Family GPS emergency alerts + Twilio SMS (`emergency_alerts`, FR-14.2) → Increment 3; Module 9
    sends family a push only.
  - Doctor alert read access follows `doctorId` on the alert; after a reassignment the old
    doctor still sees alerts addressed to them (new alerts go to the new doctor).
- App (patient/family Android): `firebase_messaging` + `flutter_local_notifications`
  (channels `careflow_alerts` high / `careflow_general`), `POST_NOTIFICATIONS` permission, core
  library desugaring. The token is registered once a user of that app is signed in and removed
  before sign-out (UC1.3); foreground pushes are shown as local notifications.
  Reading Saved (Fig 4.3.3.3) now shows the risk assessment (overall chip, each complication as
  a percentage with "<1%" for tiny values, "Already diagnosed" for onboarding conditions,
  reduced-confidence note), "readings left" before the first score, a "see your doctor soon"
  card when booking is prompted, and the FR-9.4 tips with the disclaimer.
  Flutter tests: 5 new (196 total).
- Live test fix (2026-10-13): first live reading failed with "query requires an index" (the
  emulator does not enforce composite indexes). The `clinical_alerts` (patientId, type,
  createdAt) index direction was corrected and deployed, and an alerting failure is now logged
  instead of failing `POST /vitals` (the reading was already saved; the app wrongly said it was
  not). Regression test added.
- Live check (2026-10-13, revision `careflow-api-00005-2lg`, release APK on MTN NX1): device
  token registered; 150/95 reading produced the patient push on the phone and a
  `clinical_alerts` document (threshold, high, open) for the manually assigned doctor.
- Known limitations: the staff web portal does not receive browser pushes (needs a VAPID key
  and service worker); the doctor portal (Module 8) reads `clinical_alerts` live instead. The
  booking prompt is informational until appointments (FR-7.5, Increment 3).

---

### 2026-10-13 — Increment 2 — Module 8: Healthcare Provider Portal
- FRs implemented: FR-8.1 (assigned patient list, risk filter, search), FR-8.2 (patient health
  history), FR-8.3 (clinical notes with templates, care plan editor, prescriptions with
  interaction warning), FR-8.4 (priority alerts panel + critical banner from `clinical_alerts`).
- Screens (staff portal, `/doctor/...` routes per docs/05): Doctor Dashboard (Figs 4.3.12.1 /
  4.3.12.2: summary counts, multi-select risk chips with counts, name search, patients sorted by
  risk then latest reading, live alerts panel with Review / Acknowledge / Dismiss, red banner for
  the newest open critical alert); Patient Detail (4.3.12.4: demographics, latest BP, risk
  breakdown per complication, BP trend chart 7D/30D/3M reusing the Module 4 chart, tabs for
  vitals, medications + prescriptions, care plan, clinical notes); Consultation Notes + Note Saved
  (4.3.12.5/4.3.12.6: SOAP / Hypertension F/U / Medication Adjustment templates, saved toast,
  prior notes below); Prescription Management (4.3.12.7: current regimen, latest note, form,
  recurring toggle); Care Plan editor (UC8.5).
- Use-case flows handled: UC8.1 E1 (no patients), UC8.2 A1 (clear filter), UC8.3 E1 (empty
  history per section), UC8.4 E1 (interaction warning; critical needs an explicit tick).
- Backend: `POST /provider/patients/{id}/notes`, `PUT /provider/patients/{id}/care-plan`,
  `POST /provider/patients/{id}/prescriptions` (docs/05). Doctor role + assignment check
  (`NOT_ASSIGNED` 403), audit entries ADD_CLINICAL_NOTE / UPDATE_CARE_PLAN / ISSUE_PRESCRIPTION.
  Interaction check (docs/06 §C) against the patient's `medications` and earlier
  `prescriptions` using `backend/app/services/interactions.json` (13 drug classes, 16 pairs +
  duplicate therapy); any interaction returns 409 `DRUG_INTERACTION` with details until the
  doctor acknowledges. The error envelope gained an optional `details` field.
- Reads stay direct Firestore listeners under rules: assigned patients
  (`users` role + assignedDoctorId), latest reading/risk per patient, notes, prescriptions,
  care plan, open alerts. Alert acknowledge/dismiss is the rules-checked direct update (D-32).
- Tests: backend 18 new (tests/test_provider.py); rules 19 new (firestore.provider.test.js;
  the Inc0 "closed collection" sample moved from clinical_notes to messages) → 127/127;
  Flutter 22 new (10 unit, 12 widget) → 218/218.
- Deviations / additions vs Chapter 4:
  - `prescriptions.medicationDetails` stays one string (Table 4.2.3.11); the form's name,
    dosage, frequency and duration are joined, e.g. "Losartan 50mg, Once daily, for 30 days".
  - Issuing a prescription does not add an entry to the patient's own `medications` list
    (Module 5); both lists are shown to the doctor and both feed the interaction check.
  - Clinical notes are final once saved ("Sign & Lock"); `clinical_notes` has no draft field,
    so "Save Draft" / auto-save from the mockup are not built (the text stays in the editor
    until saved). Voice dictation and rich-text formatting are not built.
  - Mockup items with no data in Ch4 are omitted: MRN, blood type, allergies, weight/BMI and
    O2 sat on the header, lab results ("Vitals & Labs" tab shows vitals only), adherence column
    (shown per medication when `adherenceRate` exists, Module 5), unread messages card
    (Module 10), "Telehealth"/"Message" buttons, population systolic trend chart (4.3.12.2).
  - UC8.4 step 4 "notify the pharmacy": prescriptions are readable by pharmacists (rules) and
    audited; the pharmacist queue and notifications arrive with Module 13 (Increment 3).
  - The prescription recurring toggle stores `isRecurring` (UC13.1); monthly orders are
    Module 13.
  - Doctor Schedule (4.3.12.3) and Messaging are Modules 7 and 10 (Increment 3).
  - Composite indexes added for `clinical_notes` (patientId, createdAt desc) and
    `prescriptions` (patientId, issuedAt desc); not in the docs/04 index table.
- Local portal check (emulators + local API, demo doctor): stage 2 then crisis readings made
  the alerts appear live without refresh; the critical banner, Review patient, risk breakdown
  with the real models and the BP trend all rendered. This check found a Module 9 bug: the
  2-hour alert dedupe matched on type only, so a crisis alert was suppressed by an earlier
  stage 2 alert. Dedupe now requires a recent alert of the same type with equal or higher
  severity (regression test added). The risk "model used" label now lists each model once.
- Known limitations: the patient list loads each patient's latest reading and risk with one
  listener per patient, fine for a single doctor's caseload but not for hundreds of patients.
