# 07 — UI Screens

Source: Ch4 §4.3 (41 mockups generated with Google Stitch) and §4.1.2 sitemap (`figures/ch4-figure-4-1-2-sitemap-*.png`). **Open each mockup image before building the screen**, and match its layout, content and states. Use the descriptions below (verbatim from the report) as acceptance criteria.

## Visual system

- Clean clinical style. Use the BP category colours from `06-algorithms-and-flows.md` §E for all BP/risk badges. Use red for emergency surfaces only.
- Define one Material 3 theme (light + dark; dark mode was a liked feature in the survey) in `core/theme/`, shared by all three entrypoints.
- Keep the mockups' **consistent** elements and resolve their **inconsistencies**: the Stitch-generated screens have an inconsistent bottom tab bar on the messaging screens and inconsistent chat bubble colours. Use the app-wide tab bar and theme colours (patient bubbles right-aligned in primary colour, doctor bubbles left-aligned in surface colour).
- Accessibility (NFR-3.1): minimum 48 dp touch targets, text scale support, sufficient contrast, semantic labels.
- Every list or chart screen needs **loading, empty, and error** states. The report explicitly designs empty states for vitals and trends.

## Known differences between mockups and the agreed design (follow the agreed design)

- **4.3.1.1 Login** shows a role selector (Patient/Doctor/Admin) and biometrics. Agreed design: the Patient and Family apps have **no role selector**, because staff sign in only through the Staff Portal login (4.3.14.8). Biometric unlock is optional (local_auth) and only after a first password login. See D-05b.
- **4.3.14.8 Staff Portal Login** shows a role selector and SSO. The role comes from the custom claim; the selector is cosmetic and must match the claim, otherwise show an error. SSO is out of scope; hide the button.
- Staff portal mockups are shown under a single "Lead Administrator" account. Real RBAC keeps Doctor / Pharmacist / Admin separate (FR-1.3).
- **4.3.4.1 Health Trends** shows 7d/30d/3m. FR-4.1 requires **7d / 30d / 3m / 1y**, so add 1y. Also add the "compare multiple vitals" overlay (UC4.3).
- **Sitemap gaps:** the Doctor Portal sitemap omits Appointment Calendar and Prescription Management. Mockups exist (4.3.12.3, 4.3.12.7), so build them.
- **Link-to-Patient pending approval:** the family side shows a pending state after entering the code. The patient side needs a screen to approve or reject requests (`/family-requests`, not mocked; follow the app style).
- **Emergency Alert (4.3.16.3):** show the location as a Google Map **and** a reverse-geocoded address line.
- Not mocked but required by the FRs, so build them in the same style: register, onboarding form steps, records upload/list (M6), pre-visit summary (FR-7.4), care plan view/editor (FR-8.3 / FR-10.2), adherence view (UC5.5), data export + delete flow (UC12.3/12.4), collection slip (FR-13.4).
This section presents the user interface design of the Hypertension Care Management Platform's Patient Mobile App, built in Flutter. Screens are organised by module, following the same structure used throughout this chapter, and each is captioned with its figure number and a short description of its purpose and the requirements it satisfies.

## 4.3.1 Shared Authentication and Onboarding Interfaces

### 4.3.1.1 Login Interface
- Route: patient/family `/login`
- Mockup: `figures/ch4-figure-4-3-1-1-login-interface.png`
- This interface allows a registered user to sign in with their email and password, or authenticate using device biometrics. A role selector (Patient, Doctor, Admin) determines which portal experience the user is directed to after signing in, and a link is provided for new patients to register (FR-1.1, FR-1.2).

### 4.3.1.2 Onboarding Complete Interface
- Route: patient `/onboard` (done state)
- Mockup: `figures/ch4-figure-4-3-1-2-onboarding-complete-interface.png`
- This confirmation screen appears immediately after a patient completes the one-time onboarding health profile (personal information, medical history, and lifestyle factors). It confirms the profile has been saved and redirects the patient to their dashboard (UC1.4).

## 4.3.2 Patient Dashboard Interface

### 4.3.2.1 Home Dashboard Interface
- Route: patient `/dashboard`
- Mockup: `figures/ch4-figure-4-3-2-1-home-dashboard-interface.png`
- This is the patient's landing screen after login, summarising the day's medication schedule, next appointment, latest blood pressure reading, and current AI-generated risk assessment in one view. Quick-access shortcuts let the patient jump directly to logging vitals, the symptom checker, messaging, or the AI health agent (FR-2.1, FR-2.2).

