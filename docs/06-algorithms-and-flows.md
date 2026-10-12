# 06 — Algorithms and Key Flows

Sources: Ch4 §4.5.1 (pseudocode A–D, authoritative) and `source/hypertension_app_reference.md` (thresholds, classifier, emergency flow, AI agent behaviour, recurring flow). Sequence diagrams for each flow are in `figures/ch4-figure-4-1-1-*.png`.

---

## A. Disease Risk Prediction — FR-9.1–9.3 (Ch4 §4.5.1 A)

```
INPUT: patientId
1. profile ← fetch HealthProfile, latest VitalReading(s), Medication list for patientId
2. inputVector ← assemble twelve input variables:
     age, gender, systolic, diastolic, heart rate, BMI, smoking status,
     family history, existing conditions, medication count, adherence rate,
     days since last reading
3. FOR EACH complication IN {Stroke, CAD, HeartFailure, CKD, T2D}:
     rfScore  ← RandomForest[complication].predict_proba(inputVector)
     xgbScore ← XGBoost[complication].predict_proba(inputVector)
     score    ← rfScore IF AUC(RF[complication]) > AUC(XGB[complication]) ELSE xgbScore
     riskLevel ← categorise(score)   // Low / Moderate / High / Critical, fixed thresholds
   SAVE one risk_scores doc: scores = { stroke:{value,level}, cad:{…}, heartFailure:{…}, ckd:{…}, t2d:{…} },
        modelUsed (e.g. "stroke:XGBoost v1; cad:RandomForest v1; …"), generatedAt
4. IF any riskLevel IN {High, Critical}: trigger escalation (UC9.2 / UC9.3)
```

