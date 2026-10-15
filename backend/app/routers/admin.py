"""Admin endpoints.

POST  /admin/staff          staff provisioning (FR-1.6, UC1.5)
GET   /admin/users          list / search / filter all users (FR-11.1, UC11.1)
PATCH /admin/users/{uid}    edit name, specialty, caseload limit; deactivate / reactivate
"""

import html
import logging
from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.integrations.email import EmailClient, EmailMessage, get_email_client
from app.schemas.auth import CreateStaffRequest, CreateStaffResponse, UpdateUserRequest
from app.services.identity import (
    EmailAlreadyRegisteredError,
    IdentityProvider,
    get_identity_provider,
)
from app.services.users import UserRepository, get_user_repository

log = logging.getLogger("careflow.admin")

router = APIRouter(prefix="/admin", tags=["admin"])

_ROLE_LABEL = {
    UserRole.DOCTOR: "Doctor",
    UserRole.PHARMACIST: "Pharmacist",
    UserRole.ADMIN: "Administrator",
}


def staff_setup_email(name: str, email: str, role: UserRole, link: str) -> EmailMessage:
    label = _ROLE_LABEL[role]
    text = (
        f"Hello {name},\n\n"
        f"A CareFlow Staff Portal account ({label}) has been created for you.\n"
        f"Set your password using this link:\n{link}\n\n"
        "Then sign in at the CareFlow Staff Portal with this email address.\n"
    )
    safe_name, safe_link = html.escape(name), html.escape(link, quote=True)
    body_html = (
        f"<p>Hello {safe_name},</p>"
        f"<p>A CareFlow Staff Portal account (<b>{label}</b>) has been created for you.</p>"
        f'<p><a href="{safe_link}">Set your password</a></p>'
        "<p>Then sign in at the CareFlow Staff Portal with this email address.</p>"
    )
    return EmailMessage(
        to_email=email,
        to_name=name,
        subject="Your CareFlow Staff Portal account",
        text=text,
        html=body_html,
    )


@router.post("/staff", response_model=CreateStaffResponse, status_code=status.HTTP_201_CREATED)
def create_staff_account(
    body: CreateStaffRequest,
    admin: CurrentUser = Depends(require_roles(UserRole.ADMIN)),
    identity: IdentityProvider = Depends(get_identity_provider),
    repo: UserRepository = Depends(get_user_repository),
    email_client: EmailClient = Depends(get_email_client),
    audit: AuditLogger = Depends(get_audit_logger),
) -> CreateStaffResponse:
    """UC1.5: Admin creates a Doctor/Pharmacist/Admin account (Fig 4.1.1.1, last frame)."""
    role = UserRole(body.role)
    try:
        uid = identity.create_user(email=body.email, display_name=body.name)
    except EmailAlreadyRegisteredError as exc:
        # UC1.5 E1: prevent duplicate accounts.
        raise ApiError(
            "EMAIL_ALREADY_REGISTERED",
            "An account with this email already exists.",
            status.HTTP_409_CONFLICT,
        ) from exc

    identity.set_role(uid, role)
    doc = {"email": body.email, "name": body.name, "role": role.value, "isActive": True}
    if role is UserRole.DOCTOR and body.specialty:
        doc["specialty"] = body.specialty
    repo.create_user(uid, doc)

    # UC1.5 step 5: send a setup link. If email fails, return the link to the admin instead.
    link = identity.password_setup_link(body.email)
    try:
        # False from the console fake: nothing was delivered, so show the link instead.
        email_sent = email_client.send(staff_setup_email(body.name, body.email, role, link))
    except Exception:  # any provider failure must not lose the new account
        log.exception("Staff setup email failed for uid=%s", uid)
        email_sent = False

    audit.log(
        user_id=admin.uid,
        action="CREATE_STAFF_ACCOUNT",
        details=f"Created {role.value} account; setup link "
        f"{'emailed' if email_sent else 'shown to admin (email not delivered)'}.",
        target_type=Collection.USERS.value,
        target_id=uid,
    )
    return CreateStaffResponse(
        uid=uid, role=role, emailSent=email_sent, setupLink=None if email_sent else link
    )


DEFAULT_MAX_PATIENTS = 30  # D-59
admin_only = require_roles(UserRole.ADMIN)


def _iso(v: Any) -> str | None:
    return v.isoformat() if isinstance(v, datetime) else None


def user_row(uid: str, u: dict[str, Any], caseload: int | None = None) -> dict[str, Any]:
    row: dict[str, Any] = {
        "uid": uid,
        "name": u.get("name") or "",
        "email": u.get("email") or "",
        "role": u.get("role"),
        "isActive": u.get("isActive") is not False,
        "createdAt": _iso(u.get("createdAt")),
        "deletionRequested": u.get("deletionRequestedAt") is not None,
    }
    if u.get("role") == UserRole.DOCTOR.value:
        row["specialty"] = u.get("specialty")
        row["maxPatients"] = int(u.get("maxPatients") or DEFAULT_MAX_PATIENTS)
        row["caseload"] = caseload or 0
    if u.get("role") == UserRole.PATIENT.value:
        row["assignedDoctorId"] = u.get("assignedDoctorId")
    return row


