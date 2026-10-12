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
