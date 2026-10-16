"""Module 12 settings API (FR-12.1, FR-12.2; UC12.1-UC12.4; D-45, D-46, D-47).

PUT    /settings/profile          name, date of birth, gender (UC12.1)
PUT    /settings/contact          phone, emergency contact (UC12.1)
PUT    /settings/health-profile   health profile; re-scores if risk inputs changed (UC12.2)
PUT    /settings/notifications    D-45 preferences
GET    /settings/export           ?format=pdf|json (UC12.3)
DELETE /settings/account          deactivate now, purge after 7 days (UC12.4, D-46)
"""

import json
import logging
from datetime import UTC, datetime, time
from typing import Any, Literal

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.ml.risk_model import RiskModel, get_risk_model
from app.schemas.settings import (
    AddressUpdate,
    ContactUpdate,
    HealthProfileUpdate,
    NotificationPrefs,
    PersonalInfoUpdate,
)
from app.services.ic import IcError, parse_ic
from app.services.identity import IdentityProvider, get_identity_provider
from app.services.notifications import TokenRepository, get_token_repository
from app.services.risk import (
    NotEnoughReadingsError,
    RiskDataRepository,
    generate_risk_score,
    get_risk_data_repository,
)
from app.services.settings import (
    DELETION_GRACE,
    SettingsRepository,
    build_export,
    export_pdf,
    get_settings_repository,
    parse_profile_field,
)
from app.services.users import UserRepository, get_user_repository

router = APIRouter(prefix="/settings", tags=["settings"])
log = logging.getLogger("careflow.settings")
patient_only = require_roles(UserRole.PATIENT)


def _active_patient(repo: SettingsRepository, uid: str) -> dict[str, Any]:
    user = repo.user(uid)
    if user is None:
        raise ApiError("PROFILE_NOT_FOUND", "Profile not found.", status.HTTP_404_NOT_FOUND)
    if user.get("isActive") is False:
        raise ApiError(
            "ACCOUNT_DEACTIVATED", "This account is deactivated.", status.HTTP_403_FORBIDDEN
        )
    return user


def _rescore(uid: str, risk_repo: RiskDataRepository, model: RiskModel | None) -> bool:
    """UC12.2 step 3: re-run UC9.1 after a relevant change. Never fails the save."""
    if model is None:
        return False
    try:
        generate_risk_score(uid, risk_repo, model)
    except NotEnoughReadingsError:
        return False
    except Exception:
        log.exception("Re-score after profile edit failed for %s", uid)
        return False
    return True


