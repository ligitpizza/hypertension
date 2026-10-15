"""Module 6 health records (FR-6.1, FR-6.2; UC6.1-UC6.3; D-58).

POST   /records                 patient: save an uploaded file with its category
PATCH  /records/{id}            patient: change the category
DELETE /records/{id}            patient: delete the record and its file
POST   /records/{id}/share      patient: share with the assigned doctor (pushed)
DELETE /records/{id}/share      patient: stop sharing
GET    /records/{id}/file       the patient, or the assigned doctor while shared

Listing is a Firestore read in the app (rules: owner, or assigned doctor for shared ones).
"""

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, Response, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.integrations.push import PushMessage
from app.schemas.records import CreateRecordRequest, UpdateRecordRequest
from app.services.notifications import Notifier, get_notifier
from app.services.records import (
    CATEGORY_LABELS,
    CONTENT_TYPES,
    MAX_BYTES,
    SUPPORTED_TEXT,
    FileStore,
    RecordRepository,
    get_file_store,
    get_record_repository,
    record_view,
    storage_path,
)

router = APIRouter(prefix="/records", tags=["records"])
patient_only = require_roles(UserRole.PATIENT)


def _not_found() -> ApiError:
    return ApiError("RECORD_NOT_FOUND", "Record not found.", status.HTTP_404_NOT_FOUND)


def _own(repo: RecordRepository, record_id: str, uid: str) -> dict[str, Any]:
    r = repo.get(record_id)
    if r is None or r.get("patientId") != uid:
        raise _not_found()
    return r


