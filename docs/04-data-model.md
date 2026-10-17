# 04 — Data Model (Cloud Firestore)

Source: Chapter 4, Section 4.2.3 Data Dictionary (20 collections). Class diagram: `figures/ch4-figure-4-2-1-class-diagram-*.png`. ERD: `figures/ch4-figure-4-2-2-erd-*.png`.

## Rules for implementation

1. **This data dictionary is the physical schema. Follow it exactly** — collection names (snake_case), field names (camelCase), enum values. Do NOT use the nested `patients/{id}/bp_readings` layout from `source/hypertension_app_reference.md`; it is superseded (decision D-01).
2. All collections are **top-level**. Ownership is a `patientId` reference field, not a sub-collection path.
3. Reference fields are stored as **document ID strings** (e.g. `patientId: "<uid>"`), not Firestore `DocumentReference` objects — simpler for Security Rules, FastAPI and JSON.
4. `users/{uid}` document ID = Firebase Auth UID. Role is stored both in `users.role` and as a Firebase Auth **custom claim** `role` (claim is what Security Rules and FastAPI trust).
5. Role-specific fields live directly on `users` (merged), as Section 4.2.3 explains. The ERD's PatientProfile / DoctorProfile / FamilyMemberProfile tables are the logical model only (decision D-02).
6. Timestamps: Firestore `Timestamp`, written with server timestamps where the dictionary says "Auto-set".
7. Enum values exactly as listed (`monitor_at_home`, `contact_doctor`, `seek_emergency_care`, `self_collection`, `home_delivery`, …). Put them in shared constants on both the Dart and Python side.
8. Any new collection or field not listed here must be added to `09-decisions-and-open-questions.md` first, because the report's Chapter 4 has to be updated to match.

## Collections

### `users`  (Table 4.2.3.1)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key (Firebase Auth UID) | Auto-generated |
| email | String | Login email | Required, unique |
| name | String | Full name | Required |
| role | String | patient / doctor / pharmacist / admin / family_member | Required |
| isActive | Boolean | Whether the account is active | Default: true |
| createdAt | Timestamp | Account creation time | Auto-set |
| updatedAt | Timestamp | Last profile update time | Auto-set on write |
| dateOfBirth | Date | Patient's date of birth | Present only when role = patient |
| gender | String | Patient's gender | Present only when role = patient |
| onboardingComplete | Boolean | Whether the onboarding health profile is complete | Present only when role = patient; default false |
| assignedDoctorId | Reference (users) | Currently assigned doctor | Present only when role = patient; null until UC7.3 assignment |
| specialty | String | Medical specialty | Present only when role = doctor |
| maxPatients | Number | Caseload limit set by the admin (D-59) | Doctor only; optional, default 30 |
| patientId | Reference (users) | Linked patient | Present only when role = family_member; null while the link is pending (UC15.1) |

> Pharmacist and Admin accounts use only the common fields above; no role-specific fields apply.

| address, addressLat, addressLng | String, Number, Number | Patient delivery address and map point (D-69) | Optional |
| phone | String | Staff contact number (D-77, portal Settings) | Optional; doctors, pharmacists, admins |
| bellPrefs | Map | D-77: bell categories switched on/off (messages, alerts, appointments, orders, medication, other) | Optional; missing = on |

### `health_profiles`  (Table 4.2.3.2)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Owning patient | Required, unique 1:1 with patient |
| medicalHistory | String | Structured/free-text medical history | Required |
| lifestyleFactors | String | Lifestyle factors captured at onboarding | Required |
| personalInfo | String | Additional personal information | Required |

### `vital_readings`  (Table 4.2.3.3)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Owning patient | Required |
| systolic | Number | Systolic BP (mmHg) | Required |
| diastolic | Number | Diastolic BP (mmHg) | Required |
| heartRate | Number | PPG-captured heart rate | Optional; present if captured in the same session (UC3.3) |
| note | String | Patient annotation | Optional |
| timestamp | Timestamp | When the reading was logged | Required |

### `risk_scores`  (Table 4.2.3.4)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Owning patient | Required |
| modelUsed | String | e.g. "RandomForest v1" | Higher-AUC model selected per complication (FR-9.2) |
| scores | Map | Per-complication results | Embedded map keyed by complication: { stroke: {value, level}, cad: {...}, heartFailure: {...}, ckd: {...}, t2d: {...} } |
| generatedAt | Timestamp | Prediction run timestamp | Required |