@router.put("/profile")
def update_profile(
    body: PersonalInfoUpdate,
    user: CurrentUser = Depends(patient_only),
    repo: SettingsRepository = Depends(get_settings_repository),
    users: UserRepository = Depends(get_user_repository),
    risk_repo: RiskDataRepository = Depends(get_risk_data_repository),
    model: RiskModel | None = Depends(get_risk_model),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    current = _active_patient(repo, user.uid)
    dob = datetime.combine(body.dateOfBirth, time.min, tzinfo=UTC)
    old_dob = current.get("dateOfBirth")
    old_dob = old_dob.date() if isinstance(old_dob, datetime) else None
    changed_inputs = old_dob != body.dateOfBirth or current.get("gender") != body.gender.value
    updates: dict[str, Any] = {"name": body.name, "dateOfBirth": dob, "gender": body.gender.value}
    if body.icNumber:  # D-51
        try:
            ic = parse_ic(body.icNumber).value
        except IcError as exc:
            raise ApiError("INVALID_IC", str(exc), status.HTTP_422_UNPROCESSABLE_CONTENT) from exc
        owner = users.ic_owner(ic)
        if owner is not None and owner != user.uid:
            raise ApiError(
                "IC_IN_USE", "This IC number is already registered.", status.HTTP_409_CONFLICT
            )
        updates["icNumber"] = ic
    repo.update_user(user.uid, updates)
    rescored = changed_inputs and _rescore(user.uid, risk_repo, model)
    audit.log(
        user_id=user.uid,
        action="UPDATE_PROFILE",
        details="Personal information updated.",
        target_type=Collection.USERS.value,
        target_id=user.uid,
    )
    return {"status": "ok", "rescored": rescored}


@router.put("/contact")
def update_contact(
    body: ContactUpdate,
    user: CurrentUser = Depends(patient_only),
    repo: SettingsRepository = Depends(get_settings_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    _active_patient(repo, user.uid)
    personal = parse_profile_field((repo.health_profile(user.uid) or {}).get("personalInfo"))
    personal["phone"] = body.phone
    personal["emergencyContact"] = (
        body.emergencyContact.model_dump(mode="json") if body.emergencyContact else None
    )
    repo.update_health_profile(user.uid, {"personalInfo": json.dumps(personal)})
    audit.log(
        user_id=user.uid,
        action="UPDATE_PROFILE",
        details="Contact details updated.",
        target_type=Collection.HEALTH_PROFILES.value,
        target_id=user.uid,
    )
    return {"status": "ok"}


def _risk_relevant(personal: dict[str, Any], history: dict[str, Any], life: dict[str, Any]) -> Any:
    """The health-profile values the risk model reads (D-31)."""
    return (
        personal.get("heightCm"),
        personal.get("weightKg"),
        sorted(history.get("conditions") or []),
        sorted(history.get("familyHistory") or []),
        history.get("hypertensionDiagnosedYear"),
        life.get("smokingStatus"),
    )


@router.put("/health-profile")
def update_health_profile(
    body: HealthProfileUpdate,
    user: CurrentUser = Depends(patient_only),
    repo: SettingsRepository = Depends(get_settings_repository),
    risk_repo: RiskDataRepository = Depends(get_risk_data_repository),
    model: RiskModel | None = Depends(get_risk_model),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    current = _active_patient(repo, user.uid)
    if not current.get("onboardingComplete"):
        raise ApiError(
            "ONBOARDING_INCOMPLETE",
            "Finish onboarding first.",
            status.HTTP_409_CONFLICT,
        )
    stored = repo.health_profile(user.uid) or {}
    personal = parse_profile_field(stored.get("personalInfo"))
    before = _risk_relevant(
        personal,
        parse_profile_field(stored.get("medicalHistory")),
        parse_profile_field(stored.get("lifestyleFactors")),
    )
    personal.update({"heightCm": body.heightCm, "weightKg": body.weightKg})
    history = body.medicalHistory.model_dump(mode="json")
    life = body.lifestyleFactors.model_dump(mode="json")
    repo.update_health_profile(
        user.uid,
        {
            "personalInfo": json.dumps(personal),
            "medicalHistory": json.dumps(history),
            "lifestyleFactors": json.dumps(life),
        },
    )
    rescored = _risk_relevant(personal, history, life) != before and _rescore(
        user.uid, risk_repo, model
    )
    audit.log(
        user_id=user.uid,
        action="UPDATE_HEALTH_PROFILE",
        details=f"Health profile updated{'; risk re-scored' if rescored else ''}.",
        target_type=Collection.HEALTH_PROFILES.value,
        target_id=user.uid,
    )
    return {"status": "ok", "rescored": rescored}


@router.put("/notifications")
def update_notifications(
    body: NotificationPrefs,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT, UserRole.FAMILY_MEMBER)),
    repo: SettingsRepository = Depends(get_settings_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    _active_patient(repo, user.uid)
    prefs = body.model_dump()
    repo.update_user(user.uid, {"notificationPrefs": prefs})
    audit.log(
        user_id=user.uid,
        action="UPDATE_NOTIFICATION_PREFS",
        details=", ".join(f"{k}={'on' if v else 'off'}" for k, v in prefs.items()),
        target_type=Collection.USERS.value,
        target_id=user.uid,
    )
    return prefs


@router.get("/export")
def export_data(
    format: Literal["pdf", "json"] = Query(default="pdf"),
    user: CurrentUser = Depends(patient_only),
    repo: SettingsRepository = Depends(get_settings_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> Response:
    """UC12.3: built on demand, never stored (D-16, D-47). E1: failure -> 500, app retries."""
    profile = _active_patient(repo, user.uid)
    now = datetime.now(UTC)
    try:
        data = build_export(
            profile,
            repo.health_profile(user.uid),
            repo.export_records(user.uid),
            repo.care_plan(user.uid),
            now,
        )
        content = (
            export_pdf(data)
            if format == "pdf"
            else json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
        )
    except Exception as exc:
        log.exception("Export failed for %s", user.uid)
        raise ApiError(
            "EXPORT_FAILED",
            "We could not create your export. Please try again.",
            status.HTTP_500_INTERNAL_SERVER_ERROR,
        ) from exc
    audit.log(
        user_id=user.uid,
        action="EXPORT_DATA",
        details=f"Health data exported as {format.upper()}.",
        target_type=Collection.USERS.value,
        target_id=user.uid,
    )
    name = f"careflow-export-{now:%Y%m%d}.{format}"
    return Response(
        content=content,
        media_type="application/pdf" if format == "pdf" else "application/json",
        headers={"Content-Disposition": f'attachment; filename="{name}"'},
    )


@router.delete("/account")
def delete_account(
    acknowledge_recurring: bool = Query(default=False, alias="acknowledgeRecurring"),
    user: CurrentUser = Depends(patient_only),
    repo: SettingsRepository = Depends(get_settings_repository),
    tokens: TokenRepository = Depends(get_token_repository),
    identity: IdentityProvider = Depends(get_identity_provider),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """UC12.4: deactivate now; the daily job purges after the grace period (D-46)."""
    _active_patient(repo, user.uid)
    recurring = repo.recurring_prescriptions(user.uid)
    if recurring and not acknowledge_recurring:
        # UC12.4 E1: warn that recurring prescriptions will stop.
        raise ApiError(
            "ACTIVE_RECURRING_PRESCRIPTION",
            "You have a recurring prescription. Deleting your account will cancel it.",
            status.HTTP_409_CONFLICT,
            details={"prescriptions": [str(p.get("medicationDetails", "")) for p in recurring]},
        )
    now = datetime.now(UTC)
    repo.update_user(user.uid, {"isActive": False, "deletionRequestedAt": now})
    for token in tokens.tokens(user.uid):
        tokens.remove(user.uid, token)
    try:
        identity.revoke_sessions(user.uid)
    except Exception:
        log.exception("Could not revoke sessions for %s", user.uid)
    audit.log(
        user_id=user.uid,
        action="REQUEST_ACCOUNT_DELETION",
        details=f"Account deactivated; data removed after {DELETION_GRACE.days} days.",
        target_type=Collection.USERS.value,
        target_id=user.uid,
    )
    return {"status": "deactivated", "purgeAfter": (now + DELETION_GRACE).isoformat()}


@router.put("/address")
def update_address(
    body: AddressUpdate,
    user: CurrentUser = Depends(patient_only),
    repo: SettingsRepository = Depends(get_settings_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """D-69: the patient's address (text + map point) for deliveries."""
    _active_patient(repo, user.uid)
    repo.update_user(
        user.uid,
        {"address": body.address, "addressLat": body.lat, "addressLng": body.lng},
    )
    audit.log(
        user_id=user.uid,
        action="UPDATE_PROFILE",
        details="Address updated.",
        target_type=Collection.USERS.value,
        target_id=user.uid,
    )
    return {"status": "ok"}
