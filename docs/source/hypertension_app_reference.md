# Hypertension Care Management Platform

## Flutter Project Reference

---

## Project Overview

A cross-platform hypertension monitoring app built with Flutter (Dart).

- **Mobile** (Android / iOS) → Patient, Family Member  
- **Web** (Flutter Web, Firebase Hosting) → Doctor, Admin, Pharmacist

### Core Problem

Hypertension affects 1.28 billion people worldwide. This platform addresses:

1. Lack of continuous monitoring tools  
2. Poor medication adherence (40–60% of patients)  
3. Fragmented care coordination across providers

---

## User Roles

| Role | Platform | Primary Access |
| :---- | :---- | :---- |
| Patient | Mobile | Dashboard, BP log, medications, appointments, AI agent |
| Doctor | Web | Patient list, care plans, prescriptions, risk alerts |
| Family Member | Mobile | Real-time patient status, emergency alerts, GPS |
| Admin | Web | User management, analytics, audit logs, system health |
| Pharmacist | Web | Prescription queue, inventory, Grab delivery coordination |

---

## Tech Stack

### Frontend

- **Flutter (Dart)** — single codebase for Android, iOS, Web  
- `go_router` — navigation \+ role-based route guards  
- `flutter_riverpod` — state management  
- `fl_chart` — BP trend charts  
- `camera` — PPG heart rate capture (mobile only)  
- `google_maps_flutter` \+ `geolocator` — GPS emergency tracking

### Backend

- **Python / FastAPI** — REST API \+ ML model serving  
- Endpoints: vitals ingestion, medication management, appointment scheduling, triage processing, risk scoring  
- NLP keyword scanner for message escalation

### Database & Services (Firebase)

- **Firestore** — patient data, vitals, medications, appointments, messaging  
- **Firebase Storage** — medical documents  
- **Firebase Auth** — authentication, session management  
- **FCM** — push notifications (medication reminders, emergency alerts)

### External APIs

| Service | Purpose |
| :---- | :---- |
| Google Gemini Flash | AI Health Agent (24/7 conversational) |
| Random Forest / XGBoost | ML disease risk prediction (served via FastAPI) |
| Stripe (Sandbox) | Medication payment processing |
| Grab API | Home medication delivery \+ real-time tracking |
| SendGrid | Email notifications (appointments, receipts, alerts) |
| Twilio | Emergency SMS to family members |
| Google Maps API | GPS tracking during emergency events |

---

## Project Folder Structure

hypertension\_app/

├── lib/

│   ├── main.dart

│   ├── core/

│   │   ├── constants/          \# app colors, text styles, route names

│   │   ├── theme/              \# ThemeData light/dark

│   │   ├── router/             \# GoRouter \+ role guards

│   │   ├── di/                 \# GetIt service locator

│   │   └── utils/              \# bp\_classifier.dart, validators, formatters

│   │

│   ├── features/

│   │   ├── auth/               \# M1 — login, register, onboarding health profile

│   │   ├── dashboard/          \# M2 — patient health overview, risk score cards

│   │   ├── vitals/             \# M3 — BP log form, PPG camera capture

│   │   ├── charts/             \# M4 — 7d/30d/3m/1y trend charts

│   │   ├── medications/        \# M5 — schedule, reminders, adherence log

│   │   ├── records/            \# M6 — document upload, share with doctor

│   │   ├── appointments/       \# M7 — booking, pre-visit summary

│   │   ├── provider\_portal/    \# M8 — doctor patient list, notes, care plans

│   │   ├── ai\_monitoring/      \# M9 — ML alerts, risk escalation logic

│   │   ├── messaging/          \# M10 — secure chat, NLP escalation

│   │   ├── admin/              \# M11 — user mgmt, audit logs, analytics

│   │   ├── settings/           \# M12 — profile, data export, account deletion

│   │   ├── pharmacy/           \# M13 — recurring Rx, Stripe payment, Grab delivery

│   │   ├── ai\_agent/           \# Feature 1 — Gemini chatbot