> All five complications are produced in the same scoring run from the same input vector, so they are embedded as a map within one document rather than five separate documents; this avoids repeating patientId/generatedAt/modelUsed five times per run.


### `triage_outcomes`  (Table 4.2.3.5)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Owning patient | Required |
| vitalReadingId | Reference (vital_readings) | Vitals captured in the same session | Optional (UC14.2) |
| symptoms | Array<Reference(symptom_catalog)> | Symptoms selected by the patient | Embedded array of references small, bounded list per submission (UC14.1) |
| severity | String | mild / moderate / severe | Required |
| outcome | String | monitor_at_home / contact_doctor / seek_emergency_care | Required |
| generatedAt | Timestamp | Submission timestamp | Required |

### `medications`  (Table 4.2.3.6)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Owning patient | Required |
| name | String | Medication name | Required |
| dosage | String | Dosage amount | Required |
| schedule | String | Dose times / frequency | Required |
| adherenceRate | Number | 0–100 computed % | Derived from dose_logs; recomputed on each dose confirmation (FR-5.3) |
| source, prescriptionId, catalogId, prescribedBy | String | D-69: `doctor` when added from a prescription | Doctor-set medicines: the patient may only change `schedule` |

### `dose_logs`  (Table 4.2.3.7)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| medicationId | Reference (medications) | Parent medication | Required |
| scheduledTime | Timestamp | When the dose was scheduled | Required |
| status | String | taken / missed | Required |
| confirmedAt | Timestamp | When the patient confirmed the dose | Optional; present if status = taken |

### `health_records`  (Table 4.2.3.8)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Owning patient | Required |
| fileUrl | String | Firebase Storage reference | Required; path `health_records/{patientId}/{recordId}` (D-58) |
| fileName | String | Original file name (D-58) | Required |
| contentType | String | application/pdf / image/jpeg / image/png (D-58) | Required |
| sizeBytes | Number | File size (D-58) | Required; ≤ 10 MB |
| category | String | lab_result / prescription / imaging / discharge_summary / referral_letter / other (D-58) | Required (UC6.1) |
| uploadedAt | Timestamp | Upload time | Required |
| sharedWithDoctor | Boolean | Whether shared with the assigned doctor | Default: false |
| sharedAt | Timestamp | When sharing was granted | Optional; present once shared (UC6.2) |

### `appointments`  (Table 4.2.3.9)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Booking patient | Required |
| doctorId | Reference (users) | Attending doctor | Optional; null until UC7.3 assignment |
| dateTime | Timestamp | Scheduled date/time | Required |
| status | String | booked / rescheduled / cancelled / completed / no_show (D-56) | Required |
| bookedBy | String | patient / admin / system (D-60) | Optional; absent = patient |

### `clinical_notes`  (Table 4.2.3.10)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Subject patient | Required |
| doctorId | Reference (users) | Authoring doctor | Required |
| content | String | Note text | Required |
| createdAt | Timestamp | Creation time | Required |

### `prescriptions`  (Table 4.2.3.11)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Receiving patient | Required |
| doctorId | Reference (users) | Issuing doctor | Required |
| medicationDetails | String | Prescribed medication details | Required |
| isRecurring | Boolean | Flags a long-term chronic prescription | Default: false (UC13.1) |
| issuedAt | Timestamp | Issue time | Required |
| monthlyPrice | Number | Price of one month's supply in RM, set by the pharmacist (D-66) | Optional; ≥ 2.00; only for older single-text prescriptions (D-69) |
| items | Array | Consolidated prescription (D-69): {catalogId, name, strength, form, dose, frequency, quantity, unitPrice} | Optional; 1-10 items; prices copied from medication_catalog at issue time |

### `care_plans`  (Table 4.2.3.12)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Owning patient | Required, unique one living plan per patient, not a log (UC8.5) |
| doctorId | Reference (users) | Maintaining doctor | Required |
| content | String | Care plan content | Required |
| updatedAt | Timestamp | Last edit time | Required |

### `messages`  (Table 4.2.3.13)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| senderId | Reference (users) | Sending user | Required |
| recipientId | Reference (users) | Receiving user | Required |
| encryptedText | String | End-to-end encrypted message body | Required (NFR-2.1) |
| isFlagged | Boolean | Set when the NLP scan detects a high-risk keyword | Default: false (UC10.3) |
| sentAt | Timestamp | Send time | Required |