def caseloads(users: list[tuple[str, dict[str, Any]]]) -> dict[str, int]:
    """Active patients per doctor (D-59)."""
    out: dict[str, int] = {}
    for _, u in users:
        doctor = u.get("assignedDoctorId")
        if u.get("role") == UserRole.PATIENT.value and doctor and u.get("isActive") is not False:
            out[str(doctor)] = out.get(str(doctor), 0) + 1
    return out


@router.get("/users")
def list_users(
    role: UserRole | None = None,
    q: str | None = None,
    _: CurrentUser = Depends(admin_only),
    repo: UserRepository = Depends(get_user_repository),
) -> dict[str, Any]:
    """UC11.1 step 1: search / filter. Newest first."""
    users = repo.list_users()
    loads = caseloads(users)
    needle = (q or "").strip().lower()
    rows = [
        user_row(uid, u, loads.get(uid))
        for uid, u in users
        if (role is None or u.get("role") == role.value)
        and (
            not needle
            or needle in str(u.get("name") or "").lower()
            or needle in str(u.get("email") or "").lower()
        )
    ]
    rows.sort(key=lambda r: r["createdAt"] or "", reverse=True)
    return {"users": rows, "total": len(rows)}


@router.patch("/users/{uid}")
def update_user(
    uid: str,
    body: UpdateUserRequest,
    admin: CurrentUser = Depends(admin_only),
    repo: UserRepository = Depends(get_user_repository),
    identity: IdentityProvider = Depends(get_identity_provider),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """UC11.1 steps 2-3: apply the change and log it (Fig 4.1.1.11)."""
    users = repo.list_users()
    target = dict(users).get(uid)
    if target is None:
        raise ApiError("USER_NOT_FOUND", "User not found.", status.HTTP_404_NOT_FOUND)
    is_doctor = target.get("role") == UserRole.DOCTOR.value
    if (body.specialty is not None or body.maxPatients is not None) and not is_doctor:
        raise ApiError(
            "NOT_A_DOCTOR",
            "Specialty and caseload limit apply to doctors only.",
            status.HTTP_422_UNPROCESSABLE_CONTENT,
        )

    edits: dict[str, Any] = {}
    if body.name is not None and body.name != target.get("name"):
        edits["name"] = body.name
    if body.specialty is not None and body.specialty != target.get("specialty"):
        edits["specialty"] = body.specialty or None
    if body.maxPatients is not None and body.maxPatients != target.get("maxPatients"):
        edits["maxPatients"] = body.maxPatients
    if edits:
        repo.update_user(uid, edits)
        audit.log(
            user_id=admin.uid,
            action="EDIT_USER",
            details="Updated " + ", ".join(sorted(edits)) + ".",
            target_type=Collection.USERS.value,
            target_id=uid,
        )

    active_now = target.get("isActive") is not False
    if body.isActive is False and active_now:
        if target.get("role") == UserRole.ADMIN.value:
            other_admins = [
                u
                for other, u in users
                if other != uid
                and u.get("role") == UserRole.ADMIN.value
                and u.get("isActive") is not False
            ]
            if not other_admins:
                # UC11.1 E1
                raise ApiError(
                    "LAST_ADMIN",
                    "This is the only active admin account, so it cannot be deactivated.",
                    status.HTTP_409_CONFLICT,
                )
        repo.update_user(uid, {"isActive": False})
        identity.set_disabled(uid, True)
        identity.revoke_sessions(uid)
        audit.log(
            user_id=admin.uid,
            action="DEACTIVATE_ACCOUNT",
            details=f"Deactivated {target.get('role')} account"
            + (f": {body.reason}" if body.reason else "."),
            target_type=Collection.USERS.value,
            target_id=uid,
        )
    elif body.isActive is True and not active_now:
        # D-46: reactivating also cancels a pending account deletion.
        repo.update_user(uid, {"isActive": True, "deletionRequestedAt": None})
        identity.set_disabled(uid, False)
        audit.log(
            user_id=admin.uid,
            action="REACTIVATE_ACCOUNT",
            details=f"Reactivated {target.get('role')} account"
            + (" (pending deletion cancelled)." if target.get("deletionRequestedAt") else "."),
            target_type=Collection.USERS.value,
            target_id=uid,
        )

    updated = dict(dict(repo.list_users()).get(uid) or target)
    return user_row(uid, updated, caseloads(repo.list_users()).get(uid))