│   │   ├── family/             \# Feature 2 — family monitoring, emergency GPS

│   │   └── symptom/            \# Feature 4 — triage engine \+ PPG capture

│   │

│   ├── shared/

│   │   ├── widgets/            \# BPCard, RiskBadge, MedTile, AlertBanner

│   │   ├── models/             \# Patient, BPReading, Medication, RiskScore, etc.

│   │   ├── services/

│   │   │   ├── firebase/       \# Firestore, Auth, Storage wrappers

│   │   │   ├── api/            \# FastAPI client — Dio \+ Retrofit

│   │   │   ├── notifications/  \# FCM \+ flutter\_local\_notifications

│   │   │   └── ppg/            \# Camera heart rate capture service

│   │   └── providers/          \# Riverpod providers per feature

│   │

│   └── l10n/                   \# Localisation (EN)

│

├── functions/                   \# Firebase Cloud Functions (emergency triggers)

├── test/

│   ├── unit/

│   ├── widget/

│   └── integration/

└── pubspec.yaml

---

## pubspec.yaml — Key Dependencies

dependencies:

  flutter:

    sdk: flutter

  \# State management

  flutter\_riverpod: ^2.5.1

  riverpod\_annotation: ^2.3.5

  \# Navigation

  go\_router: ^13.2.0

  \# Firebase

  firebase\_core: ^3.3.0

  firebase\_auth: ^5.1.4

  cloud\_firestore: ^5.2.1

  firebase\_storage: ^12.1.3

  firebase\_messaging: ^15.0.4

  \# HTTP / API client

  dio: ^5.6.0

  retrofit: ^4.1.0

  \# Charts

  fl\_chart: ^0.68.0

  \# Camera (PPG heart rate)

  camera: ^0.11.0

  \# Maps & GPS

  google\_maps\_flutter: ^2.7.0

  geolocator: ^12.0.0

  \# Payments

  flutter\_stripe: ^10.2.0

  \# Local notifications

  flutter\_local\_notifications: ^17.2.2

  \# UI utilities

  cached\_network\_image: ^3.3.1

  file\_picker: ^8.0.3

  intl: ^0.19.0

  \# Dependency injection

  get\_it: ^7.7.0

dev\_dependencies:

  flutter\_test:

    sdk: flutter

  riverpod\_generator: ^2.4.0

  build\_runner: ^2.4.9

  retrofit\_generator: ^8.1.0

---

## Role-Based Routing (GoRouter)

// lib/core/router/app\_router.dart

final routerProvider \= Provider\<GoRouter\>((ref) {

  final authState \= ref.watch(authStateProvider);

  return GoRouter(

    initialLocation: '/splash',

    redirect: (context, state) {

      if (authState.isLoading) return '/splash';

      if (\!authState.isAuthenticated) return '/login';

      return switch (authState.role) {

        UserRole.patient    \=\> '/dashboard',

        UserRole.doctor     \=\> '/provider',

        UserRole.admin      \=\> '/admin',

        UserRole.pharmacist \=\> '/pharmacy',

        UserRole.family     \=\> '/family',

      };

    },

    routes: \[

      GoRoute(path: '/splash', builder: (\_, \_\_) \=\> const SplashScreen()),

      GoRoute(path: '/login',  builder: (\_, \_\_) \=\> const LoginScreen()),

      GoRoute(path: '/onboard', builder: (\_, \_\_) \=\> const OnboardingFlow()),

      // Patient shell (mobile BottomNavigationBar)

      ShellRoute(

        builder: (\_, \_\_, child) \=\> PatientShell(child: child),

        routes: \[

          GoRoute(path: '/dashboard',    builder: (\_, \_\_) \=\> const DashboardScreen()),

          GoRoute(path: '/vitals/log',   builder: (\_, \_\_) \=\> const VitalLogScreen()),

          GoRoute(path: '/medications',  builder: (\_, \_\_) \=\> const MedicationScreen()),

          GoRoute(path: '/appointments', builder: (\_, \_\_) \=\> const AppointmentScreen()),

          GoRoute(path: '/records',      builder: (\_, \_\_) \=\> const RecordsScreen()),

          GoRoute(path: '/chat',         builder: (\_, \_\_) \=\> const MessagingScreen()),

          GoRoute(path: '/ai-agent',     builder: (\_, \_\_) \=\> const AIAgentScreen()),

          GoRoute(path: '/symptom',      builder: (\_, \_\_) \=\> const SymptomCheckerScreen()),

        \],

      ),

      // Doctor shell (web sidebar layout)

      ShellRoute(

        builder: (\_, \_\_, child) \=\> ProviderShell(child: child),

        routes: \[

          GoRoute(path: '/provider',

            builder: (\_, \_\_) \=\> const ProviderDashboard()),

          GoRoute(path: '/provider/patient/:id',

            builder: (\_, s) \=\> PatientDetailScreen(id: s.pathParameters\['id'\]\!)),

          GoRoute(path: '/provider/patient/:id/notes',

            builder: (\_, s) \=\> ClinicalNotesScreen(id: s.pathParameters\['id'\]\!)),

        \],

      ),

      GoRoute(path: '/admin',    builder: (\_, \_\_) \=\> const AdminPanel()),

      GoRoute(path: '/pharmacy', builder: (\_, \_\_) \=\> const PharmacyDashboard()),

      GoRoute(path: '/family',   builder: (\_, \_\_) \=\> const FamilyMonitorScreen()),

    \],

  );

});

