# 02 — System Requirements

Source: Chapter 3, Sections 3.6 and 3.7 (latest version). **52 functional + 15 non-functional requirements.** Requirement text is verbatim from the report — do not reword IDs or meaning in code comments, tests, or commit messages.

Columns: **UC** = use cases in `03-use-cases.md`; **Inc** = build increment in `08-build-plan.md`.

Every feature you implement must cite its FR/NFR ID (in the PR/commit message body and in test names, e.g. `test('FR-5.3 computes adherence over 30-day window')`).


## Module 1: User and Access Management
_Increment 1 — sequence diagram Fig 4.1.1.1_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-1.1 | The system shall allow patients and family members to self-register a new account using email/password via Firebase Authentication. Doctor, Pharmacist, and Admin accounts are provisioned by the Admin rather than self-registered (see FR-1.6). | UC1.1 | 1 |
| FR-1.2 | The system shall allow all registered users, regardless of role, to log in and log out using email/password via Firebase Authentication. | UC1.2, UC1.3 | 1 |
| FR-1.3 | The system shall enforce role-based access control for Patient, Doctor, Family Member, Pharmacist, and Admin roles. | all | 1 |
| FR-1.4 | The system shall require patients to complete a one-time onboarding health profile covering personal information, medical history, and lifestyle, immediately after their first registration. | UC1.4 | 1 |
| FR-1.5 | The system shall log all user activity for audit purposes. | UC11.3 | 1 |
| FR-1.6 | The system shall allow only the Admin to create Doctor, Pharmacist, and Admin accounts; these roles shall have no self-registration access of their own. | UC1.5 | 1 |

## Module 2: Patient Health Overview
_Increment 1 — sequence diagram Fig 4.1.1.2_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-2.1 | The system shall display a personalised dashboard summarising medication schedule, upcoming appointments, recent BP readings, and current risk score. | UC2.1–UC2.4 | 1 |
| FR-2.2 | The system shall provide quick-access navigation to vitals logging, symptom checker, messaging, and the AI Health Agent. | UC2.5 | 1 |

## Module 3: Vital Signs Tracking
_Increment 1 — sequence diagram Fig 4.1.1.3_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-3.1 | The system shall allow patients to manually log blood pressure readings with optional notes. | UC3.1, UC3.2 | 1 |
| FR-3.2 | The system shall capture heart rate via mobile camera PPG (Yan et al., 2017). | UC3.3, UC14.2 | 1 |

## Module 4: Health Data Visualisation
_Increment 1 — sequence diagram Fig 4.1.1.4_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-4.1 | The system shall display BP trend charts across 7-day, 30-day, 3-month, and 1-year views. | UC4.1, UC4.3 | 1 |
| FR-4.2 | The system shall display statistical summaries (average, minimum, maximum) for logged vitals. | UC4.2 | 1 |
| FR-4.3 | The system shall display disease risk score trends over time. | UC4.4 | 1 |

## Module 5: Medication Management
_Increment 3 — sequence diagram Fig 4.1.1.5_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-5.1 | The system shall allow patients to add, edit, and delete medications with dosage and schedule. | UC5.1 | 3 |
| FR-5.2 | The system shall send push notification reminders for scheduled doses. | UC5.3 | 3 |
| FR-5.3 | The system shall log missed doses and compute a running adherence rate. | UC5.4, UC5.5 | 3 |
| FR-5.4 | The system shall send refill and drug interaction alerts. | UC5.2, UC5.6 | 3 |

## Module 6: Health Records Management
_Increment 3 — sequence diagram Fig 4.1.1.6_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-6.1 | The system shall allow patients to upload and categorise medical documents. | UC6.1 | 3 |
| FR-6.2 | The system shall allow patients to share documents with their assigned doctor. | UC6.2, UC6.3 | 3 |

## Module 7: Appointment Scheduling
_Increment 3 — sequence diagram Fig 4.1.1.7_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-7.1 | The system shall allow patients to book, reschedule, and cancel appointments. | UC7.1, UC7.2 | 3 |
| FR-7.2 | The system shall allow the Admin to assign a doctor to a patient upon booking. | UC7.3 | 3 |
| FR-7.3 | The system shall send appointment reminders via push notification and email. | UC7.4 | 3 |
| FR-7.4 | The system shall generate a pre-visit summary before each appointment. | UC7.5 | 3 |
| FR-7.5 | The system shall prompt the patient to book an appointment when disease risk reaches High or Critical. | UC7.1 (A1), UC9.2 | 3 |