Implementation notes:
- Triggered after every new vital reading or symptom-checker submission (UC9.1), and after relevant health-profile edits (UC12.2).
- **Missing inputs:** use the last known value and flag reduced confidence (UC9.1 E1). Store `lowConfidence: true` only if added to the data dictionary (D-03). Otherwise return the flag in the API response only.
- **Cut-points are fixed.** They are calibrated during training, saved in `ml/artifacts/thresholds.json`, and not changeable at runtime.
- **Minimum data:** the UI shows the risk assessment only after **≥ 3 readings** (Ch4 Figs 4.3.3.1 and 4.3.4.2, empty states).
- **Overall level** for the patient (used for the doctor's risk filter, FR-8.1) = the highest level across the 5 complications. Compute it at read time (D-03).
- **Performance:** load the models once at FastAPI startup; inference must take < 3 s (NFR-1.2).

### Training (`ml/`)

| Complication | Dataset (from reference md) |
|---|---|
| CAD / Coronary Heart Disease | Framingham Heart Study (Kaggle, aasheesh200) |
| Type 2 Diabetes | Pima Indians Diabetes Database (Kaggle/UCI) |
| Stroke | Stroke Prediction Dataset (Kaggle, fedesoriano) |
| Heart Failure | Heart Failure Clinical Data (Kaggle, andrewmvd) |
| CKD | Chronic Kidney Disease (Kaggle, mansoordaku) |

- Train an RF model and an XGB model per complication. Use a stratified train/test split and 5-fold CV. Report **AUC-ROC per model**. Objective 2 requires **≥ 0.80** for each complication's selected model.
- Save `ml/artifacts/{complication}_{rf|xgb}.joblib`, `metrics.json` (AUC per model), `thresholds.json`, and `feature_map.json`.
- **Known issue (D-04):** each dataset has different columns, and none contains all 12 variables. `feature_map.json` must map the platform's 12 inputs to each model's actual features and document defaults for features the platform doesn't collect. Write this mapping up honestly; it goes into Chapter 5.
- Produce a `ml/REPORT.md` with the metrics table, ROC curves and the feature mapping. This feeds Chapter 5.

---

## B. Heart Rate via Camera PPG — FR-3.2, UC3.3 / UC14.2 (Ch4 §4.5.1 B)

```
INPUT: 10-second video frame stream from rear camera with fingertip covering the lens (torch ON)
1. FOR EACH frame: extract mean green-channel pixel intensity
2. Band-pass filter 0.67–3.3 Hz (40–200 bpm)
3. Peak detection on the filtered signal
4. bpm ← (peak count / capture duration) × 60
5. IF signal-to-noise ratio too low: return CAPTURE_FAILED (prompt retry / skip)
   ELSE return bpm
```

- Run the processing in a Dart `Isolate`. Show a progress ring and a live signal trace.
- Use the YUV420 Y/U/V planes from the `camera` image stream converted to green intensity, or the green channel when the format is BGRA.
- Unit-test the signal pipeline with synthetic sine waves at known BPM (e.g. 60/90/120 bpm ± noise). This supports Objective 1's "verified through unit testing".
- Label the result "estimate" in the UI (Ch1 limitation).

---

## C. Medication Adherence Rate — FR-5.3 (Ch4 §4.5.1 C)

```
INPUT: medicationId
1. logs ← all dose_logs for medicationId within rolling window (default 30 days)
2. adherenceRate ← (COUNT(status = taken) / COUNT(*)) × 100
3. UPDATE medications.adherenceRate
```

Recompute whenever a `dose_logs` entry is written, either on confirmation or when the missed-dose job runs (UC5.4). Do not recompute on dashboard reads. If there are no logs, leave it null and show an empty state (UC5.5 E1).

Supporting rules:
- **Missed dose (UC5.4):** if a scheduled dose isn't confirmed within the window (default 2 h after `scheduledTime`), the job writes `status: missed`.
- **Refill alert (UC5.2):** remaining supply = starting quantity − taken doses. Alert when supply drops below the threshold (default 7 days of supply). This needs a quantity field (D-05).
- **Drug interaction (UC5.6, UC8.4 E1):** check the new medication against the current list using a small static interaction table in `backend/app/services/interactions.json` (common antihypertensive pairs, e.g. ACE inhibitor + potassium-sparing diuretic, ACE inhibitor + ARB). Severity is `minor | major | critical`. If critical, block the save until the user acknowledges it.

---

## D. Symptom Checker Triage — FR-14.3 (Ch4 §4.5.1 D)

```
INPUT: selected symptoms, severity, patientId
1. vitals ← most recent vital_readings entry (captured this session, per UC14.2)
2. riskScore ← most recent risk_scores document for patientId
3. outcome ← classify(symptoms, severity, vitals, riskScore) against fixed clinical thresholds
4. SAVE triage_outcomes(patientId, vitals._id, symptoms, severity, outcome)
5. IF outcome IN {contact_doctor, seek_emergency_care}: notify assigned doctor (UC14.4)
```

### `classify()`: fixed rule table (thresholds from the reference md; confirm in D-10)

Evaluate top-down; the first match wins.

| Rule | Outcome |
|---|---|
| Systolic ≥ 180 **or** diastolic ≥ 120 | `seek_emergency_care` |
| Severity = severe **and** (any red-flag symptom **or** systolic ≥ 160) | `seek_emergency_care` |
| Any red-flag symptom (chest pain, shortness of breath, sudden weakness/numbness, confusion/difficulty speaking, vision loss, severe headache) | `seek_emergency_care` |
| Systolic 140–179 **or** diastolic 90–119 | `contact_doctor` |
| Severity = moderate **or** any complication risk level ∈ {High, Critical} | `contact_doctor` |
| Heart rate > 120 or < 45 (if captured) | `contact_doctor` |
| Otherwise | `monitor_at_home` |

- Red-flag symptoms are marked `isRedFlag` in the seeded `symptom_catalog` (D-10).
- If PPG fails, proceed without heart rate and note it (UC14.1 E1).
- On **Emergency**, also do the following (UC14.4 step 3): auto-book an emergency appointment, reassigning to the next available doctor if the assigned one is unavailable; send a family alert (UC15.2); and unlock one-tap call on the patient app.
- The result screen shows the outcome, the reported critical symptoms, numbered immediate actions, and a disclaimer (Fig 4.3.8.2).
- **Unit-test every rule row and boundary** (179/180, 139/140, 119/120). Objective 1 requires the thresholds to be verified by unit tests.

---

## E. BP Classification and Threshold Alerts — FR-9.1

`core/utils/bp_classifier.dart`, with a Python mirror in `backend/app/services/bp.py`. The **same table on both sides is unit-tested** against shared fixtures (`docs/fixtures/bp_cases.json`, which you create).

| Category | Rule (first match, top-down) | Label | Colour |
|---|---|---|---|
| crisis | sys ≥ 180 or dia ≥ 120 | Hypertensive Crisis | `#A32D2D` |
| stage2 | sys ≥ 140 or dia ≥ 90 | High — Stage 2 | `#E24B4A` |
| stage1 | sys ≥ 130 or dia ≥ 80 | High — Stage 1 | `#D85A30` |
| elevated | sys ≥ 120 and dia < 80 | Elevated | `#EF9F27` |
| normal | otherwise | Normal | `#1D9E75` |

**Plausible range validation** (UC3.1 E1): systolic 70–250, diastolic 40–150, systolic > diastolic. Otherwise reject with `READING_OUT_OF_RANGE`.

**Threshold alert levels** (Ch1 §1.4.1, Objective 1) and their actions (reference md):

| Alert | BP band | System actions |
|---|---|---|
| **Mild** | sys 130–139 / dia 80–89 | Notify patient. Email BP report to the assigned doctor (SendGrid). Offer optional booking. Escalate to Moderate if the next reading is still abnormal. |
| **Moderate** | sys 140–179 / dia 90–119 | Urgent FCM to the doctor with BP, HR, symptoms and risk. Show the Book Appointment button. Notify family. AI agent advises avoiding exertion. Escalate to Emergency if the doctor hasn't responded within the timeout (default 2 h). |
| **Emergency** | sys ≥ 180 / dia ≥ 120 | Auto-book an emergency appointment (reassign if needed). Notify the doctor immediately with the vitals history. Flag the patient as Emergency on the doctor list. Send family a GPS alert via FCM + Twilio SMS. Activate one-tap call on the patient dashboard. AI agent sends a calm reassurance message. Log the event to the patient record. |

---

## F. Escalation and Emergency Alert — FR-9.5, FR-9.6, FR-14.2 (UC9.2, UC9.3, UC15.2, UC15.3)

Triggered when a reading is classified `crisis`, **or** any complication level is `Critical`, **or** triage = `seek_emergency_care`, **or** the patient presses SOS. Steps:

1. FCM to the patient device (emergency banner + action buttons).
2. Get the patient's GPS via geolocator. The patient app sends its location with the reading or SOS request.
3. For each family member (`users` where `role == family_member && patientId == patient`), create an `emergency_alerts` doc (`riskScoreId`, `gpsLocation`, `sentAt`). Send FCM with `alertId` + GPS, and Twilio SMS. If there are no family members, log it and rely on doctor escalation (UC15.2 E1).
4. Notify the assigned doctor. The patient appears flagged at the top of the doctor's list in real time through a Firestore listener.
5. `audit_logs` entry.

**Family side (UC15.3):** opening the alert shows the triggering reading, the last known location on a Google Map, a one-tap **call patient** / **call 999** button (Malaysia emergency number), and **Acknowledge**, which sets `acknowledgedAt`.

- **30-day deterioration (FR-9.6):** a daily job runs a linear regression of each complication score over the last 30 days. If the slope is above the threshold and the latest score is higher than 30 days ago, alert the doctor.
- **Medication review flag (UC9.3 step 4):** raised when the risk rises significantly.

---

## G. AI Health Agent — FR-14.1 (UC2.6, UC2.7; sequence Fig 4.1.1.16)

- Never call Gemini directly from Flutter. All calls go through `POST /api/v1/agent/chat`.
- FastAPI builds the system prompt from:
  - the last 7 days of BP readings
  - the latest risk scores and levels
  - active medications and adherence rate
  - upcoming appointments
  - a medical history summary
  - the last N `agent_messages` for session context
- Persist both the patient's message and the reply to `agent_messages` (`role: patient | agent`).
- Guardrails:
  - plain language
  - no diagnosis or dosage changes
  - always suggest contacting the care team for anything serious
  - emergency wording → instruct the patient to call 999 and surface the SOS action
  - disclaimer shown in the UI
- **On API failure or timeout:** show a fallback message and suggest contacting the care team (UC2.6 E1).

**Proactive update after each vital entry (UC2.7):**

| Risk level | Agent response + action buttons |
|---|---|
| Low / Moderate | Status explanation + health tips |
| High | Explanation + **Book Appointment** + **View Medications** |
| Critical | Emergency instructions + **Book Emergency Appointment** + **Call Emergency Contact** + **Alert Family** |

---

## H. NLP Message Escalation — FR-10.3, FR-14.4 (UC10.1, UC10.3)

- Rule-based keyword and phrase list, e.g. "chest pain", "severe headache", "can't breathe", "shortness of breath", "fainted", "numbness", "blurred vision", "severe dizziness". Keep it in a shared JSON file so Dart and Python stay identical.
- Use simple negation handling ("no longer have chest pain") to reduce false positives. Document the residual false positives honestly (Ch1 limitation).
- **Where to scan:** because messages are E2E encrypted (NFR-2.1), the server can't read them. The **sending client scans the plaintext before encrypting**, sets `isFlagged`, and calls the escalate path. The doctor's client also re-scans after decrypting, for defence in depth (D-09).
- If flagged, FCM goes to the doctor with high priority. The patient sees the red banner from Fig 4.3.15.3. The doctor can dismiss a false positive (UC10.3 E1).

## I. End-to-end message encryption — NFR-2.1

- Each user generates an X25519 key pair on first login (`cryptography` package).
- The private key is kept in `flutter_secure_storage`. The public key is published to `users/{uid}/publicKey` (D-07).
- Per-conversation shared key = X25519 → HKDF → AES-256-GCM. Store `encryptedText` as base64 (nonce + ciphertext + tag).
- **Web portal:** keep the private key in IndexedDB via the same package. Document that it is lost if browser storage is cleared. This is an acceptable proof-of-concept limitation; note it in Chapter 5.

---

## J. Recurring Medication, Payment & Delivery — FR-13.x (UC13.1–13.6; sequence Fig 4.1.1.13)

1. The doctor toggles **recurring** on a prescription (`prescriptions.isRecurring = true`) (UC13.1).
2. A monthly job creates a `medication_orders` doc (`paymentStatus: pending`, `cycleDate`) and sends FCM "Confirm this month's order" (UC13.2).
   - **Skip:** pause until the next cycle.
   - **No response:** follow-up reminder after 48 h.
3. The patient reviews the order (itemised cost) and picks `self_collection` or `home_delivery` (UC13.3).
4. Pay with Stripe PaymentSheet: FastAPI creates a PaymentIntent, and the Stripe webhook writes `payment_transactions` and sets `paymentStatus: paid`. On decline, allow a retry with another method (UC13.3 E1). Store the receipt in health records.
5. The pharmacist is notified, prepares the order, and marks it Ready for Collection or Ready for Delivery (UC13.6). If out of stock, flag it to the admin and notify the patient of the delay (UC13.6 E1).
6. **Self-collection:** generate a collection slip (prescription ID + ready time).
7. **Home delivery:** dispatch via Grab (UC13.4). Each Grab webhook appends a `delivery_tracking_events` entry and updates `medication_orders.deliveryStatus`. The patient sees a 4-stage timeline: Order Confirmed → Preparing → Out for Delivery → Delivered (Fig 4.3.10.3), plus FCM at each stage (UC13.5).
8. **If dispatch or delivery fails:** retry, then prompt the patient to reschedule or switch to self-collection (FR-13.5).
9. The cycle repeats the next month.