## 4.3.3 Vital Signs Tracking Interfaces

### 4.3.3.1 Vitals Tracking Interface (Empty State)
- Route: patient `/vitals` (empty)
- Mockup: `figures/ch4-figure-4-3-3-1-vitals-tracking-interface-empty-state.png`
- Shown to a patient who has not yet logged any readings, this state replaces charts and summaries with a prompt to log a first reading and explains that the AI risk assessment unlocks once at least three readings are recorded. Designing an explicit empty state avoids showing blank or misleading charts before real data exists.

### 4.3.3.2 Log Vitals Interface
- Route: patient `/vitals/log`
- Mockup: `figures/ch4-figure-4-3-3-2-log-vitals-interface.png`
- This screen lets the patient log a blood pressure reading manually by entering systolic and diastolic values, or measure heart rate by placing a fingertip over the rear camera for a PPG-based capture. Both paths feed the same vitals record used for trend charts and risk scoring (FR-3.1, FR-3.2, UC3.3).

### 4.3.3.3 Reading Saved Interface
- Route: patient `/vitals/log` (saved)
- Mockup: `figures/ch4-figure-4-3-3-3-reading-saved-interface.png`
- After a reading is logged, the patient sees an immediate summary confirming the value is within normal range alongside their resting heart rate, reinforcing that the entry was saved successfully. A short encouragement message supports consistent logging habits.

## 4.3.4 Health Data Visualisation Interfaces

### 4.3.4.1 Health Trends Interface
- Route: patient `/trends`
- Mockup: `figures/ch4-figure-4-3-4-1-health-trends-interface.png`
- This screen visualises the patient's blood pressure history as a line chart across selectable time windows (7 days, 30 days, 3 months), with average, minimum, and maximum statistics shown below it. A cardiovascular risk score card at the bottom shows the current risk percentage and recent trend direction (FR-4.1, FR-4.2, FR-4.3).

### 4.3.4.2 Weekly Trends Interface (Empty State)
- Route: patient `/trends` (empty)
- Mockup: `figures/ch4-figure-4-3-4-2-weekly-trends-interface-empty-state.png`
- This is the equivalent empty state for the trends view, shown before enough readings exist to plot a meaningful chart. It prompts the patient to log at least three readings and shows placeholder cards for average heart rate, average blood pressure, and risk score until real data is available.

## 4.3.5 Medication Management Interface

### 4.3.5.1 Medications Interface
- Route: patient `/medications`
- Mockup: `figures/ch4-figure-4-3-5-1-medications-interface.png`
- This screen lists the patient's medications grouped by time of day (morning, evening, as-needed), showing which doses have already been taken and which are still upcoming. A refill alert is surfaced when a medication is running low, with a direct action to request a refill from the pharmacy (FR-5.1, FR-5.2, FR-5.4).

## 4.3.6 Appointment Scheduling Interfaces

### 4.3.6.1 Appointments Interface
- Route: patient `/appointments`
- Mockup: `figures/ch4-figure-4-3-6-1-appointments-interface.png`
- This screen shows the patient's next upcoming appointment with a link to its pre-visit summary, alongside a calendar and time-slot picker for booking a new appointment with their assigned doctor (FR-7.1, FR-7.4).

### 4.3.6.2 Booking Confirmed Interface
- Route: patient `/appointments/book` (confirmed)
- Mockup: `figures/ch4-figure-4-3-6-2-booking-confirmed-interface.png`
- After booking, this screen confirms the appointment's doctor, date, time, and location, and gives the patient the option to reschedule or cancel. It also surfaces pre-visit tasks such as reviewing the pre-visit summary and completing an intake form before arrival.

## 4.3.7 AI Health Agent Interface

### 4.3.7.1 AI Health Agent Chat Interface
- Route: patient `/ai-agent`
- Mockup: `figures/ch4-figure-4-3-7-1-ai-health-agent-chat-interface.png`
- This conversational interface lets the patient ask the AI Health Agent questions about their health status in plain language. In this example, the agent proactively raises a recent elevated blood pressure reading, asks about symptoms, and offers a quick-book option for a telehealth check-in, with an emergency escalation notice shown in case symptoms worsen (FR-14.1).

## 4.3.8 Symptom Checker and Triage Interfaces