## Module 8: Healthcare Provider Portal
_Increment 2 — sequence diagram Fig 4.1.1.8_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-8.1 | The system shall display only the doctor's assigned patient list, searchable and filterable by ML-predicted risk level. | UC8.1, UC8.2 | 2 |
| FR-8.2 | The system shall allow doctors to view full health history for assigned patients. | UC8.3 | 2 |
| FR-8.3 | The system shall allow doctors to write clinical notes, update care plans, and issue prescriptions. | UC8.4, UC8.5 | 2 |
| FR-8.4 | The system shall deliver risk alerts, triage notifications, and deterioration alerts to the assigned doctor. | UC8.6 | 2 |

## Module 9: AI-Powered Health Monitoring
_Increment 2 — sequence diagram Fig 4.1.1.9_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-9.1 | The system shall generate real-time threshold alerts for critically out-of-range BP readings. | UC9.2 | 2 |
| FR-9.2 | The system shall predict patient risk for Stroke, Coronary Artery Disease, Heart Failure, Chronic Kidney Disease, and Type 2 Diabetes using Random Forest/XGBoost models (Breiman, 2001; Chen & Guestrin, 2016). | UC9.1 | 2 |
| FR-9.3 | The system shall categorise each risk score as Low, Moderate, High, or Critical. | UC9.1 | 2 |
| FR-9.4 | The system shall auto-generate personalized recommendations based on risk level. | UC2.7, UC9.2 | 2 |
| FR-9.5 | The system shall notify the assigned doctor when patient risk escalates, and family members when risk reaches Critical. | UC9.3 | 2 |
| FR-9.6 | The system shall send a deterioration alert to the doctor when risk worsens steadily over 30 days. | UC9.3 | 2 |

## Module 10: Care Coordination and Messaging
_Increment 3 — sequence diagram Fig 4.1.1.10_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-10.1 | The system shall provide secure messaging between patients and their assigned doctor. | UC10.1 | 3 |
| FR-10.2 | The system shall provide shared care plan access across the assigned care team. | UC10.2 | 3 |
| FR-10.3 | The system shall auto-escalate messages containing high-risk keywords to the assigned doctor. | UC10.3 | 3 |

## Module 11: Admin Panel
_Increment 3 — sequence diagram Fig 4.1.1.11_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-11.1 | The system shall allow the Admin to manage all user accounts (view, edit, deactivate). | UC11.1 | 3 |
| FR-11.2 | The system shall allow the Admin to assign and reassign patients to doctors. | UC11.2 | 3 |
| FR-11.3 | The system shall provide audit log access and system health monitoring. | UC11.3 | 3 |
| FR-11.4 | The system shall allow the Admin to oversee medication delivery orders and generate hospital-wide reports as PDF. | UC11.4, UC11.5 | 3 |

## Module 12: Settings and Preferences
_Increment 3 — sequence diagram Fig 4.1.1.12_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-12.1 | The system shall allow patients to update profile, contact information, and onboarding health profile. | UC12.1, UC12.2 | 3 |
| FR-12.2 | The system shall allow patients to export their health data or delete their account. | UC12.3, UC12.4 | 3 |

## Module 13: Recurring Medication, Payment and Delivery
_Increment 3 — sequence diagram Fig 4.1.1.13_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-13.1 | The system shall allow doctors to flag a patient as long-term chronic and issue a recurring prescription. | UC13.1 | 3 |
| FR-13.2 | The system shall automatically notify the patient monthly to confirm their medication order. | UC13.2 | 3 |
| FR-13.3 | The system shall process payment via Stripe and notify the pharmacist upon confirmation. | UC13.3, UC13.6 | 3 |
| FR-13.4 | The system shall support self-collection (with collection slip) and home delivery (via Grab API with real-time tracking) fulfilment paths. | UC13.3–UC13.5 | 3 |
| FR-13.5 | The system shall prompt the patient to reschedule or switch the collection method upon failed delivery. | UC13.4 (E1), UC13.5 (E1) | 3 |

## Cross-Cutting Features (FR-14.x)
_Increment 2–3_

