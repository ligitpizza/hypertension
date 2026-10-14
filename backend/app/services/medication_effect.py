"""Risk before vs after starting medication, for the doctor (Module 5 x Module 9; D-44).

Why not just compare the stored risk scores? The NHANES models learned that people on BP
medicine are, on average, sicker (confounding by indication), so switching `bp_medication`
from 0 to 1 *raises* the estimate even when nothing else changes. Comparing stored scores
would suggest the medicine made things worse.

Instead the model is run twice on the patient's current profile with every input held the
same, including the medication flag, and only blood pressure changes: the average of up to
three readings before the first medicine was added vs the latest three since. The
difference is the model's view of what the BP change means for risk. It is an estimate,
not proof that the medicine caused the change.
"""

from __future__ import annotations

import math
from datetime import UTC, datetime
from typing import Any

from app.ml.risk_inputs import READINGS_FOR_BP, assemble
from app.ml.risk_model import RiskModel
from app.services.risk import RiskDataRepository

# Most BP medicines take 2-4 weeks to reach full effect.
EARLY_DAYS = 14


def _when(value: object) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=UTC)
    return None


def _average(readings: list[dict[str, Any]]) -> dict[str, float]:
    return {
        "systolic": round(sum(float(r["systolic"]) for r in readings) / len(readings), 1),
        "diastolic": round(sum(float(r["diastolic"]) for r in readings) / len(readings), 1),
    }


def medication_effect(
    uid: str, repo: RiskDataRepository, model: RiskModel | None, now: datetime | None = None
) -> dict[str, Any]:
    now = now or datetime.now(UTC)
    meds = repo.medications(uid)
    starts = [s for m in meds if (s := _when(m.get("createdAt"))) is not None]
    if not starts:
        return {"status": "no_medication"}
    start = min(starts)
    first = next(m for m in meds if _when(m.get("createdAt")) == start)
    base: dict[str, Any] = {
        "startedAt": start.isoformat(),
        "firstMedication": f"{first.get('name', '')} {first.get('dosage', '')}".strip(),
        "daysOnMedication": max((now - start).days, 0),
    }
    before = repo.readings_before(uid, start, READINGS_FOR_BP)
    after = [
        r
        for r in repo.recent_readings(uid, limit=READINGS_FOR_BP)
        if (t := _when(r.get("timestamp"))) is not None and t >= start
    ]
    if not before:
        return {**base, "status": "no_baseline"}
    if not after:
        return {**base, "status": "no_followup"}

    bp_before, bp_after = _average(before), _average(after)
    result = {
        **base,
        "status": "ok",
        "early": base["daysOnMedication"] < EARLY_DAYS,
        "readingsBefore": len(before),
        "readingsAfter": len(after),
        "bpBefore": bp_before,
        "bpAfter": bp_after,
    }
    if model is None:
        return {**result, "status": "model_unavailable"}

    user = repo.user(uid) or {}
    profile = repo.health_profile(uid)
    now_inputs = assemble(user, profile, after, meds, now).features
    then_inputs = assemble(user, profile, before, meds, now).features
    # Hold everything but BP fixed; a hypertension flag inferred from either period stays on.
    shared = {
        **now_inputs,
        "hypertension": max(now_inputs["hypertension"], then_inputs["hypertension"]),
    }
    pred_before = model.predict({**shared, **bp_before})
    pred_after = model.predict({**shared, **bp_after})
    complications = {}
    for c, after_score in pred_after.scores.items():
        before_score = pred_before.scores[c]
        if math.isnan(before_score.value) or math.isnan(after_score.value):
            continue
        complications[c.value] = {
            "before": round(before_score.value * 100, 1),
            "after": round(after_score.value * 100, 1),
            "levelBefore": before_score.level.value,
            "levelAfter": after_score.level.value,
        }
    return {**result, "complications": complications, "modelUsed": pred_after.model_used}
