# 03 — Use Cases

Source: Chapter 3, Section 3.4 (67 use cases across 13 modules + 2 cross-cutting groups). Generated directly from the report tables — flows, exceptions and triggers are the behavioural spec. Implement every Exception Flow (E1, E2…) as a handled error path with a test.

Diagrams: `figures/ch3-figure-3-26…3-38-use-case-diagram-*.gif` (Modules 1–13) and `figures/ch3-figure-3-39…3-53-activity-diagram-*.gif` (one activity diagram per module/feature). Matching sequence diagrams (BCE notation) are `figures/ch4-figure-4-1-1-*`.

Section 3.4.14 = Symptom Checker & Triage (FR-14.3). Section 3.4.15 = Family Monitoring & Emergency Alert (FR-14.2). UC2.6 / UC2.7 = AI Health Agent (FR-14.1).

## 3.4.1 Module 1 User and Access Management

### UC1.1 Register Account
- **Actors:** Patient, Family Member (secondary: None)
- **Trigger:** Triggered when a Patient or Family Member submits the registration form.
- **Description:** Creates a new self-service account for a Patient or Family Member, establishing the identity used for all subsequent role-scoped use cases. Doctor, Pharmacist, and Admin accounts are not created this way (see Create Staff Account, UC1.5).
- **Pre-conditions:** The email/credentials used are not already associated with an existing account.
- **Basic flow:**
  1. Patient or Family Member provides email, password, and name.
  2. The system creates the record via Firebase Authentication.
  3. The system creates a corresponding Firestore user document.
  4. System assigns the Patient or Family Member role to the account.
  5. The system directs the user to the role-appropriate entry point.
- **Alternative:**
  -
  - A1: If the actor is a Patient, the system triggers Complete Onboarding Health Profile (UC1.4) immediately after account creation.
- **Exception:**
  -
  - E1: Email already registered system displays an error and prompts the user to log in instead.
  - E2: Password does not meet complexity requirements system rejects submission and shows validation guidance.

### UC1.2 Log In
- **Actors:** All roles (Patient, Doctor, Family Member, Pharmacist, Admin) (secondary: None)
- **Trigger:** Triggered when a user submits login credentials.
- **Description:** Authenticates a returning user of any role and restores their role-scoped session.
- **Pre-conditions:** An account already exists for the credentials provided.
- **Basic flow:**
  1. The user enters an email and password.
  2. System validates credentials via Firebase Authentication.
  3. The system retrieves the user's role and profile.
  4. The system directs the user to their role-specific dashboard.
- **Alternative:**
  -
  - A1: User selects "Forgot password" system, sends a password reset link and returns to the login screen.
- **Exception:**
  -
  - E1: Incorrect credentials system displays an error without indicating whether the email or password was wrong.
  - E2: Account deactivated by Admin system denies login and displays a contact-support message.

### UC1.3 Log Out
- **Actors:** All roles (Patient, Doctor, Family Member, Pharmacist, Admin) (secondary: None)
- **Trigger:** Triggered when the user selects Log Out.
- **Description:** Ends the user's authenticated session, regardless of role.
- **Pre-conditions:** The user has an active session.
- **Basic flow:**
  1. User selects Log Out.
  2. The system invalidates the session token.
  3. The system returns the user to the login screen.
- **Exception:**
  -
  - E1: Network interruption during logout system clears local session state regardless, to avoid an unlocked device remaining signed in.

### UC1.4 Complete Onboarding Health Profile
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered automatically the first time a Patient account logs in after registration.
- **Description:** One-time intake of clinical and lifestyle data (medical history, lifestyle factors) for a newly registered patient. Extends Register Account (UC1.1); applies only to the Patient role, and only on first login.
- **Pre-conditions:** The actor has just registered as a Patient and has not previously completed onboarding.
- **Basic flow:**
  1. The system presents the onboarding form (personal information, medical history, lifestyle factors).
  2. The patient completes each section.
  3. The patient submits the form.
  4. The system validates and stores the profile.
  5. The system marks onboarding as complete and proceeds to the Patient dashboard.
- **Alternative:**
  -
  - A1: Patient saves partial progress and resumes onboarding at next login.
- **Exception:**
  -
  - E1: Required field left blank system blocks submission and highlights missing fields.

### UC1.5 Create Staff Account
- **Actors:** Admin (secondary: None)
- **Trigger:** Triggered when the Admin submits the new staff account form.
- **Description:** Allows the Admin to provision a new Doctor, Pharmacist, or Admin account on behalf of hospital staff, since these roles have no self-registration access of their own.
- **Pre-conditions:** Admin is authenticated; the staff member's employment/role has been verified outside the system.
- **Basic flow:**
  1. Admin opens the Create Staff Account screen.
  2. Admin enters the staff member's name, email, and assigns a role (Doctor, Pharmacist, or Admin).
  3. The system creates the account via Firebase Authentication.
  4. The system creates a corresponding Firestore user document with the assigned role.
  5. The system sends the new staff member their login credentials or a setup link.
- **Alternative:**
  -
  - A1: Admin assigns a Doctor to specific patients as part of account setup.
- **Exception:**
  -
  - E1: Email already registered system displays an error and prevents duplicate account creation.


## 3.4.2 Module 2 Patient Health Overview

