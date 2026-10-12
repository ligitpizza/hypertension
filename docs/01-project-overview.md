# 01 — Project Overview

Source: Chapter 1 (Introduction), with technology justification from Chapter 2 §2.6.

## What we are building

**CareFlow — Hypertension Care Management Platform.** An academic proof-of-concept FYP (BMCS3403, TAR UMT) by Woo Yee Ping, a solo developer. It targets a Malaysian **private hospital** setting.

It addresses three problems:
1. **Lack of continuous monitoring.** BP is only measured at clinic visits.
2. **Poor medication adherence.** 40–60% of hypertension patients are non-adherent.
3. **Fragmented care coordination.** Patients, doctors, pharmacy and family are disconnected.

## Users and client surfaces

| Role | Client surface | Primary access |
|---|---|---|
| Patient | Patient mobile app (Android) | Dashboard, BP log, PPG, medications, appointments, records, messaging, AI agent, symptom checker, SOS, settings, recurring orders |
| Family Member | Family Member mobile app (Android, separate build, read-only) | Link to patient, real-time status, emergency alerts with GPS, one-tap call |
| Doctor | Staff Web Portal (Flutter Web) | Patient list by risk, patient detail, notes, care plans, prescriptions, risk alerts, schedule |
| Pharmacist | Staff Web Portal | Prescription and order queue, inventory, Grab dispatch |
| Admin | Staff Web Portal | User management, staff provisioning, patient–doctor assignment, audit logs, delivery oversight, analytics, system health, PDF reports |

## Project objectives (SMART; these are evaluated in Chapter 5)

- **Objective 1, Monitoring.** Manual BP logging, camera PPG heart rate, trend charts (7d/30d/3m/1y), and threshold alerts (Mild/Moderate/Emergency). Also a Symptom Checker & Triage engine. *All alert thresholds must be verified by unit tests, and all visualisation views must be validated by integration tests.*
- **Objective 2, AI.** Random Forest and XGBoost risk prediction for Stroke, CAD, Heart Failure, CKD and Type 2 Diabetes, using 12 input variables. **Each complication predictor must reach AUC-ROC ≥ 0.80.** Risk has 4 levels (Low/Moderate/High/Critical). A Gemini Flash AI Health Agent explains scores in plain language.
- **Objective 3, Coordination.** End-to-end encrypted patient–doctor messaging, a shared care plan, and an NLP high-risk keyword escalation scanner. Also family GPS emergency alerts at Critical risk, and an AI-prioritised doctor dashboard filterable by risk.

## Scope

**In scope:** all 13 modules and all 4 cross-cutting features (AI Health Agent, Family Monitoring & Emergency Alert, Medication Delivery, Symptom Checker & Triage). Android mobile app plus Flutter Web portal. Integrations: Google Gemini Flash, Stripe **Sandbox**, Grab API (**sandbox/test**), Google Maps API, SendGrid, Twilio.

**Out of scope:**
- iOS build and App Store submission (Android only)
- Integration with a hospital HIS/EMR (the platform is standalone)
- Production Grab credentials and live Stripe charges
- Clinical validation or medical-device certification
- Public hospital deployment
- Multi-language support (English only)

## Acknowledged limitations (keep the implementation honest about these)

- ML models are trained on public Kaggle datasets, not Malaysian clinical data.
- Camera PPG is supplementary and less accurate than a medical device. The UI must present it as an estimate.
- The NLP scanner is rule-based keyword matching, so false positives and negatives are expected. The doctor can dismiss a flag (UC10.3 E1).
- This is a proof-of-concept and must not be used for real clinical decisions. Show a disclaimer in the AI agent and the symptom checker. The interview respondent explicitly asked for "not a replacement for a doctor" messaging.

## Methodology

**Incremental Development** across 3 build increments, followed by integration testing/UAT (Ch1 §1.9, Ch3 §3.1). Each increment covers requirements → design → implementation → testing, and must be independently testable before the next starts. See `08-build-plan.md`.

## Tech stack (Ch4 Table 4.4.3)

| Component | Language | Technology |
|---|---|---|
| Patient / Family mobile apps | Dart | Flutter (Android) |
| Staff Web Portal | Dart | Flutter Web (same codebase) |
| Application server | Python | FastAPI on Google Cloud Run |
| Real-time sync | — | Cloud Firestore snapshot listeners |
| Database | — | Cloud Firestore |
| File storage | — | Firebase Cloud Storage |
| Auth | — | Firebase Authentication (+ custom claims for role) |
| Push notifications | — | Firebase Cloud Messaging |
| Risk prediction | Python | scikit-learn (Random Forest) + XGBoost |
| AI Health Agent | — | Google Gemini Flash API (proxied via FastAPI) |
| Payments | — | Stripe API (sandbox) |
| Delivery | — | Grab API (sandbox) |
| Maps / GPS | — | Google Maps API, geolocator |
| Email / SMS | — | SendGrid, Twilio |
| Web hosting | — | Firebase Hosting (rewrites `/api/**` → Cloud Run) |
