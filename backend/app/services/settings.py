"""Module 12 settings: profile edits, export and account deletion (FR-12.1, FR-12.2; UC12.1-12.4;
docs/04 "Deletion cascade"; D-16, D-45, D-46, D-47)."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore

DELETION_GRACE = timedelta(days=7)  # D-46

# docs/04 deletion cascade: patient-owned collections (by patientId). dose_logs follow their
# medications; health_profiles is keyed by uid. Retained: clinical_notes, prescriptions,
# care_plans, audit_logs (plus messages and clinical_alerts, D-46).
PATIENT_OWNED = (
    Collection.VITAL_READINGS,
    Collection.RISK_SCORES,
    Collection.MEDICATIONS,
    Collection.HEALTH_RECORDS,
    Collection.TRIAGE_OUTCOMES,
    Collection.MEDICATION_ORDERS,
    Collection.AGENT_MESSAGES,
)

# What the export contains (D-47), in the order shown in the PDF.
EXPORT_SECTIONS = (
    ("vital_readings", "Blood pressure readings"),
    ("risk_scores", "Risk scores"),
    ("medications", "Medications"),
    ("dose_logs", "Dose history"),
    ("triage_outcomes", "Symptom checks"),
    ("prescriptions", "Prescriptions"),
    ("clinical_notes", "Clinical notes"),
)


def parse_profile_field(raw: object) -> dict[str, Any]:
    """D-25: each health_profiles field is a JSON object stored as a String."""
    if isinstance(raw, dict):
        return dict(raw)
    if isinstance(raw, str) and raw:
        try:
            value = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        return value if isinstance(value, dict) else {}
    return {}


class SettingsRepository(Protocol):
    def user(self, uid: str) -> dict[str, Any] | None: ...

    def health_profile(self, uid: str) -> dict[str, Any] | None: ...

    def update_user(self, uid: str, data: dict[str, Any]) -> None: ...

    def update_health_profile(self, uid: str, data: dict[str, str]) -> None: ...

    def export_records(self, uid: str) -> dict[str, list[dict[str, Any]]]:
        """Every exported collection's documents for this patient (D-47)."""
        ...

    def care_plan(self, uid: str) -> dict[str, Any] | None: ...

    def recurring_prescriptions(self, uid: str) -> list[dict[str, Any]]: ...

    def due_deletions(self, requested_before: datetime) -> list[str]: ...

    def purge(self, uid: str) -> int:
        """Run the docs/04 cascade; returns the number of documents deleted."""
        ...


class FirestoreSettingsRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _col(self, c: Collection) -> Any:
        return self._db.collection(c.value)

    def _mine(self, c: Collection, uid: str) -> Any:
        return self._col(c).where(filter=firestore.FieldFilter("patientId", "==", uid))

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._col(Collection.USERS).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def health_profile(self, uid: str) -> dict[str, Any] | None:
        snap = self._col(Collection.HEALTH_PROFILES).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def update_user(self, uid: str, data: dict[str, Any]) -> None:
        self._col(Collection.USERS).document(uid).update(
            {**data, "updatedAt": firestore.SERVER_TIMESTAMP}
        )

    def update_health_profile(self, uid: str, data: dict[str, str]) -> None:
        self._col(Collection.HEALTH_PROFILES).document(uid).set(
            {**data, "patientId": uid}, merge=True
        )

    def export_records(self, uid: str) -> dict[str, list[dict[str, Any]]]:
        out: dict[str, list[dict[str, Any]]] = {}
        for c in (
            Collection.VITAL_READINGS,
            Collection.RISK_SCORES,
            Collection.MEDICATIONS,
            Collection.TRIAGE_OUTCOMES,
            Collection.PRESCRIPTIONS,
            Collection.CLINICAL_NOTES,
        ):
            out[c.value] = [{"id": d.id, **d.to_dict()} for d in self._mine(c, uid).stream()]
        logs: list[dict[str, Any]] = []
        for med in out[Collection.MEDICATIONS.value]:
            q = self._col(Collection.DOSE_LOGS).where(
                filter=firestore.FieldFilter("medicationId", "==", med["id"])
            )
            logs += [{"id": d.id, **d.to_dict()} for d in q.stream()]
        out[Collection.DOSE_LOGS.value] = logs
        return out

    def care_plan(self, uid: str) -> dict[str, Any] | None:
        snap = self._col(Collection.CARE_PLANS).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def recurring_prescriptions(self, uid: str) -> list[dict[str, Any]]:
        q = self._mine(Collection.PRESCRIPTIONS, uid).where(
            filter=firestore.FieldFilter("isRecurring", "==", True)
        )
        return [{"id": d.id, **d.to_dict()} for d in q.stream()]

    def due_deletions(self, requested_before: datetime) -> list[str]:
        q = self._col(Collection.USERS).where(
            filter=firestore.FieldFilter("deletionRequestedAt", "<=", requested_before)
        )
        return [d.id for d in q.stream()]

    def _delete_all(self, refs: list[Any]) -> int:
        for i in range(0, len(refs), 400):  # Firestore batches hold up to 500 writes
            batch = self._db.batch()
            for ref in refs[i : i + 400]:
                batch.delete(ref)
            batch.commit()
        return len(refs)

    def purge(self, uid: str) -> int:
        refs: list[Any] = []
        med_ids = [d.id for d in self._mine(Collection.MEDICATIONS, uid).stream()]
        for med_id in med_ids:
            q = self._col(Collection.DOSE_LOGS).where(
                filter=firestore.FieldFilter("medicationId", "==", med_id)
            )
            refs += [d.reference for d in q.stream()]
        for c in PATIENT_OWNED:
            refs += [d.reference for d in self._mine(c, uid).stream()]
        user_ref = self._col(Collection.USERS).document(uid)
        refs += [d.reference for d in user_ref.collection("fcmTokens").stream()]
        refs.append(self._col(Collection.HEALTH_PROFILES).document(uid))
        # UC12.4 E1: retained prescriptions stop renewing.
        for p in self.recurring_prescriptions(uid):
            self._col(Collection.PRESCRIPTIONS).document(p["id"]).update({"isRecurring": False})
        # docs/04: health_records go with their Storage files (D-58).
        from app.services.records import get_file_store

        get_file_store().delete_prefix(f"health_records/{uid}/")
        refs.append(user_ref)  # last, so a failed purge is retried by the next daily run
        return self._delete_all(refs)


def get_settings_repository() -> SettingsRepository:
    return FirestoreSettingsRepository(get_firestore())


# ---------------- export (D-47) ----------------


