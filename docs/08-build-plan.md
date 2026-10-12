# 08 — Build Plan (Incremental Development)

Follows Ch1 §1.9.2 and Ch3 §3.1: **three increments**, each independently functional and tested before the next starts, then Phase 5 integration testing/UAT. Ping is the developer; Claude Code implements. Work one increment at a time, and inside an increment work one module at a time.

## Definition of Done (every module)

1. Every FR in scope is implemented and its use-case exception flows are handled (`03-use-cases.md`).
2. Unit tests: Dart (`flutter test`) and Python (`pytest`). Test names cite FR/UC IDs.
3. Firestore rules tests (emulator) for every new collection access path, covering each role.
4. Widget test for each new screen (renders the loading/empty/data/error states).
5. Behaviour matches the module's sequence diagram (`figures/ch4-figure-4-1-1-*`) and mockup (`07-ui-screens.md`).
6. `audit_logs` written for each state change (FR-1.5).
7. `flutter analyze` and `ruff` + `mypy` (backend) are clean.
8. Append an entry to `docs/IMPLEMENTATION_LOG.md` (create it): date, module, FRs done, test count, deviations from Ch4. This becomes the raw material for Chapter 5.
9. Commit with a conventional message (see the commit rules in `CLAUDE.md`).

---

## Prerequisite (Ping, before Increment 0)

Firebase project on the **Blaze plan** with a budget alert, products and APIs enabled in `asia-southeast1`, and the CLIs logged in. See `10-environment-and-deployment.md` §2. Claude Code should ask for the project ID if it hasn't been given one, and never handles billing.

## Increment 0 — Project setup

- Monorepo skeleton (`05-architecture.md`). Flutter app with 3 entrypoints and Android flavors (`patient`, `family`) plus a web target for staff.
- Firebase project config, emulator suite (Auth, Firestore, Storage) wired for local dev, and FastAPI skeleton with auth dependency + audit logger + health endpoint.
- Shared constants (enums from `04-data-model.md`) in Dart and Python, plus `docs/fixtures/` shared test fixtures.
- Seed script: `symptom_catalog` and one demo account per role.
- Install the commit-msg hook (`git config core.hooksPath scripts/git-hooks`).
- CI-ready scripts: `make test`, `make lint`, `make emulators`.
- VS Code: `.vscode/launch.json` compound config (emulators + uvicorn + Flutter), `extensions.json` recommendations, dev CORS, debug-only cleartext config, `--dart-define` API base URL (`10-environment-and-deployment.md` §3).
- Deploy artefacts: Dockerfile, deploy scripts, `firebase.json` rewrite, scheduler job script, `.env.example` (§4).
- **Walking-skeleton deploy:** FastAPI health endpoint on Cloud Run, empty staff portal on Hosting with a working `/api/**` rewrite, rules + indexes deployed, one test scheduler job.

**Exit test:** the local stack starts from one VS Code launch; `https://<project>.web.app/api/v1/health` returns 200 through the rewrite; the patient app on the Android emulator reaches local FastAPI via `10.0.2.2`.

> **Every increment ends with a redeploy** to Cloud Run + Hosting, a smoke test on the live URL and a real Android device, and the deployed version noted in `IMPLEMENTATION_LOG.md`.

## Increment 1 — Core System & Patient Monitoring (Ch1 Phase 2)

| Module | FRs | Notes |
|---|---|---|
| M1 User & Access Management | FR-1.1–1.6 | Firebase Auth; custom claims; `users` + `health_profiles`; onboarding (save partial progress, UC1.4 A1); staff provisioning by admin; deactivated-account login block; audit logging; Firestore rules for all 5 roles |
| M2 Patient Health Overview | FR-2.1, FR-2.2 | Dashboard cards. Medication, appointment and risk cards show empty states until Inc 2/3 modules exist. Per-section error isolation (UC2.1 E1) |
| M3 Vital Signs Tracking | FR-3.1, FR-3.2 | BP log + note, plausible-range validation, PPG capture (algorithm B), BP classifier (algorithm E). Threshold alert *classification* is built here; alert *delivery* is wired in Inc 2 |
| M4 Health Data Visualisation | FR-4.1–4.3 | fl_chart trends 7d/30d/3m/1y, stats, compare vitals, risk trend (empty until Inc 2) |

