"""Module 1 endpoints for patients and family members (FR-1.1, FR-1.2, FR-1.4, FR-1.5).

Sign-up and sign-in themselves happen on the device with Firebase Authentication
(Fig 4.1.1.1 AuthNService); these endpoints create the Firestore profile, set the
role claim, store onboarding data and write audit_logs.
"""

import html
import json
import logging
from datetime import UTC, datetime, time
from functools import lru_cache
from typing import Any

from fastapi import APIRouter, Depends, Request, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, get_current_user, require_roles
from app.core.config import Settings, get_settings
from app.core.enums import (
    APP_ROLES,
    AssignmentRequestKind,
    AssignmentRequestStatus,
    Collection,
    SessionEvent,
    UserRole,
)
from app.core.errors import ApiError
from app.core.rate_limit import RateLimiter
from app.integrations.email import EmailClient, EmailMessage, get_email_client
from app.schemas.auth import (
    LoginFailedRequest,
    OnboardingRequest,
    PasswordResetRequest,
    RegisterProfileRequest,
    RegisterProfileResponse,
    SessionEventRequest,
)
from app.services.assignments import AssignmentRepository, get_assignment_repository
from app.services.ic import IcError, parse_ic
from app.services.identity import IdentityProvider, get_identity_provider
from app.services.users import UserRepository, get_user_repository, new_link_code

log = logging.getLogger("careflow.auth")
router = APIRouter(prefix="/auth", tags=["auth"])

ANONYMOUS_USER = "anonymous"
_LINK_CODE_ATTEMPTS = 5


def _deactivated() -> ApiError:
    # UC1.2 E2: deny and show a contact-support message.
    return ApiError(
        "ACCOUNT_DEACTIVATED",
        "This account has been deactivated. Please contact support.",
        status.HTTP_403_FORBIDDEN,
    )


def _unique_link_code(repo: UserRepository) -> str:
    for _ in range(_LINK_CODE_ATTEMPTS):
        code = new_link_code()
        if not repo.link_code_exists(code):
            return code
    raise ApiError(
        "LINK_CODE_UNAVAILABLE", "Please try again.", status.HTTP_503_SERVICE_UNAVAILABLE
    )


def _patient_ic(raw: str | None, role: UserRole, repo: UserRepository, uid: str) -> str | None:
    """D-51: patients must give a valid IC number that nobody else uses."""
    if role is not UserRole.PATIENT:
        return None
    if not raw:
        raise ApiError(
            "IC_REQUIRED", "Enter your IC number.", status.HTTP_422_UNPROCESSABLE_CONTENT
        )
    try:
        ic = parse_ic(raw).value
    except IcError as exc:
        raise ApiError("INVALID_IC", str(exc), status.HTTP_422_UNPROCESSABLE_CONTENT) from exc
    owner = repo.ic_owner(ic)
    if owner is not None and owner != uid:
        raise ApiError(
            "IC_IN_USE",
            "This IC number is already registered. Sign in instead, or contact support.",
            status.HTTP_409_CONFLICT,
        )
    return ic


@router.post("/register-profile", response_model=RegisterProfileResponse)
def register_profile(
    body: RegisterProfileRequest,
    user: CurrentUser = Depends(get_current_user),
    repo: UserRepository = Depends(get_user_repository),
    identity: IdentityProvider = Depends(get_identity_provider),
    audit: AuditLogger = Depends(get_audit_logger),
) -> RegisterProfileResponse:
    """UC1.1 steps 3-4: create the `users` doc and assign the Patient/Family role (FR-1.1)."""
    role = UserRole(body.role)
    existing = repo.get_user(user.uid)
    if existing is not None:
        if existing.get("role") != role.value:
            raise ApiError(
                "ALREADY_REGISTERED",
                "This account is already registered.",
                status.HTTP_409_CONFLICT,
            )
        # Idempotent retry (e.g. the app lost connection after the first call).
        identity.set_role(user.uid, role)
        return RegisterProfileResponse(
            uid=user.uid, role=role, onboardingComplete=existing.get("onboardingComplete")
        )
    if user.role is not None and user.role != role:
        # Staff accounts (FR-1.6) can never re-register as patient/family.
        raise ApiError(
            "ALREADY_REGISTERED", "This account is already registered.", status.HTTP_409_CONFLICT
        )
    if not user.email:
        raise ApiError("EMAIL_REQUIRED", "The account has no email address.")
    ic = _patient_ic(body.icNumber, role, repo, user.uid)

    doc: dict[str, Any] = {
        "email": user.email,
        "name": body.name,
        "role": role.value,
        "isActive": True,
    }
    if role is UserRole.PATIENT:
        doc |= {
            "icNumber": ic,  # D-51
            "onboardingComplete": False,
            "assignedDoctorId": None,
            "linkCode": _unique_link_code(repo),  # D-06
        }
    else:
        doc["patientId"] = None  # pending until linked (UC15.1)

    repo.create_user(user.uid, doc)
    identity.set_role(user.uid, role)
    audit.log(
        user_id=user.uid,
        action="REGISTER_ACCOUNT",
        details=f"Self-registered as {role.value}.",
        target_type=Collection.USERS.value,
        target_id=user.uid,
    )
    onboarding = False if role is UserRole.PATIENT else None
    return RegisterProfileResponse(uid=user.uid, role=role, onboardingComplete=onboarding)


