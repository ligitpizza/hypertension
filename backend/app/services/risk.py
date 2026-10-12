"""Risk scoring service (FR-9.2, FR-9.3; UC9.1; docs/06 algorithm A).

Reads the patient's profile, health profile, recent readings and medications, runs the
risk models and stores one `risk_scores` document (Ch4 Table 4.2.3.4 shape).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore
from app.ml.risk_inputs import MIN_READINGS, RiskInputs, assemble
from app.ml.risk_model import RiskModel, RiskPrediction, scores_document


class RiskDataRepository(Protocol):
    def user(self, uid: str) -> dict[str, Any] | None: ...

    def health_profile(self, uid: str) -> dict[str, Any] | None: ...

    def recent_readings(self, uid: str, limit: int) -> list[dict[str, Any]]: ...

    def medications(self, uid: str) -> list[dict[str, Any]]: ...

    def save_risk_score(self, data: dict[str, Any]) -> str: ...


class FirestoreRiskDataRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def health_profile(self, uid: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.HEALTH_PROFILES.value).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def recent_readings(self, uid: str, limit: int) -> list[dict[str, Any]]:
        query = (
            self._db.collection(Collection.VITAL_READINGS.value)
            .where(filter=firestore.FieldFilter("patientId", "==", uid))
            .order_by("timestamp", direction=firestore.Query.DESCENDING)
            .limit(limit)
        )
        return [dict(d.to_dict()) for d in query.stream()]

    def medications(self, uid: str) -> list[dict[str, Any]]:
        query = self._db.collection(Collection.MEDICATIONS.value).where(
            filter=firestore.FieldFilter("patientId", "==", uid)
        )
        return [dict(d.to_dict()) for d in query.stream()]

    def save_risk_score(self, data: dict[str, Any]) -> str:
        _, ref = self._db.collection(Collection.RISK_SCORES.value).add(
            {**data, "generatedAt": firestore.SERVER_TIMESTAMP}
        )
        return str(ref.id)


def get_risk_data_repository() -> RiskDataRepository:
    return FirestoreRiskDataRepository(get_firestore())


@dataclass(frozen=True)
class RiskResult:
    score_id: str
    prediction: RiskPrediction
    inputs: RiskInputs

    def to_response(self) -> dict[str, Any]:
        return {
            "scoreId": self.score_id,
            "overallLevel": self.prediction.overall_level.value,
            "scores": scores_document(self.prediction),
            "modelUsed": self.prediction.model_used,
            # D-03: reduced confidence is returned in the API response only.
            "lowConfidence": self.inputs.low_confidence,
            "missingInputs": self.inputs.missing,
        }


class NotEnoughReadingsError(Exception):
    pass


def generate_risk_score(
    uid: str, repo: RiskDataRepository, model: RiskModel, now: datetime | None = None
) -> RiskResult:
    """UC9.1 Generate Risk Score. Requires at least MIN_READINGS readings."""
    now = now or datetime.now(UTC)
    readings = repo.recent_readings(uid, limit=10)
    if len(readings) < MIN_READINGS:
        raise NotEnoughReadingsError(f"{MIN_READINGS} readings are needed for a risk score.")
    user = repo.user(uid) or {}
    inputs = assemble(user, repo.health_profile(uid), readings, repo.medications(uid), now)
    prediction = model.predict(inputs.features)
    score_id = repo.save_risk_score(
        {
            "patientId": uid,
            "modelUsed": prediction.model_used,
            "scores": scores_document(prediction),
        }
    )
    return RiskResult(score_id=score_id, prediction=prediction, inputs=inputs)
