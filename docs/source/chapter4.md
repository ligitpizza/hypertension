Chapter 4

# System Analysis and Design

##  

**Chapter 4 System Analysis and Design**

## 4.1 System Design

### 4.1.1 Sequence Diagram

Each module's sequence diagram follows Boundary-Control-Entity notation: actor icons for human participants, boundary objects (:XxxUI) for the presentation layer, control objects (:XxxCtrl) for application logic, and entity objects (instance:Type) for persisted data, with activation bars showing exactly when each object is processing. Every diagram traces directly to its corresponding Chapter 3 activity diagram and use case.

4.1.1.1 User Management (Register Account) Sequence Diagram


*Figure 4.1.1.1: User Management (Register Account) Sequence Diagram*

4.1.1.2 View Health Summary Dashboard Sequence Diagram


*Figure 4.1.1.2: View Health Summary Dashboard Sequence Diagram*

4.1.1.3 Log Blood Pressure Reading Sequence Diagram


*Figure 4.1.1.3: Log Blood Pressure Reading Sequence Diagram*

4.1.1.4 View BP Trend & Compare Vitals Sequence Diagram


*Figure 4.1.1.4: View BP Trend & Compare Vitals Sequence Diagram*

4.1.1.5 Manage Medication List Sequence Diagram


*Figure 4.1.1.5: Manage Medication List Sequence Diagram*

4.1.1.6 Upload & Share Health Record Sequence Diagram


*Figure 4.1.1.6: Upload & Share Health Record Sequence Diagram*

4.1.1.7 Book & Reschedule Appointment Sequence Diagram


*Figure 4.1.1.7: Book & Reschedule Appointment Sequence Diagram*

4.1.1.8 Review Patient & Write Note Sequence Diagram


*Figure 4.1.1.8: Review Patient & Write Note Sequence Diagram*

4.1.1.9 Generate Risk Score & Escalate Sequence Diagram


*Figure 4.1.1.9: Generate Risk Score & Escalate Sequence Diagram*

4.1.1.10 Send Secure Message & Escalate Sequence Diagram


*Figure 4.1.1.10: Send Secure Message & Escalate Sequence Diagram*

4.1.1.11 Admin Account & Oversight Flow Sequence Diagram


*Figure 4.1.1.11: Admin Account & Oversight Flow Sequence Diagram*

4.1.1.12 Update Profile, Export & Delete Sequence Diagram


*Figure 4.1.1.12: Update Profile, Export & Delete Sequence Diagram*

4.1.1.13 Confirm Order, Pay & Dispatch Sequence Diagram


*Figure 4.1.1.13: Confirm Order, Pay & Dispatch Sequence Diagram*

4.1.1.14 Symptom Checker & Triage (FR-14.3) Sequence Diagram


*Figure 4.1.1.14: Symptom Checker & Triage (FR-14.3) Sequence Diagram*

4.1.1.15 Family Monitoring & Emergency Alert Response (FR-14.2) Sequence Diagram


*Figure 4.1.1.15: Family Monitoring & Emergency Alert Response (FR-14.2) Sequence Diagram*

Figure 4.1.1.16 AI Health Agent (FR-14.1) Sequence Diagram


*Figure 4.1.1.16: AI Health Agent(FR-14.1) Sequence Diagram*

### 4.1.2 Sitemap

The sitemap covers all screens across the three client surfaces, grouped by platform (colour-coded banner) and then by functional category within each platform. Where a screen has more than one meaningful end state (e.g. a save succeeding vs. a validation error), both states are shown as branches beneath it.


Figure 4.1.2: Sitemap – Hypertension Care Management Platform

## 4.2 Database Design

### 4.2.1 Class Diagram

The class diagram models the software/domain layer: a User base class with five role subtypes (Patient, Doctor, Pharmacist, Admin, Family Member), the health-data entities each patient owns, and the shared clinical-coordination entities linking patients and doctors. Composition (filled diamond) marks data that is deleted along with the owning record; aggregation (hollow diamond) marks data that should outlive its parent for audit/history purposes; plain associations carry explicit UML multiplicities at both ends.


Figure 4.2.1: Class Diagram – Hypertension Care Management Platform

### 4.2.2 ERD Diagram

The ERD documents the corresponding relational design: primary keys are underlined, foreign keys are marked with their referenced table, and every relationship uses crow's-foot notation for cardinality (one / zero-or-one / many). This is the logical design that Section 4.2.3's Firestore data dictionary is derived from, with the two documented departures (role-specific fields merged into users; small bounded lists embedded rather than split into child collections) explained there.


Figure 4.2.2: ERD – Hypertension Care Management Platform

### 4.2.3 Data Dictionary