### 4.3.8.1 Symptom Selection Interface
- Route: patient `/symptom`
- Mockup: `figures/ch4-figure-4-3-8-1-symptom-selection-interface.png`
- This is the entry point to the symptom checker, where the patient selects from a predefined list of common symptoms and rates overall severity (mild, moderate, severe) before continuing (UC14.1).

### 4.3.8.2 Triage Result Interface
- Route: patient `/symptom/result/:id`
- Mockup: `figures/ch4-figure-4-3-8-2-triage-result-interface.png`
- Based on the selected symptoms, severity, and the patient's current vitals and risk score, this screen displays the resulting triage outcome in this case Seek Emergency Care along with the reported critical symptoms and a numbered list of immediate actions. Direct-call and vitals-sharing actions are provided for the most urgent outcome level (FR-14.3).

## 4.3.9 Family Monitoring and Emergency Alert Interface

### 4.3.9.1 Emergency SOS Interface
- Route: patient `/sos`
- Mockup: `figures/ch4-figure-4-3-9-1-emergency-sos-interface.png`
- This screen gives the patient one-tap access to call emergency services, view the nearest hospital, share live vitals with the ER, and notify their linked family members, all from a single high-visibility screen reserved for genuine emergencies (FR-14.2).

## 4.3.10 Recurring Medication, Payment and Delivery Interfaces

### 4.3.10.1 Order Confirmation Interface
- Route: patient `/orders/:id/confirm`
- Mockup: `figures/ch4-figure-4-3-10-1-order-confirmation-interface.png`
- This screen presents the monthly recurring medication order for review itemised cost and insurance coverage before the patient selects a fulfilment method of self-collection or home delivery (FR-13.2, FR-13.4).

### 4.3.10.2 Secure Payment Interface
- Route: patient `/orders/:id/pay`
- Mockup: `figures/ch4-figure-4-3-10-2-secure-payment-interface.png`
- This screen collects payment for the confirmed order using a saved card or a newly added payment method, processed through Stripe, with the order summary and total shown alongside a reminder that payment details are encrypted (FR-13.3).

### 4.3.10.3 Delivery Tracking Interface
- Route: patient `/orders/:id/track`
- Mockup: `figures/ch4-figure-4-3-10-3-delivery-tracking-interface.png`
- This screen shows the real-time status of a home-delivery order against a four-stage timeline (Order Confirmed, Preparing, Out for Delivery, Delivered) along with an estimated arrival time, updating as each Grab delivery status event is received (FR-13.4).

## 4.3.11 Settings and Preferences Interface

### 4.3.11.1 Settings Interface
- Route: patient `/settings`
- Mockup: `figures/ch4-figure-4-3-11-1-settings-interface.png`
- This screen lets the patient manage their profile (personal information, contact details, health profile), toggle push notification preferences, review data and privacy settings, and sign out or permanently delete their account (FR-12.1, FR-12.2, UC12.4).
- The remaining interfaces cover the Web Portal used by Doctor, Pharmacist, and Admin accounts. In the prototype these are demonstrated under a single “Lead Administrator” account for convenience, but the platform's actual role-based access control (FR-1.3) keeps these as three separate account types, each restricted to their own functions.

## 4.3.12 Doctor Portal Interfaces

### 4.3.12.1 Doctor Dashboard Interface
- Route: staff `/doctor`
- Mockup: `figures/ch4-figure-4-3-12-1-doctor-dashboard-interface.png`
- This is the doctor's landing screen, listing all assigned patients sorted by risk level with their latest blood pressure reading and last update time, alongside summary counts for total, high-risk, and elevated-risk patients. A priority alerts panel on the right surfaces the most urgent events BP spikes, missed medication, and AI-detected trends for immediate review (FR-8.1, FR-8.4).

### 4.3.12.2 Doctor Dashboard Interface (Critical Alert Active)
- Route: staff `/doctor` (critical banner)
- Mockup: `figures/ch4-figure-4-3-12-2-doctor-dashboard-interface-critical-alert-active.png`
- This is the same dashboard shown with an active Critical-level alert: two consecutive readings above 180/110 combined with poor medication adherence trigger a red banner requiring the doctor to either intervene immediately or dismiss it. A population-level systolic trend chart below tracks controlled versus uncontrolled patients over the past 30 days (FR-8.4, FR-9.5).

