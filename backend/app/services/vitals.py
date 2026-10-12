"""Firestore writes for `vital_readings` (docs/04 Table 4.2.3.3)."""

from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore


class VitalsRepository(Protocol):
    def add_reading(self, data: dict[str, Any]) -> str: ...


class FirestoreVitalsRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def add_reading(self, data: dict[str, Any]) -> str:
        # Server timestamp: the device clock is never trusted for clinical data.
        _, ref = self._db.collection(Collection.VITAL_READINGS.value).add(
            {**data, "timestamp": firestore.SERVER_TIMESTAMP}
        )
        return str(ref.id)


def get_vitals_repository() -> VitalsRepository:
    return FirestoreVitalsRepository(get_firestore())