### `medication_orders`  (Table 4.2.3.14)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Ordering patient | Required |
| prescriptionId | Reference (prescriptions) | Recurring prescription this order fulfils | Required |
| pharmacistId | Reference (users) | Preparing pharmacist | Optional; null until an order is claimed |
| method | String | self_collection / home_delivery | Required (UC13.3) |
| paymentStatus | String | pending / paid / failed | Required |
| deliveryStatus | String | dispatched / in_transit / delivered / failed | Optional; only applies when method = home_delivery |
| cycleDate | Date | Monthly recurrence date | Required |
| medicationDetails | String | Snapshot of the prescription details (D-66) | Required |
| items | Array | Snapshot of the prescription's items (D-69) | Empty for older orders; amount = sum(quantity x unitPrice) |
| patientName | String | Copied for the pharmacy queue (D-66) | Optional |
| amount | Number | Medicine price in RM, from `prescriptions.monthlyPrice` (D-66) | Null until priced |
| deliveryFee | Number | RM5.00 for home delivery, else 0 (D-66) | Required |
| fulfilmentStatus | String | awaiting_confirmation / skipped / awaiting_payment / preparing / out_of_stock / ready_for_collection / ready_for_delivery / collected / delivered / failed (D-66) | Required |
| deliveryAddress | String | Typed by the patient for home delivery (D-66) | Optional |
| deliveryLat, deliveryLng | Number | Drop-off point from the phone's GPS at confirmation (D-67) | Required for home delivery |
| deliveryPhone | String | Contact number for the courier, typed at confirmation (D-67) | Required for home delivery |
| paymentIntentId | String | Stripe PaymentIntent (or simulated) id (D-66) | Optional |
| courierRef | String | Courier booking id: Lalamove order id, Grab delivery id or simulator GRB-… (D-66, D-68) | Optional |
| trackingUrl | String | Courier's live tracking page (Lalamove share link) (D-68) | Optional |
| stockItemId | Reference (medication_stock) | Stock the units were taken from (D-66) | Optional |
| receiptRecordId | Reference (health_records) | Receipt PDF saved for the patient (D-66) | Optional |
| failureReason | String | Out-of-stock note or delivery failure reason (D-66) | Optional |
| createdAt, confirmedAt, paidAt, readyAt, dispatchedAt, etaAt, reminderSentAt | Timestamp | Order timeline (D-66) | Optional except createdAt |

> D-66: one order per recurring prescription per month, document id `{prescriptionId}_{YYYY-MM}`.
> `method` stays empty until the patient confirms (Ch4 says Required). Written only by FastAPI.

### `audit_logs`  (Table 4.2.3.15)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| userId | Reference (users) | Actor who performed the action | Required |
| action | String | Action performed, e.g. "DEACTIVATE_ACCOUNT" | Required |
| targetType | String | Type of entity affected, e.g. "users", "appointments" | Optional |
| targetId | String | ID of the affected document | Optional |
| details | String | Additional context | Required |
| timestamp | Timestamp | When the action occurred | Required |

### `agent_messages`  (Table 4.2.3.16)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Owning patient | Required |
| role | String | patient / agent | Required distinguishes the patient's message from the Gemini-generated reply |
| text | String | Message content | Required |
| sentAt | Timestamp | Send time | Required |
| kind | String | chat_alert / weekly_summary (D-76) | Optional; absent for ordinary turns |
| doctorId | Reference (users) | The doctor whose chat a chat_alert belongs to (D-76) | Only for chat_alert |

> Persists the AI Health Agent's conversation history (FR-14.1) so Gemini has session context and past exchanges can be reviewed. A separate collection rather than an embedded array, since a 24/7 agent produces an unbounded, ever-growing history per patient.


### `emergency_alerts`  (Table 4.2.3.17)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | Patient whose risk triggered the alert | Required |
| familyMemberId | Reference (users) | Recipient family member | Required |
| riskScoreId | Reference (risk_scores) | Risk score document that triggered the alert | Required for reading/risk triggers; optional for SOS/triage (D-62) |
| gpsLocation | GeoPoint | Patient's location at the time of the alert | Required; null when the phone gave no location (D-62) |
| sentAt | Timestamp | When the alert was sent | Required |
| acknowledgedAt | Timestamp | When the family member opened the alert | Optional |
| trigger | String | emergency_reading / critical_risk / sos / triage (D-62) | Required |
| patientPhone | String | Copied from the health profile for "Call patient" (D-62) | Optional |
| locationUpdatedAt | Timestamp | Last GPS update while the alert is open (D-62) | Optional |