### 4.3.12.3 Doctor Schedule Interface
- Route: staff `/doctor/schedule`
- Mockup: `figures/ch4-figure-4-3-12-3-doctor-schedule-interface.png`
- This calendar view shows the doctor's scheduled appointments across monthly, weekly, and daily layouts, colour-coded by type (regular checkup, emergency, follow-up), giving a full view of upcoming consultations without opening each patient record individually (FR-7.1).

### 4.3.12.4 Patient Detail Interface
- Route: staff `/doctor/patient/:id`
- Mockup: `figures/ch4-figure-4-3-12-4-patient-detail-interface.png`
- This screen presents a patient's complete clinical picture in one place: demographics, current hypertension risk score with contributing factors, a blood pressure trend chart, recent lab results, active medications, and a clinical notes panel. Tabs let the doctor switch between vitals and labs, medications, care plan, and past clinical notes without leaving the page (FR-8.2, FR-8.3).

### 4.3.12.5 Consultation Notes Interface
- Route: staff `/doctor/patient/:id/notes`
- Mockup: `figures/ch4-figure-4-3-12-5-consultation-notes-interface.png`
- This screen lets the doctor write a new clinical note against a patient's record, with smart templates (SOAP Note, Hypertension Follow-up, Medication Adjustment) to speed up documentation, alongside a summary of the patient's latest vitals and active risk factors for reference while writing (FR-8.3).

### 4.3.12.6 Note Saved Interface
- Route: staff `/doctor/patient/:id/notes` (saved)
- Mockup: `figures/ch4-figure-4-3-12-6-note-saved-interface.png`
- This screen confirms a clinical note has been saved successfully via a toast notification, shown alongside the patient's risk level, care protocol, and latest BP trend, with prior notes listed chronologically below the new entry (FR-8.3).

### 4.3.12.7 Prescription Management Interface
- Route: staff `/doctor/patient/:id/prescriptions`
- Mockup: `figures/ch4-figure-4-3-12-7-prescription-management-interface.png`
- This screen lets the doctor issue a new prescription, showing the patient's current medication regimen and relevant clinical notes for context alongside a form for medication name, dosage, frequency, and duration. A toggle marks the prescription as recurring for a chronic condition, which automatically generates monthly renewal requests (FR-8.3, UC13.1).

## 4.3.13 Pharmacist Portal Interface

### 4.3.13.1 Pharmacist View Interface
- Route: staff `/pharmacy`
- Mockup: `figures/ch4-figure-4-3-13-1-pharmacist-view-interface.png`
- This is the pharmacist's working screen, listing the active prescription queue with each order's status (preparing, ready for delivery, ready for collection) alongside current medication inventory levels and expiry dates. A patient lookup panel and quick actions for logging new stock, reporting issues, and dispatching a Grab delivery batch support the day-to-day fulfilment workflow (FR-13.3, FR-13.4).

## 4.3.14 Admin Portal Interfaces

### 4.3.14.1 User Management Interface
- Route: staff `/admin/users`
- Mockup: `figures/ch4-figure-4-3-14-1-user-management-interface.png`
- This screen lists every system user with their role, account status, and join date, and lets the admin add new staff accounts, filter by role, or deactivate an existing account. This is where Doctor, Pharmacist, and Admin accounts are provisioned, since these roles cannot self-register (FR-1.6, FR-11.1).

### 4.3.14.2 Patient Assignments Interface
- Route: staff `/admin/assignments`
- Mockup: `figures/ch4-figure-4-3-14-2-patient-assignments-interface.png`
- This screen shows unassigned patients alongside each doctor's current caseload and availability, letting the admin manually assign a patient to a doctor or use auto-assign to distribute the workload automatically (FR-11.2, UC7.3).

### 4.3.14.3 Audit Logs Interface
- Route: staff `/admin/audit-logs`
- Mockup: `figures/ch4-figure-4-3-14-3-audit-logs-interface.png`
- This screen provides a searchable, filterable log of system activity user actions, failed logins, privilege escalations, and data exports with each entry showing the acting user, action taken, affected module, and timestamp. Logs can be exported to CSV for compliance review (FR-1.5, FR-11.3).

### 4.3.14.4 Delivery Oversight Interface
- Route: staff `/admin/deliveries`
- Mockup: `figures/ch4-figure-4-3-14-4-delivery-oversight-interface.png`
- This screen gives the admin platform-wide visibility into medication delivery dispatches across all pharmacies, with live status, assigned courier, and ETA for each order, plus the ability to manually dispatch an order if needed (FR-11.4, FR-13.4).

