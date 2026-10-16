"""Pharmacy chat (D-69): one 'Harvey Pharmacy' conversation per patient.

Every pharmacist can read and answer it. Messages go through FastAPI (pushes, audit) and
are stored in `pharmacy_messages`, protected by Security Rules and HTTPS. Unlike the
patient-doctor chat (NFR-2.1, D-09) they are not end-to-end encrypted: they carry order
and refill updates, not clinical advice (documented deviation).
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore

MAX_LENGTH = 2000
# Pharmacist conversation list: the most recent messages scanned for thread summaries.
RECENT_SCAN = 500


def message_view(message_id: str, m: dict[str, Any]) -> dict[str, Any]:
    sent = m.get("sentAt")
    return {
        "id": message_id,
        "patientId": m.get("patientId"),
        "senderId": m.get("senderId"),
        "senderRole": m.get("senderRole"),
        "senderName": m.get("senderName"),
        "text": m.get("text"),
        "sentAt": sent.isoformat() if isinstance(sent, datetime) else None,
    }


class PharmacyChatRepository(Protocol):
    def add(self, data: dict[str, Any]) -> str: ...

    def thread(self, patient_id: str) -> list[tuple[str, dict[str, Any]]]:
        """Oldest first."""
        ...

    def recent(self, limit: int) -> list[tuple[str, dict[str, Any]]]:
        """Newest first, across all patients."""
        ...


class FirestorePharmacyChatRepository:
    def __init__(self, db: Any) -> None:
        self._col = db.collection(Collection.PHARMACY_MESSAGES.value)

    def add(self, data: dict[str, Any]) -> str:
        _, ref = self._col.add(data)
        return str(ref.id)

    def thread(self, patient_id: str) -> list[tuple[str, dict[str, Any]]]:
        q = self._col.where(filter=firestore.FieldFilter("patientId", "==", patient_id))
        out = [(d.id, dict(d.to_dict())) for d in q.stream()]
        floor = datetime.min.replace(tzinfo=UTC)
        out.sort(key=lambda p: p[1].get("sentAt") or floor)
        return out

    def recent(self, limit: int) -> list[tuple[str, dict[str, Any]]]:
        q = self._col.order_by("sentAt", direction=firestore.Query.DESCENDING).limit(limit)
        return [(d.id, dict(d.to_dict())) for d in q.stream()]


def get_pharmacy_chat_repository() -> PharmacyChatRepository:
    return FirestorePharmacyChatRepository(get_firestore())


def conversations(recent: list[tuple[str, dict[str, Any]]]) -> list[dict[str, Any]]:
    """Latest message per patient, newest conversation first."""
    seen: dict[str, dict[str, Any]] = {}
    for message_id, m in recent:
        pid = str(m.get("patientId"))
        if pid not in seen:
            seen[pid] = message_view(message_id, m)
    return list(seen.values())