**Exit test:** a patient registers, onboards, logs BP and PPG HR, and sees trend charts. A doctor/admin can log in to the staff portal shell. The rules suite passes.

## Increment 2 — AI & Clinical Intelligence (Ch1 Phase 3)

| Module | FRs | Notes |
|---|---|---|
| ML pipeline (`ml/`) | supports FR-9.2 | Train RF + XGB × 5. Each selected model needs AUC ≥ 0.80. `REPORT.md`, `feature_map.json`, thresholds |
| M9 AI-Powered Health Monitoring | FR-9.1–9.6 | Risk scoring on each reading, recommendations (FR-9.4), threshold alerts, escalation to doctor/family, 30-day deterioration job |
| FR-14.1 AI Health Agent | FR-14.1 | Gemini proxy, context builder, `agent_messages`, proactive post-reading update (UC2.7), fallback on failure |
| FR-14.3 Symptom Checker & Triage | FR-14.3 | Symptom picker, mandatory PPG step (skippable on failure), classify() rule table, doctor notification |
| M8 Healthcare Provider Portal | FR-8.1–8.4 | Patient list (assigned only) with risk filter + search, patient detail, clinical notes (templates), care plan editor, prescriptions (with interaction warning), alerts panel + critical banner |

**Exit test:** logging a crisis reading produces a risk score, an alert to the patient, an alert on the doctor portal in real time, and an emergency alert record. Triage produces the correct outcomes for all fixture cases. The AI agent answers using the patient's context.

## Increment 3 — Coordination, Medication & Extended Features (Ch1 Phase 4)

| Module | FRs | Notes |
|---|---|---|
| M10 Care Coordination & Messaging + FR-14.4 | FR-10.1–10.3, FR-14.4 | E2E encryption, inbox/thread, offline queue (UC10.1 E1), client-side keyword scan, flagged banner, doctor dismiss, shared care plan view |
| FR-14.2 Family Monitoring & Emergency Alert | FR-14.2 | Family app: link by code → patient approves; read-only dashboard; emergency alert with map, call, acknowledge; Twilio SMS; patient SOS screen |
| M5 Medication Management | FR-5.1–5.4 | Medication CRUD, reminders (local + FCM), dose confirm, missed-dose job, adherence (algorithm C), refill + interaction alerts |
| M13 Recurring Medication, Payment & Delivery | FR-13.1–13.5 | Recurring flag, monthly job, confirm/skip, method choice, Stripe PaymentSheet + webhook, pharmacist queue, collection slip, Grab adapter (real or fake) + tracking timeline, failed-delivery handling |
| M7 Appointment Scheduling | FR-7.1–7.5 | Slots, book/reschedule/cancel, admin assignment, reminders (FCM + SendGrid), pre-visit summary, High/Critical booking prompt, doctor schedule calendar |
| M6 Health Records Management | FR-6.1–6.2 | Storage upload (PDF/JPG/PNG, ≤ 10 MB), category, share with doctor, doctor view |
| M11 Admin Panel | FR-11.1–11.4 | Users, assignments (manual + auto-assign by lowest caseload), audit logs + CSV, delivery oversight, hospital/system analytics, system health, PDF report |
| M12 Settings & Preferences | FR-12.1–12.2 | Profile/contact/health profile edit (re-score on change), notification toggles, export, delete with cascade |

**Exit test:** full end-to-end runs for every role on the emulator, plus the Stripe test card and fake/sandbox Grab.

## Phase 5 — Integration testing & refinement

- `integration_test/` flows for each role (patient happy path, emergency path, recurring order path, doctor review path, admin provisioning path).
- Backend integration tests against the emulators, with mocked third parties.
- Performance checks for NFR-1.1 (sync < 2 s) and NFR-1.2 (inference < 3 s). Record the results in `IMPLEMENTATION_LOG.md`.
- A traceability check script (`scripts/trace.py`) that greps tests for every FR ID and prints any FR without a test. Target: zero.
- Final deploy: Cloud Run (backend), Firebase Hosting (staff portal), and release APKs for the patient and family flavors. Run the NFR-1.1 / NFR-1.2 checks against the live environment.