---

## Firestore Data Models

### Firestore Collection Structure

patients/{patientId}

    → bp\_readings/{readingId}

    → risk\_scores/{scoreId}

    → medications/{medId}

    → appointments/{apptId}

    → health\_records/{recordId}

    → ai\_sessions/{sessionId}

doctors/{doctorId}

    → clinical\_notes/{noteId}

    → care\_plans/{planId}

messages/{conversationId}

    → messages/{messageId}

prescriptions/{prescriptionId}

    → delivery\_orders/{orderId}

users/{uid}          ← top-level for auth \+ role

family\_links/{linkId}

### BPReading

class BPReading {

  final String id;

  final int systolic;

  final int diastolic;

  final int? heartRate;        // PPG or manual entry

  final String? notes;

  final DateTime timestamp;

  final String patientId;

  // Firestore path: patients/{patientId}/bp\_readings/{id}

}

### RiskScore

class RiskScore {

  final String patientId;

  final double strokeRisk;       // 0.0 – 1.0

  final double cadRisk;          // Coronary Artery Disease

  final double heartFailureRisk;

  final double ckdRisk;          // Chronic Kidney Disease

  final double diabetesRisk;

  final RiskLevel overallLevel;  // low | moderate | high | critical

  final DateTime computedAt;

  // Firestore path: patients/{patientId}/risk\_scores/{id}

}

### PatientProfile

class PatientProfile {

  final String uid;

  final String name;

  final int age;

  final String gender;

  final double bmi;

  final bool isSmoker;

  final bool consumesAlcohol;

  final String activityLevel;    // sedentary | light | moderate | active

  final String dietType;

  final List\<String\> familyHistory;

  final String assignedDoctorId;

  final List\<String\> familyMemberIds;

  final bool isChronicPatient;   // triggers recurring prescription flow

  final int durationOfHypertension; // years

  // Firestore path: patients/{uid}

}

### Medication

class Medication {

  final String id;

  final String name;

  final String dosage;

  final String frequency;          // once daily | twice daily | etc.

  final List\<TimeOfDay\> remindAt;

  final bool isRecurring;

  final int? refillReminderDaysLeft;

  final List\<DateTime\> missedDoses;

  final double adherenceRate;      // computed field

  // Firestore path: patients/{patientId}/medications/{id}

}

---

## BP Classification Utility

// lib/core/utils/bp\_classifier.dart

enum BPCategory { normal, elevated, stage1, stage2, crisis }

enum RiskLevel   { low, moderate, high, critical }

class BPClassifier {

