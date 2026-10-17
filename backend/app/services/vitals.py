"""Firestore writes for `vital_readings` (docs/04 Table 4.2.3.3)."""

from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore


class VitalsRepository(Protocol):
    def add_reading(self, data: dict[str, Any]) -> str: ...

    def reading(self, reading_id: str) -> dict[str, Any] | None: ...

    def reading_ids(self, uid: str) -> list[str]: ...

    def delete_readings(self, ids: list[str]) -> None: ...

    def delete_risk_scores(self, uid: str) -> int:
        """D-78 dev tools: the scores are recomputed from the readings that remain."""
        ...


class FirestoreVitalsRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def add_reading(self, data: dict[str, Any]) -> str:
        # Server timestamp: the device clock is never trusted for clinical data.
        _, ref = self._db.collection(Collection.VITAL_READINGS.value).add(
            {**data, "timestamp": firestore.SERVER_TIMESTAMP}
        )
        return str(ref.id)

    def reading(self, reading_id: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.VITAL_READINGS.value).document(reading_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def reading_ids(self, uid: str) -> list[str]:
        q = self._db.collection(Collection.VITAL_READINGS.value).where(
            filter=firestore.FieldFilter("patientId", "==", uid)
        )
        return [d.id for d in q.stream()]

    def delete_readings(self, ids: list[str]) -> None:
        col = self._db.collection(Collection.VITAL_READINGS.value)
        for start in range(0, len(ids), 400):
            batch = self._db.batch()
            for rid in ids[start : start + 400]:
                batch.delete(col.document(rid))
            batch.commit()

    def delete_risk_scores(self, uid: str) -> int:
        q = self._db.collection(Collection.RISK_SCORES.value).where(
            filter=firestore.FieldFilter("patientId", "==", uid)
        )
        refs = [d.reference for d in q.stream()]
        for start in range(0, len(refs), 400):
            batch = self._db.batch()
            for ref in refs[start : start + 400]:
                batch.delete(ref)
            batch.commit()
        return len(refs)


def get_vitals_repository() -> VitalsRepository:
    return FirestoreVitalsRepository(get_firestore())
