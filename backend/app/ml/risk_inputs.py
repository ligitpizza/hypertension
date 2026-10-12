"""Assemble model inputs for one patient (docs/06 algorithm A step 2; D-04, D-29).

Pure functions over plain dicts so they are unit-tested without Firestore.

The platform's twelve inputs are age, gender, systolic, diastolic, heart rate, BMI,
smoking status, family history, existing conditions, medication count, adherence rate and
days since last reading. The NHANES models (D-29) use the first ten (existing conditions
expanded to hypertension, high cholesterol and the other complications, plus BP
medication); adherence and days-since-last-reading are reported but not model inputs.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from typing import Any

from app.services.bp import classify

READINGS_FOR_BP = 3  # NHANES averaged three measurements; we average the last three readings.
MIN_READINGS = 3  # Risk is shown only after three readings (Figs 4.3.3.1 / 4.3.4.2).

SMOKING = {"never": 0.0, "former": 1.0, "current": 2.0}
# App onboarding condition -> model input column for that complication.
CONDITION_COLUMNS = {
    "stroke": "stroke",
    "heart_disease": "cad",
    "heart_failure": "heartFailure",
    "chronic_kidney_disease": "ckd",
    "diabetes": "t2d",
}
# NHANES family history = close relative with heart attack or diabetes.
FAMILY_HISTORY_KEYS = {"heart_disease", "diabetes"}

# Inputs whose absence lowers confidence (UC9.1 E1).
CONFIDENCE_INPUTS = ("age", "female", "bmi", "heart_rate", "smoking")


@dataclass
class RiskInputs:
    features: dict[str, float]
    missing: list[str] = field(default_factory=list)
    adherence_rate: float | None = None
    days_since_last_reading: int | None = None

    @property
    def low_confidence(self) -> bool:
        return bool(self.missing)


def _parse_json(raw: object) -> dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str) and raw:
        try:
            value = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        return value if isinstance(value, dict) else {}
    return {}


def _age(dob: object, today: date) -> float:
    if isinstance(dob, datetime):
        dob = dob.date()
    if not isinstance(dob, date):
        return math.nan
    return float(today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day)))


def _as_datetime(value: object) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=UTC)
    return None


def assemble(
    user: dict[str, Any],
    health_profile: dict[str, Any] | None,
    readings_newest_first: list[dict[str, Any]],
    medications: list[dict[str, Any]],
    now: datetime,
) -> RiskInputs:
    personal = _parse_json((health_profile or {}).get("personalInfo"))
    history = _parse_json((health_profile or {}).get("medicalHistory"))
    lifestyle = _parse_json((health_profile or {}).get("lifestyleFactors"))
    conditions = set(history.get("conditions") or [])
    family = set(history.get("familyHistory") or [])

    recent = readings_newest_first[:READINGS_FOR_BP]
    systolic = sum(float(r["systolic"]) for r in recent) / len(recent) if recent else math.nan
    diastolic = sum(float(r["diastolic"]) for r in recent) / len(recent) if recent else math.nan
    heart_rate = next(
        (float(r["heartRate"]) for r in readings_newest_first if r.get("heartRate") is not None),
        math.nan,
    )

    height = personal.get("heightCm")
    weight = personal.get("weightKg")
    bmi = (
        float(weight) / (float(height) / 100) ** 2
        if isinstance(height, int | float) and isinstance(weight, int | float) and height > 0
        else math.nan
    )
    gender = user.get("gender")
    female = 1.0 if gender == "female" else 0.0 if gender == "male" else math.nan

    # Hypertension: diagnosed at onboarding, or the recent average is stage 2 or higher.
    diagnosed = history.get("hypertensionDiagnosedYear") is not None
    high_now = not math.isnan(systolic) and classify(round(systolic), round(diastolic)).value in (
        "stage2",
        "crisis",
    )

    features: dict[str, float] = {
        "age": _age(user.get("dateOfBirth"), now.date()),
        "female": female,
        "systolic": systolic,
        "diastolic": diastolic,
        "heart_rate": heart_rate,
        "bmi": bmi,
        "smoking": SMOKING.get(str(lifestyle.get("smokingStatus")), math.nan),
        "family_history": 1.0 if family & FAMILY_HISTORY_KEYS else 0.0,
        "hypertension": 1.0 if diagnosed or high_now else 0.0,
        "high_cholesterol": 1.0 if "high_cholesterol" in conditions else 0.0,
        # Module 5 medications are the patient's own list; on a hypertension platform any
        # listed medicine is treated as BP medication until drugs are classified (D-31).
        "bp_medication": 1.0 if medications else 0.0,
        "medication_count": float(len(medications)),
    }
    for condition, column in CONDITION_COLUMNS.items():
        features[column] = 1.0 if condition in conditions else 0.0

    missing = [k for k in CONFIDENCE_INPUTS if math.isnan(features[k])]

    rates = [float(m["adherenceRate"]) for m in medications if m.get("adherenceRate") is not None]
    last = (
        _as_datetime(readings_newest_first[0].get("timestamp")) if readings_newest_first else None
    )
    return RiskInputs(
        features=features,
        missing=missing,
        adherence_rate=sum(rates) / len(rates) if rates else None,
        days_since_last_reading=(now - last).days if last else None,
    )