### UC2.1 View Health Summary Dashboard
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient opens the app or navigates to the dashboard.
- **Description:** Displays a consolidated view of the patient's current status, composed of the medication schedule, upcoming appointments, and risk score card.
- **Pre-conditions:** The patient has completed onboarding.
- **Basic flow:**
  1. The patient opens the dashboard.
  2. System retrieves and displays Medication Schedule (UC2.2), Upcoming Appointments (UC2.3), and Risk Score Card (UC2.4).
- **Exception:**
  -
  - E1: One or more data sources fail to load system displays the remaining sections and an inline error for the failed section.

### UC2.2 Medication Schedule
- **Actors:** Patient (secondary: None)
- **Trigger:** Rendered automatically whenever the dashboard loads.
- **Description:** Shows the patient's medications due today. Includes into View Health Summary Dashboard (UC2.1); always shown as part of it.
- **Pre-conditions:** At least one medication is on the patient's list (Module 5).
- **Basic flow:**
  1. System retrieves today's scheduled doses from Module
  5.
  2. System renders them on the dashboard.
- **Exception:**
  -
  - E1: No medications on file system displays an empty state with a prompt to add one.

### UC2.3 Upcoming Appointments
- **Actors:** Patient (secondary: None)
- **Trigger:** Rendered automatically whenever the dashboard loads.
- **Description:** Shows the patient's next scheduled appointments. Includes into View Health Summary Dashboard (UC2.1); always shown as part of it.
- **Pre-conditions:** None (an empty list is a valid state).
- **Basic flow:**
  1. System retrieves upcoming bookings from Module
  7.
  2. The system renders them on the dashboard.
- **Exception:**
  -
  - E1: No appointments booked system displays a prompt to book one.

### UC2.4 Risk Score Card
- **Actors:** Patient (secondary: System)
- **Trigger:** Rendered automatically whenever the dashboard loads.
- **Description:** Shows the patient's current ML-predicted disease risk levels. Includes into View Health Summary Dashboard (UC2.1); always shown as part of it.
- **Pre-conditions:** At least one risk score has been generated (Module 9, UC9.1).
- **Basic flow:**
  1. The system retrieves the most recent risk scores.
  2. System renders the risk level (Low/Moderate/High/Critical) per complication.
- **Exception:**
  -
  - E1: No risk score generated yet (e.g. no vitals logged) system displays a prompt to log a reading.

### UC2.5 Navigate to Key Modules
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient taps a navigation shortcut.
- **Description:** Provides shortcut navigation from the dashboard to Vitals, Symptom Checker, Messaging, and the AI Agent.
- **Pre-conditions:** The patient is on the dashboard.
- **Basic flow:**
  1. The patient taps a shortcut.
  2. System routes to the corresponding module.

### UC2.6 Ask AI Health Agent
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered when the Patient sends a message to the AI agent.
- **Description:** Patient-initiated query to the conversational AI Health Agent (Google Gemini Flash), grounded in the patient's live vitals, risk scores, and medications.
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. Patient types a question.
  2. The system assembles context (vitals, risk scores, medications, medical history).
  3. The system sends the query and context to the Gemini API.
  4. The system returns a plain-language response to the patient.
- **Alternative:**
  -
  - A1: Patient asks about a risk score, specifically the system explains the score and contributing factors.
- **Exception:**
  -
  - E1: AI API call fails or times out system displays a fallback message and suggests contacting the care team directly.

### UC2.7 Receive Proactive Health Update
- **Actors:** System (secondary: Patient)
- **Trigger:** Triggered automatically immediately after Log Blood Pressure Reading (UC3.1) completes and a new risk score is generated.
- **Description:** System-generated status message delivered automatically after each vital entry, summarising the updated risk level and next-step guidance.
- **Pre-conditions:** A new vital reading has just been logged and a risk score generated.
- **Basic flow:**
  1. The system detects a new risk score following a vital entry.
  2. The system composes a plain-language status update via the AI Health Agent.
  3. The system displays the update to the patient with relevant action buttons (e.g. Book Appointment for High risk, Alert Family for Critical).


## 3.4.3 Module 3 Vital Signs Tracking

### UC3.1 Log Blood Pressure Reading
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered when the Patient opens Vital Signs Tracking and submits a reading.
- **Description:** Manual entry of a blood pressure reading, the platform's primary continuous-monitoring input.
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. The patient opens the Vital Signs Tracking screen.
  2. The patient enters systolic and diastolic values.
  3. The system validates the reading is within a plausible physiological range.
  4. The system saves the reading, timestamped, to Firestore.
  5. System triggers Generate Risk Score (UC9.1).
- **Alternative:**
  -
  - A1: Patient adds an optional note (UC3.2) before saving.
- **Exception:**
  -
  - E1: Reading outside the plausible range (e.g. systolic 400) system rejects the entry and asks the patient to re-check.

### UC3.2 Add Note to Reading
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient chooses to add a note during logging.
- **Description:** Optional free-text annotation on a BP entry (e.g. "after exercise"). Extends Log Blood Pressure Reading (UC3.1) as an optional, same-session step.
- **Pre-conditions:** The patient is in the process of logging a reading (UC3.1).
- **Basic flow:**
  1. Patient types a note.
  2. The system attaches it to the reading being saved.

