# 05 — Architecture

Sources: Ch4 §4.4 (package diagram, deployment diagram, framework table), §4.5.2 (adopted technology), and `source/hypertension_app_reference.md` (folder structure, packages, routing, endpoints). Where these conflict, Chapter 4 wins (see `09-decisions-and-open-questions.md`).

Figures: `figures/ch4-figure-4-5-package-diagram-*.png`, `figures/ch4-figure-4-6-deployment-diagram-*.png`.

## Deployment (Ch4 §4.4.2)

Cloud plan, region, local-dev wiring and deploy scripts are in `10-environment-and-deployment.md`.

```
Patient app / Family app (Android) ──HTTPS/REST──▶ FastAPI on Cloud Run ──▶ Firebase Auth / Firestore / Storage
        │                                            │                    └▶ Gemini, Stripe, Grab, SendGrid, Twilio, FCM
        └── Firestore SDK (real-time listeners, reads)
Staff browser ──▶ Firebase Hosting (Flutter Web build) ── rewrite /api/** ──▶ same Cloud Run service
```

### Read/write split (follow this consistently)

- **Reads** that need real-time behaviour (NFR-1.1) go **directly from Flutter to Firestore** via snapshot listeners, protected by Security Rules. This covers vitals, risk scores, messages, alerts, orders and the family dashboard.
- **Writes with business logic or side effects** go **through FastAPI**: logging a reading (which triggers risk scoring), triage, AI agent, prescriptions, orders/payments, staff provisioning, assignment, exports and deletion. FastAPI uses the Firebase Admin SDK and writes `audit_logs` for every state change (FR-1.5).
- Simple owner-only CRUD with no side effects (e.g. editing a personal medication entry or a health record category) may write directly to Firestore if the rules allow it. Server-side code must still emit the audit log, so prefer FastAPI when in doubt.
- FastAPI verifies the Firebase ID token on **every** request (`Authorization: Bearer <idToken>`) and reads the `role` custom claim. It is stateless (NFR-5.1).

### Scheduled / background jobs

Ch4 has no Cloud Functions node, so keep all logic in the one FastAPI service. Use **Cloud Scheduler → authenticated FastAPI `/internal/jobs/*` endpoints** for:
- missed-dose detection (UC5.4)
- refill threshold check (UC5.2)
- appointment reminders (UC7.4)
- pre-visit summary generation (UC7.5)
- monthly recurring order prompts (UC13.2)
- 30-day deterioration scan (FR-9.6)
- moderate-triage escalation timeout
- account deletion cascade