### 4.3.14.5 Hospital Analytics Interface
- Route: staff `/admin/analytics/hospital`
- Mockup: `figures/ch4-figure-4-3-14-5-hospital-analytics-interface.png`
- This screen aggregates clinical outcome metrics across all active patients risk distribution, consultation volume trends, medication adherence, and delivery success rate supporting the admin's hospital-wide reporting function (FR-11.4).

### 4.3.14.6 System Analytics Interface
- Route: staff `/admin/analytics/system`
- Mockup: `figures/ch4-figure-4-3-14-6-system-analytics-interface.png`
- This screen tracks platform usage and engagement of active clinicians, system uptime, messages sent, and usage by clinical departments giving the admin insight into how the platform is being adopted across the organisation (FR-11.3).

### 4.3.14.7 System Health Interface
- Route: staff `/admin/system-health`
- Mockup: `figures/ch4-figure-4-3-14-7-system-health-interface.png`
- This screen monitors the technical health of each backend service: the API, database, ML risk model, Grab delivery integration, Stripe payments, and notification service showing uptime and latency per service so degraded components, such as the ML model shown here, can be identified quickly (FR-11.3).

### 4.3.14.8 Staff Portal Login Interface
- Route: staff `/login`
- Mockup: `figures/ch4-figure-4-3-14-8-staff-portal-login-interface.png`
- This interface is the sign-in entry point for Doctor, Pharmacist, and Admin accounts on the Web Portal, kept separate from the Patient/Family mobile login shown in Figure 4.3.1.1. A role selector (Doctor, Admin, Pharmacist) determines which portal view loads after authentication, alongside an SSO option for institutional sign-in (FR-1.1, FR-1.2, FR-1.3).

## 4.3.15 Secure Messaging Interfaces

### 4.3.15.1 Message Inbox Interface
- Route: patient `/chat` · staff `/doctor/messages`
- Mockup: `figures/ch4-figure-4-3-15-1-message-inbox-interface.png`
- This screen lists the patient's message threads with their care team, showing each sender's name, role, a preview of the latest message, timestamp, and an unread-count badge, with a search bar to locate a specific conversation (UC10.1).

### 4.3.15.2 Chat Thread Interface
- Route: patient `/chat/:threadId`
- Mockup: `figures/ch4-figure-4-3-15-2-chat-thread-interface.png`
- This screen shows a full conversation thread with a single doctor, with the patient's own messages right-aligned and the doctor's replies left-aligned. Messages are end-to-end encrypted before being written to Firestore, indicated by the lock icon above the compose bar (NFR-2.1).

### 4.3.15.3 Flagged Message Interface
- Route: patient `/chat/:threadId` (flagged)
- Mockup: `figures/ch4-figure-4-3-15-3-flagged-message-interface.png`
- This is the same chat thread shown after the NLP scanner detects a high-risk keyword in the patient's message. A red banner confirms the care team has been notified and, for urgent language, prompts the patient to call 911 or go to the nearest emergency room (UC10.3).

## 4.3.16 Family Member App Interfaces
- The remaining interfaces cover the Family Member mobile app, the third client surface defined in the Sitemap (Figure 4.1.2). This is a separate app build from the Patient Mobile App, reflecting the read-only, monitoring-only nature of the family member role.

### 4.3.16.1 Link to Patient Interface
- Route: family `/link`
- Mockup: `figures/ch4-figure-4-3-16-1-link-to-patient-interface.png`
- This screen lets a family member enter the unique link code shared by a patient to request monitoring access. The request remains pending until the patient approves it from their own CareFlow app, consistent with the requestLink/linkPending flow in Figure 4.1.1.15 (UC15.1).

### 4.3.16.2 Family Dashboard Interface
- Route: family `/home`
- Mockup: `figures/ch4-figure-4-3-16-2-family-dashboard-interface.png`
- This is the family member's read-only view of a linked patient's health status: current risk level, today's blood pressure and heart rate readings, and a 7-day trend summary. No logging or edit actions are available from this screen, consistent with the family member's monitoring-only role (FR-14.2).

### 4.3.16.3 Emergency Alert Interface
- Route: family `/alert/:alertId`
- Mockup: `figures/ch4-figure-4-3-16-3-emergency-alert-interface.png`
- This screen renders when a linked patient's risk reaches Critical level, surfacing the triggering reading, the patient's last known location, and one-tap actions to call the patient or acknowledge the alert (FR-14.2, Figure 4.1.1.15).