@router.post("/onboarding", status_code=status.HTTP_201_CREATED)
def complete_onboarding(
    body: OnboardingRequest,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    repo: UserRepository = Depends(get_user_repository),
    assignments: AssignmentRepository = Depends(get_assignment_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """UC1.4: validate and store the health profile, mark onboarding complete (FR-1.4)."""
    existing = repo.get_user(user.uid)
    if existing is None:
        raise ApiError("PROFILE_NOT_FOUND", "Finish registration first.", status.HTTP_404_NOT_FOUND)
    if existing.get("isActive") is False:
        raise _deactivated()
    if existing.get("onboardingComplete"):
        raise ApiError(
            "ONBOARDING_ALREADY_COMPLETE",
            "Onboarding is already complete. Edit your profile in Settings.",
            status.HTTP_409_CONFLICT,
        )

    # D-25: each Ch4 String field holds a JSON object.
    profile = {
        "patientId": user.uid,
        "personalInfo": json.dumps(body.personalInfo.model_dump(mode="json")),
        "medicalHistory": json.dumps(body.medicalHistory.model_dump(mode="json")),
        "lifestyleFactors": json.dumps(body.lifestyleFactors.model_dump(mode="json")),
    }
    user_updates = {
        "dateOfBirth": datetime.combine(body.dateOfBirth, time.min, tzinfo=UTC),
        "gender": body.gender.value,
        "onboardingComplete": True,
    }
    repo.complete_onboarding(user.uid, profile, user_updates)
    audit.log(
        user_id=user.uid,
        action="COMPLETE_ONBOARDING",
        details="Onboarding health profile saved.",
        target_type=Collection.HEALTH_PROFILES.value,
        target_id=user.uid,
    )
    # D-54: every new patient appears in the admin's Assignments list automatically.
    if not str(existing.get("assignedDoctorId") or "").strip() and not assignments.has_pending(
        user.uid
    ):
        request_id = assignments.create(
            {
                "patientId": user.uid,
                "requestedBy": user.uid,
                "kind": AssignmentRequestKind.NEW_PATIENT.value,
                "status": AssignmentRequestStatus.PENDING.value,
            }
        )
        audit.log(
            user_id=user.uid,
            action="REQUEST_DOCTOR",
            details="Doctor requested automatically after onboarding.",
            target_type=Collection.DOCTOR_ASSIGNMENT_REQUESTS.value,
            target_id=request_id,
        )
    return {"status": "ok", "onboardingComplete": True}


@router.post("/session-events")
def session_event(
    body: SessionEventRequest,
    user: CurrentUser = Depends(get_current_user),
    repo: UserRepository = Depends(get_user_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """Audit sign-in / sign-out (FR-1.5) and enforce app + active-account checks on LOGIN."""
    if body.event is SessionEvent.LOGOUT:
        audit.log(user_id=user.uid, action="LOGOUT", details=f"Signed out of the {body.app} app.")
        return {"status": "ok"}

    if user.role not in APP_ROLES[body.app]:
        raise ApiError("WRONG_APP", "This account cannot use this app.", status.HTTP_403_FORBIDDEN)
    profile = repo.get_user(user.uid)
    if profile is None:
        raise ApiError("PROFILE_NOT_FOUND", "Finish registration first.", status.HTTP_404_NOT_FOUND)
    if profile.get("isActive") is False:
        audit.log(
            user_id=user.uid,
            action="LOGIN_BLOCKED",
            details=f"Deactivated account tried to sign in to the {body.app} app.",
        )
        raise _deactivated()

    audit.log(user_id=user.uid, action="LOGIN", details=f"Signed in to the {body.app} app.")
    return {
        "status": "ok",
        "role": user.role.value if user.role else None,
        "onboardingComplete": profile.get("onboardingComplete"),
    }


@lru_cache
def _failed_login_limiter() -> RateLimiter:
    return RateLimiter(get_settings().failed_login_rate_per_minute)


def get_failed_login_limiter() -> RateLimiter:
    return _failed_login_limiter()


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


@router.post("/login-failed", status_code=status.HTTP_202_ACCEPTED)
def login_failed(
    body: LoginFailedRequest,
    request: Request,
    limiter: RateLimiter = Depends(get_failed_login_limiter),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, str]:
    """D-27: unauthenticated report of a failed sign-in. Stores the email domain only."""
    if not limiter.allow(_client_ip(request)):
        raise ApiError(
            "RATE_LIMITED", "Too many attempts. Try again later.", status.HTTP_429_TOO_MANY_REQUESTS
        )
    audit.log(
        user_id=ANONYMOUS_USER,
        action="LOGIN_FAILED",
        details=f"app={body.app}; reason={body.reason}; emailDomain={body.email_domain()}",
    )
    return {"status": "recorded"}


# ---------------- D-65: password reset email through Brevo ----------------


@lru_cache
def _reset_limiter() -> RateLimiter:
    return RateLimiter(5)


def get_reset_limiter() -> RateLimiter:
    return _reset_limiter()


def password_reset_email(name: str, email: str, link: str) -> EmailMessage:
    greeting = f"Hello {name}," if name else "Hello,"
    text = (
        f"{greeting}\n\nWe received a request to reset your CareFlow password.\n"
        f"Choose a new password here (the link works for 1 hour):\n{link}\n\n"
        "Afterwards, return to the CareFlow app (or the staff portal) and sign in.\n"
        "If you did not ask for this, ignore this email; your password stays the same.\n"
    )
    safe_link = html.escape(link, quote=True)
    body = (
        f"<p>{html.escape(greeting)}</p>"
        "<p>We received a request to reset your <b>CareFlow</b> password.</p>"
        f'<p><a href="{safe_link}" style="background:#2D6A8E;color:#fff;padding:10px 18px;'
        'border-radius:20px;text-decoration:none">Reset password</a></p>'
        "<p>The link works for 1 hour. Afterwards, return to the CareFlow app (or the staff "
        "portal) and sign in.</p>"
        "<p>If you did not ask for this, ignore this email; your password stays the same.</p>"
    )
    return EmailMessage(
        to_email=email,
        to_name=name or email,
        subject="Reset your CareFlow password",
        text=text,
        html=body,
    )


@router.post("/password-reset", status_code=status.HTTP_202_ACCEPTED)
def request_password_reset(
    body: PasswordResetRequest,
    request: Request,
    limiter: RateLimiter = Depends(get_reset_limiter),
    identity: IdentityProvider = Depends(get_identity_provider),
    email_client: EmailClient = Depends(get_email_client),
    settings: Settings = Depends(get_settings),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, str]:
    """UC1.2 forgot password (D-65): Brevo email with Firebase's reset link. The answer is
    the same whether or not the account exists, so emails can't be probed."""
    if not limiter.allow(_client_ip(request)):
        raise ApiError(
            "RATE_LIMITED", "Too many attempts. Try again later.", status.HTTP_429_TOO_MANY_REQUESTS
        )
    email = body.email.strip().lower()
    found = identity.password_reset_link(
        email, f"{settings.public_base_url.rstrip('/')}/reset-done.html"
    )
    if found is not None:
        link, name = found
        try:
            email_client.send(password_reset_email(name, email, link))
        except Exception:  # never reveal provider problems to an anonymous caller
            log.exception("Password reset email failed")
        audit.log(
            user_id=ANONYMOUS_USER,
            action="PASSWORD_RESET_REQUESTED",
            details=f"Reset email sent; emailDomain={email.rsplit('@', 1)[-1]}.",
        )
    return {"status": "sent_if_exists"}