  static BPCategory classify(int systolic, int diastolic) {

    if (systolic \>= 180 || diastolic \>= 120\) return BPCategory.crisis;

    if (systolic \>= 140 || diastolic \>= 90\)  return BPCategory.stage2;

    if (systolic \>= 130 || diastolic \>= 80\)  return BPCategory.stage1;

    if (systolic \>= 120 && diastolic \< 80\)   return BPCategory.elevated;

    return BPCategory.normal;

  }

  static Color categoryColor(BPCategory cat) \=\> switch (cat) {

    BPCategory.normal   \=\> const Color(0xFF1D9E75),

    BPCategory.elevated \=\> const Color(0xFFEF9F27),

    BPCategory.stage1   \=\> const Color(0xFFD85A30),

    BPCategory.stage2   \=\> const Color(0xFFE24B4A),

    BPCategory.crisis   \=\> const Color(0xFFA32D2D),

  };

  static String categoryLabel(BPCategory cat) \=\> switch (cat) {

    BPCategory.normal   \=\> 'Normal',

    BPCategory.elevated \=\> 'Elevated',

    BPCategory.stage1   \=\> 'High — Stage 1',

    BPCategory.stage2   \=\> 'High — Stage 2',

    BPCategory.crisis   \=\> 'Hypertensive Crisis',

  };

}

---

## FastAPI — Key Endpoints

POST   /api/v1/auth/register

POST   /api/v1/auth/login

POST   /api/v1/vitals/bp              \# log new BP reading

GET    /api/v1/vitals/bp/{patientId}  \# fetch history

POST   /api/v1/risk-score             \# run ML prediction

GET    /api/v1/risk-score/{patientId}/latest

POST   /api/v1/triage                 \# symptom triage engine

POST   /api/v1/ai-agent/chat          \# Gemini proxy with patient context

POST   /api/v1/appointments

PATCH  /api/v1/appointments/{id}

DELETE /api/v1/appointments/{id}

POST   /api/v1/prescriptions

POST   /api/v1/prescriptions/{id}/order    \# trigger Stripe \+ Grab

GET    /api/v1/prescriptions/{id}/delivery \# delivery status

POST   /api/v1/messages

GET    /api/v1/messages/{conversationId}

GET    /api/v1/admin/analytics

GET    /api/v1/admin/audit-logs

---

## ML Risk Prediction (Module 9\)

### Input features sent to FastAPI `/risk-score`:

{

  "systolic\_avg":   135,

  "diastolic\_avg":  88,

  "heart\_rate\_avg": 78,

  "bmi":            27.4,

  "age":            52,

  "gender":         "male",

  "is\_smoker":      true,

  "alcohol":        false,

  "activity\_level": "sedentary",

  "diet\_type":      "high\_sodium",

  "family\_history": \["stroke", "diabetes"\],

  "adherence\_rate": 0.72,

  "hypertension\_years": 5

}

### Output:

{

  "stroke\_risk":        0.34,

  "cad\_risk":           0.28,

  "heart\_failure\_risk": 0.19,

  "ckd\_risk":           0.41,

  "diabetes\_risk":      0.55,

  "overall\_level":      "high",

  "computed\_at":        "2026-06-26T10:00:00Z"

}

### Training datasets:

| Disease | Dataset |
| :---- | :---- |
| Coronary Heart Disease | Framingham Heart Study (Kaggle) |
| Diabetes | Pima Indians Diabetes Database (UCI/Kaggle) |
| Stroke | Stroke Prediction Dataset (Kaggle, fedesoriano) |
| Heart Failure | Heart Failure Clinical Data (Kaggle, andrewmvd) |
| Chronic Kidney Disease | CKD Dataset (Kaggle, mansoordaku) |

---

## Symptom Triage Engine (Feature 4\)

### Triage levels & system actions:

**Mild** — Systolic 130–139 / Diastolic 80–89

- Email BP report to assigned doctor  
- Doctor notified: possible medication review  
- Patient offered: optional appointment booking  
- Auto-escalates to Moderate if follow-up BP remains abnormal