Medication reminders on-device use `flutter_local_notifications` scheduled from the medication schedule, plus FCM as a backup. (Cloud Scheduler is not drawn in Ch4's deployment diagram; see D-08.)

## Monorepo layout

```
hypertension/                 # repo root (app name stays CareFlow)
├── CLAUDE.md
├── docs/                         # this spec package
├── app/                          # Flutter (one codebase, three entrypoints)
│   ├── lib/
│   │   ├── main_patient.dart     # Patient mobile app (Android)
│   │   ├── main_family.dart      # Family Member mobile app (Android)
│   │   ├── main_staff.dart       # Staff Web Portal (Flutter Web)
│   │   ├── core/                 # constants, theme, router, di (GetIt), utils (bp_classifier.dart, validators)
│   │   ├── features/
│   │   │   ├── auth/             # M1 (FR-1.x)
│   │   │   ├── dashboard/        # M2
│   │   │   ├── vitals/           # M3 (+ PPG)
│   │   │   ├── charts/           # M4
│   │   │   ├── medications/      # M5
│   │   │   ├── records/          # M6
│   │   │   ├── appointments/     # M7
│   │   │   ├── provider_portal/  # M8
│   │   │   ├── ai_monitoring/    # M9 (alerts UI, risk card)
│   │   │   ├── messaging/        # M10 (+ client-side encryption & keyword scan)
│   │   │   ├── admin/            # M11
│   │   │   ├── settings/         # M12
│   │   │   ├── pharmacy/         # M13 (pharmacist side) + recurring orders (patient side)
│   │   │   ├── ai_agent/         # FR-14.1
│   │   │   ├── family/           # FR-14.2
│   │   │   └── symptom/          # FR-14.3
│   │   ├── shared/{widgets,models,services/{firebase,api,notifications,ppg,crypto},providers}
│   │   └── l10n/                 # EN only
│   └── test/{unit,widget,integration}
├── backend/                      # FastAPI
│   ├── app/
│   │   ├── main.py
│   │   ├── core/                 # config, firebase admin init, auth dependency, audit logger
│   │   ├── routers/              # one router per module: auth, vitals, risk, triage, agent, medications,
│   │   │                         # records, appointments, provider, messaging, admin, settings, orders, jobs, webhooks
│   │   ├── services/             # business logic per module
│   │   ├── integrations/         # External Integration Adapter: gemini.py, stripe.py, grab.py, sendgrid.py, twilio.py, fcm.py
│   │   ├── ml/                   # model loading + inference (loads artefacts from ml/artifacts)
│   │   └── schemas/              # Pydantic models mirroring 04-data-model.md
│   ├── tests/
│   └── Dockerfile
├── ml/                           # training pipeline (notebooks/scripts), datasets README, artifacts/, metrics report
├── firebase/
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   ├── storage.rules
│   ├── firebase.json             # hosting rewrites /api/** → Cloud Run
│   └── seed/                     # symptom_catalog, demo users per role
└── scripts/git-hooks/commit-msg
```

The package diagram's layers map like this:
- **client** → `app/`
- **backend API** → `backend/app/routers`
- **Core Domain Packages** → one folder per module
- **infrastructure/integration** → `backend/app/integrations` + `shared/services/firebase`

Cross-module dependencies are only allowed where Ch4 shows one, e.g. Vitals → AI Monitoring, and Medication → Recurring Orders.

## Flutter conventions (from the reference md)

- **State:** `flutter_riverpod`. Use `AsyncNotifierProvider` for loaded data (vitals, risk scores) and `Notifier`/`StateNotifier` for local UI state (forms, triage steps).
- **Navigation:** `go_router` with role guards. Each entrypoint has its own router and only registers routes for its roles (NFR-3.2).
- **DI:** `get_it` for services. **HTTP:** `dio` + `retrofit`.
- **Charts:** `fl_chart`. **Camera:** `camera` for PPG, processed in a Dart `Isolate`. **Maps:** `google_maps_flutter` + `geolocator`.
- **Payments:** `flutter_stripe` PaymentSheet.
- **Notifications:** `firebase_messaging` + `flutter_local_notifications`.
- **Files:** `file_picker`; `cached_network_image`; `intl`.
- **Responsive layout:** staff portal uses a NavigationRail/sidebar shell at ≥ 800 px width.
- Camera PPG is mobile-only. Provide a manual heart-rate field fallback where the camera is unavailable.
- Show an offline banner when disconnected. Firestore offline persistence stays on (NFR-4.2).
- The reference md's pubspec versions are a starting point. Resolve to current stable versions at `flutter pub get` time rather than pinning old ones.

### Routes per entrypoint

**Patient app** (`main_patient.dart`, BottomNavigationBar shell):
`/splash`, `/login`, `/register`, `/onboard`, `/dashboard`, `/vitals`, `/vitals/log`, `/trends`, `/medications`, `/appointments`, `/appointments/book`, `/records`, `/chat`, `/chat/:threadId`, `/ai-agent`, `/symptom`, `/symptom/result/:id`, `/sos`, `/orders/:id/confirm`, `/orders/:id/pay`, `/orders/:id/track`, `/settings`, `/family-requests`

**Family app** (`main_family.dart`): `/splash`, `/login`, `/register`, `/link`, `/link/pending`, `/home`, `/alert/:alertId`

**Staff portal** (`main_staff.dart`, sidebar shell):
- `/login`
- Doctor: `/doctor`, `/doctor/schedule`, `/doctor/patient/:id`, `/doctor/patient/:id/notes`, `/doctor/patient/:id/prescriptions`, `/doctor/patient/:id/care-plan`, `/doctor/messages`
- Pharmacist: `/pharmacy`
- Admin: `/admin/users`, `/admin/assignments`, `/admin/audit-logs`, `/admin/deliveries`, `/admin/analytics/hospital`, `/admin/analytics/system`, `/admin/system-health`

Redirects: unauthenticated → `/login`. A patient with `onboardingComplete == false` → `/onboard`. A role that doesn't match the entrypoint → sign out with the message "Please use the correct app".

## FastAPI endpoints (prefix `/api/v1`)

| Method & path | Purpose | FR |
|---|---|---|
| POST `/auth/register-profile` | After client-side Firebase sign-up: create `users` doc, set role claim (patient/family_member only) | FR-1.1 |
| POST `/auth/onboarding` | Save `health_profiles`, set `onboardingComplete` | FR-1.4 |
| POST `/admin/staff` | Create doctor/pharmacist/admin account + claim, send setup link | FR-1.6 |
| GET/PATCH `/admin/users`, `/admin/users/{uid}` | List/edit/deactivate (block deactivating last admin) | FR-11.1 |
| PUT `/admin/assignments/{patientId}` | Assign/reassign doctor | FR-7.2, FR-11.2 |
| GET `/admin/audit-logs` | Filter by user/date/action, CSV export | FR-1.5, FR-11.3 |
| GET `/admin/system-health` | Ping each dependency: API, Firestore, ML, Stripe, Grab, FCM | FR-11.3 |
| GET `/admin/analytics/{hospital/system}`, POST `/admin/reports` (PDF) | Analytics + hospital-wide PDF | FR-11.4 |
| GET `/admin/deliveries` | Delivery oversight | FR-11.4 |
| POST `/vitals` | Validate plausible range, save reading, run risk scoring, run threshold alerts, return AI proactive update | FR-3.1, FR-9.1, FR-9.2 |
| POST `/risk-score/{patientId}` · GET `/risk-score/{patientId}/latest` | Manual re-score (e.g. after profile change) | FR-9.2–9.4 |
| POST `/triage` | Symptom checker classification + doctor notify | FR-14.3 |
| POST `/agent/chat` | Gemini proxy with patient context; persists `agent_messages` | FR-14.1 |
| POST `/medications`, PATCH/DELETE `/medications/{id}` | With drug-interaction check | FR-5.1, FR-5.4 |
| POST `/medications/{id}/doses` | Confirm dose (taken) → recompute adherence | FR-5.3 |
| POST `/records` (signed upload), POST `/records/{id}/share` | Upload/categorise, share | FR-6.1, FR-6.2 |
| GET `/appointments/slots`, POST `/appointments`, PATCH `/appointments/{id}` | Book/reschedule/cancel | FR-7.1 |
| GET `/appointments/{id}/pre-visit-summary` | | FR-7.4 |
| POST `/provider/patients/{id}/notes`, PUT `/provider/patients/{id}/care-plan`, POST `/provider/patients/{id}/prescriptions` | Doctor actions | FR-8.3 |
| POST `/prescriptions/{id}/recurring` | Flag recurring | FR-13.1 |
| POST `/messages` | Store ciphertext + `isFlagged` from client scan; escalate if flagged | FR-10.1, FR-10.3, FR-14.4 |
| POST `/messages/{id}/dismiss-flag` | Doctor dismisses false positive | UC10.3 E1 |
| POST `/orders/{id}/confirm`, POST `/orders/{id}/payment-intent`, POST `/orders/{id}/method` | Monthly order flow | FR-13.2–13.4 |
| PATCH `/orders/{id}/status` | Pharmacist: preparing / ready | UC13.6 |
| POST `/webhooks/stripe`, POST `/webhooks/grab` | Payment + delivery events → `payment_transactions`, `delivery_tracking_events` | FR-13.3, FR-13.4 |
| POST `/family/link-requests`, POST `/family/link-requests/{id}/approve` | Family link flow | UC15.1 (see D-06) |
| POST `/emergency/sos` | Patient-triggered SOS → family alert with GPS | FR-14.2 |
| POST `/emergency-alerts/{id}/ack` | Family acknowledges | UC15.3 |
| GET `/settings/export` · DELETE `/settings/account` | Export JSON/PDF, deletion cascade | FR-12.2 |
| POST `/internal/jobs/{job}` | Cloud Scheduler targets (OIDC-authenticated) | — |

Return errors as `{ "error": { "code": "...", "message": "..." } }`. Codes map to use-case exception flows, e.g. `READING_OUT_OF_RANGE` for UC3.1 E1 and `PAYMENT_DECLINED` for UC13.3 E1.

## Notifications (reference md + use cases)

| Trigger | Channel | Recipients |
|---|---|---|
| Medication reminder | Local notification + FCM | Patient |
| Missed dose / refill low | FCM | Patient |
| Drug interaction | In-app dialog (block save on critical) | Patient / Doctor |
| Appointment reminder | FCM + SendGrid email | Patient |
| BP threshold alert (Mild/Moderate/Emergency) | FCM | Patient (+ Doctor at Moderate+) |
| Risk High/Critical | FCM | Patient, Doctor |
| Critical risk / crisis BP | FCM (GPS payload) + Twilio SMS | Family members |
| 30-day deterioration, medication review flag | FCM + portal banner | Doctor |
| Flagged message | FCM + portal banner | Doctor |
| Triage Moderate/Emergency | FCM | Doctor |
| New paid order | FCM / portal | Pharmacist |
| Delivery stage update | FCM | Patient |
| Monthly order confirm | FCM | Patient |

Store FCM tokens per device in `users/{uid}/fcmTokens`. This is not in the data dictionary; see D-07.

## External integrations

Wrap every provider behind an interface in `backend/app/integrations/` (Ch4 §4.5.2, "third-party API isolation"). Each has a **real** implementation and a **fake** one, selected by env var, so the demo works without live credentials:
- **Gemini:** model `gemini-flash` family (use the current Flash model ID). The system prompt includes the patient context and a non-diagnostic disclaimer.
- **Stripe:** test keys only. PaymentIntent + PaymentSheet; the webhook is the source of truth for `payment_transactions`.
- **Grab:** sandbox. If sandbox access can't be obtained, `FakeGrabClient` simulates `dispatched → picked_up → in_transit → delivered` with timed webhook calls (see D-11).
- **SendGrid / Twilio:** trial accounts; fake clients log to console in dev.
- **Google Maps:** API key restricted to the Android app package and the web domain.

All secrets live in env vars / Secret Manager. Never commit keys. Provide `.env.example`.
