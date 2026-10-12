"""Module 3: log a vital reading (FR-3.1, FR-3.2; Fig 4.1.1.3 VitalsCtrl).

Validates the plausible range (UC3.1 E1), saves the reading with an optional note
(UC3.2) and PPG heart rate (UC3.3), and returns the BP category and threshold alert
level. Risk scoring (UC9.1) and alert delivery (UC9.2) hook in here in Increment 2.
"""

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.schemas.vitals import LogReadingRequest, LogReadingResponse
from app.services.bp import alert_level, classify, plausibility_error
from app.services.users import UserRepository, get_user_repository
from app.services.vitals import VitalsRepository, get_vitals_repository

router = APIRouter(prefix="/vitals", tags=["vitals"])


@router.post("", response_model=LogReadingResponse, status_code=status.HTTP_201_CREATED)
def log_reading(
    body: LogReadingRequest,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    users: UserRepository = Depends(get_user_repository),
    vitals: VitalsRepository = Depends(get_vitals_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> LogReadingResponse:
    reason = plausibility_error(body.systolic, body.diastolic, body.heartRate)
    if reason is not None:
        raise ApiError("READING_OUT_OF_RANGE", reason, status.HTTP_422_UNPROCESSABLE_CONTENT)

    profile = users.get_user(user.uid)
    if profile is None:
        raise ApiError("PROFILE_NOT_FOUND", "Finish registration first.", status.HTTP_404_NOT_FOUND)
    if profile.get("isActive") is False:
        raise ApiError(
            "ACCOUNT_DEACTIVATED",
            "This account has been deactivated. Please contact support.",
            status.HTTP_403_FORBIDDEN,
        )

    data: dict[str, object] = {
        "patientId": user.uid,
        "systolic": body.systolic,
        "diastolic": body.diastolic,
    }
    # Optional fields are omitted rather than stored as null (docs/04).
    if body.heartRate is not None:
        data["heartRate"] = body.heartRate
    if body.note:
        data["note"] = body.note
    reading_id = vitals.add_reading(data)

    category = classify(body.systolic, body.diastolic)
    alert = alert_level(category)
    audit.log(
        user_id=user.uid,
        action="LOG_VITAL_READING",
        details=f"Logged BP reading ({category.value}"
        f"{', heart rate attached' if body.heartRate is not None else ''}).",
        target_type=Collection.VITAL_READINGS.value,
        target_id=reading_id,
    )
    return LogReadingResponse(
        id=reading_id,
        systolic=body.systolic,
        diastolic=body.diastolic,
        heartRate=body.heartRate,
        category=category,
        alertLevel=alert,
    )
