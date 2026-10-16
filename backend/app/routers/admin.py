"""Admin endpoints.

POST  /admin/staff          staff provisioning (FR-1.6, UC1.5)
GET   /admin/users          list / search / filter all users (FR-11.1, UC11.1)
PATCH /admin/users/{uid}    edit name, specialty, caseload limit; deactivate / reactivate
POST  /admin/patients       create a patient account (D-60)
DELETE /admin/users/{uid}   permanently delete a user (D-60)
GET   /admin/users/{uid}    detail page for a patient, doctor or pharmacist (D-61)
"""

import html
import logging
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, Response, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.integrations.email import (
    EmailClient,
    EmailMessage,
    get_email_client,
    plain_link_html,
)
from app.schemas.auth import (
    CreatePatientRequest,
    CreateStaffRequest,
    CreateStaffResponse,
    UpdateUserRequest,
)
from app.services.analytics import AnalyticsSource, get_analytics_source, overall_level
from app.services.appointments import (
    AppointmentRepository,
    booked_by,
    get_appointment_repository,
)
from app.services.audit_view import AuditReader, get_audit_reader
from app.services.ic import mask_ic
from app.services.identity import (
    EmailAlreadyRegisteredError,
    IdentityProvider,
    get_identity_provider,
)
from app.services.settings import SettingsRepository, get_settings_repository
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
    safe_name = html.escape(name)
    body_html = (
        f"<p>Hello {safe_name},</p>"
        f"<p>A CareFlow Staff Portal account (<b>{label}</b>) has been created for you.</p>"
        + plain_link_html(link, "Set your password with this link (tap or copy it):")
        + "<p>Then sign in at the CareFlow Staff Portal with this email address.</p>"
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


def patient_setup_email(name: str, email: str, link: str) -> EmailMessage:
    text = (
        f"Hello {name},\n\n"
        "The clinic has created a CareFlow account for you.\n"
        f"Set your password using this link:\n{link}\n\n"
        "Then sign in to the CareFlow app with this email address and complete your health "
        "profile.\n"
    )
    safe_name = html.escape(name)
    body_html = (
        f"<p>Hello {safe_name},</p>"
        "<p>The clinic has created a CareFlow account for you.</p>"
        + plain_link_html(link, "Set your password with this link (tap or copy it):")
        + "<p>Then sign in to the CareFlow app with this email address and complete your "
        "health profile.</p>"
    )
    return EmailMessage(
        to_email=email,
        to_name=name,
        subject="Your CareFlow account",
        text=text,
        html=body_html,
    )


@router.post("/patients", status_code=status.HTTP_201_CREATED)
def create_patient_account(
    body: CreatePatientRequest,
    admin: CurrentUser = Depends(admin_only),
    identity: IdentityProvider = Depends(get_identity_provider),
    repo: UserRepository = Depends(get_user_repository),
    email_client: EmailClient = Depends(get_email_client),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """D-60: same account shape as self-registration (D-51 IC check, D-06 link code)."""
    from app.routers.auth import _patient_ic, _unique_link_code

    ic = _patient_ic(body.icNumber, UserRole.PATIENT, repo, "")
    try:
        uid = identity.create_user(email=body.email, display_name=body.name)
    except EmailAlreadyRegisteredError as exc:
        raise ApiError(
            "EMAIL_ALREADY_REGISTERED",
            "An account with this email already exists.",
            status.HTTP_409_CONFLICT,
        ) from exc
    identity.set_role(uid, UserRole.PATIENT)
    repo.create_user(
        uid,
        {
            "email": body.email,
            "name": body.name,
            "role": UserRole.PATIENT.value,
            "isActive": True,
            "icNumber": ic,
            "onboardingComplete": False,
            "assignedDoctorId": None,
            "linkCode": _unique_link_code(repo),
        },
    )
    link = identity.password_setup_link(body.email)
    try:
        email_sent = email_client.send(patient_setup_email(body.name, body.email, link))
    except Exception:
        log.exception("Patient setup email failed for uid=%s", uid)
        email_sent = False
    audit.log(
        user_id=admin.uid,
        action="CREATE_PATIENT_ACCOUNT",
        details="Admin created a patient account; setup link "
        f"{'emailed' if email_sent else 'shown to admin'}.",
        target_type=Collection.USERS.value,
        target_id=uid,
    )
    return {"uid": uid, "emailSent": email_sent, "setupLink": None if email_sent else link}


@router.delete("/users/{uid}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    uid: str,
    admin: CurrentUser = Depends(admin_only),
    repo: UserRepository = Depends(get_user_repository),
    settings_repo: SettingsRepository = Depends(get_settings_repository),
    appointments: AppointmentRepository = Depends(get_appointment_repository),
    identity: IdentityProvider = Depends(get_identity_provider),
    audit: AuditLogger = Depends(get_audit_logger),
) -> Response:
    """D-60: permanent removal. Patients go through the D-46 cascade (doctor-authored
    records are kept); a doctor must hand over patients and appointments first."""
    users = repo.list_users()
    target = dict(users).get(uid)
    if target is None:
        raise ApiError("USER_NOT_FOUND", "User not found.", status.HTTP_404_NOT_FOUND)
    if uid == admin.uid:
        raise ApiError(
            "CANNOT_DELETE_SELF", "You cannot delete your own account.", status.HTTP_409_CONFLICT
        )
    role = target.get("role")
    if role == UserRole.ADMIN.value and not any(
        other != uid and u.get("role") == UserRole.ADMIN.value and u.get("isActive") is not False
        for other, u in users
    ):
        raise ApiError(
            "LAST_ADMIN", "This is the only active admin account.", status.HTTP_409_CONFLICT
        )
    if role == UserRole.DOCTOR.value:
        now = datetime.now(UTC)
        patients = caseloads(users).get(uid, 0)
        upcoming = len(appointments.taken(uid, now, now + timedelta(days=365)))
        if patients or upcoming:
            raise ApiError(
                "DOCTOR_IN_USE",
                f"This doctor still has {patients} assigned patients and {upcoming} upcoming "
                "appointments. Reassign or cancel them first.",
                status.HTTP_409_CONFLICT,
            )
    removed = settings_repo.purge(uid)
    identity.delete_user(uid)
    audit.log(
        user_id=admin.uid,
        action="DELETE_USER",
        details=f"Permanently deleted {role} account ({removed} records removed).",
        target_type=Collection.USERS.value,
        target_id=uid,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------- D-61: user detail pages ----------------


def _iso_or_none(v: Any) -> str | None:
    return v.isoformat() if isinstance(v, datetime) else None


def _appointment_rows(
    appts: list[dict[str, Any]], names: dict[str, str], key: str, limit: int
) -> list[dict[str, Any]]:
    rows = sorted(
        (a for a in appts if isinstance(a.get("dateTime"), datetime)),
        key=lambda a: a["dateTime"],
        reverse=True,
    )[:limit]
    return [
        {
            "dateTime": a["dateTime"].isoformat(),
            "status": a.get("status"),
            "type": a.get("type"),
            "bookedBy": booked_by(a),
            "other": names.get(str(a.get(key)), "Unknown"),
            "changeReason": a.get("changeReason"),
        }
        for a in rows
    ]


@router.get("/users/{uid}")
def user_detail(
    uid: str,
    _: CurrentUser = Depends(admin_only),
    repo: UserRepository = Depends(get_user_repository),
    src: AnalyticsSource = Depends(get_analytics_source),
    reader: AuditReader = Depends(get_audit_reader),
) -> dict[str, Any]:
    """D-61: one person at a glance, by role (patient / doctor / pharmacist / admin / family)."""
    users = repo.list_users()
    people = dict(users)
    target = people.get(uid)
    if target is None:
        raise ApiError("USER_NOT_FOUND", "User not found.", status.HTTP_404_NOT_FOUND)
    names = {k: str(v.get("name") or v.get("email") or "Unknown") for k, v in people.items()}
    now = datetime.now(UTC)
    role = target.get("role")
    out: dict[str, Any] = {"user": user_row(uid, target, caseloads(users).get(uid))}
    profile: dict[str, Any] = {}
    if target.get("icNumber"):
        profile["icNumber"] = mask_ic(str(target["icNumber"]))
    for field in ("gender", "phone", "onboardingComplete"):
        if target.get(field) is not None:
            profile[field] = target[field]
    if isinstance(target.get("dateOfBirth"), datetime):
        profile["dateOfBirth"] = target["dateOfBirth"].date().isoformat()
    elif target.get("dateOfBirth"):
        profile["dateOfBirth"] = str(target["dateOfBirth"])
    out["profile"] = profile

    if role == UserRole.PATIENT.value:
        doctor_id = target.get("assignedDoctorId")
        readings = sorted(
            (
                r
                for r in src.where_equal(Collection.VITAL_READINGS, "patientId", uid)
                if isinstance(r.get("timestamp"), datetime)
            ),
            key=lambda r: r["timestamp"],
        )
        scores = sorted(
            (
                r
                for r in src.where_equal(Collection.RISK_SCORES, "patientId", uid)
                if isinstance(r.get("generatedAt"), datetime)
            ),
            key=lambda r: r["generatedAt"],
        )
        records = src.where_equal(Collection.HEALTH_RECORDS, "patientId", uid)
        latest = readings[-1] if readings else None
        out["patient"] = {
            "doctor": {"uid": doctor_id, "name": names.get(str(doctor_id))} if doctor_id else None,
            "latestReading": None
            if latest is None
            else {
                "systolic": latest.get("systolic"),
                "diastolic": latest.get("diastolic"),
                "heartRate": latest.get("heartRate"),
                "timestamp": latest["timestamp"].isoformat(),
            },
            "readingsLast30Days": sum(
                1 for r in readings if r["timestamp"] >= now - timedelta(days=30)
            ),
            "risk": None
            if not scores
            else {
                "level": overall_level(scores[-1]),
                "generatedAt": scores[-1]["generatedAt"].isoformat(),
            },
            "medications": [
                {
                    "name": m.get("name"),
                    "dosage": m.get("dosage"),
                    "adherenceRate": m.get("adherenceRate"),
                }
                for m in src.where_equal(Collection.MEDICATIONS, "patientId", uid)
            ],
            "appointments": _appointment_rows(
                src.where_equal(Collection.APPOINTMENTS, "patientId", uid), names, "doctorId", 20
            ),
            "records": {
                "total": len(records),
                "shared": sum(1 for r in records if r.get("sharedWithDoctor")),
            },
            "family": [
                {"uid": k, "name": names[k]}
                for k, v in users
                if v.get("role") == UserRole.FAMILY_MEMBER.value and v.get("patientId") == uid
            ],
        }
    elif role == UserRole.DOCTOR.value:
        mine = [
            (k, v)
            for k, v in users
            if v.get("role") == UserRole.PATIENT.value and v.get("assignedDoctorId") == uid
        ]
        latest_level: dict[str, str | None] = {}
        for pid, _v in mine:
            scores = [
                r
                for r in src.where_equal(Collection.RISK_SCORES, "patientId", pid)
                if isinstance(r.get("generatedAt"), datetime)
            ]
            latest_level[pid] = (
                overall_level(max(scores, key=lambda r: r["generatedAt"])) if scores else None
            )
        appts = src.where_equal(Collection.APPOINTMENTS, "doctorId", uid)
        upcoming = [
            a
            for a in appts
            if isinstance(a.get("dateTime"), datetime)
            and a["dateTime"] >= now
            and a.get("status") in ("booked", "rescheduled")
        ]
        out["doctor"] = {
            "patients": [
                {
                    "uid": pid,
                    "name": names[pid],
                    "riskLevel": latest_level[pid],
                    "isActive": v.get("isActive") is not False,
                }
                for pid, v in sorted(mine, key=lambda x: names[x[0]])
            ],
            "upcoming": list(
                reversed(_appointment_rows(upcoming, names, "patientId", len(upcoming)))
            )[:20],
            "completedTotal": sum(1 for a in appts if a.get("status") == "completed"),
            "openAlerts": sum(
                1
                for a in src.where_equal(Collection.CLINICAL_ALERTS, "doctorId", uid)
                if a.get("status") == "open"
            ),
        }
    elif role == UserRole.PHARMACIST.value:
        out["pharmacist"] = {
            "orders": None,  # D-59: medication orders arrive with Module 13
        }

    events = [
        e
        for _id, e in reader.between(now - timedelta(days=30), now + timedelta(seconds=1))
        if e.get("userId") == uid
    ]
    out["activity"] = [
        {
            "timestamp": _iso_or_none(e.get("timestamp")),
            "action": e.get("action"),
            "details": e.get("details"),
        }
        for e in sorted(events, key=lambda e: e["timestamp"], reverse=True)[:20]
    ]
    return out