### UC3.3 Capture Heart Rate (PPG)
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered when the Patient places a finger over the camera during a vitals or symptom-checker session.
- **Description:** Captures heart rate using the smartphone camera: the patient's fingertip over the lens, analysed via green-channel pixel intensity and peak detection (Yan et al., 2017).
- **Pre-conditions:** The device has a functioning rear camera; sufficient ambient lighting.
- **Basic flow:**
  1. The patient places fingertip over the camera lens.
  2. The system captures RGB frames and isolates the green channel.
  3. The system applies peak detection to compute beats per minute.
  4. The system stores the value alongside the current session (vitals entry or symptom checker).
- **Exception:**
  -
  - E1: Poor signal (movement, lighting, placement) system prompts the patient to reposition and retry.


## 3.4.4 Module 4 Health Data Visualisation

### UC4.1 View BP Trend Chart
- **Actors:** Patient, Doctor (secondary: None)
- **Trigger:** Triggered when the actor opens the visualisation screen (patient for their own data; doctor for an assigned patient's data).
- **Description:** Displays interactive blood pressure trend charts across 7-day, 30-day, 3-month, and 1-year views.
- **Pre-conditions:** At least one BP reading exists for the patient in question.
- **Basic flow:**
  1. Actor selects a timeframe.
  2. System retrieves readings within that range.
  3. The system renders the trend chart.
- **Alternative:**
  -
  - A1: Actor switches timeframe system re-renders without leaving the screen.
- **Exception:**
  -
  - E1: No readings in the selected range system displays an empty chart with a message.

### UC4.2 View Statistical Summary
- **Actors:** Patient, Doctor (secondary: None)
- **Trigger:** Rendered alongside the trend chart.
- **Description:** Displays average, minimum, and maximum BP values for the selected period.
- **Pre-conditions:** At least one BP reading exists in the selected range.
- **Basic flow:**
  1. The system computes average/min/max over the selected range.
  2. The system displays the summary alongside the chart.
- **Exception:**
  -
  - E1: Insufficient data (fewer than two readings) system displays available values and omits trend-based statistics.

### UC4.3 Compare Multiple Vitals
- **Actors:** Patient, Doctor (secondary: None)
- **Trigger:** Triggered when the actor selects a second vital to overlay.
- **Description:** Overlays BP against another vital (e.g. heart rate) on a single chart.
- **Pre-conditions:** Readings exist for both selected vitals.
- **Basic flow:**
  1. The actor selects a second vital.
  2. The system retrieves and overlays both series on one chart.
- **Exception:**
  -
  - E1: Second vital has no data in range system displays the primary vital only and notes the gap.

### UC4.4 View Risk Score Trend
- **Actors:** Patient, Doctor (secondary: System)
- **Trigger:** Triggered when the actor opens the risk trend view.
- **Description:** Displays the historical trend of ML-predicted disease risk scores over time.
- **Pre-conditions:** At least two risk scores have been generated over time.
- **Basic flow:**
  1. The system retrieves historical risk scores.
  2. The system renders the trend per complication.
- **Exception:**
  -
  - E1: Fewer than two data points system displays the single available score without a trend line.


## 3.4.5 Module 5 Medication Management

### UC5.1 Manage Personal Medication List
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient opens the medication list and adds/edits/deletes an entry.
- **Description:** Add, edit, or delete entries in the patient's own medication tracking and reminder list. Governs reminder scheduling and self-tracking only, not the doctor's clinical prescription record.
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. The patient opens the medication list.
  2. Patient adds, edits, or deletes an entry (name, dosage, schedule).
  3. The system validates and saves the change.
- **Exception:**
  -
  - E1: Duplicate or conflicting schedule entry system warns the patient before saving.

### UC5.2 Receive Refill Alert
- **Actors:** System (secondary: Patient)
- **Trigger:** Triggered automatically when computed remaining supply falls below the configured threshold.
- **Description:** Automated alert when remaining medication supply drops below a threshold. Extends Manage Personal Medication List (UC5.1); System-triggered.
- **Pre-conditions:** A medication's dosage/schedule data exists and consumption has been tracked.
- **Basic flow:**
  1. The system computes remaining supply from schedule and adherence data.
  2. System detects supply below threshold.
  3. The system sends a refill alert to the patient.

### UC5.3 Receive Reminder
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered at the scheduled dose time.
- **Description:** Scheduled push notification prompting the patient to take a dose.
- **Pre-conditions:** A medication schedule exists (UC5.1).
- **Basic flow:**
  1. The system reaches the scheduled dose time.
  2. The system sends a push notification.
  3. The patient confirms the dose was taken.
- **Exception:**
  -
  - E1: Patient does not respond within the window system triggers Log Missed Dose (UC5.4).

### UC5.4 Log Missed Dose
- **Actors:** System (secondary: Patient)
- **Trigger:** Triggered automatically when the confirmation window following a reminder elapses without patient action.
- **Description:** Automatically records a dose as missed when not confirmed within the reminder window. Extends Receive Reminder (UC5.3); System-triggered.
- **Pre-conditions:** A reminder (UC5.3) has been sent and the response window has elapsed.
- **Basic flow:**
  1. The system detects the window has elapsed with no confirmation.
  2. The system logs the dose as missed.
  3. System updates the adherence rate (UC5.5).

### UC5.5 View Adherence Rate
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered when the Patient opens the adherence view.
- **Description:** Displays the calculated percentage of doses taken on schedule.
- **Pre-conditions:** At least one reminder cycle has occurred.
- **Basic flow:**
  1. System computes adherence rate from confirmed vs. missed doses.
  2. The system displays the rate to the patient.
- **Exception:**
  -
  - E1: No dose history yet system displays an empty state.

### UC5.6 Receive Drug Interaction Alert
- **Actors:** System (secondary: Patient)
- **Trigger:** Triggered automatically when a newly added or edited medication is detected to interact with an existing entry.
- **Description:** Automated warning when a newly added medication conflicts with an existing entry on the patient's medication list. Extends Manage Personal Medication List (UC5.1); System-triggered.
- **Pre-conditions:** At least one existing medication entry exists (UC5.1).
- **Basic flow:**
  1. Patient adds or edits a medication entry.
  2. The system cross-checks the new entry against the existing medication list for known interactions.
  3. The system detects a conflicting interaction.
  4. The system displays a drug interaction warning to the patient.
- **Exception:**
  -
  - E1: Interaction severity is critical system blocks saving the entry until the patient acknowledges or removes the conflicting item.


## 3.4.6 Module 6 Health Records Management

### UC6.1 Upload & Categorise Document
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient uploads a file.
- **Description:** Upload a medical document and assign it a category; categorisation is a mandatory same-session step.
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. The patient selects a file to upload.
  2. The system uploads it to Firebase Storage.
  3. The patient assigns a category.
  4. The system saves the categorised record.
- **Exception:**
  -
  - E1: Unsupported file type system rejects the upload and lists supported formats.
  - E2: Upload fails (network) system retries and notifies the patient on repeated failure.

### UC6.2 Share Document with Doctor
- **Actors:** Patient (secondary: Doctor)
- **Trigger:** Triggered when the Patient chooses to share an existing document.
- **Description:** Voluntary, later decision to share a previously uploaded document with the assigned doctor. Extends Upload & Categorise Document (UC6.1).
- **Pre-conditions:** At least one document has been uploaded (UC6.1).
- **Basic flow:**
  1. The patient selects a document.
  2. The patient chooses to share with the Doctor.
  3. The system grants the assigned doctor access to the document.

### UC6.3 View Shared Records
- **Actors:** Doctor (secondary: None)
- **Trigger:** Triggered when the Doctor opens a patient's shared records.
- **Description:** Allows the doctor to view documents a patient has shared.
- **Pre-conditions:** At least one document has been shared (UC6.2).
- **Basic flow:**
  1. The doctor opens the patient's record.
  2. The system displays shared documents.
- **Exception:**
  -
  - E1: No documents shared system displays an empty state.


## 3.4.7 Module 7 Appointment Scheduling

### UC7.1 Book Appointment
- **Actors:** Patient (secondary: Admin)
- **Trigger:** Triggered when the Patient submits a booking request.
- **Description:** Schedules a new consultation between a patient and a doctor.
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. The patient selects a preferred date/time.
  2. The system checks doctor availability.
  3. System triggers Assign Doctor to Patient (UC7.3) if none is yet assigned.
  4. The system confirms the booking and triggers Receive Appointment Reminder (UC7.4) and View Pre-Visit Summary (UC7.5).
- **Alternative:**
  -
  - A1: Disease risk is High/Critical system proactively prompts the patient to book (per Module 9).
- **Exception:**
  -
  - E1: No slots available in the desired window system offers the nearest alternatives.

### UC7.2 Reschedule or Cancel Appointment
- **Actors:** Patient (secondary: Doctor)
- **Trigger:** Triggered when the Patient selects Reschedule or Cancel on an existing booking.
- **Description:** Patient-initiated, later modification of an existing booking. Extends Book Appointment (UC7.1).
- **Pre-conditions:** A booked appointment (UC7.1) exists.
- **Basic flow:**
  1. The patient selects an existing appointment.
  2. The patient chooses Reschedule (selects a new slot) or Cancel.
  3. The system updates the booking and notifies the doctor.
- **Exception:**
  -
  - E1: Cancellation attempted within a restricted window system warns the patient before confirming.

### UC7.3 Assign Doctor to Patient
- **Actors:** Admin (secondary: Patient)
- **Trigger:** Triggered when a booking requires a doctor assignment.
- **Description:** Admin assigns the attending doctor for a booking.
- **Pre-conditions:** A booking request exists without an assigned doctor.
- **Basic flow:**
  1. Admin reviews the booking.
  2. Admin selects an available doctor.
  3. The system links the doctor to the booking and the patient's care team.
- **Exception:**
  -
  - E1: No doctor available for the requested specialty/time system flags the booking for manual follow-up.

### UC7.4 Receive Appointment Reminder
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered at a configured interval before the appointment time.
- **Description:** Push/email reminder sent ahead of a scheduled appointment.
- **Pre-conditions:** A booked appointment exists (UC7.1).
- **Basic flow:**
  1. The system reaches the reminder interval.
  2. The system sends a push notification and email.

### UC7.5 View Pre-Visit Summary
- **Actors:** Doctor (secondary: System)
- **Trigger:** Generated automatically ahead of a scheduled appointment.
- **Description:** System-generated summary (recent vitals, risk scores, notes) the doctor reviews shortly before the visit.
- **Pre-conditions:** A booked appointment exists (UC7.1).
- **Basic flow:**
  1. The system compiles the patient's recent vitals, risk scores, and open items.
  2. The doctor opens the summary before the consultation.
- **Exception:**
  -
  - E1: Insufficient recent data system displays available history and flags data gaps.


## 3.4.8 Module 8 Healthcare Provider Portal

### UC8.1 View Assigned Patient List
- **Actors:** Doctor (secondary: None)
- **Trigger:** Triggered when the Doctor opens the portal.
- **Description:** Displays the list of patients assigned to the doctor.
- **Pre-conditions:** At least one patient is assigned to the doctor.
- **Basic flow:**
  1. The Doctor opens the portal.
  2. The system retrieves and displays the assigned patient list.
- **Exception:**
  -
  - E1: No patients assigned to the system display an empty state.

### UC8.2 Filter Patients by Risk Level
- **Actors:** Doctor (secondary: None)
- **Trigger:** Triggered when the Doctor applies a risk-level filter.
- **Description:** Optional refinement of the patient list by ML-predicted risk category. Extends View Assigned Patient List (UC8.1).
- **Pre-conditions:** The assigned patient list (UC8.1) is displayed.
- **Basic flow:**
  1. The doctor selects one or more risk levels.
  2. The system filters the displayed list accordingly.
- **Alternative:**
  -
  - A1: Doctor clears the filter system restores the full list.

### UC8.3 View Patient Health History
- **Actors:** Doctor (secondary: None)
- **Trigger:** Triggered when the Doctor selects a patient from the list.
- **Description:** Displays full vitals, medication, and records history for one assigned patient.
- **Pre-conditions:** The patient is assigned to the doctor (UC7.3).
- **Basic flow:**
  1. The doctor selects a patient.
  2. The system retrieves and displays vitals, medications, and shared records.
- **Exception:**
  -
  - E1: Patient has no recorded history yet system displays an empty state.

### UC8.4 Write Clinical Note / Issue Prescription
- **Actors:** Doctor (secondary: Pharmacist)
- **Trigger:** Triggered when the Doctor chooses to add a note or issue a prescription.
- **Description:** Deliberate doctor action taken after reviewing a patient's history. Extends View Patient Health History (UC8.3).
- **Pre-conditions:** The doctor is viewing the patient's health history (UC8.3).
- **Basic flow:**
  1. Doctor selects Add Note or Issue Prescription.
  2. The doctor enters the note text or prescription details.
  3. The system saves the entry to the patient's record.
  4. If a prescription was issued, the system notifies the pharmacy.
- **Exception:**
  -
  - E1: Drug interaction detected against the patient's current medication list system warns before saving.

### UC8.5 Update Care Plan
- **Actors:** Doctor (secondary: Patient)
- **Trigger:** Triggered when the Doctor edits the care plan.
- **Description:** Edits the shared care plan visible to the full care team for a patient.
- **Pre-conditions:** The patient is assigned to the doctor.
- **Basic flow:**
  1. The doctor opens the care plan.
  2. Doctor edits it.
  3. The system saves and syncs the update to the patient's shared view (UC10.2).

### UC8.6 Receive Risk Alerts
- **Actors:** Doctor (secondary: System)
- **Trigger:** Triggered automatically by Module 9's escalation logic.
- **Description:** Notifies the doctor of ML-flagged risk changes for assigned patients.
- **Pre-conditions:** An assigned patient's risk score has escalated (Module 9).
- **Basic flow:**
  1. The system detects a risk escalation for an assigned patient.
  2. The system notifies the doctor via the portal.


## 3.4.9 Module 9 AI-Powered Health Monitoring

### UC9.1 Generate Risk Score
- **Actors:** System (secondary: Patient, Doctor)
- **Trigger:** Triggered automatically whenever a new vital reading or symptom-checker submission occurs.
- **Description:** ML inference (Random Forest/XGBoost) predicting patient risk across five complications (stroke, coronary artery disease, heart failure, chronic kidney disease, type 2 diabetes) from twelve input variables (Breiman, 2001; Chen & Guestrin, 2016).
- **Pre-conditions:** Sufficient input variables (vitals, lifestyle, medical history) are available.
- **Basic flow:**
  1. The system assembles the twelve input variables.
  2. The system runs the Random Forest and XGBoost models per complication.
  3. System selects the higher-AUC-ROC model's output per complication.
  4. The system categorises each result as Low, Moderate, High, or Critical.
  5. The system stores the scores and updates the Risk Score Card (UC2.4).
- **Exception:**
  -
  - E1: Missing input variables system uses the last known value where available and flags reduced confidence.

### UC9.2 Send Patient Alerts
- **Actors:** System (secondary: Patient)
- **Trigger:** Triggered automatically when a reading crosses a safe threshold, or a risk score reaches High/Critical.
- **Description:** Covers threshold alerts and consultation prompts. Extends Generate Risk Score (UC9.1); fires when a reading is abnormal or a risk score reaches High/Critical.
- **Pre-conditions:** A risk score or reading evaluation (UC9.1) has just been completed.
- **Basic flow:**
  1. System evaluates the new reading/score against thresholds.
  2. System categorises the alert (Mild/Moderate/Emergency threshold, or High/Critical risk).
  3. The system delivers the alert and, where applicable, a Book Appointment prompt (UC7.1) to the patient.

### UC9.3 Escalate to Doctor/Family
- **Actors:** System (secondary: Doctor, Family Member)
- **Trigger:** Triggered automatically when risk reaches Critical, or a 30-day worsening trend is detected.
- **Description:** Covers the 30-day deterioration alert, Critical-risk family emergency alert, and medication review flag. Extends Generate Risk Score (UC9.1); fires on Critical risk or a sustained worsening trend.
- **Pre-conditions:** A risk score history spanning at least 30 days exists, or the current score is Critical.
- **Basic flow:**
  1. System evaluates the risk trend and current level.
  2. System notifies the assigned doctor (UC8.6) if Critical or worsening.
  3. System triggers Send Emergency Alert to Family (UC15.2) if Critical.
  4. System raises a medication review flag on the doctor's dashboard if risk is rising significantly.


## 3.4.10 Module 10 Care Coordination and Messaging

### UC10.1 Send Secure Message
- **Actors:** Patient, Doctor (secondary: System)
- **Trigger:** Triggered when the actor sends a message.
- **Description:** End-to-end encrypted messaging between a patient and their assigned doctor.
- **Pre-conditions:** A doctor is assigned to the patient.
- **Basic flow:**
  1. The actor composes a message.
  2. The system encrypts and delivers it to the recipient.
  3. The system scans the message for high-risk keywords, triggering Escalate High-Risk Message (UC10.3) if matched.
- **Exception:**
  -
  - E1: Recipient not reachable (offline) message is queued and delivered on reconnect, with a push notification.

### UC10.2 View Shared Care Plan
- **Actors:** Patient, Doctor (secondary: None)
- **Trigger:** Triggered when the actor opens the care plan.
- **Description:** Shared view of the current care plan across the patient-doctor relationship.
- **Pre-conditions:** A care plan exists (UC8.5).
- **Basic flow:**
  1. The actor opens the care plan.
  2. The system displays the current, synced version.
- **Exception:**
  -
  - E1: No care plan created yet system displays an empty state.

### UC10.3 Escalate High-Risk Message
- **Actors:** System (secondary: Doctor)
- **Trigger:** Triggered automatically during message delivery when the NLP keyword scanner finds a match.
- **Description:** Automatically flags a message as urgent when a high-risk keyword (e.g. "chest pain") is detected. Extends Send Secure Message (UC10.1); System-triggered.
- **Pre-conditions:** A message (UC10.1) is being sent.
- **Basic flow:**
  1. The system scans the outgoing message text.
  2. The system matches one or more high-risk terms.
  3. The system flags the message as urgent and pushes an immediate notification to the assigned doctor.
- **Exception:**
  -
  - E1: False positive (high-risk term used in a non-urgent context) doctor reviews and dismisses the flag; no automatic correction is applied.


## 3.4.11 Module 11 Admin Panel

### UC11.1 Manage User Accounts
- **Actors:** Admin (secondary: None)
- **Trigger:** Triggered when the Admin opens account management.
- **Description:** View, edit, or deactivate user accounts across all roles.
- **Pre-conditions:** Admin is authenticated.
- **Basic flow:**
  1. Admin searches for or selects a user.
  2. Admin edits or deactivates the account.
  3. The system applies the change and logs it.
- **Exception:**
  -
  - E1: Attempt to deactivate the only remaining Admin system blocks the action.

### UC11.2 Assign/Reassign Patient to Doctor
- **Actors:** Admin (secondary: Patient, Doctor)
- **Trigger:** Triggered when the Admin reassigns a patient's care team.
- **Description:** Changes a patient's assigned doctor, independent of a specific booking.
- **Pre-conditions:** The patient has an existing account.
- **Basic flow:**
  1. Admin selects a patient.
  2. Admin selects a new doctor.
  3. The system updates the assignment and notifies both parties.

### UC11.3 View Audit Logs
- **Actors:** Admin (secondary: None)
- **Trigger:** Triggered when the Admin opens the audit log screen.
- **Description:** System-wide activity log review for compliance monitoring.
- **Pre-conditions:** Logged activity exists.
- **Basic flow:**
  1. Admin opens audit logs.
  2. System displays system-wide events, filterable by user/date/action.

### UC11.4 Oversee Delivery Orders
- **Actors:** Admin (secondary: Pharmacist)
- **Trigger:** Triggered when the Admin opens the delivery oversight screen.
- **Description:** Monitors medication delivery operations across all patients.
- **Pre-conditions:** At least one recurring medication order exists (Module 13).
- **Basic flow:**
  1. Admin opens delivery oversight.
  2. The system displays order/delivery statuses across patients.
- **Exception:**
  -
  - E1: Delivery integration (Grab API) unavailable system displays last known status with a stale-data warning.

### UC11.5 Export Hospital-Wide Report
- **Actors:** Admin (secondary: None)
- **Trigger:** Triggered when the Admin requests a report export.
- **Description:** Generates a PDF summary report across the hospital's patient population.
- **Pre-conditions:** Sufficient data exists for the requested reporting period.
- **Basic flow:**
  1. Admin selects report parameters (date range, scope).
  2. The system compiles the report.
  3. The system generates and offers the PDF for download.
- **Exception:**
  -
  - E1: No data in the selected range system notifies the admin instead of generating an empty report.


## 3.4.12 Module 12 Settings and Preferences

### UC12.1 Update Profile/Contact Info
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient edits settings.
- **Description:** Edits account-level contact details from the settings screen.
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. Patient opens Settings.
  2. Patient edits contact info.
  3. The system saves the update.
- **Exception:**
  -
  - E1: Invalid input system rejects the save and highlights the field.

### UC12.2 Update Health Profile
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient edits their health profile.
- **Description:** Edits the onboarding clinical/lifestyle data captured in UC1.4.
- **Pre-conditions:** Onboarding (UC1.4) has been completed.
- **Basic flow:**
  1. The patient opens the health profile section.
  2. The patient edits medical history or lifestyle fields.
  3. System saves the update and re-triggers Generate Risk Score (UC9.1) if relevant fields changed.

### UC12.3 Export Health Data
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient requests a data export, or automatically offered during account deletion.
- **Description:** Downloads a copy of the patient's own health data. Also included by Delete Account (UC12.4).
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. The patient requests an export.
  2. The system compiles the patient's data into a downloadable file.
  3. The system provides the file to the patient.
- **Exception:**
  -
  - E1: Export generation fails system notifies the patient and allows retry.

### UC12.4 Delete Account
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient requests account deletion.
- **Description:** Permanently removes the patient's account. Includes Export Health Data (UC12.3), which is always offered before deletion proceeds.
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. Patient requests account deletion.
  2. The system offers Export Health Data (UC12.3).
  3. Patient confirms deletion.
  4. System deactivates and schedules the account and associated data for removal.
- **Alternative:**
  -
  - A1: Patient declines the export and proceeds directly to deletion.
- **Exception:**
  -
  - E1: Patient has an active recurring prescription (Module 13) system warns that this will be cancelled before allowing deletion to proceed.


## 3.4.13 Module 13 Recurring Medication, Payment and Delivery

### UC13.1 Flag Patient as Recurring
- **Actors:** Doctor (secondary: Patient)
- **Trigger:** Triggered when the Doctor enables recurring status for a patient.
- **Description:** Marks a long-term chronic patient for the recurring prescription workflow.
- **Pre-conditions:** The doctor has issued a prescription for the patient (UC8.4).
- **Basic flow:**
  1. The doctor selects a patient's prescription.
  2. Doctor flags it as recurring.
  3. System schedules the monthly Confirm Monthly Order cycle (UC13.2).

### UC13.2 Confirm Monthly Order
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered automatically on the monthly cycle date.
- **Description:** Monthly confirmation prompt for a patient's recurring prescription.
- **Pre-conditions:** The patient is flagged as recurring (UC13.1).
- **Basic flow:**
  1. The system sends a monthly confirmation prompt.
  2. The patient confirms the order.
  3. System triggers Select Method & Pay (UC13.3).
- **Alternative:**
  -
  - A1: Patient skips this month's order system pauses the cycle until the next scheduled date.
- **Exception:**
  -
  - E1: Patient does not respond within the confirmation window system sends a follow-up reminder.

### UC13.3 Select Method & Pay
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered immediately after the patient confirms a monthly order.
- **Description:** Choice of self-collection or home delivery plus Stripe payment. Includes into Confirm Monthly Order (UC13.2); always required to confirm an order.
- **Pre-conditions:** The patient has confirmed the monthly order (UC13.2).
- **Basic flow:**
  1. The patient selects self-collection or home delivery.
  2. Patient completes payment via Stripe.
  3. The system confirms payment and notifies the pharmacist to prepare the order (UC13.6).
  4. If home delivery was selected, the system triggers Dispatch Delivery (UC13.4).
- **Exception:**
  -
  - E1: Payment declined system notifies the patient and allows retry with an alternate method.

### UC13.4 Dispatch Delivery
- **Actors:** System (secondary: Patient)
- **Trigger:** Triggered automatically once the pharmacist marks the order Ready for Delivery.
- **Description:** Grab API dispatch of the prepared medication. Extends Select Method & Pay (UC13.3); fires only when home delivery is chosen.
- **Pre-conditions:** Home delivery was selected (UC13.3) and the order is ready.
- **Basic flow:**
  1. The system dispatches the order via the Grab API.
  2. The system notifies the patient the delivery is in progress.
  3. System triggers Track Delivery Status (UC13.5).
- **Exception:**
  -
  - E1: Grab API dispatch fails system retries and, if unsuccessful, prompts the patient to switch to self-collection.

### UC13.5 Track Delivery Status
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered when the Patient opens delivery tracking, available after dispatch.
- **Description:** Real-time delivery tracking, available once a delivery has been dispatched. Extends Dispatch Delivery (UC13.4).
- **Pre-conditions:** A delivery has been dispatched (UC13.4).
- **Basic flow:**
  1. Patient opens delivery tracking.
  2. System displays live status updates from the Grab API.
- **Exception:**
  -
  - E1: Delivery fails en route system notifies the patient and offers to reschedule or switch to self-collection.

### UC13.6 Prepare Medication
- **Actors:** Pharmacist (secondary: System)
- **Trigger:** Triggered automatically once payment is confirmed (UC13.3).
- **Description:** The pharmacist prepares the medication order after payment confirmation.
- **Pre-conditions:** Payment has been confirmed for an order.
- **Basic flow:**
  1. The system notifies the pharmacist of a new order.
  2. The pharmacist prepares the medication.
  3. Pharmacists mark the order Ready for Collection or Ready for Delivery.
- **Exception:**
  -
  - E1: Medication out of stock pharmacist flags the shortage to the Admin (UC11.4) and notifies the patient of a delay.


## 3.4.14 Symptom Checker and Triage

### UC14.1 Complete Symptom Checker
- **Actors:** Patient (secondary: None)
- **Trigger:** Triggered when the Patient opens the Symptom Checker.
- **Description:** The patient selects symptoms from a structured hypertension-related list and rates severity.
- **Pre-conditions:** The patient is authenticated.
- **Basic flow:**
  1. The patient opens the Symptom Checker.
  2. The system triggers Capture Heart Rate via PPG (UC14.2).
  3. The patient selects symptoms and rates severity (Mild/Moderate/Severe).
  4. The patient submits the checker.
  5. System triggers Generate Triage Outcome (UC14.3).
- **Exception:**
  -
  - E1: PPG capture fails system proceeds using symptoms, current BP, and last known risk score only, noting the missing heart rate input.

### UC14.2 Capture Heart Rate via PPG
- **Actors:** Patient (secondary: System)
- **Trigger:** Triggered automatically when the Symptom Checker opens.
- **Description:** Mandatory heart-rate capture on opening the checker. Includes into Complete Symptom Checker (UC14.1).
- **Pre-conditions:** None (same procedure as UC3.3).
- **Basic flow:**
  1. The system prompts the patient to place a finger over the camera.
  2. The system captures and computes heart rate (as per UC3.3).
- **Exception:**
  -
  - E1: Poor signal system allows the patient to retry or skip.

### UC14.3 Generate Triage Outcome
- **Actors:** System (secondary: Patient)
- **Trigger:** Triggered automatically upon symptom checker submission.
- **Description:** Cross-references symptoms, severity, current BP, heart rate, and ML risk score into a triage result: Monitor at Home, Contact Your Doctor, or Seek Emergency Care. Included into Complete Symptom Checker (UC14.1); performed by System.
- **Pre-conditions:** Symptom checker (UC14.1) has been submitted.
- **Basic flow:**
  1. System retrieves current BP, heart rate, and latest ML risk score.
  2. System cross-references these against the reported symptoms and severity.
  3. System classifies the outcome (Mild/Moderate/Emergency per the defined BP and symptom thresholds).
  4. The system saves the outcome to the patient's health record.
  5. The system triggers Notify Doctor (UC14.4) if the outcome is Moderate or Emergency.

### UC14.4 Notify Doctor
- **Actors:** System (secondary: Doctor)
- **Trigger:** Triggered automatically when the triage outcome is Moderate or Emergency.
- **Description:** Automatic doctor notification. Extends Generate Triage Outcome (UC14.3); fires only when the outcome is Moderate or Emergency.
- **Pre-conditions:** A triage outcome of Moderate or Emergency has just been generated.
- **Basic flow:**
  1. The system composes an urgent notification with the patient's vitals, symptoms, and risk scores.
  2. The system sends it to the assigned doctor.
  3. In an emergency, the system additionally triggers emergency appointment booking, family alert (UC15.2), and reassigns to the next available doctor if the assigned one is unavailable.


## 3.4.15 Family Monitoring and Emergency Alert

### UC15.1 View Patient Vitals
- **Actors:** Family Member (secondary: None)
- **Trigger:** Triggered when the Family Member opens the monitoring view.
- **Description:** Real-time view of the linked patient's readings and health status.
- **Pre-conditions:** The Family Member account is linked to a patient profile.
- **Basic flow:**
  1. Family Member opens the app.
  2. The system displays the linked patient's current vitals and status.
- **Exception:**
  -
  - E1: Patient has not granted/linked access system displays a pending-link state.

### UC15.2 Send Emergency Alert to Family
- **Actors:** System (secondary: Family Member)
- **Trigger:** Triggered automatically by Escalate to Doctor/Family (UC9.3) or Notify Doctor (UC14.4) when risk is Critical.
- **Description:** Automated notification to linked family members when the patient's risk reaches Critical.
- **Pre-conditions:** At least one family member is linked to the patient.
- **Basic flow:**
  1. The system detects a Critical risk event.
  2. The system sends an emergency alert with the patient's live GPS location to all linked family members.
- **Exception:**
  -
  - E1: No family member linked, system logs the event and relies solely on doctor/emergency escalation.

### UC15.3 Enable GPS Tracking & Emergency Call
- **Actors:** Family Member (secondary: System)
- **Trigger:** Triggered automatically as soon as the family member receives an emergency alert.
- **Description:** GPS tracking and one-tap emergency call, available only after an emergency alert has been received. Extends Send Emergency Alert to Family (UC15.2).
- **Pre-conditions:** An emergency alert (UC15.2) has just been received.
- **Basic flow:**
  1. The system unlocks live GPS tracking and the one-tap emergency call button on the family member's view.
  2. Family Members may track the patient's location.
  3. Family Members may use the one-tap button to call emergency services or the patient directly.
