"""Module 6 health records (FR-6.1, FR-6.2; UC6.1-UC6.3; D-58).

The app uploads the file straight to Storage at `health_records/{patientId}/{recordId}`
(Storage rules: owner, create once, PDF/JPG/PNG, <= 10 MB). FastAPI then saves the
categorised `health_records` document after checking the file, and serves the bytes to
the patient or, while shared, to the assigned doctor.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol

from google.cloud import firestore as gfs

from app.core.config import get_settings
from app.core.enums import Collection
from app.core.firebase import get_firebase_app, get_firestore

MAX_BYTES = 10 * 1024 * 1024
CONTENT_TYPES = ("application/pdf", "image/jpeg", "image/png")
SUPPORTED_TEXT = "PDF, JPG or PNG, up to 10 MB"

CATEGORY_LABELS = {
    "lab_result": "Lab result",
    "prescription": "Prescription",
    "imaging": "Imaging / scan",
    "discharge_summary": "Discharge summary",
    "referral_letter": "Referral letter",
    "other": "Other",
}


def storage_path(patient_id: str, record_id: str) -> str:
    return f"health_records/{patient_id}/{record_id}"


@dataclass(frozen=True)
class StoredFile:
    size: int
    content_type: str


class FileStore(Protocol):
    def stat(self, path: str) -> StoredFile | None: ...

    def read(self, path: str) -> bytes: ...

    def delete(self, path: str) -> None: ...

    def delete_prefix(self, prefix: str) -> int:
        """Removes every file under [prefix] (account purge); returns how many."""
        ...


class RecordRepository(Protocol):
    def user(self, uid: str) -> dict[str, Any] | None: ...

    def get(self, record_id: str) -> dict[str, Any] | None: ...

    def create(self, record_id: str, data: dict[str, Any]) -> None: ...

    def update(self, record_id: str, data: dict[str, Any]) -> None: ...

    def delete(self, record_id: str) -> None: ...


class FirestoreRecordRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _col(self) -> Any:
        return self._db.collection(Collection.HEALTH_RECORDS.value)

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def get(self, record_id: str) -> dict[str, Any] | None:
        snap = self._col().document(record_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def create(self, record_id: str, data: dict[str, Any]) -> None:
        self._col().document(record_id).create(data)

    def update(self, record_id: str, data: dict[str, Any]) -> None:
        self._col().document(record_id).update(
            {k: (gfs.DELETE_FIELD if v is None else v) for k, v in data.items()}
        )

    def delete(self, record_id: str) -> None:
        self._col().document(record_id).delete()


class StorageFileStore:
    """The default Firebase Storage bucket."""

    def __init__(self) -> None:
        from firebase_admin import storage

        self._bucket = storage.bucket(get_settings().storage_bucket, app=get_firebase_app())

    def stat(self, path: str) -> StoredFile | None:
        blob = self._bucket.get_blob(path)
        if blob is None:
            return None
        return StoredFile(int(blob.size or 0), str(blob.content_type or ""))

    def read(self, path: str) -> bytes:
        return bytes(self._bucket.blob(path).download_as_bytes())

    def delete(self, path: str) -> None:
        blob = self._bucket.get_blob(path)
        if blob is not None:
            blob.delete()

    def delete_prefix(self, prefix: str) -> int:
        blobs = list(self._bucket.list_blobs(prefix=prefix))
        for b in blobs:
            b.delete()
        return len(blobs)


def get_record_repository() -> RecordRepository:
    return FirestoreRecordRepository(get_firestore())


def get_file_store() -> FileStore:
    return StorageFileStore()


def record_view(record_id: str, r: dict[str, Any]) -> dict[str, Any]:
    def iso(v: Any) -> str | None:
        return v.isoformat() if isinstance(v, datetime) else None

    return {
        "id": record_id,
        "category": r.get("category"),
        "fileName": r.get("fileName"),
        "contentType": r.get("contentType"),
        "sizeBytes": r.get("sizeBytes"),
        "uploadedAt": iso(r.get("uploadedAt")),
        "sharedWithDoctor": bool(r.get("sharedWithDoctor")),
        "sharedAt": iso(r.get("sharedAt")),
    }
