"""Doctor actions on assigned patients (Module 8, FR-8.3; UC8.4, UC8.5; Fig 4.1.1.8).

Reads (patient list, history) go straight to Firestore under Security Rules; these
writes go through FastAPI so they are checked against the assignment and audited.
"""

from __future__ import annotations

from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore

CARE_PLAN_VERSIONS = "versions"  # D-41: care_plans/{patientId}/versions


class ProviderRepository(Protocol):
    def patient(self, uid: str) -> dict[str, Any] | None: ...

    def current_medicines(self, uid: str) -> list[str]:
        """Names of the patient's medications plus earlier prescriptions' details."""
        ...

    def add_note(self, data: dict[str, Any]) -> str: ...

    def set_care_plan(self, patient_id: str, data: dict[str, Any]) -> None: ...

    def add_prescription(self, data: dict[str, Any]) -> str: ...

    def prescription(self, rx_id: str) -> dict[str, Any] | None: ...

    def update_prescription(self, rx_id: str, data: dict[str, Any]) -> None: ...

    def delete_prescription(self, rx_id: str) -> None: ...


class FirestoreProviderRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def patient(self, uid: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def current_medicines(self, uid: str) -> list[str]:
        meds = self._db.collection(Collection.MEDICATIONS.value).where(
            filter=firestore.FieldFilter("patientId", "==", uid)
        )
        rx = self._db.collection(Collection.PRESCRIPTIONS.value).where(
            filter=firestore.FieldFilter("patientId", "==", uid)
        )
        names = [str(d.get("name") or "") for d in meds.stream()]
        names += [str(d.get("medicationDetails") or "") for d in rx.stream()]
        return [n for n in names if n]

    def add_note(self, data: dict[str, Any]) -> str:
        _, ref = self._db.collection(Collection.CLINICAL_NOTES.value).add(
            {**data, "createdAt": firestore.SERVER_TIMESTAMP}
        )
        return str(ref.id)

    def set_care_plan(self, patient_id: str, data: dict[str, Any]) -> None:
        # One living plan per patient (docs/04): document id = patient uid. D-41: every save
        # also appends a version, in the same batch so the history never misses an edit.
        plan = self._db.collection(Collection.CARE_PLANS.value).document(patient_id)
        batch = self._db.batch()
        batch.set(plan, {**data, "updatedAt": firestore.SERVER_TIMESTAMP})
        batch.set(
            plan.collection(CARE_PLAN_VERSIONS).document(),
            {
                "content": data["content"],
                "doctorId": data["doctorId"],
                "savedAt": firestore.SERVER_TIMESTAMP,
            },
        )
        batch.commit()

    def add_prescription(self, data: dict[str, Any]) -> str:
        _, ref = self._db.collection(Collection.PRESCRIPTIONS.value).add(
            {**data, "issuedAt": firestore.SERVER_TIMESTAMP}
        )
        return str(ref.id)

    def prescription(self, rx_id: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.PRESCRIPTIONS.value).document(rx_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def update_prescription(self, rx_id: str, data: dict[str, Any]) -> None:
        self._db.collection(Collection.PRESCRIPTIONS.value).document(rx_id).update(data)

    def delete_prescription(self, rx_id: str) -> None:
        self._db.collection(Collection.PRESCRIPTIONS.value).document(rx_id).delete()


def get_provider_repository() -> ProviderRepository:
    return FirestoreProviderRepository(get_firestore())


def medication_details(
    name: str, dosage: str, frequency: str, duration: str | None, clinic: str | None = None
) -> str:
    """prescriptions.medicationDetails is one string in Ch4 (Table 4.2.3.11)."""
    parts = [f"{name} {dosage}".strip(), frequency]
    if duration:
        parts.append(f"for {duration}")
    if clinic:  # D-50: patient-reported, where it was prescribed
        parts.append(f"from {clinic}")
    return ", ".join(p for p in parts if p)