**Moderate** — Systolic 140–179 / Diastolic 90–109

- Urgent message to doctor with BP, heart rate, symptoms, risk scores  
- Book Appointment button shown to patient  
- Family members notified  
- AI agent advises patient to avoid exertion  
- Auto-escalates to Emergency if doctor silent within threshold

**Emergency** — Systolic ≥ 180 / Diastolic ≥ 120

- Emergency appointment auto-booked (reassigned if doctor unavailable)  
- Doctor notified immediately with full vitals history  
- Patient flagged as Emergency on doctor's list  
- Family members receive GPS location alert via FCM \+ Twilio SMS  
- One-tap emergency call button activated on patient dashboard  
- AI agent: calm reassurance message  
- Full event logged to patient medical records

### PPG Heart Rate Capture flow:

1. Patient opens Symptom Checker  
2. `camera` plugin streams frames  
3. Green channel intensity isolated per frame (most sensitive to blood flow)  
4. Peak detection algorithm runs in a Dart `Isolate`  
5. BPM calculated and fed into triage engine alongside BP \+ risk scores

---

## Emergency Alert Flow (Firebase Cloud Function)

Triggered when: BP reading classified as `crisis` OR risk score \= `critical`

Crisis BP logged

    │

    ├── FCM push → patient device   (emergency banner \+ action buttons)

    ├── FCM push → family devices   (GPS payload included)

    ├── Twilio SMS → family phone numbers

    ├── Firestore flag → doctors/{doctorId}/alerts/{patientId}

    └── Firestore update → patients/{id}.status \= 'emergency'

Doctor app (real-time Firestore stream)

    └── Alert banner appears at top of patient list

---

## AI Health Agent (Feature 1 — Gemini Flash)

- **NOT called directly from Flutter** — proxied through FastAPI `/ai-agent/chat`  
- FastAPI injects patient context into Gemini system prompt:  
  - Latest BP readings (last 7 days)  
  - Current risk scores \+ overall level  
  - Active medications \+ adherence rate  
  - Upcoming appointments  
- Conversation history stored in Firestore: `patients/{id}/ai_sessions/{sessionId}`

### Post-vital-entry auto-prompt behaviour:

| Risk Level | AI Agent Response |
| :---- | :---- |
| Low / Moderate | Current status explanation \+ health tips |
| High | Status explanation \+ **Book Appointment** \+ **View Medications** buttons |
| Critical | Emergency instructions \+ **Book Emergency Appointment** \+ **Call Emergency Contact** \+ **Alert Family** buttons |

---

## Recurring Medication & Delivery (Module 13\)

Doctor marks patient as chronic

    │

    └── Monthly cycle begins:

          │

          ├── Patient receives notification: confirm medication order

          │

          ├── Patient selects collection method:

          │     ├── Self-collection → collection slip (prescription ID \+ ready time)

          │     └── Home delivery   → Stripe payment → Grab API dispatch

          │

          ├── Pharmacist notified → status: Preparing → Ready

          │

          ├── Grab API: real-time tracking, push notifications at each stage

          │

          ├── Failed delivery → reschedule or switch to self-collection

          │

          └── Payment receipt stored under patient health records

                  → cycle repeats next month

---

## Platform Layout Strategy

// Use LayoutBuilder to adapt between mobile and web

class ResponsiveLayout extends StatelessWidget {

  final Widget mobile;

  final Widget web;

  const ResponsiveLayout({required this.mobile, required this.web});

  @override

  Widget build(BuildContext context) {

    return LayoutBuilder(

      builder: (context, constraints) {

        if (constraints.maxWidth \>= 800\) return web;

        return mobile;

      },

    );

  }

}

// Patient screens → mobile BottomNavigationBar shell

// Doctor / Admin / Pharmacist → web NavigationRail or Sidebar shell

---

## Notification Types