| ID | Requirement | UC | Inc |
|---|---|---|---|
| FR-14.1 | (AI Health Agent) The system shall provide a 24/7 conversational agent, powered by Google Gemini Flash, that answers patient queries and explains risk scores in plain language. | UC2.6, UC2.7 | 2 |
| FR-14.2 | (Family Monitoring) The system shall allow linked family members to view real-time BP readings and receive Critical-level emergency alerts with GPS location. | UC15.1–UC15.3 | 3 |
| FR-14.3 | (Symptom Checker and Triage) The system shall cross-reference symptoms, severity, vitals, and risk scores to produce a triage outcome of Monitor at Home, Contact Your Doctor, or Seek Emergency Care. | UC14.1–UC14.4 | 2 |
| FR-14.4 | (NLP Message Analysis) The system shall scan patient messages for high-risk keywords and auto-escalate flagged messages. | UC10.1, UC10.3 | 3 |

Cross-cutting sequence diagrams: FR-14.1 → Fig 4.1.1.16, FR-14.2 → Fig 4.1.1.15, FR-14.3 → Fig 4.1.1.14, FR-14.4 → Fig 4.1.1.10.

## Non-Functional Requirements (3.7)

| ID | Category | Requirement | How it is met (Ch4 §4.5.2 / §4.5.3) |
|---|---|---|---|
| NFR-1.1 | Performance | BP readings and messages shall synchronise across connected clients within 2 seconds under normal network conditions, leveraging Firestore's real-time listeners. | Firestore snapshot listeners on clients; no polling |
| NFR-1.2 | Performance | ML risk prediction inference shall return a result within 3 seconds of request. | Models pre-loaded in FastAPI process at startup; inference only per request |
| NFR-2.1 | Security | All patient-doctor messaging shall be end-to-end encrypted. | Client-side encryption before write to `messages.encryptedText` (see decision D-09) |
| NFR-2.2 | Security | Role-based access control shall be enforced at the database level via Firestore security rules, ensuring patients can access only their own data and doctors only their assigned patients' data. | Firestore Security Rules on `patientId` / `assignedDoctorId` + same filters in FastAPI queries |
| NFR-2.3 | Security | All payment processing shall comply with PCI DSS via Stripe. | Stripe hosted PaymentSheet; platform never sees card data |
| NFR-2.4 | Security | All data transmission shall occur over HTTPS. | HTTPS only (Cloud Run + Firebase Hosting enforce TLS) |
| NFR-3.1 | Usability | The mobile application interface shall be usable by patients with limited digital literacy, supported by the AI Health Agent's plain-language explanations. | Large touch targets, plain language, AI agent explanations |
| NFR-3.2 | Usability | Each user role shall be presented with a role-specific interface limited to functions relevant to that role. | Separate app entrypoints + role-guarded routes |
| NFR-4.1 | Reliability & Availability | The system shall maintain 99% uptime, leveraging Firebase's managed, auto-scaling infrastructure. | Managed Firebase + Cloud Run |
| NFR-4.2 | Reliability & Availability | The mobile application shall retain offline access to previously loaded data via Firestore's offline persistence, syncing automatically upon reconnection. | Firestore offline persistence; queued writes; offline banner |
| NFR-5.1 | Scalability | The backend shall support horizontal scaling of concurrent users without requiring architectural change, via Firebase's managed infrastructure and FastAPI's asynchronous request handling. | Stateless FastAPI, bearer tokens, Cloud Run autoscaling |
| NFR-6.1 | Compatibility | The mobile application shall be compatible with Android devices running [INSERT: minimum Android API level]. | **Placeholder in report** — pick minSdk (decision D-12) |
| NFR-6.2 | Compatibility | The Healthcare Provider Portal and Admin Panel shall be accessible via modern web browsers through the Flutter web build. | Flutter Web build on Firebase Hosting |
| NFR-7.1 | Maintainability | The codebase shall follow a modular architecture aligned to the thirteen system modules, allowing individual modules to be updated independently. | One feature folder / backend router per module |
| NFR-8.1 | Compliance | The system shall handle patient health data in accordance with Malaysia's Personal Data Protection Act (PDPA) principles, including purpose limitation and data minimisation, given the platform's academic proof-of-concept status noted in Section 1.6 (Personal Data Protection Act 2010). | Data minimisation, cascade delete on account deletion, audit logs |
