"""Admin endpoints. Module 1: staff provisioning (FR-1.6, UC1.5).

The rest of the Admin Panel (FR-11.x: list/edit/deactivate, assignments, audit
log viewer, ...) is added in Increment 3.
"""

import html
import logging

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.integrations.email import EmailClient, EmailMessage, get_email_client
from app.schemas.auth import CreateStaffRequest, CreateStaffResponse
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
    email_sent = True
    try:
        email_client.send(staff_setup_email(body.name, body.email, role, link))
    except Exception:  # any provider failure must not lose the new account
        log.exception("Staff setup email failed for uid=%s", uid)
        email_sent = False

    audit.log(
        user_id=admin.uid,
        action="CREATE_STAFF_ACCOUNT",
        details=f"Created {role.value} account; setup email {'sent' if email_sent else 'failed'}.",
        target_type=Collection.USERS.value,
        target_id=uid,
    )
    return CreateStaffResponse(
        uid=uid, role=role, emailSent=email_sent, setupLink=None if email_sent else link
    )