The platform uses Cloud Firestore, a document-oriented database, so the schema below is expressed as collections rather than relational tables. Relationships that would be foreign keys in a relational design are implemented as reference fields (e.g. patientId referencing the users collection). Where a Firestore document benefits from denormalisation for read performance or because a list is small and bounded, the field is embedded directly (e.g. a triage submission's symptoms array, or the five per-complication results embedded in one risk_scores document) rather than stored in a separate collection; these cases are noted under "Constraints / Notes" in each table.

This also means the users collection carries role-specific fields directly (e.g. dateOfBirth only applies when role = patient) rather than the separate PatientProfile / DoctorProfile / FamilyMemberProfile extension tables shown in the relational ERD (Section 4.2.2). Both are correct for their purpose: the ERD documents the logical relational design, while this dictionary documents the actual physical Firestore schema, which favours a single flexible-schema document over multiple small joined ones.

Table 4.2.3.1 Collection: users

| Field              | Type              | Description                                           | Constraints / Notes                                                             |
|--------------------|-------------------|-------------------------------------------------------|---------------------------------------------------------------------------------|
| \_id               | String            | Primary key (Firebase Auth UID)                       | Auto-generated                                                                  |
| email              | String            | Login email                                           | Required, unique                                                                |
| name               | String            | Full name                                             | Required                                                                        |
| role               | String            | patient / doctor / pharmacist / admin / family_member | Required                                                                        |
| isActive           | Boolean           | Whether the account is active                         | Default: true                                                                   |
| createdAt          | Timestamp         | Account creation time                                 | Auto-set                                                                        |
| updatedAt          | Timestamp         | Last profile update time                              | Auto-set on write                                                               |
| dateOfBirth        | Date              | Patient's date of birth                               | Present only when role = patient                                                |
| gender             | String            | Patient's gender                                      | Present only when role = patient                                                |
| onboardingComplete | Boolean           | Whether the onboarding health profile is complete     | Present only when role = patient; default false                                 |
| assignedDoctorId   | Reference (users) | Currently assigned doctor                             | Present only when role = patient; null until UC7.3 assignment                   |
| specialty          | String            | Medical specialty                                     | Present only when role = doctor                                                 |
| patientId          | Reference (users) | Linked patient                                        | Present only when role = family_member; null while the link is pending (UC15.1) |

Pharmacist and Admin accounts use only the common fields above; no role-specific fields apply.

Table 4.2.3.2 Collection: health_profiles

| Field            | Type              | Description                              | Constraints / Notes               |
|------------------|-------------------|------------------------------------------|-----------------------------------|
| \_id             | String            | Primary key                              | Auto-generated                    |
| patientId        | Reference (users) | Owning patient                           | Required, unique 1:1 with patient |
| medicalHistory   | String            | Structured/free-text medical history     | Required                          |
| lifestyleFactors | String            | Lifestyle factors captured at onboarding | Required                          |
| personalInfo     | String            | Additional personal information          | Required                          |

Table 4.2.3.3 Collection: vital_readings

| Field     | Type              | Description                 | Constraints / Notes                                       |
|-----------|-------------------|-----------------------------|-----------------------------------------------------------|
| \_id      | String            | Primary key                 | Auto-generated                                            |
| patientId | Reference (users) | Owning patient              | Required                                                  |
| systolic  | Number            | Systolic BP (mmHg)          | Required                                                  |
| diastolic | Number            | Diastolic BP (mmHg)         | Required                                                  |
| heartRate | Number            | PPG-captured heart rate     | Optional; present if captured in the same session (UC3.3) |
| note      | String            | Patient annotation          | Optional                                                  |
| timestamp | Timestamp         | When the reading was logged | Required                                                  |

Table 4.2.3.4 Collection: risk_scores

| Field       | Type              | Description              | Constraints / Notes                                                                                                     |
|-------------|-------------------|--------------------------|-------------------------------------------------------------------------------------------------------------------------|
| \_id        | String            | Primary key              | Auto-generated                                                                                                          |
| patientId   | Reference (users) | Owning patient           | Required                                                                                                                |
| modelUsed   | String            | e.g. "RandomForest v1"   | Higher-AUC model selected per complication (FR-9.2)                                                                     |
| scores      | Map               | Per-complication results | Embedded map keyed by complication: { stroke: {value, level}, cad: {...}, heartFailure: {...}, ckd: {...}, t2d: {...} } |
| generatedAt | Timestamp         | Prediction run timestamp | Required                                                                                                                |

All five complications are produced in the same scoring run from the same input vector, so they are embedded as a map within one document rather than five separate documents; this avoids repeating patientId/generatedAt/modelUsed five times per run.

Table 4.2.3.5 Collection: triage_outcomes

| Field          | Type                                | Description                                            | Constraints / Notes                                                      |
|----------------|-------------------------------------|--------------------------------------------------------|--------------------------------------------------------------------------|
| \_id           | String                              | Primary key                                            | Auto-generated                                                           |
| patientId      | Reference (users)                   | Owning patient                                         | Required                                                                 |
| vitalReadingId | Reference (vital_readings)          | Vitals captured in the same session                    | Optional (UC14.2)                                                        |
| symptoms       | Array\<Reference(symptom_catalog)\> | Symptoms selected by the patient                       | Embedded array of references small, bounded list per submission (UC14.1) |
| severity       | String                              | mild / moderate / severe                               | Required                                                                 |
| outcome        | String                              | monitor_at_home / contact_doctor / seek_emergency_care | Required                                                                 |
| generatedAt    | Timestamp                           | Submission timestamp                                   | Required                                                                 |

Table 4.2.3.6 Collection: medications

| Field         | Type              | Description            | Constraints / Notes                                                   |
|---------------|-------------------|------------------------|-----------------------------------------------------------------------|
| \_id          | String            | Primary key            | Auto-generated                                                        |
| patientId     | Reference (users) | Owning patient         | Required                                                              |
| name          | String            | Medication name        | Required                                                              |
| dosage        | String            | Dosage amount          | Required                                                              |
| schedule      | String            | Dose times / frequency | Required                                                              |
| adherenceRate | Number            | 0–100 computed %       | Derived from dose_logs; recomputed on each dose confirmation (FR-5.3) |

Table 4.2.3.7 Collection: dose_logs

| Field         | Type                    | Description                         | Constraints / Notes                 |
|---------------|-------------------------|-------------------------------------|-------------------------------------|
| \_id          | String                  | Primary key                         | Auto-generated                      |
| medicationId  | Reference (medications) | Parent medication                   | Required                            |
| scheduledTime | Timestamp               | When the dose was scheduled         | Required                            |
| status        | String                  | taken / missed                      | Required                            |
| confirmedAt   | Timestamp               | When the patient confirmed the dose | Optional; present if status = taken |

Table 4.2.3.8 Collection: health_records

| Field            | Type              | Description                             | Constraints / Notes                   |
|------------------|-------------------|-----------------------------------------|---------------------------------------|
| \_id             | String            | Primary key                             | Auto-generated                        |
| patientId        | Reference (users) | Owning patient                          | Required                              |
| fileUrl          | String            | Firebase Storage reference              | Required                              |
| category         | String            | Document category assigned at upload    | Required (UC6.1)                      |
| uploadedAt       | Timestamp         | Upload time                             | Required                              |
| sharedWithDoctor | Boolean           | Whether shared with the assigned doctor | Default: false                        |
| sharedAt         | Timestamp         | When sharing was granted                | Optional; present once shared (UC6.2) |

Table 4.2.3.9 Collection: appointments

| Field     | Type              | Description                                  | Constraints / Notes                   |
|-----------|-------------------|----------------------------------------------|---------------------------------------|
| \_id      | String            | Primary key                                  | Auto-generated                        |
| patientId | Reference (users) | Booking patient                              | Required                              |
| doctorId  | Reference (users) | Attending doctor                             | Optional; null until UC7.3 assignment |
| dateTime  | Timestamp         | Scheduled date/time                          | Required                              |
| status    | String            | booked / rescheduled / cancelled / completed | Required                              |

Table 4.2.3.10 Collection: clinical_notes

| Field     | Type              | Description      | Constraints / Notes |
|-----------|-------------------|------------------|---------------------|
| \_id      | String            | Primary key      | Auto-generated      |
| patientId | Reference (users) | Subject patient  | Required            |
| doctorId  | Reference (users) | Authoring doctor | Required            |
| content   | String            | Note text        | Required            |
| createdAt | Timestamp         | Creation time    | Required            |

Table 4.2.3.11 Collection: prescriptions

| Field             | Type              | Description                            | Constraints / Notes     |
|-------------------|-------------------|----------------------------------------|-------------------------|
| \_id              | String            | Primary key                            | Auto-generated          |
| patientId         | Reference (users) | Receiving patient                      | Required                |
| doctorId          | Reference (users) | Issuing doctor                         | Required                |
| medicationDetails | String            | Prescribed medication details          | Required                |
| isRecurring       | Boolean           | Flags a long-term chronic prescription | Default: false (UC13.1) |
| issuedAt          | Timestamp         | Issue time                             | Required                |

Table 4.2.3.12 Collection: care_plans

| Field     | Type              | Description        | Constraints / Notes                                             |
|-----------|-------------------|--------------------|-----------------------------------------------------------------|
| \_id      | String            | Primary key        | Auto-generated                                                  |
| patientId | Reference (users) | Owning patient     | Required, unique one living plan per patient, not a log (UC8.5) |
| doctorId  | Reference (users) | Maintaining doctor | Required                                                        |
| content   | String            | Care plan content  | Required                                                        |
| updatedAt | Timestamp         | Last edit time     | Required                                                        |

Table 4.2.3.13 Collection: messages

| Field         | Type              | Description                                       | Constraints / Notes     |
|---------------|-------------------|---------------------------------------------------|-------------------------|
| \_id          | String            | Primary key                                       | Auto-generated          |
| senderId      | Reference (users) | Sending user                                      | Required                |
| recipientId   | Reference (users) | Receiving user                                    | Required                |
| encryptedText | String            | End-to-end encrypted message body                 | Required (NFR-2.1)      |
| isFlagged     | Boolean           | Set when the NLP scan detects a high-risk keyword | Default: false (UC10.3) |
| sentAt        | Timestamp         | Send time                                         | Required                |

Table 4.2.3.14 Collection: medication_orders

| Field          | Type                      | Description                                  | Constraints / Notes                                |
|----------------|---------------------------|----------------------------------------------|----------------------------------------------------|
| \_id           | String                    | Primary key                                  | Auto-generated                                     |
| patientId      | Reference (users)         | Ordering patient                             | Required                                           |
| prescriptionId | Reference (prescriptions) | Recurring prescription this order fulfils    | Required                                           |
| pharmacistId   | Reference (users)         | Preparing pharmacist                         | Optional; null until an order is claimed           |
| method         | String                    | self_collection / home_delivery              | Required (UC13.3)                                  |
| paymentStatus  | String                    | pending / paid / failed                      | Required                                           |
| deliveryStatus | String                    | dispatched / in_transit / delivered / failed | Optional; only applies when method = home_delivery |
| cycleDate      | Date                      | Monthly recurrence date                      | Required                                           |

Table 4.2.3.15 Collection: audit_logs

| Field      | Type              | Description                                           | Constraints / Notes |
|------------|-------------------|-------------------------------------------------------|---------------------|
| \_id       | String            | Primary key                                           | Auto-generated      |
| userId     | Reference (users) | Actor who performed the action                        | Required            |
| action     | String            | Action performed, e.g. "DEACTIVATE_ACCOUNT"           | Required            |
| targetType | String            | Type of entity affected, e.g. "users", "appointments" | Optional            |
| targetId   | String            | ID of the affected document                           | Optional            |
| details    | String            | Additional context                                    | Required            |
| timestamp  | Timestamp         | When the action occurred                              | Required            |

Table 4.2.3.16 Collection: agent_messages

| Field     | Type              | Description     | Constraints / Notes                                                          |
|-----------|-------------------|-----------------|------------------------------------------------------------------------------|
| \_id      | String            | Primary key     | Auto-generated                                                               |
| patientId | Reference (users) | Owning patient  | Required                                                                     |
| role      | String            | patient / agent | Required distinguishes the patient's message from the Gemini-generated reply |
| text      | String            | Message content | Required                                                                     |
| sentAt    | Timestamp         | Send time       | Required                                                                     |

Persists the AI Health Agent's conversation history (FR-14.1) so Gemini has session context and past exchanges can be reviewed. A separate collection rather than an embedded array, since a 24/7 agent produces an unbounded, ever-growing history per patient.

Table 4.2.3.17 Collection: emergency_alerts

| Field          | Type                    | Description                                  | Constraints / Notes |
|----------------|-------------------------|----------------------------------------------|---------------------|
| \_id           | String                  | Primary key                                  | Auto-generated      |
| patientId      | Reference (users)       | Patient whose risk triggered the alert       | Required            |
| familyMemberId | Reference (users)       | Recipient family member                      | Required            |
| riskScoreId    | Reference (risk_scores) | Risk score document that triggered the alert | Required            |
| gpsLocation    | GeoPoint                | Patient's location at the time of the alert  | Required            |
| sentAt         | Timestamp               | When the alert was sent                      | Required            |
| acknowledgedAt | Timestamp               | When the family member opened the alert      | Optional            |

Records each Critical-level emergency alert (FR-14.2) so it can be retrieved by alertId when the family member opens it, and so acknowledgement can be tracked.

Table 4.2.3.18 Collection: symptom_catalog

| Field    | Type   | Description                                     | Constraints / Notes |
|----------|--------|-------------------------------------------------|---------------------|
| \_id     | String | Primary key                                     | Auto-generated      |
| name     | String | Symptom name shown to the patient               | Required            |
| category | String | Grouping used to organise the symptom picker UI | Required            |

A static reference/lookup collection with no patientId not owned by any patient. Backs the "patient selects symptoms" step of UC14.1 with a controlled vocabulary instead of free text, and is referenced by triage_outcomes.symptoms.

Table 4.2.3.19 Collection: payment_transactions

| Field          | Type                          | Description                           | Constraints / Notes |
|----------------|-------------------------------|---------------------------------------|---------------------|
| \_id           | String                        | Primary key                           | Auto-generated      |
| orderId        | Reference (medication_orders) | Order this transaction belongs to     | Required            |
| stripeChargeId | String                        | Stripe's transaction reference        | Required            |
| amount         | Number                        | Amount charged                        | Required            |
| status         | String                        | succeeded / failed / refunded         | Required            |
| processedAt    | Timestamp                     | When Stripe processed the transaction | Required            |

Logs each Stripe charge (FR-13.3) independently of medication_orders.paymentStatus, so refunds and reconciliation have their own auditable history rather than overwriting a single status field.

Table 4.2.3.20 Collection: delivery_tracking_events

| Field     | Type                          | Description                                              | Constraints / Notes |
|-----------|-------------------------------|----------------------------------------------------------|---------------------|
| \_id      | String                        | Primary key                                              | Auto-generated      |
| orderId   | Reference (medication_orders) | Order being delivered                                    | Required            |
| status    | String                        | dispatched / picked_up / in_transit / delivered / failed | Required            |
| location  | String                        | Courier location at this event, if available             | Optional            |
| timestamp | Timestamp                     | When this status was recorded                            | Required            |

Captures the status-over-time history that FR-13.4's "real-time tracking" requires medication_orders.deliveryStatus only reflects the current state, not the trail of updates from the Grab API.

## 4.3 UI Design

This section presents the user interface design of the Hypertension Care Management Platform's Patient Mobile App, built in Flutter. Screens are organised by module, following the same structure used throughout this chapter, and each is captioned with its figure number and a short description of its purpose and the requirements it satisfies.

4.3.1 Shared Authentication and Onboarding Interfaces

4.3.1.1 Login Interface


*Figure 4.3.1.1 Login Interface*

This interface allows a registered user to sign in with their email and password, or authenticate using device biometrics. A role selector (Patient, Doctor, Admin) determines which portal experience the user is directed to after signing in, and a link is provided for new patients to register (FR-1.1, FR-1.2).

4.3.1.2 Onboarding Complete Interface


*Figure 4.3.1.2 Onboarding Complete Interface*

This confirmation screen appears immediately after a patient completes the one-time onboarding health profile (personal information, medical history, and lifestyle factors). It confirms the profile has been saved and redirects the patient to their dashboard (UC1.4).

4.3.2 Patient Dashboard Interface

4.3.2.1 Home Dashboard Interface


*Figure 4.3.2.1 Home Dashboard Interface*

This is the patient's landing screen after login, summarising the day's medication schedule, next appointment, latest blood pressure reading, and current AI-generated risk assessment in one view. Quick-access shortcuts let the patient jump directly to logging vitals, the symptom checker, messaging, or the AI health agent (FR-2.1, FR-2.2).

4.3.3 Vital Signs Tracking Interfaces

4.3.3.1 Vitals Tracking Interface (Empty State)


*Figure 4.3.3.1 Vitals Tracking Interface (Empty State)*

Shown to a patient who has not yet logged any readings, this state replaces charts and summaries with a prompt to log a first reading and explains that the AI risk assessment unlocks once at least three readings are recorded. Designing an explicit empty state avoids showing blank or misleading charts before real data exists.

4.3.3.2 Log Vitals Interface


*Figure 4.3.3.2 Log Vitals Interface*

This screen lets the patient log a blood pressure reading manually by entering systolic and diastolic values, or measure heart rate by placing a fingertip over the rear camera for a PPG-based capture. Both paths feed the same vitals record used for trend charts and risk scoring (FR-3.1, FR-3.2, UC3.3).

4.3.3.3 Reading Saved Interface


Figure 4.3.3.3 Reading Saved Interface

After a reading is logged, the patient sees an immediate summary confirming the value is within normal range alongside their resting heart rate, reinforcing that the entry was saved successfully. A short encouragement message supports consistent logging habits.

4.3.4 Health Data Visualisation Interfaces

4.3.4.1 Health Trends Interface


*Figure 4.3.4.1 Health Trends Interface*

This screen visualises the patient's blood pressure history as a line chart across selectable time windows (7 days, 30 days, 3 months), with average, minimum, and maximum statistics shown below it. A cardiovascular risk score card at the bottom shows the current risk percentage and recent trend direction (FR-4.1, FR-4.2, FR-4.3).

4.3.4.2 Weekly Trends Interface (Empty State)


*Figure 4.3.4.2 Weekly Trends Interface (Empty State)*

This is the equivalent empty state for the trends view, shown before enough readings exist to plot a meaningful chart. It prompts the patient to log at least three readings and shows placeholder cards for average heart rate, average blood pressure, and risk score until real data is available.

4.3.5 Medication Management Interface

4.3.5.1 Medications Interface


*Figure 4.3.5.1 Medications Interface*

This screen lists the patient's medications grouped by time of day (morning, evening, as-needed), showing which doses have already been taken and which are still upcoming. A refill alert is surfaced when a medication is running low, with a direct action to request a refill from the pharmacy (FR-5.1, FR-5.2, FR-5.4).

4.3.6 Appointment Scheduling Interfaces

4.3.6.1 Appointments Interface


*Figure 4.3.6.1 Appointments Interface*

This screen shows the patient's next upcoming appointment with a link to its pre-visit summary, alongside a calendar and time-slot picker for booking a new appointment with their assigned doctor (FR-7.1, FR-7.4).

4.3.6.2 Booking Confirmed Interface


*Figure 4.3.6.2 Booking Confirmed Interface*

After booking, this screen confirms the appointment's doctor, date, time, and location, and gives the patient the option to reschedule or cancel. It also surfaces pre-visit tasks such as reviewing the pre-visit summary and completing an intake form before arrival.

4.3.7 AI Health Agent Interface

4.3.7.1 AI Health Agent Chat Interface


*Figure 4.3.7.1 AI Health Agent Chat Interface*

This conversational interface lets the patient ask the AI Health Agent questions about their health status in plain language. In this example, the agent proactively raises a recent elevated blood pressure reading, asks about symptoms, and offers a quick-book option for a telehealth check-in, with an emergency escalation notice shown in case symptoms worsen (FR-14.1).

4.3.8 Symptom Checker and Triage Interfaces

4.3.8.1 Symptom Selection Interface


*Figure 4.3.8.1 Symptom Selection Interface*

This is the entry point to the symptom checker, where the patient selects from a predefined list of common symptoms and rates overall severity (mild, moderate, severe) before continuing (UC14.1).

4.3.8.2 Triage Result Interface


*Figure 4.3.8.2 Triage Result Interface*

Based on the selected symptoms, severity, and the patient's current vitals and risk score, this screen displays the resulting triage outcome in this case Seek Emergency Care along with the reported critical symptoms and a numbered list of immediate actions. Direct-call and vitals-sharing actions are provided for the most urgent outcome level (FR-14.3).

4.3.9 Family Monitoring and Emergency Alert Interface

4.3.9.1 Emergency SOS Interface


*Figure 4.3.9.1 Emergency SOS Interface*

This screen gives the patient one-tap access to call emergency services, view the nearest hospital, share live vitals with the ER, and notify their linked family members, all from a single high-visibility screen reserved for genuine emergencies (FR-14.2).

4.3.10 Recurring Medication, Payment and Delivery Interfaces

4.3.10.1 Order Confirmation Interface


*Figure 4.3.10.1 Order Confirmation Interface*

This screen presents the monthly recurring medication order for review itemised cost and insurance coverage before the patient selects a fulfilment method of self-collection or home delivery (FR-13.2, FR-13.4).

4.3.10.2 Secure Payment Interface


*Figure 4.3.10.2 Secure Payment Interface*

This screen collects payment for the confirmed order using a saved card or a newly added payment method, processed through Stripe, with the order summary and total shown alongside a reminder that payment details are encrypted (FR-13.3).

4.3.10.3 Delivery Tracking Interface


*Figure 4.3.10.3 Delivery Tracking Interface*

This screen shows the real-time status of a home-delivery order against a four-stage timeline (Order Confirmed, Preparing, Out for Delivery, Delivered) along with an estimated arrival time, updating as each Grab delivery status event is received (FR-13.4).

4.3.11 Settings and Preferences Interface

4.3.11.1 Settings Interface


*Figure 4.3.11.1 Settings Interface*

This screen lets the patient manage their profile (personal information, contact details, health profile), toggle push notification preferences, review data and privacy settings, and sign out or permanently delete their account (FR-12.1, FR-12.2, UC12.4).

The remaining interfaces cover the Web Portal used by Doctor, Pharmacist, and Admin accounts. In the prototype these are demonstrated under a single “Lead Administrator” account for convenience, but the platform's actual role-based access control (FR-1.3) keeps these as three separate account types, each restricted to their own functions.

4.3.12 Doctor Portal Interfaces

4.3.12.1 Doctor Dashboard Interface


Figure 4.3.12.1 Doctor Dashboard Interface

This is the doctor's landing screen, listing all assigned patients sorted by risk level with their latest blood pressure reading and last update time, alongside summary counts for total, high-risk, and elevated-risk patients. A priority alerts panel on the right surfaces the most urgent events BP spikes, missed medication, and AI-detected trends for immediate review (FR-8.1, FR-8.4).

4.3.12.2 Doctor Dashboard Interface (Critical Alert Active)


Figure 4.3.12.2 Doctor Dashboard Interface (Critical Alert Active)

This is the same dashboard shown with an active Critical-level alert: two consecutive readings above 180/110 combined with poor medication adherence trigger a red banner requiring the doctor to either intervene immediately or dismiss it. A population-level systolic trend chart below tracks controlled versus uncontrolled patients over the past 30 days (FR-8.4, FR-9.5).

4.3.12.3 Doctor Schedule Interface


Figure 4.3.12.3 Doctor Schedule Interface

This calendar view shows the doctor's scheduled appointments across monthly, weekly, and daily layouts, colour-coded by type (regular checkup, emergency, follow-up), giving a full view of upcoming consultations without opening each patient record individually (FR-7.1).

4.3.12.4 Patient Detail Interface


Figure 4.3.12.4 Patient Detail Interface

This screen presents a patient's complete clinical picture in one place: demographics, current hypertension risk score with contributing factors, a blood pressure trend chart, recent lab results, active medications, and a clinical notes panel. Tabs let the doctor switch between vitals and labs, medications, care plan, and past clinical notes without leaving the page (FR-8.2, FR-8.3).

4.3.12.5 Consultation Notes Interface


Figure 4.3.12.5 Consultation Notes Interface

This screen lets the doctor write a new clinical note against a patient's record, with smart templates (SOAP Note, Hypertension Follow-up, Medication Adjustment) to speed up documentation, alongside a summary of the patient's latest vitals and active risk factors for reference while writing (FR-8.3).

4.3.12.6 Note Saved Interface


Figure 4.3.12.6 Note Saved Interface

This screen confirms a clinical note has been saved successfully via a toast notification, shown alongside the patient's risk level, care protocol, and latest BP trend, with prior notes listed chronologically below the new entry (FR-8.3).

4.3.12.7 Prescription Management Interface


Figure 4.3.12.7 Prescription Management Interface

This screen lets the doctor issue a new prescription, showing the patient's current medication regimen and relevant clinical notes for context alongside a form for medication name, dosage, frequency, and duration. A toggle marks the prescription as recurring for a chronic condition, which automatically generates monthly renewal requests (FR-8.3, UC13.1).

4.3.13 Pharmacist Portal Interface

4.3.13.1 Pharmacist View Interface


Figure 4.3.13.1 Pharmacist View Interface

This is the pharmacist's working screen, listing the active prescription queue with each order's status (preparing, ready for delivery, ready for collection) alongside current medication inventory levels and expiry dates. A patient lookup panel and quick actions for logging new stock, reporting issues, and dispatching a Grab delivery batch support the day-to-day fulfilment workflow (FR-13.3, FR-13.4).

4.3.14 Admin Portal Interfaces

4.3.14.1 User Management Interface


Figure 4.3.14.1 User Management Interface

This screen lists every system user with their role, account status, and join date, and lets the admin add new staff accounts, filter by role, or deactivate an existing account. This is where Doctor, Pharmacist, and Admin accounts are provisioned, since these roles cannot self-register (FR-1.6, FR-11.1).

4.3.14.2 Patient Assignments Interface


Figure 4.3.14.2 Patient Assignments Interface

This screen shows unassigned patients alongside each doctor's current caseload and availability, letting the admin manually assign a patient to a doctor or use auto-assign to distribute the workload automatically (FR-11.2, UC7.3).

4.3.14.3 Audit Logs Interface


Figure 4.3.14.3 Audit Logs Interface

This screen provides a searchable, filterable log of system activity user actions, failed logins, privilege escalations, and data exports with each entry showing the acting user, action taken, affected module, and timestamp. Logs can be exported to CSV for compliance review (FR-1.5, FR-11.3).

4.3.14.4 Delivery Oversight Interface


Figure 4.3.14.4 Delivery Oversight Interface

This screen gives the admin platform-wide visibility into medication delivery dispatches across all pharmacies, with live status, assigned courier, and ETA for each order, plus the ability to manually dispatch an order if needed (FR-11.4, FR-13.4).

4.3.14.5 Hospital Analytics Interface


Figure 4.3.14.5 Hospital Analytics Interface

This screen aggregates clinical outcome metrics across all active patients risk distribution, consultation volume trends, medication adherence, and delivery success rate supporting the admin's hospital-wide reporting function (FR-11.4).

4.3.14.6 System Analytics Interface


Figure 4.3.14.6 System Analytics Interface

This screen tracks platform usage and engagement of active clinicians, system uptime, messages sent, and usage by clinical departments giving the admin insight into how the platform is being adopted across the organisation (FR-11.3).

4.3.14.7 System Health Interface


Figure 4.3.14.7 System Health Interface

This screen monitors the technical health of each backend service: the API, database, ML risk model, Grab delivery integration, Stripe payments, and notification service showing uptime and latency per service so degraded components, such as the ML model shown here, can be identified quickly (FR-11.3).

4.3.14.8 Staff Portal Login Interface


*Figure 4.3.14.8 Staff Portal Login Interface*

This interface is the sign-in entry point for Doctor, Pharmacist, and Admin accounts on the Web Portal, kept separate from the Patient/Family mobile login shown in Figure 4.3.1.1. A role selector (Doctor, Admin, Pharmacist) determines which portal view loads after authentication, alongside an SSO option for institutional sign-in (FR-1.1, FR-1.2, FR-1.3).

4.3.15 Secure Messaging Interfaces

4.3.15.1 Message Inbox Interface


*Figure 4.3.15.1 Message Inbox Interface*

This screen lists the patient's message threads with their care team, showing each sender's name, role, a preview of the latest message, timestamp, and an unread-count badge, with a search bar to locate a specific conversation (UC10.1).

4.3.15.2 Chat Thread Interface


*Figure 4.3.15.2 Chat Thread Interface*

This screen shows a full conversation thread with a single doctor, with the patient's own messages right-aligned and the doctor's replies left-aligned. Messages are end-to-end encrypted before being written to Firestore, indicated by the lock icon above the compose bar (NFR-2.1).

4.3.15.3 Flagged Message Interface


*Figure 4.3.15.3 Flagged Message Interface*

This is the same chat thread shown after the NLP scanner detects a high-risk keyword in the patient's message. A red banner confirms the care team has been notified and, for urgent language, prompts the patient to call 911 or go to the nearest emergency room (UC10.3).

4.3.16 Family Member App Interfaces

The remaining interfaces cover the Family Member mobile app, the third client surface defined in the Sitemap (Figure 4.1.2). This is a separate app build from the Patient Mobile App, reflecting the read-only, monitoring-only nature of the family member role.

4.3.16.1 Link to Patient Interface


*Figure 4.3.16.1 Link to Patient Interface*

This screen lets a family member enter the unique link code shared by a patient to request monitoring access. The request remains pending until the patient approves it from their own CareFlow app, consistent with the requestLink/linkPending flow in Figure 4.1.1.15 (UC15.1).

4.3.16.2 Family Dashboard Interface


*Figure 4.3.16.2 Family Dashboard Interface*

This is the family member's read-only view of a linked patient's health status: current risk level, today's blood pressure and heart rate readings, and a 7-day trend summary. No logging or edit actions are available from this screen, consistent with the family member's monitoring-only role (FR-14.2).

4.3.16.3 Emergency Alert Interface


*Figure 4.3.16.3 Emergency Alert Interface*

This screen renders when a linked patient's risk reaches Critical level, surfacing the triggering reading, the patient's last known location, and one-tap actions to call the patient or acknowledge the alert (FR-14.2, Figure 4.1.1.15).

## 4.4 Software Architecture Design

### 4.4.1 Package diagram

Figure 4.5 organises the codebase into a client/backend/security layer, a Core Domain Packages region containing one package per system module (mirroring the thirteen modules from Chapter 3), and an infrastructure/integration layer wrapping Firestore and the third-party APIs. Dependencies are shown as «uses» / «import» / «access» relationships: both presentation packages depend on the shared client and backend API packages; domain packages depend on each other only where a real cross-module interaction exists (e.g. Vital Signs Tracking → AI-Powered Health Monitoring, Medication Management → Recurring Medication, Payment & Delivery); and the backend depends on the infrastructure layer, which in turn wraps the concrete Firebase, ML, and external-service packages.


Figure 4.5: Package Diagram – Hypertension Care Management Platform

### 4.4.2 Deployment diagram

Figure 4.6 maps the package structure onto physical and cloud nodes. The Patient/Family Mobile Device calls the Application Server (Cloud Run) directly over HTTPS/REST. The Doctor/Admin/Pharmacist Workstation loads the compiled Flutter Web build from Firebase Hosting, which rewrites API traffic (/api/\*\*) through to the same Application Server this is the standard Firebase Hosting + Cloud Run integration pattern, so the web portal is served as static assets while all business logic still runs through one backend. The Application Server in turn calls the Firebase Platform (Authentication, Firestore, Storage) and the three external services (Gemini, Stripe, Grab).


Figure 4.6: Deployment Diagram – Hypertension Care Management Platform

### 4.4.3 Framework & language

Each technology choice is tied to a specific non-functional requirement established in Chapter 3, rather than chosen by default.

Table 4.4.3 Framework and Programming Language of Platform Development

| System component                         | Language | Framework or technology                | Purpose                                                                                                            |
|------------------------------------------|----------|----------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| Patient/Family Mobile Application        | Dart     | Flutter                                | Develops the cross-platform Android and iOS application                                                            |
| Web Portal (Doctor / Admin / Pharmacist) | Dart     | Flutter Web                            | Develops the browser-based portal interface, compiled from the same codebase                                       |
| Application Server                       | Python   | FastAPI                                | Processes business logic, REST API requests, authentication, vitals, appointments, messaging, and admin operations |
| Real-Time Data Sync                      | —        | Cloud Firestore listeners              | Enables real-time updates across mobile and web clients (NFR-1.1)                                                  |
| Database Layer                           | —        | Cloud Firestore                        | Stores and manages users, vitals, medications, appointments, and other system data                                 |
| File Storage                             | —        | Firebase Cloud Storage                 | Stores uploaded health record documents                                                                            |
| Risk Prediction                          | Python   | scikit-learn (Random Forest) & XGBoost | Predicts patient risk for five complications from vitals and profile data (FR-9.2)                                 |
| AI Health Agent                          | —        | Google Gemini Flash API                | Powers the 24/7 conversational health agent (FR-14.1)                                                              |
| Payment Processing                       | —        | Stripe API                             | Processes recurring medication order payments (FR-13.3)                                                            |
| Delivery                                 | —        | Grab API                               | Dispatches and tracks home delivery orders (FR-13.4)                                                               |
| Web Hosting                              | —        | Firebase Hosting                       | Serves the compiled Flutter Web portal build and rewrites API traffic to the Application Server                    |
| Application Hosting                      | —        | Google Cloud Run                       | Runs the containerised FastAPI backend                                                                             |

# 

## 4.5 Algorithm Design / Adopted Technology Description / Security Design

## 4.5.1 Algorithm Design

### A. Disease Risk Prediction (FR-9.1–FR-9.3)

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p>INPUT: patientId</p>
<p>1. profile ← fetch HealthProfile, latest VitalReading(s), Medication list for patientId</p>
<p>2. inputVector ← assemble twelve input variables from profile</p>
<p>(age, gender, systolic, diastolic, heart rate, BMI, smoking status,</p>
<p>family history, existing conditions, medication count, adherence rate,</p>
<p>days since last reading)</p>
<p>3. FOR EACH complication IN {Stroke, CAD, HeartFailure, CKD, T2D}:</p>
<p>rfScore ← RandomForest[complication].predict_proba(inputVector)</p>
<p>xgbScore ← XGBoost[complication].predict_proba(inputVector)</p>
<p>score ← rfScore IF AUC(RandomForest[complication]) &gt; AUC(XGBoost[complication]) ELSE xgbScore</p>
<p>riskLevel ← categorise(score) // Low / Moderate / High / Critical, fixed thresholds</p>
<p>SAVE RiskScore(patientId, complication, score, riskLevel)</p>
<p>4. IF any riskLevel IN {High, Critical}: trigger escalation (Figure 4.1)</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Thresholds for categorise() are fixed cut-points on the predicted probability, calibrated during model training and validated against the labelled dataset described in Chapter 3; they are not adjustable at runtime, since undocumented threshold drift would undermine the reproducibility of a clinical-facing score.

### B. Heart Rate via Camera PPG (FR-3.2, UC3.3/UC14.2)

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p>INPUT: 10-second video frame stream from rear camera with fingertip covering the lens</p>
<p>1. FOR EACH frame: extract mean green-channel pixel intensity</p>
<p>2. Apply a band-pass filter to isolate the plausible heart-rate frequency range (0.67–3.3 Hz, i.e. 40–200 bpm)</p>
<p>3. Run peak detection on the filtered signal</p>
<p>4. beatsPerMinute ← (peak count / capture duration) × 60</p>
<p>5. IF signal-to-noise ratio is too low: return CAPTURE_FAILED (prompt retry/skip)</p>
<p>ELSE: return beatsPerMinute</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

### C. Medication Adherence Rate (FR-5.3, cached on medications.adherenceRate)

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p>INPUT: medicationId</p>
<p>1. logs ← all dose_logs for medicationId within the rolling window (default 30 days)</p>
<p>2. adherenceRate ← (COUNT(status = taken) / COUNT(*)) × 100</p>
<p>3. UPDATE medications.adherenceRate</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Recomputed incrementally whenever a new dose_logs entry is written (on confirmation or on missed-dose timeout), rather than on every dashboard read, since the aggregate is cheap to update but would be repeatedly recomputed from full history otherwise.

### D. Symptom Checker Triage (FR-14.3)

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p>INPUT: selected symptoms, severity, patientId</p>
<p>1. vitals ← most recent vital_readings entry (captured in this session, per UC14.2)</p>
<p>2. riskScore ← most recent risk_scores document for patientId</p>
<p>3. outcome ← classify(symptoms, severity, vitals, riskScore) against fixed clinical thresholds</p>
<p>// e.g. severity = severe AND systolic &gt; 180 -&gt; seek_emergency_care</p>
<p>4. SAVE triage_outcomes(patientId, vitals._id, symptoms, severity, outcome)</p>
<p>5. IF outcome IN {contact_doctor, seek_emergency_care}: notify assigned doctor (FR-14.3/UC14.4)</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

##  

## 4.5.2 Adopted Technology Description

- Real-time synchronisation: Firestore's snapshot listeners push changes to connected clients directly, which is how a new vital_readings entry or updated risk_scores document reaches the Patient dashboard and the Doctor portal within the 2-second bound set by NFR-1.1, without polling.

- Offline-first mobile experience: Firestore's local cache satisfies NFR-4.2 by serving the last-synced data when the device is offline and queuing writes (e.g. a logged BP reading) for automatic sync on reconnect.

- Stateless backend: FastAPI's request handlers hold no session state between calls; combined with Firebase Auth's bearer tokens, this allows the backend to scale horizontally (NFR-5.1) behind Cloud Run without sticky sessions.

- Third-party API isolation: Stripe, Grab, and Gemini are each accessed through a thin client wrapper in the External Integration Adapter package (Figure 4.5), so a provider change is contained to one package rather than scattered across the API layer.

## 4.5.3 Security Design

Table 4.5.3 Security Design

| Concern                 | Mechanism                                                                                                                                                                                                                                                                    | Requirement     |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------|
| Authentication          | Firebase Authentication issues short-lived bearer tokens validated on every API request                                                                                                                                                                                      | FR-1.2, NFR-2.4 |
| Authorisation           | Firestore Security Rules enforce that a patient can read/write only documents where patientId matches their own uid, and a doctor can read only patients where assignedDoctorId matches their own uid                                                                        | NFR-2.2         |
| Transport security      | All client-backend and backend-third-party traffic is over HTTPS/TLS                                                                                                                                                                                                         | NFR-2.4         |
| Message confidentiality | messages.encryptedText is encrypted end-to-end before it is written to Firestore, so the stored document itself is not human-readable server-side                                                                                                                            | NFR-2.1         |
| Payment data            | No card data is handled or stored by the platform; Stripe's hosted payment flow returns only a payment status/token                                                                                                                                                          | NFR-2.3         |
| Audit trail             | Every state-changing action writes an audit_logs entry with userId, action, targetType, targetId, enabling after-the-fact review of who changed what                                                                                                                         | FR-1.5, FR-11.3 |
| Data minimisation       | The onboarding health_profiles and vital_readings collections capture only fields directly used by the risk-prediction and dashboard features, in line with PDPA's purpose-limitation principle                                                                              | NFR-8.1         |
| Account deletion        | Patient account deletion schedules cascade deletion of the patient's owned data (vital_readings, risk_scores, medications, health_records, triage_outcomes, medication_orders), while doctor-authored clinical records are retained under standard record-retention practice | FR-12.2, UC12.4 |

# 

## 4.6 Chapter Summary and Evaluation

This chapter presented the complete system analysis and design for the CareFlow Hypertension Care Management Platform, moving from the requirements and use cases established in Chapter 3 into a concrete technical design. The behavioural design was captured through a set of sequence diagrams covering every functional module, supported by a sitemap describing the full screen structure across the platform's three client surfaces. This was followed by the structural design: a class diagram modelling the system's domain layer, a relational ERD, and a corresponding Firestore data dictionary, with any deliberate differences between the relational and document-oriented models explained rather than left unaddressed. The chapter then presented UI designs for the patient-facing mobile app, the clinical/staff web portal, and the family member app, followed by a package diagram and deployment diagram describing the software architecture and its mapping onto cloud infrastructure. Finally, the chapter documented the core algorithms underpinning the platform's intelligent features and a security design summarising how key risks are mitigated.

Overall, the design demonstrates a consistent line of traceability from requirements through to implementation-ready artefacts: each diagram and interface can be linked back to the functional and non-functional requirements it satisfies, and the various design artefacts remain consistent with one another. A consistent set of design conventions was applied throughout, which made the documentation easier to review and revise as issues were identified. Some trade-offs were necessary, particularly around reconciling a conceptually clean relational model with the practical realities of a document-oriented database, and these were addressed as deliberate design decisions rather than oversights.

##  

## Appendix

Diagram

[<u>https://app.diagrams.net/#G1ieyECnINzmTQ6YdfxLaUPkMYq\_\_GNh8r#%7B%22pageId%22%3A%22iBxM9t2WA8dYLebpY6nR%22%7D</u>](https://app.diagrams.net/#G1ieyECnINzmTQ6YdfxLaUPkMYq__GNh8r#%7B%22pageId%22%3A%22iBxM9t2WA8dYLebpY6nR%22%7D)