> Records each Critical-level emergency alert (FR-14.2) so it can be retrieved by alertId when the family member opens it, and so acknowledgement can be tracked.


### `symptom_catalog`  (Table 4.2.3.18)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| name | String | Symptom name shown to the patient | Required |
| category | String | Grouping used to organise the symptom picker UI | Required |

> A static reference/lookup collection with no patientId not owned by any patient. Backs the "patient selects symptoms" step of UC14.1 with a controlled vocabulary instead of free text, and is referenced by triage_outcomes.symptoms.


### `payment_transactions`  (Table 4.2.3.19)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| orderId | Reference (medication_orders) | Order this transaction belongs to | Required |
| stripeChargeId | String | Stripe's transaction reference | Required |
| amount | Number | Amount charged | Required |
| status | String | succeeded / failed / refunded | Required |
| processedAt | Timestamp | When Stripe processed the transaction | Required |

> Logs each Stripe charge (FR-13.3) independently of medication_orders.paymentStatus, so refunds and reconciliation have their own auditable history rather than overwriting a single status field.


### `delivery_tracking_events`  (Table 4.2.3.20)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| orderId | Reference (medication_orders) | Order being delivered | Required |
| status | String | dispatched / picked_up / in_transit / delivered / failed | Required |
| location | String | Courier location at this event, if available | Optional |
| timestamp | Timestamp | When this status was recorded | Required |

> Captures the status-over-time history that FR-13.4's "real-time tracking" requires medication_orders.deliveryStatus only reflects the current state, not the trail of updates from the Grab API.


### `medication_catalog`  (D-69, not in Ch4)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Stable seed ids, e.g. `amlodipine-5` |
| name, strength, form, unitLabel | String | Medicine, e.g. Amlodipine / 5mg / tablet | Required |
| drugClass | String | e.g. Calcium channel blocker | Optional |
| unitPrice | Number | RM per unit (indicative demo prices) | Required; edited by pharmacist/admin |
| active | Boolean | Offered to doctors | Default true |
| updatedAt | Timestamp | Last change | Required |

### `pharmacy_messages`  (D-69, not in Ch4)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| patientId | Reference (users) | The conversation (one per patient) | Required |
| senderId | Reference (users) | Patient or pharmacist | Required |
| senderRole | String | patient / pharmacist | Required |
| senderName | String | Shown in the chat | Required |
| text | String | Message | Required; ≤ 2000; not end-to-end encrypted (D-69) |
| sentAt | Timestamp | Send time | Required |

### `conversations`  (D-76, not in Ch4)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | `{uidA}__{uidB}` (sorted) | One chat per pair |
| participantIds | Array | The two users | Required |
| openedBy | Reference (users) | Who started it | Required |
| openedByRole | String | Role of the opener | Required |
| openedByAdmin | Boolean | An admin opened it between two other people | Required |
| createdAt, lastMessageAt | Timestamp | Created / latest message | Required |
| lastText, lastSenderId | String | Inbox preview (≤ 120 chars) | |
| unread | Map | uid -> unread count | Updated by FastAPI |

### `conversation_messages`  (D-76, not in Ch4)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| conversationId | Reference (conversations) | The chat | Required |
| senderId | Reference (users) | Sender | Required |
| senderRole | String | doctor / pharmacist / admin / patient / system | Required |
| senderName | String | Shown in the chat | Required |
| text | String | Message | Required; ≤ 2000; not end-to-end encrypted (D-76) |
| sentAt | Timestamp | Send time | Required |

> Both are read and written only through FastAPI (Security Rules deny client access).

### `notifications`  (D-77, not in Ch4)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| userId | Reference (users) | Owner | Required |
| title, body | String | As pushed | Required |
| type | String | Push data type (message, order, ...) | Optional |
| category | String | messages / alerts / appointments / orders / medication / other | Required |
| data | Map | Push data (ids for opening the right page) | |
| urgent | Boolean | Always kept, whatever bellPrefs say | Required |
| read | Boolean | Opened in the bell | Default false |
| createdAt | Timestamp | Saved at | Required; removed after 30 days |

> Written by the backend Notifier for every push; read only through FastAPI.

### `medication_stock`  (D-66, not in Ch4)

