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

---

### 2026-10-13 — Increment 2 — FR-14.1: AI Health Agent
- FRs implemented: FR-14.1 (UC2.6 Ask AI Health Agent incl. A1 risk explanation and E1
  fallback; UC2.7 Receive Proactive Health Update; Fig 4.1.1.16 UC-14.1.1 and UC-14.1.3).
- Backend: `POST /api/v1/agent/chat`, `POST /api/v1/agent/proactive` (patient only, 10
  requests/min per patient). Gemini (`gemini-2.5-flash`, configurable `GEMINI_MODEL`) is called
  over REST from FastAPI only (`app/integrations/gemini.py`, 20 s timeout, thinking disabled for
  latency); without `GEMINI_API_KEY` a fake client answers. The request body is never logged.
- Context builder (`app/services/agent_context.py`): one function per data source, joined into
  the system prompt: patient (name, age, gender), medical history + lifestyle, BP readings of
  the last 7 days with category and camera-estimate heart rate, latest risk score per
  complication, medications + adherence, doctor prescriptions, upcoming appointments, care
  plan, plus the last 10 `agent_messages` as conversation history. Sources whose module is not
  built yet (medications: Module 5, appointments: Module 7) say "none recorded" and fill in
  automatically once those modules write data. Times are given in Malaysia time.
- Guardrails (docs/06 §G): plain language, facts only from the supplied data, risk is an
  estimate not a diagnosis, no diagnosis / prescribing / dose changes, contact the doctor for
  anything serious, 999 for emergency symptoms, PPG heart rate is an estimate.
- D-34: dangerous messages are detected by a deterministic keyword check (chest pain,
  breathing difficulty, stroke signs, fainting, sudden vision loss, seizure, a few Malay
  phrases; self-harm separately) and never sent to Gemini: the patient gets a fixed reply with
  999 (self-harm reply also gives Talian HEAL 15555) and the assigned doctor gets a
  `flagged_message` critical clinical alert (via the Module 9 escalator: dedupe, push, audit).
  Normal questions such as "what is my stroke risk?" are not flagged (tested).
- UC2.7: after a reading with a risk score, Reading Saved requests the update; the card shows
  the agent's text, the risk chip and rule-chosen buttons (High: Book appointment, View
  medications; Critical or crisis reading: Book emergency appointment). The update is also
  saved to the chat history. If Gemini fails, a rule-based text is used.
