"""Symptom checker triage (FR-14.3; UC14.1-UC14.4; Fig 4.1.1.14; docs/06 §D; D-10, D-36).

`classify` is the fixed rule table, evaluated top-down, first match wins. Every row and
boundary (179/180, 139/140, 119/120, 89/90, 45/44, 120/121) is unit-tested (Objective 1).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection, RiskLevel, TriageOutcome, TriageSeverity
from app.core.firebase import get_firestore

EMERGENCY_SYSTOLIC = 180
EMERGENCY_DIASTOLIC = 120
SEVERE_SYSTOLIC = 160
HIGH_SYSTOLIC = 140
HIGH_DIASTOLIC = 90
HEART_RATE_HIGH = 120  # contact doctor above this
HEART_RATE_LOW = 45  # ... or below this
# D-36: without a BP entered in the checker, use the latest reading only if this recent.
RECENT_BP = timedelta(hours=24)


@dataclass(frozen=True)
class Decision:
    outcome: TriageOutcome
    reason: str


def classify(
    severity: TriageSeverity,
    red_flags: list[str],
    systolic: int | None,
    diastolic: int | None,
    heart_rate: int | None,
    risk_levels: list[RiskLevel],
) -> Decision:
    """docs/06 §D rule table. `red_flags` = names of selected red-flag symptoms."""
    sys_ = systolic if systolic is not None else 0
    dia = diastolic if diastolic is not None else 0
    has_bp = systolic is not None and diastolic is not None

    if has_bp and (sys_ >= EMERGENCY_SYSTOLIC or dia >= EMERGENCY_DIASTOLIC):
        return Decision(
            TriageOutcome.SEEK_EMERGENCY_CARE,
            f"Your blood pressure ({sys_}/{dia} mmHg) is in the hypertensive crisis range.",
        )
    if severity is TriageSeverity.SEVERE and (red_flags or (has_bp and sys_ >= SEVERE_SYSTOLIC)):
        why = ", ".join(red_flags) if red_flags else f"blood pressure {sys_}/{dia} mmHg"
        return Decision(TriageOutcome.SEEK_EMERGENCY_CARE, f"Severe symptoms with {why}.")
    if red_flags:
        return Decision(
            TriageOutcome.SEEK_EMERGENCY_CARE,
            f"{', '.join(red_flags)} can be a sign of a serious problem.",
        )
    if has_bp and (sys_ >= HIGH_SYSTOLIC or dia >= HIGH_DIASTOLIC):
        return Decision(
            TriageOutcome.CONTACT_DOCTOR,
            f"Your blood pressure ({sys_}/{dia} mmHg) is high.",
        )
    if severity is TriageSeverity.MODERATE:
        return Decision(TriageOutcome.CONTACT_DOCTOR, "Your symptoms are moderate.")
    if any(level in (RiskLevel.HIGH, RiskLevel.CRITICAL) for level in risk_levels):
        return Decision(TriageOutcome.CONTACT_DOCTOR, "Your health risk assessment is high.")
    if heart_rate is not None and (heart_rate > HEART_RATE_HIGH or heart_rate < HEART_RATE_LOW):
        return Decision(
            TriageOutcome.CONTACT_DOCTOR,
            f"Your estimated heart rate ({heart_rate} bpm) is outside the usual range.",
        )
    return Decision(TriageOutcome.MONITOR_AT_HOME, "Your symptoms and readings look mild.")


# ---------------- data ----------------


@dataclass(frozen=True)
class Symptom:
    id: str
    name: str
    is_red_flag: bool


class TriageRepository(Protocol):
    def symptoms(self, ids: list[str]) -> dict[str, Symptom]: ...

    def reading(self, reading_id: str) -> dict[str, Any] | None: ...

    def latest_reading(self, uid: str) -> tuple[str, dict[str, Any]] | None: ...

    def latest_risk_levels(self, uid: str) -> list[RiskLevel]: ...

    def save_outcome(self, data: dict[str, Any]) -> str: ...


class FirestoreTriageRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def symptoms(self, ids: list[str]) -> dict[str, Symptom]:
        col = self._db.collection(Collection.SYMPTOM_CATALOG.value)
        out: dict[str, Symptom] = {}
        for snap in self._db.get_all([col.document(i) for i in ids]):
            if snap.exists:
                d = snap.to_dict()
                out[snap.id] = Symptom(snap.id, str(d.get("name")), bool(d.get("isRedFlag")))
        return out

    def reading(self, reading_id: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.VITAL_READINGS.value).document(reading_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def latest_reading(self, uid: str) -> tuple[str, dict[str, Any]] | None:
        query = (
            self._db.collection(Collection.VITAL_READINGS.value)
            .where(filter=firestore.FieldFilter("patientId", "==", uid))
            .order_by("timestamp", direction=firestore.Query.DESCENDING)
            .limit(1)
        )
        return next(((d.id, dict(d.to_dict())) for d in query.stream()), None)

    def latest_risk_levels(self, uid: str) -> list[RiskLevel]:
        query = (
            self._db.collection(Collection.RISK_SCORES.value)
            .where(filter=firestore.FieldFilter("patientId", "==", uid))
            .order_by("generatedAt", direction=firestore.Query.DESCENDING)
            .limit(1)
        )
        for d in query.stream():
            return [RiskLevel(v["level"]) for v in (d.to_dict().get("scores") or {}).values()]
        return []

    def save_outcome(self, data: dict[str, Any]) -> str:
        _, ref = self._db.collection(Collection.TRIAGE_OUTCOMES.value).add(
            {**data, "generatedAt": firestore.SERVER_TIMESTAMP}
        )
        return str(ref.id)


def get_triage_repository() -> TriageRepository:
    return FirestoreTriageRepository(get_firestore())


@dataclass
class TriageInputs:
    """What the decision was based on (shown on the result; UC14.1 E1 notes gaps)."""

    reading_id: str | None = None
    systolic: int | None = None
    diastolic: int | None = None
    measured_at: datetime | None = None
    heart_rate: int | None = None
    risk_levels: list[RiskLevel] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)


def gather_inputs(
    repo: TriageRepository,
    uid: str,
    reading_id: str | None,
    heart_rate: int | None,
    now: datetime,
) -> TriageInputs:
    inputs = TriageInputs(heart_rate=heart_rate)
    reading: dict[str, Any] | None = None
    if reading_id is not None:
        reading = repo.reading(reading_id)
        if reading is None or reading.get("patientId") != uid:
            raise LookupError("Reading not found.")
    else:
        latest = repo.latest_reading(uid)
        if latest is not None:
            measured = latest[1].get("timestamp")
            if isinstance(measured, datetime) and now - measured <= RECENT_BP:
                reading_id, reading = latest
    if reading is not None:
        inputs.reading_id = reading_id
        inputs.systolic = int(reading["systolic"])
        inputs.diastolic = int(reading["diastolic"])
        ts = reading.get("timestamp")
        inputs.measured_at = ts if isinstance(ts, datetime) else None
        if inputs.heart_rate is None and reading.get("heartRate") is not None:
            inputs.heart_rate = int(reading["heartRate"])
    else:
        inputs.missing.append("recent_blood_pressure")
    if inputs.heart_rate is None:
        inputs.missing.append("heart_rate")
    inputs.risk_levels = repo.latest_risk_levels(uid)
    if not inputs.risk_levels:
        inputs.missing.append("risk_score")
    return inputs