| Field | Type | Description | Constraints / Notes |
|---|---|---|---|
| _id | String | Primary key | Auto-generated |
| name | String | Medicine and strength, e.g. "Amlodipine 5mg" | Required |
| catalogId | Reference (medication_catalog) | Linked catalogue medicine (D-69) | Optional; catalogue orders take stock through it |
| units | Number | Units on hand | Required; ≥ 0; marking an order ready deducts from it |
| expiryDate | Timestamp | Earliest expiry among units on hand | Required |
| lowStockAt | Number | Low-stock warning level | Default 50 |
| updatedAt | Timestamp | Last change | Required |

> Pharmacist and admin read; written only by FastAPI (pharmacist actions).

## Relationships (from class diagram)

- `users` (patient) 1 — 1 `health_profiles`
- patient 1 — * `vital_readings`, `risk_scores`, `triage_outcomes`, `medications`, `health_records`, `appointments`, `agent_messages`, `medication_orders`, `emergency_alerts`
- `medications` 1 — * `dose_logs`
- `triage_outcomes` * — * `symptom_catalog` (embedded array of IDs)
- `triage_outcomes` 0..1 — 1 `vital_readings` (same session)
- doctor 1 — * `clinical_notes`, `prescriptions`, `appointments`; patient 1 — 0..1 `care_plans` (one living plan per patient)
- `prescriptions` 1 — * `medication_orders` (only when `isRecurring = true`)
- `medication_orders` 1 — * `payment_transactions`, `delivery_tracking_events`
- family_member `users.patientId` → patient (each family member monitors one patient; a patient may have many family members)
- `emergency_alerts` → `risk_scores` (trigger), → family member (recipient)
- `messages` sender/recipient → `users`
- `audit_logs.userId` → `users`

## Required composite indexes (create in `firestore.indexes.json`)

| Collection | Fields | Used by |
|---|---|---|
| vital_readings | patientId ASC, timestamp DESC | dashboard, trend charts (FR-4.1) |
| risk_scores | patientId ASC, generatedAt DESC | risk card, trend (FR-4.3), 30-day deterioration (FR-9.6) |
| dose_logs | medicationId ASC, scheduledTime DESC | adherence (FR-5.3) |
| appointments | patientId ASC, dateTime ASC / doctorId ASC, dateTime ASC | patient + doctor schedules |
| messages | senderId ASC, recipientId ASC, sentAt ASC | chat thread |
| agent_messages | patientId ASC, sentAt ASC | AI agent history |
| agent_messages | patientId ASC, kind ASC, sentAt ASC / DESC | D-76 chat alerts, latest weekly summary |
| conversation_messages | conversationId ASC, sentAt DESC | D-76 chat thread |
| notifications | userId ASC, createdAt DESC | D-77 bell |
| users | role ASC, assignedDoctorId ASC | doctor patient list (FR-8.1) |
| users | role ASC, patientId ASC | family members of a patient (FR-14.2) |
| medication_orders | patientId ASC, cycleDate DESC / pharmacistId ASC, paymentStatus ASC | patient orders, pharmacist queue |
| audit_logs | userId ASC, timestamp DESC / action ASC, timestamp DESC | audit log filters (UC11.3) |

## Security Rules summary (Ch4 Table 4.5.3, NFR-2.2)

- Patient: read/write only docs where `patientId == request.auth.uid` (and own `users` doc, minus `role`, `isActive`, `assignedDoctorId`).
- Doctor: read patient-owned docs only where the patient's `users.assignedDoctorId == request.auth.uid`; write `clinical_notes`, `care_plans`, `prescriptions` for those patients.
- Family member: read-only on linked patient's `vital_readings`, `risk_scores` and own `emergency_alerts`; nothing else.
- Pharmacist: read `prescriptions`, `medication_orders`; update order status fields only.
- Admin: read all; write `users` (role, isActive, assignedDoctorId), read `audit_logs`.
- `audit_logs`, `risk_scores`, `payment_transactions`, `delivery_tracking_events`, `emergency_alerts`: **server-only writes** (FastAPI with Admin SDK). Clients never write these.
- `symptom_catalog`: read for any authenticated user; server-only writes (seeded).
- Write Firestore rules unit tests with the emulator for every role.

## Account deletion cascade (UC12.4)

Delete patient-owned: `vital_readings`, `risk_scores`, `medications` (+ `dose_logs`), `health_records` (+ Storage files), `triage_outcomes`, `medication_orders`, `agent_messages`, `health_profiles`. **Retain** doctor-authored `clinical_notes`, `prescriptions`, `care_plans`, and `audit_logs`. Set `users.isActive = false` first, then delete in a backend job. Warn and cancel active recurring prescriptions first (UC12.4 E1). Offer data export first (UC12.3).
