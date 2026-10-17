"""Admin center (D-78): doctors and pharmacists send requests to the admin.

POST  /staff-requests        doctor / pharmacist: new request
GET   /staff-requests        doctor / pharmacist: their own; admin: everyone's
PATCH /staff-requests/{id}   admin: status and reply

New requests notify every admin; a reply or status change notifies the requester.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, Literal, Protocol

from fastapi import APIRouter, Depends, status
from firebase_admin import firestore
from pydantic import BaseModel, ConfigDict, Field

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.core.firebase import get_firestore
from app.integrations.push import PushMessage
from app.services.notifications import Notifier, get_notifier
from app.services.users import UserRepository, get_user_repository

router = APIRouter(prefix="/staff-requests", tags=["staff-requests"])
requester_only = require_roles(UserRole.DOCTOR, UserRole.PHARMACIST)
staff = require_roles(UserRole.DOCTOR, UserRole.PHARMACIST, UserRole.ADMIN)
admin_only = require_roles(UserRole.ADMIN)

CATEGORIES = ("account", "leave", "stock", "it", "other")
STATUSES = ("open", "in_progress", "done")
CATEGORY_NAMES = {
    "account": "Account or role change",
    "leave": "Leave or unavailability",
    "stock": "Stock or supplier issue",
    "it": "IT problem",
    "other": "Other",
}


class StaffRequestRepository(Protocol):
    def add(self, data: dict[str, Any]) -> str: ...

    def get(self, request_id: str) -> dict[str, Any] | None: ...

    def update(self, request_id: str, data: dict[str, Any]) -> None: ...

    def all(self) -> list[tuple[str, dict[str, Any]]]: ...

    def by_requester(self, uid: str) -> list[tuple[str, dict[str, Any]]]: ...


class FirestoreStaffRequestRepository:
    def __init__(self, db: Any) -> None:
        self._col = db.collection(Collection.STAFF_REQUESTS.value)

    def add(self, data: dict[str, Any]) -> str:
        _, ref = self._col.add(data)
        return str(ref.id)

    def get(self, request_id: str) -> dict[str, Any] | None:
        snap = self._col.document(request_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def update(self, request_id: str, data: dict[str, Any]) -> None:
        self._col.document(request_id).update(data)

    def all(self) -> list[tuple[str, dict[str, Any]]]:
        q = self._col.order_by("createdAt", direction=firestore.Query.DESCENDING).limit(200)
        return [(d.id, dict(d.to_dict())) for d in q.stream()]

    def by_requester(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        q = self._col.where(filter=firestore.FieldFilter("requesterId", "==", uid))
        return [(d.id, dict(d.to_dict())) for d in q.stream()]


def get_staff_request_repository() -> StaffRequestRepository:
    return FirestoreStaffRequestRepository(get_firestore())


class NewRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    category: Literal["account", "leave", "stock", "it", "other"]
    subject: str = Field(min_length=3, max_length=120)
    details: str = Field(min_length=3, max_length=2000)


class AdminUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    status: Literal["open", "in_progress", "done"] | None = None
    reply: str | None = Field(default=None, max_length=2000)


def _iso(v: Any) -> str | None:
    return v.isoformat() if isinstance(v, datetime) else None


def _view(request_id: str, r: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": request_id,
        "requesterId": r.get("requesterId"),
        "requesterName": r.get("requesterName"),
        "requesterRole": r.get("requesterRole"),
        "category": r.get("category"),
        "subject": r.get("subject"),
        "details": r.get("details"),
        "status": r.get("status"),
        "reply": r.get("reply"),
        "repliedBy": r.get("repliedBy"),
        "createdAt": _iso(r.get("createdAt")),
        "updatedAt": _iso(r.get("updatedAt")),
    }


def _sorted(rows: list[tuple[str, dict[str, Any]]]) -> list[dict[str, Any]]:
    out = [_view(i, r) for i, r in rows]
    out.sort(key=lambda v: v["createdAt"] or "", reverse=True)
    return out


@router.post("", status_code=status.HTTP_201_CREATED)
def create(
    body: NewRequest,
    user: CurrentUser = Depends(requester_only),
    repo: StaffRequestRepository = Depends(get_staff_request_repository),
    users: UserRepository = Depends(get_user_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    me = users.get_user(user.uid) or {}
    now = datetime.now(UTC)
    data = {
        "requesterId": user.uid,
        "requesterName": me.get("name") or "Staff",
        "requesterRole": user.role.value if user.role else "",
        "category": body.category,
        "subject": body.subject,
        "details": body.details,
        "status": "open",
        "reply": None,
        "createdAt": now,
        "updatedAt": now,
    }
    request_id = repo.add(data)
    for uid, u in users.list_users():
        if u.get("role") == UserRole.ADMIN.value and u.get("isActive", True) is not False:
            notifier.notify(
                uid,
                PushMessage(
                    f"New staff request from {data['requesterName']}",
                    f"{CATEGORY_NAMES[body.category]}: {body.subject}",
                    {"type": "staff_request", "id": request_id},
                ),
            )
    audit.log(
        user_id=user.uid,
        action="STAFF_REQUEST",
        details=f"Request to admin: {CATEGORY_NAMES[body.category]}.",
        target_type=Collection.STAFF_REQUESTS.value,
        target_id=request_id,
    )
    return _view(request_id, data)


@router.get("")
def list_requests(
    user: CurrentUser = Depends(staff),
    repo: StaffRequestRepository = Depends(get_staff_request_repository),
) -> dict[str, Any]:
    rows = repo.all() if user.role is UserRole.ADMIN else repo.by_requester(user.uid)
    return {"requests": _sorted(rows)}


@router.patch("/{request_id}")
def update(
    request_id: str,
    body: AdminUpdate,
    user: CurrentUser = Depends(admin_only),
    repo: StaffRequestRepository = Depends(get_staff_request_repository),
    users: UserRepository = Depends(get_user_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    r = repo.get(request_id)
    if r is None:
        raise ApiError("REQUEST_NOT_FOUND", "Request not found.", 404)
    if body.status is None and not body.reply:
        raise ApiError("NOTHING_TO_UPDATE", "Set a status or write a reply.", 422)
    changes: dict[str, Any] = {"updatedAt": datetime.now(UTC)}
    if body.status:
        changes["status"] = body.status
    if body.reply:
        admin = users.get_user(user.uid) or {}
        changes["reply"] = body.reply
        changes["repliedBy"] = admin.get("name") or "Admin"
    repo.update(request_id, changes)
    label = {"open": "Open", "in_progress": "In progress", "done": "Done"}
    notifier.notify(
        str(r.get("requesterId")),
        PushMessage(
            f"Admin updated your request: {r.get('subject')}",
            body.reply or f"Status: {label[str(changes.get('status', r.get('status')))]}",
            {"type": "staff_request", "id": request_id},
        ),
    )
    audit.log(
        user_id=user.uid,
        action="STAFF_REQUEST_UPDATE",
        details=f"Staff request updated (status {changes.get('status', r.get('status'))}).",
        target_type=Collection.STAFF_REQUESTS.value,
        target_id=request_id,
    )
    return _view(request_id, {**r, **changes})
