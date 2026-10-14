"""Doctor assignment requests (FR-7.2, UC7.3; D-54).

A patient keeps their personal doctor; the admin changes it only on request: a new patient
asks for a doctor, or a doctor asks for a patient to be reassigned.
"""

from __future__ import annotations

from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import AssignmentRequestStatus, Collection
from app.core.firebase import get_firestore


class AssignmentRepository(Protocol):
    def user(self, uid: str) -> dict[str, Any] | None: ...

    def request(self, request_id: str) -> dict[str, Any] | None: ...

    def has_pending(self, patient_id: str) -> bool: ...

    def create(self, data: dict[str, Any]) -> str: ...

    def resolve(self, request_id: str, data: dict[str, Any]) -> None: ...

    def set_doctor(self, patient_id: str, doctor_id: str) -> None: ...


class FirestoreAssignmentRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _col(self) -> Any:
        return self._db.collection(Collection.DOCTOR_ASSIGNMENT_REQUESTS.value)

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def request(self, request_id: str) -> dict[str, Any] | None:
        snap = self._col().document(request_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def has_pending(self, patient_id: str) -> bool:
        q = (
            self._col()
            .where(filter=firestore.FieldFilter("patientId", "==", patient_id))
            .where(
                filter=firestore.FieldFilter("status", "==", AssignmentRequestStatus.PENDING.value)
            )
            .limit(1)
        )
        return any(True for _ in q.stream())

    def create(self, data: dict[str, Any]) -> str:
        _, ref = self._col().add({**data, "createdAt": firestore.SERVER_TIMESTAMP})
        return str(ref.id)

    def resolve(self, request_id: str, data: dict[str, Any]) -> None:
        self._col().document(request_id).update({**data, "resolvedAt": firestore.SERVER_TIMESTAMP})

    def set_doctor(self, patient_id: str, doctor_id: str) -> None:
        self._db.collection(Collection.USERS.value).document(patient_id).update(
            {"assignedDoctorId": doctor_id, "updatedAt": firestore.SERVER_TIMESTAMP}
        )


def get_assignment_repository() -> AssignmentRepository:
    return FirestoreAssignmentRepository(get_firestore())