- App: `/ai-agent` chat (Fig 4.3.7.1): disclaimer bar ("not a substitute for a doctor ... call
  999"), suggestion chips, live history from Firestore, optimistic patient bubble + typing
  indicator, fallback notice, red 999 card after an emergency message.
- Rules: `agent_messages` readable by the patient (and assigned doctor/admin per docs/04),
  never writable from clients so replies cannot be forged.
- Tests: backend 36 new (tests/test_agent.py: danger phrases incl. false-positive checks,
  context sections, chat/history/persistence, fallback, emergency path, rate limit, roles,
  proactive levels); rules 4 new → 131/131; Flutter 10 new → 229/229.
- Deviations / additions vs Chapter 4:
  - D-34 (no `flagged` field; doctor alert of type `flagged_message` instead).
  - Severity analysis (Fig 4.1.1.16 step 3 `analyzeSeverity`) is a keyword rule, not a Gemini
    call, so it is deterministic, testable and works when Gemini is down.
  - The fallback reply is shown but not saved to `agent_messages` (so a failed call does not
    pollute later context).
  - "Call Emergency Contact" and "Alert Family" buttons (UC2.7 Critical) wait for FR-14.2
    family monitoring (Increment 3); the critical update text tells the patient to call 999.
  - Booking buttons open the Appointments screen, which is built in Module 7 (Increment 3).
  - UC-14.1.2 family "vitals insight" is part of FR-14.2 (Increment 3).
  - Mockup quick-reply symptom chips ("I have a slight headache") are replaced by question
    suggestions on an empty chat; voice input is not built.
- Live Gemini check (synthetic data only, model `gemini-3.1-flash-lite` chosen by Ping):
  answers quoted the supplied readings and dates, explained risk as an estimate, refused a dose
  change ("ask your doctor or pharmacist") and pointed to 999 for emergency symptoms; 3-9 s per
  answer. Gemini returned a 503 and a timeout at a busy moment, so the adapter now retries once
  (429/500/503/timeouts), Gemini 3 models use a low thinking level, each attempt times out at
  12 s and the app waits up to 35 s for agent calls (other calls keep 15 s).
- Live test fix: the first live chat returned 500 because the history query (`agent_messages`
  patientId + sentAt descending) had no composite index (the emulator does not enforce
  indexes; second time this class of bug appeared). Index added; every backend and app query
  was then checked against `firestore.indexes.json` (no other gaps). The agent now degrades
  instead of failing: a failing context section reads "temporarily unavailable" and a failing
  history read answers without history (both logged as errors). In the app, a message whose
  request failed stays on screen with "Not sent. Tap to retry".
- Known limitations: the cloud deploy needs `GEMINI_API_KEY` in Cloud Run; it should come from
  Secret Manager (to be confirmed with Ping before enabling that service).

---

### 2026-10-13 — Increment 2 — FR-14.3: Symptom Checker & Triage
- FRs implemented: FR-14.3 (UC14.1 incl. E1, UC14.2 incl. E1, UC14.3, UC14.4 steps 1-2;
  Fig 4.1.1.14).
- Rule table (`backend/app/services/triage.py`, docs/06 §D, D-10): crisis BP (>=180 / >=120)
  -> seek emergency care; severe + (red flag or systolic >=160) -> emergency; any red-flag
  symptom (catalog `isRedFlag`) -> emergency; BP >=140 / >=90 -> contact doctor; moderate
  severity or any High/Critical complication -> contact doctor; heart rate >120 or <45 ->
  contact doctor; otherwise monitor at home. First match wins. **Every row and boundary is
  unit-tested** (179/180, 119/120, 159/160, 139/140, 89/90, 120/121, 44/45; all six red flags;
  top-down precedence) for Objective 1.
- `POST /api/v1/triage` (patient only): symptom ids validated against `symptom_catalog`;
  BP from the reading logged in the same session (`vitalReadingId`, must belong to the
  patient) or else the latest reading within 24 h (D-36); camera heart rate from the request
  or that reading; latest risk levels. Saves `triage_outcomes` (patientId, vitalReadingId,
  symptoms as catalog ids, severity, outcome, generatedAt) and audits TRIAGE. UC14.4: for
  contact_doctor (severity high) and seek_emergency_care (critical) a `triage` clinical alert
  goes to the assigned doctor with symptoms, severity, BP, heart rate and overall risk (Module 9
  escalator: dedupe, push, audit). The response lists missing inputs (UC14.1 E1).
- App: `/symptom` step 1 "Your vitals now" (camera heart rate via the Module 3 card, skippable;
  optional BP just measured, validated, saved through `POST /vitals` so it also gets a risk
  score and alerts, and reused on retry so it is never logged twice); step 2 symptoms grouped
  by catalog category + Mild/Moderate/Severe (Fig 4.3.8.1). `/symptom/result/:id`
  (Fig 4.3.8.2): coloured outcome banner, reported symptoms with red flags marked, the reason,
  BP and heart rate (estimate) used, missing inputs, three numbered immediate actions per
  outcome, "Your doctor has been notified", **Call 999 Now** (url_launcher opens the dialer),
  AI agent link, not-a-doctor disclaimer.
- Rules: `triage_outcomes` readable by patient, assigned doctor, admin; never written by
  clients. Doctor portal shows triage alerts as "Symptom triage" in Priority alerts.
- Tests: backend 46 new (tests/test_triage.py); rules 2 new -> 133/133; Flutter 10 new ->
  239/239.
- Deviations / additions vs Chapter 4:
  - D-36 (optional BP in the checker; 24-hour window for "current BP"; heart rate without a BP
    is used but not stored, since Table 4.2.3.5 has no heart-rate field).
  - Mockup "Call 911" is 999 (CLAUDE.md). "Share Vitals with ER" is not built (no ER
    integration in scope).
  - UC14.4 step 3 (emergency appointment auto-booking, family alert, doctor reassignment)
    depends on Module 7 and FR-14.2 (Increment 3).
  - The result screen is reached from the submission; opening `/symptom/result/:id` directly
    returns to the checker (no stored "reason" to redisplay).
- Known limitations: the red-flag list comes from the seeded catalog; changing it needs a
  re-seed (local) or a console edit (live).

---

### 2026-10-13 — Increment 2 exit test
- Scenario (docs/08), local emulators + local FastAPI (real models, real Gemini
  `gemini-3.1-flash-lite`), demo patient and demo doctor:
  1. Crisis reading 186/122 (after two normal readings): saved, classified emergency, risk
     score generated (overall high), guidance mentions 999, push to the patient device, a
     critical `threshold` clinical alert for the assigned doctor readable by the doctor under
     Security Rules (patient gets 403), doctor push sent. **PASS.** The real-time portal update
     was checked earlier in the browser (alerts and critical banner appeared without refresh).
  2. `emergency_alerts` record: **deferred**. Family emergency alerts are FR-14.2
     (Increment 3; docs/09 "Module 9 never creates EmergencyAlert").
  3. Triage fixtures through the API: red flag, severe + crisis BP, crisis BP rule 1, moderate
     severity, high BP, high heart rate all gave the expected outcome; one "monitor at home"
     fixture correctly became "contact doctor" because the patient's risk score was High at
     that moment (rule 5). 7 outcomes saved and readable by the patient. **PASS** (every rule
     row and boundary is also unit-tested).
  4. AI agent: listed the day's actual readings with Malaysia times, explained the risk
     breakdown as model estimates, emergency message got the fixed 999 reply and a doctor
     alert, proactive update matched the current (moderate) risk with no buttons. **PASS.**
     The first attempt fell back because Gemini timed out and then returned 503 (overloaded);
     the fallback message showed as designed and a re-run answered normally (14-27 s with the
     retry at a busy time).
  Result: **all criteria pass except the emergency_alerts record, deferred to FR-14.2.**
- Found and fixed during the exit test: the backend never configured logging, so `careflow.*`
  INFO messages (pushes, jobs) were invisible locally and in Cloud Logging. `main.py` now adds
  a console handler for `careflow` at INFO; the local push log prints the title only (no
  readings). Request bodies are never logged.
- Patient debug APK with url_launcher built successfully.
- Test totals: backend pytest all passing (3 emulator integration tests skipped without
  emulators), rules 133/133, Flutter 239/239; ruff, mypy, flutter analyze clean.
- **Increment 2 complete** (pending Ping's live redeploy: deploy-all + phone-live).

---

### 2026-10-13 — Increment 2 — Feature 4 band actions (gap review, D-37)
- Ping compared FR-14.3 with the reference md "Feature 4" Mild / Moderate / Emergency
  actions (also docs/06 §E). The core checker matched; several band actions were missing or
  partial. Built now (D-37):
  - **Mild (130-139 / 80-89):** low-severity `threshold` doctor alert at most once per 24 h
    that also **emails a BP report** (recent readings, risk breakdown, "may require a
    medication review" when any complication is High/Critical); the symptom checker does the
    same for a mild-band BP; Reading Saved offers booking ("Would you like to book an
    appointment?"). **Follow-up rule:** a second abnormal reading in a row (previous reading
    >= 130/80) is treated as Moderate.
  - **Moderate:** doctor message now carries BP, heart rate and overall risk for readings
    too; symptom-checker contact/emergency outcomes push to linked family; a fixed "avoid
    physical exertion" AI Health Agent note is saved to the chat; the triage result's second
    action is "Avoid physical exertion". **2-hour escalation:** job `escalation`
    (`/internal/jobs/escalation`, Cloud Scheduler `*/15 * * * *`, the project's third and
    last free job) raises a critical alert (doctor push, urgent patient and family push) for
    any open high `threshold`/`triage` alert not acknowledged within 2 h, once.
  - **Emergency:** patient rows with an open critical alert show a red **EMERGENCY** chip and
    sort first on the doctor's list; the patient dashboard shows a **Call 999 Now** card while
    an emergency is active (crisis reading or emergency triage in the last 6 h); a fixed
    "stay calm" agent note goes to the chat; the doctor's patient page has an **Alerts &
    triage** history tab.
- Deferred to Increment 3: emergency appointment auto-booking and reassignment (Module 7),
  family GPS alert + SMS (FR-14.2), live booking buttons (Module 7 page is still a placeholder).
- Privacy: the fake email client no longer logs email bodies at INFO (BP reports).
- Indexes added for the new queries before deploying: `clinical_alerts` (status, severity,
  createdAt) for the job, (patientId, doctorId, createdAt desc) for the history tab;
  `triage_outcomes` (patientId, generatedAt desc).
- Tests: backend 23 new (tests/test_band_actions.py) and two existing expectations updated
  (Mild now also reports to the doctor; 122/80 is stage 1, so the "no alert" triage fixture
  uses 118/76); Flutter 10 new -> 249/249.
- Live check fix: the live symptom checker showed no symptoms, so Continue stayed disabled.
  `symptom_catalog` had only ever been seeded into the emulators. Added
  `firebase/seed/catalog_live.py` + `python tasks.py seed-catalog-live --yes` (reference data
  only, same stable ids, idempotent, refuses to run against emulators) and made it step 2 of
  `deploy-all`. The checker now explains an empty list ("not available right now ... call
  999") instead of showing a blank screen (widget test added). Demo accounts stay
  emulator-only.
- Ping's review of the live checker (2026-10-14):
  - Doctor's Alerts & triage history now shows when each alert was raised and when it was
    acknowledged or dismissed (`acknowledgedAt`, D-32), e.g. "Raised 14 Oct 2026, 11:32 PM ·
    Acknowledged 14 Oct 2026, 11:40 PM".
  - Severity stays (UC14.1 step 3, Fig 4.3.8.1, Feature 4); a one-line plain-language hint
    under the choice explains the selected level.
  - AI chat quick replies: a row of tappable replies above the input, always visible (Fig
    4.3.7.1 reply chips). Opened from a triage result they follow that result ("Explain my
    symptom check result", "What can I do about <symptom>?", ...); from the reading update
    card they are about the reading.
  - Noted: 110/50 with blurred vision is "monitor at home" under the rule table (blurred
    vision is not a red flag; the table has no low-BP rule). Not changed without Ping's
    decision.
  - Flutter 254/254.
- Symptom checker step 1 now says which BP it will use (Ping, 2026-10-14): with a Vitals
  reading in the last 24 h it shows "135/85 mmHg — The blood pressure you logged in Vitals
  today, 9:12 AM will be used for this check." and hides the BP boxes; "I have a newer
  reading" opens them (and "Use my earlier reading instead" undoes it). Without a recent
  reading the boxes show with "No blood pressure logged in Vitals in the last 24 hours...".
  Same 24-hour window as the server (D-36). Flutter 258/258.
- **D-38 (Ping, 2026-10-14): heart rate and a fresh BP are compulsory in the symptom checker**,
  superseding the optional BP / 24-hour reuse of D-36 and the skip in UC14.1 E1 / UC14.2 E1
  (**Needs Ch3 update**). Step 1 shows "Heart rate (required)" (camera, or the pulse typed from
  the BP monitor; the card's Skip button is hidden here via `allowSkip: false`, still shown in
  Log Vitals) and "Blood pressure (required)"; Continue stays disabled until both are valid. The
  BP is always saved to Vitals and linked to the triage. A "Feeling very unwell or can't
  measure right now? Call 999" card stays on the step so the compulsory step never blocks
  emergency help. `POST /triage` enforces it: `heartRate` and `vitalReadingId` required (422),
  the reading must belong to the patient (404) and be logged within the last hour (409
  `READING_TOO_OLD`). The "use your Vitals reading" card from earlier the same day was removed.
  Tests: backend triage endpoint tests rewritten (all passing); Flutter 255/255.
- **D-39 (Ping, 2026-10-14): low BP rule in triage.** After the high-BP rule: systolic < 90
  or diastolic < 60 -> contact_doctor, reason "Your blood pressure (110/50 mmHg) is low. With
  your symptoms, your doctor should check whether your treatment needs adjusting." The doctor
  gets the usual triage alert. Emergency rules still win (chest pain at 85/55 -> seek
  emergency care). Not applied to ordinary Vitals readings. Boundaries 89/90 and 59/60
  unit-tested; docs/06 §D table updated. **Needs Ch4 update.**