def _plain(value: Any) -> Any:
    """Firestore values -> JSON-safe values."""
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, dict):
        return {k: _plain(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_plain(v) for v in value]
    return value


def build_export(
    user: dict[str, Any],
    profile: dict[str, Any] | None,
    records: dict[str, list[dict[str, Any]]],
    care_plan: dict[str, Any] | None,
    now: datetime,
) -> dict[str, Any]:
    keep = ("name", "email", "icNumber", "dateOfBirth", "gender", "createdAt")
    data: dict[str, Any] = _plain(
        {
            "exportedAt": now,
            "profile": {k: user.get(k) for k in keep if user.get(k) is not None},
            "healthProfile": {
                k: parse_profile_field((profile or {}).get(k))
                for k in ("personalInfo", "medicalHistory", "lifestyleFactors")
            },
            "carePlan": (
                {"content": care_plan.get("content"), "updatedAt": care_plan.get("updatedAt")}
                if care_plan
                else None
            ),
            **{key: records.get(key, []) for key, _ in EXPORT_SECTIONS},
            "note": "Messages are end-to-end encrypted and are not included.",
        }
    )
    return data


# arrow, bullet, en dash, em dash -> ASCII
_LATIN1_SUBS = {0x2192: "->", 0x2022: "-", 0x2013: "-", 0x2014: "-"}


def _latin1(text: object) -> str:
    """fpdf2 core fonts are Latin-1; replace anything else."""
    return str(text).translate(_LATIN1_SUBS).encode("latin-1", "replace").decode("latin-1")


_MYT = timedelta(hours=8)
_RISK_NAMES = {
    "stroke": "Stroke",
    "cad": "Heart disease",
    "heartFailure": "Heart failure",
    "ckd": "Kidney disease",
    "t2d": "Diabetes",
}


def _when(value: object, with_time: bool = True) -> str:
    """ISO UTC text -> Malaysia time 'YYYY-MM-DD HH:MM' (the exports are read in Malaysia)."""
    try:
        moment = datetime.fromisoformat(str(value))
    except ValueError:
        return str(value or "")
    if moment.tzinfo is not None:
        moment = moment.astimezone(UTC) + _MYT
    return moment.strftime("%Y-%m-%d %H:%M" if with_time else "%Y-%m-%d")


def _words(value: object) -> str:
    if isinstance(value, list):
        return ", ".join(_words(v) for v in value) or "None"
    if value is None or value == "":
        return "-"
    return str(value).replace("_", " ")


def _health_lines(health: dict[str, dict[str, Any]]) -> list[str]:
    p, h, life = (
        health.get(k) or {} for k in ("personalInfo", "medicalHistory", "lifestyleFactors")
    )
    ec = p.get("emergencyContact") or {}
    contact = f"{ec.get('name')} ({ec.get('relationship')}), {ec.get('phone')}" if ec else "-"
    return [
        f"Height: {_words(p.get('heightCm'))} cm    Weight: {_words(p.get('weightKg'))} kg",
        f"Phone: {_words(p.get('phone'))}",
        f"Emergency contact: {contact}",
        f"Year diagnosed with high blood pressure: {_words(h.get('hypertensionDiagnosedYear'))}",
        f"Conditions: {_words(h.get('conditions', []))}",
        f"Family history: {_words(h.get('familyHistory', []))}",
        f"Allergies: {_words(h.get('allergies'))}",
        f"Smoking: {_words(life.get('smokingStatus'))}    Alcohol: {_words(life.get('alcohol'))}",
        f"Exercise days per week: {_words(life.get('exerciseDaysPerWeek'))}    "
        f"Salt intake: {_words(life.get('saltIntake'))}",
    ]


def _row(key: str, r: dict[str, Any]) -> str:
    match key:
        case "vital_readings":
            hr = f", HR {r['heartRate']} (estimate)" if r.get("heartRate") else ""
            bp = f"{r.get('systolic')}/{r.get('diastolic')} mmHg"
            return f"{_when(r.get('timestamp'))}  {bp}{hr}"
        case "risk_scores":
            scores = r.get("scores") or {}
            parts = [
                f"{_RISK_NAMES.get(k, k)} {float(v.get('value', 0)) * 100:.1f}%"
                for k, v in scores.items()
                if isinstance(v, dict)
            ]
            return f"{_when(r.get('generatedAt'))}  " + ", ".join(parts)
        case "medications":
            return f"{r.get('name')} {r.get('dosage')}  ({r.get('schedule')})"
        case "dose_logs":
            return f"{_when(r.get('scheduledTime'))}  {r.get('status')}"
        case "triage_outcomes":
            return f"{_when(r.get('generatedAt'))}  {_words(r.get('outcome'))}"
        case "prescriptions":
            return f"{_when(r.get('issuedAt'), False)}  {r.get('medicationDetails')}"
        case "clinical_notes":
            return f"{_when(r.get('createdAt'), False)}  {r.get('content')}"
    return json.dumps(r)


def export_pdf(data: dict[str, Any]) -> bytes:
    from fpdf import FPDF

    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.add_page()
    width = pdf.epw

    def line(text: object, size: int = 10, style: str = "") -> None:
        pdf.set_font("Helvetica", style, size)
        # Start every line back at the left margin (fpdf2 otherwise continues to the right).
        pdf.multi_cell(width, 5 if size <= 10 else 8, _latin1(text), new_x="LMARGIN", new_y="NEXT")

    line("CareFlow health data export", 16, "B")
    line(f"Exported {_when(data['exportedAt'])} (Malaysia time)")
    pdf.ln(3)
    profile = data["profile"]
    line("Profile", 13, "B")
    line(f"Name: {_words(profile.get('name'))}")
    line(f"Email: {_words(profile.get('email'))}")
    line(f"IC number: {profile.get('icNumber') or '-'}")
    dob = profile.get("dateOfBirth")
    line(f"Date of birth: {_when(dob, False) if dob else '-'}")
    line(f"Gender: {_words(profile.get('gender'))}")
    pdf.ln(2)
    line("Health profile", 13, "B")
    for text in _health_lines(data["healthProfile"]):
        line(text)
    if data.get("carePlan"):
        pdf.ln(2)
        line("Care plan", 13, "B")
        line(data["carePlan"].get("content") or "")
    for key, title in EXPORT_SECTIONS:
        rows = data.get(key) or []
        pdf.ln(2)
        line(f"{title} ({len(rows)})", 13, "B")
        for r in rows:
            line(_row(key, r), 9)
    pdf.ln(3)
    line(data["note"], 9, "I")
    line("This export is a copy of your records, not medical advice.", 9, "I")
    return bytes(pdf.output())


def now_utc() -> datetime:
    return datetime.now(UTC)