| Trigger | Channel | Recipients |
| :---- | :---- | :---- |
| Medication reminder | FCM push | Patient |
| Appointment reminder | FCM push \+ SendGrid email | Patient |
| Critical BP reading | FCM push \+ Twilio SMS | Patient, Family |
| Risk escalates to High/Critical | FCM push | Patient, Doctor |
| Deterioration over 30 days | FCM push | Doctor |
| Medication review flag | FCM push | Doctor |
| Delivery stage update | FCM push | Patient |
| Missed doctor response (Moderate triage) | FCM push | Doctor |

---

## Key Implementation Notes

**State management pattern** — use Riverpod with `AsyncNotifierProvider` for data that requires loading states (vitals, risk scores). Use `StateNotifierProvider` for local UI state (form inputs, triage flow steps).

**Offline handling** — Firestore offline persistence is enabled by default. Queue BP readings locally when offline; sync automatically on reconnect. Show a subtle connectivity banner when offline.

**Web vs mobile feature flags** — use a `PlatformService` abstraction. Camera PPG is mobile-only; disable gracefully on web with a manual heart rate input field fallback.

**Security** — all Firestore reads/writes gated by Firebase Security Rules matching the user's role claim set in Firebase Auth custom claims. FastAPI validates the Firebase ID token on every request.

**Doctor–patient assignment** — managed by Admin via the Admin Panel. Stored on `patients/{id}.assignedDoctorId`. Doctors can only query patients where this field matches their UID (enforced in both Firestore rules and FastAPI query filters).

---

## Screens to Build (Priority Order)

### Mobile (Patient)

1. Login / Register / Onboarding flow  
2. Patient Dashboard (M2) — summary cards, quick actions  
3. BP Log form \+ reading history (M3)  
4. BP Trend Charts — 7d/30d/3m/1y (M4)  
5. Medication list \+ reminder setup (M5)  
6. AI Health Agent chat (Feature 1\)  
7. Symptom Checker \+ triage result (Feature 4\)  
8. Appointment booking (M7)  
9. Secure messaging (M10)  
10. Health Records upload (M6)  
11. Emergency screen (Feature 2\)

### Web (Doctor / Admin / Pharmacist)

1. Doctor — patient list with risk filter  
2. Doctor — patient detail (full history, vitals, risk score timeline)  
3. Doctor — clinical notes \+ care plan editor  
4. Doctor — prescription issuer  
5. Admin — user management table  
6. Admin — system analytics dashboard  
7. Pharmacist — prescription queue \+ delivery management

---

## References

- WHO Hypertension Fact Sheet: [https\://www\.who.int/news-room/fact-sheets/detail/hypertension](https://www.who.int/news-room/fact-sheets/detail/hypertension)  
- Medication Adherence in Hypertension: [https\://pubmed.ncbi.nlm.nih.gov/30920917/](https://pubmed.ncbi.nlm.nih.gov/30920917/)  
- Fragmented Care Review: [https\://pmc.ncbi.nlm.nih.gov/articles/PMC10170908/](https://pmc.ncbi.nlm.nih.gov/articles/PMC10170908/)  
- Framingham CHD Dataset: [https\://www\.kaggle.com/datasets/aasheesh200/framingham-heart-study-dataset](https://www.kaggle.com/datasets/aasheesh200/framingham-heart-study-dataset)  
- Pima Diabetes Dataset: [https\://www\.kaggle.com/datasets/uciml/pima-indians-diabetes-database](https://www.kaggle.com/datasets/uciml/pima-indians-diabetes-database)  
- Stroke Dataset: [https\://www\.kaggle.com/datasets/fedesoriano/stroke-prediction-dataset](https://www.kaggle.com/datasets/fedesoriano/stroke-prediction-dataset)  
- Heart Failure Dataset: [https\://www\.kaggle.com/datasets/andrewmvd/heart-failure-clinical-data](https://www.kaggle.com/datasets/andrewmvd/heart-failure-clinical-data)  
- CKD Dataset: [https\://www\.kaggle.com/datasets/mansoordaku/ckdisease](https://www.kaggle.com/datasets/mansoordaku/ckdisease)