@router.post("", status_code=status.HTTP_201_CREATED)
def create_record(
    body: CreateRecordRequest,
    user: CurrentUser = Depends(patient_only),
    repo: RecordRepository = Depends(get_record_repository),
    files: FileStore = Depends(get_file_store),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    path = storage_path(user.uid, body.recordId)
    stored = files.stat(path)
    if stored is None:
        raise ApiError(
            "UPLOAD_MISSING",
            "The upload did not finish. Please try again.",
            status.HTTP_409_CONFLICT,
        )
    if stored.content_type not in CONTENT_TYPES or stored.size > MAX_BYTES:
        # UC6.1 E1 (Storage rules already block this; checked again here).
        files.delete(path)
        raise ApiError(
            "UNSUPPORTED_FILE",
            f"This file type is not supported. Please upload {SUPPORTED_TEXT}.",
            status.HTTP_422_UNPROCESSABLE_CONTENT,
        )
    if repo.get(body.recordId) is not None:
        raise ApiError("RECORD_EXISTS", "This record was already saved.", status.HTTP_409_CONFLICT)
    data = {
        "patientId": user.uid,
        "fileUrl": path,
        "fileName": body.fileName,
        "contentType": stored.content_type,
        "sizeBytes": stored.size,
        "category": body.category,
        "uploadedAt": datetime.now(UTC),
        "sharedWithDoctor": False,
    }
    repo.create(body.recordId, data)
    audit.log(
        user_id=user.uid,
        action="UPLOAD_RECORD",
        details=f"{CATEGORY_LABELS[body.category]} uploaded ({stored.size} bytes).",
        target_type=Collection.HEALTH_RECORDS.value,
        target_id=body.recordId,
    )
    return record_view(body.recordId, data)


@router.patch("/{record_id}")
def update_record(
    record_id: str,
    body: UpdateRecordRequest,
    user: CurrentUser = Depends(patient_only),
    repo: RecordRepository = Depends(get_record_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    r = _own(repo, record_id, user.uid)
    repo.update(record_id, {"category": body.category})
    audit.log(
        user_id=user.uid,
        action="RECATEGORISE_RECORD",
        details=f"{CATEGORY_LABELS.get(str(r.get('category')), 'Record')} -> "
        f"{CATEGORY_LABELS[body.category]}.",
        target_type=Collection.HEALTH_RECORDS.value,
        target_id=record_id,
    )
    return record_view(record_id, {**r, "category": body.category})


@router.delete("/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_record(
    record_id: str,
    user: CurrentUser = Depends(patient_only),
    repo: RecordRepository = Depends(get_record_repository),
    files: FileStore = Depends(get_file_store),
    audit: AuditLogger = Depends(get_audit_logger),
) -> Response:
    r = _own(repo, record_id, user.uid)
    repo.delete(record_id)
    files.delete(str(r.get("fileUrl") or storage_path(user.uid, record_id)))
    audit.log(
        user_id=user.uid,
        action="DELETE_RECORD",
        details=f"{CATEGORY_LABELS.get(str(r.get('category')), 'Record')} deleted.",
        target_type=Collection.HEALTH_RECORDS.value,
        target_id=record_id,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{record_id}/share")
def share_record(
    record_id: str,
    user: CurrentUser = Depends(patient_only),
    repo: RecordRepository = Depends(get_record_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """UC6.2: grant the assigned doctor access and tell them."""
    r = _own(repo, record_id, user.uid)
    me = repo.user(user.uid) or {}
    doctor_id = me.get("assignedDoctorId")
    if not doctor_id:
        raise ApiError(
            "NO_DOCTOR",
            "You don't have a doctor yet. You can share once one is assigned.",
            status.HTTP_409_CONFLICT,
        )
    now = datetime.now(UTC)
    if not r.get("sharedWithDoctor"):
        repo.update(record_id, {"sharedWithDoctor": True, "sharedAt": now})
        category = CATEGORY_LABELS.get(str(r.get("category")), "Document")
        notifier.notify(
            str(doctor_id),
            PushMessage(
                "New shared document",
                f"{me.get('name') or 'A patient'} shared a document: {category}.",
                {"type": "record_shared", "patientId": user.uid, "recordId": record_id},
            ),
        )
        audit.log(
            user_id=user.uid,
            action="SHARE_RECORD",
            details=f"{category} shared with the assigned doctor.",
            target_type=Collection.HEALTH_RECORDS.value,
            target_id=record_id,
        )
        r = {**r, "sharedWithDoctor": True, "sharedAt": now}
    return record_view(record_id, r)


@router.delete("/{record_id}/share")
def unshare_record(
    record_id: str,
    user: CurrentUser = Depends(patient_only),
    repo: RecordRepository = Depends(get_record_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """D-58: the patient withdraws the doctor's access."""
    r = _own(repo, record_id, user.uid)
    if r.get("sharedWithDoctor"):
        repo.update(record_id, {"sharedWithDoctor": False, "sharedAt": None})
        audit.log(
            user_id=user.uid,
            action="UNSHARE_RECORD",
            details=f"{CATEGORY_LABELS.get(str(r.get('category')), 'Document')} no longer shared.",
            target_type=Collection.HEALTH_RECORDS.value,
            target_id=record_id,
        )
    out = {**r, "sharedWithDoctor": False}
    out.pop("sharedAt", None)
    return record_view(record_id, out)


@router.get("/{record_id}/file")
def record_file(
    record_id: str,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT, UserRole.DOCTOR)),
    repo: RecordRepository = Depends(get_record_repository),
    files: FileStore = Depends(get_file_store),
) -> Response:
    """UC6.3: the owner, or the assigned doctor while the record is shared."""
    r = repo.get(record_id)
    if r is None:
        raise _not_found()
    patient_id = str(r.get("patientId"))
    if user.role is UserRole.PATIENT:
        allowed = patient_id == user.uid
    else:
        owner = repo.user(patient_id) or {}
        allowed = bool(r.get("sharedWithDoctor")) and owner.get("assignedDoctorId") == user.uid
    if not allowed:
        raise _not_found()
    data = files.read(str(r.get("fileUrl") or storage_path(patient_id, record_id)))
    return Response(
        content=data,
        media_type=str(r.get("contentType") or "application/octet-stream"),
        headers={"Cache-Control": "private, no-store"},
    )
