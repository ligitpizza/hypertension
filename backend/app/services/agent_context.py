"""Patient context for the AI Health Agent (FR-14.1; UC2.6 step 2; docs/06 §G).

Each context section is one small function reading one kind of data. Sections whose
module is not built yet (medications: Module 5, appointments: Module 7) simply say
"none recorded" and fill in automatically once those modules write data. To give the
agent a new kind of data, add a section function to SECTIONS.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta, timezone
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore
from app.integrations.gemini import Turn
from app.ml.risk_inputs import existing_conditions, profile_json
from app.services.bp import classify

log = logging.getLogger("careflow.agent")

MYT = timezone(timedelta(hours=8), "MYT")  # Malaysia has no daylight saving
READINGS_WINDOW = timedelta(days=7)
HISTORY_TURNS = 10

COMPLICATION_NAMES = {
    "stroke": "stroke",
    "cad": "coronary artery disease",
    "heartFailure": "heart failure",
    "ckd": "chronic kidney disease",
    "t2d": "type 2 diabetes",
}


# D-40: plain-language names for model inputs (contributing factors).
FACTOR_NAMES = {
    "age": "age",
    "female": "sex",
    "systolic": "systolic (top) blood pressure",
    "diastolic": "diastolic (bottom) blood pressure",
    "heart_rate": "heart rate",
    "bmi": "body weight (BMI)",
    "smoking": "smoking",
    "family_history": "family history of heart disease or diabetes",
    "hypertension": "high blood pressure (diagnosed or recent readings)",
    "high_cholesterol": "high cholesterol",
    "bp_medication": "taking blood pressure medicine",
    "medication_count": "number of medicines",
    "stroke": "previous stroke",
    "cad": "existing coronary artery disease",
    "heartFailure": "existing heart failure",
    "ckd": "existing kidney disease",
    "t2d": "existing diabetes",
}


class AgentDataRepository(Protocol):
    def user(self, uid: str) -> dict[str, Any] | None: ...

    def health_profile(self, uid: str) -> dict[str, Any] | None: ...

    def readings_since(self, uid: str, since: datetime) -> list[dict[str, Any]]:
        """Newest first."""
        ...

    def latest_risk(self, uid: str) -> dict[str, Any] | None: ...

    def medications(self, uid: str) -> list[dict[str, Any]]: ...

    def upcoming_appointments(self, uid: str, now: datetime) -> list[dict[str, Any]]: ...

    def care_plan(self, uid: str) -> dict[str, Any] | None: ...

    def recent_prescriptions(self, uid: str, limit: int) -> list[dict[str, Any]]: ...

    def recent_turns(self, uid: str, limit: int) -> list[Turn]:
        """Oldest first."""
        ...

    def add_message(self, uid: str, role: str, text: str) -> str: ...


class FirestoreAgentDataRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _where(self, collection: Collection, uid: str) -> Any:
        return self._db.collection(collection.value).where(
            filter=firestore.FieldFilter("patientId", "==", uid)
        )

    def _doc(self, collection: Collection, doc_id: str) -> dict[str, Any] | None:
        snap = self._db.collection(collection.value).document(doc_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._doc(Collection.USERS, uid)

    def health_profile(self, uid: str) -> dict[str, Any] | None:
        return self._doc(Collection.HEALTH_PROFILES, uid)

    def readings_since(self, uid: str, since: datetime) -> list[dict[str, Any]]:
        query = (
            self._where(Collection.VITAL_READINGS, uid)
            .where(filter=firestore.FieldFilter("timestamp", ">=", since))
            .order_by("timestamp", direction=firestore.Query.DESCENDING)
            .limit(50)
        )
        return [dict(d.to_dict()) for d in query.stream()]

    def latest_risk(self, uid: str) -> dict[str, Any] | None:
        query = (
            self._where(Collection.RISK_SCORES, uid)
            .order_by("generatedAt", direction=firestore.Query.DESCENDING)
            .limit(1)
        )
        return next((dict(d.to_dict()) for d in query.stream()), None)

    def medications(self, uid: str) -> list[dict[str, Any]]:
        return [dict(d.to_dict()) for d in self._where(Collection.MEDICATIONS, uid).stream()]

    def upcoming_appointments(self, uid: str, now: datetime) -> list[dict[str, Any]]:
        query = (
            self._where(Collection.APPOINTMENTS, uid)
            .where(filter=firestore.FieldFilter("dateTime", ">=", now))
            .order_by("dateTime")
            .limit(3)
        )
        return [dict(d.to_dict()) for d in query.stream()]

    def care_plan(self, uid: str) -> dict[str, Any] | None:
        return self._doc(Collection.CARE_PLANS, uid)

    def recent_prescriptions(self, uid: str, limit: int) -> list[dict[str, Any]]:
        query = (
            self._where(Collection.PRESCRIPTIONS, uid)
            .order_by("issuedAt", direction=firestore.Query.DESCENDING)
            .limit(limit)
        )
        return [dict(d.to_dict()) for d in query.stream()]

    def recent_turns(self, uid: str, limit: int) -> list[Turn]:
        query = (
            self._where(Collection.AGENT_MESSAGES, uid)
            .order_by("sentAt", direction=firestore.Query.DESCENDING)
            .limit(limit)
        )
        rows = [d.to_dict() for d in query.stream()]
        return [Turn(r["role"], r["text"]) for r in reversed(rows)]

    def add_message(self, uid: str, role: str, text: str) -> str:
        _, ref = self._db.collection(Collection.AGENT_MESSAGES.value).add(
            {"patientId": uid, "role": role, "text": text, "sentAt": firestore.SERVER_TIMESTAMP}
        )
        return str(ref.id)


def get_agent_data_repository() -> AgentDataRepository:
    return FirestoreAgentDataRepository(get_firestore())


# ---------------- sections ----------------


def _when(value: Any) -> str:
    if isinstance(value, datetime):
        t = value if value.tzinfo else value.replace(tzinfo=UTC)
        return t.astimezone(MYT).strftime("%a %d %b %Y, %I:%M %p")
    return "unknown time"


@dataclass(frozen=True)
class Ctx:
    repo: AgentDataRepository
    uid: str
    now: datetime


def section_about(c: Ctx) -> str:
    user = c.repo.user(c.uid) or {}
    parts = [f"Name: {user.get('name') or 'the patient'}"]
    dob = user.get("dateOfBirth")
    if isinstance(dob, datetime):
        age = c.now.year - dob.year - ((c.now.month, c.now.day) < (dob.month, dob.day))
        parts.append(f"age {age}")
    if user.get("gender"):
        parts.append(str(user["gender"]))
    return "PATIENT: " + ", ".join(parts)


def section_history(c: Ctx) -> str:
    profile = c.repo.health_profile(c.uid)
    if not profile:
        return "MEDICAL HISTORY: not provided."
    history = profile_json(profile, "medicalHistory")
    lifestyle = profile_json(profile, "lifestyleFactors")
    lines = []
    conditions = existing_conditions(profile)
    lines.append("conditions: " + (", ".join(conditions) if conditions else "none reported"))
    if history.get("hypertensionDiagnosedYear"):
        lines.append(f"hypertension diagnosed in {history['hypertensionDiagnosedYear']}")
    if history.get("familyHistory"):
        lines.append("family history: " + ", ".join(map(str, history["familyHistory"])))
    if history.get("allergies"):
        lines.append(f"allergies: {history['allergies']}")
    for key, label in (
        ("smokingStatus", "smoking"),
        ("alcohol", "alcohol"),
        ("exerciseDaysPerWeek", "exercise days per week"),
        ("saltIntake", "salt intake"),
    ):
        if lifestyle.get(key) is not None:
            lines.append(f"{label}: {lifestyle[key]}")
    return "MEDICAL HISTORY: " + "; ".join(lines)


def section_readings(c: Ctx) -> str:
    rows = c.repo.readings_since(c.uid, c.now - READINGS_WINDOW)
    if not rows:
        return "BLOOD PRESSURE (last 7 days): no readings."
    lines = []
    for r in rows:
        category = classify(int(r["systolic"]), int(r["diastolic"])).value
        hr = f", heart rate {r['heartRate']} bpm (camera estimate)" if r.get("heartRate") else ""
        lines.append(
            f"- {_when(r.get('timestamp'))}: {r['systolic']}/{r['diastolic']} mmHg ({category}){hr}"
        )
    return "BLOOD PRESSURE (last 7 days, newest first):\n" + "\n".join(lines)


def section_risk(c: Ctx) -> str:
    risk = c.repo.latest_risk(c.uid)
    if not risk:
        return "RISK ASSESSMENT: none yet (needs three readings)."
    order = ["low", "moderate", "high", "critical"]
    scores = risk.get("scores") or {}
    overall = max((s["level"] for s in scores.values()), key=order.index, default="low")
    lines = []
    for k, v in scores.items():
        line = f"- {COMPLICATION_NAMES.get(k, k)}: {round(float(v['value']) * 100)}% ({v['level']})"
        factors = [FACTOR_NAMES.get(f, f) for f in v.get("factors") or []]
        if factors:
            line += f"; factors that most raised this estimate: {', '.join(factors)}"
        lines.append(line)
    return (
        f"RISK ASSESSMENT ({_when(risk.get('generatedAt'))}), overall {overall}. "
        "Estimated chance of each condition from a machine-learning model, not a diagnosis. "
        "The listed factors are what most raised each estimate for this patient (statistical "
        "associations, not proven causes):\n" + "\n".join(lines)
    )


def section_medications(c: Ctx) -> str:
    meds = c.repo.medications(c.uid)
    if not meds:
        return "MEDICATIONS: none recorded."
    lines = []
    for m in meds:
        rate = m.get("adherenceRate")
        adherence = f", adherence {round(float(rate))}%" if rate is not None else ""
        lines.append(f"- {m.get('name')} {m.get('dosage', '')}, {m.get('schedule', '')}{adherence}")
    return "MEDICATIONS:\n" + "\n".join(lines)


def section_prescriptions(c: Ctx) -> str:
    rx = c.repo.recent_prescriptions(c.uid, 5)
    if not rx:
        return "PRESCRIPTIONS FROM DOCTOR: none."
    return "PRESCRIPTIONS FROM DOCTOR (newest first):\n" + "\n".join(
        f"- {p.get('medicationDetails')} (issued {_when(p.get('issuedAt'))})" for p in rx
    )


def section_appointments(c: Ctx) -> str:
    appts = c.repo.upcoming_appointments(c.uid, c.now)
    if not appts:
        return "UPCOMING APPOINTMENTS: none booked."
    return "UPCOMING APPOINTMENTS:\n" + "\n".join(
        f"- {_when(a.get('dateTime'))} ({a.get('status', 'booked')})" for a in appts
    )


def section_care_plan(c: Ctx) -> str:
    plan = c.repo.care_plan(c.uid)
    if not plan or not plan.get("content"):
        return "CARE PLAN FROM DOCTOR: none yet."
    return f"CARE PLAN FROM DOCTOR (updated {_when(plan.get('updatedAt'))}):\n{plan['content']}"


SECTIONS: list[Callable[[Ctx], str]] = [
    section_about,
    section_history,
    section_readings,
    section_risk,
    section_medications,
    section_prescriptions,
    section_appointments,
    section_care_plan,
]


def _safe(section: Callable[[Ctx], str], ctx: Ctx) -> str:
    """One failing source (e.g. a missing index) must not break the whole answer."""
    try:
        return section(ctx)
    except Exception:
        log.exception("Agent context section %s failed", section.__name__)
        name = section.__name__.removeprefix("section_").upper()
        return f"{name}: temporarily unavailable."


def build_context(repo: AgentDataRepository, uid: str, now: datetime) -> str:
    ctx = Ctx(repo, uid, now)
    return f"Current time: {_when(now)}\n\n" + "\n\n".join(_safe(s, ctx) for s in SECTIONS)
