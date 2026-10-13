"""Module 3: log a vital reading (FR-3.1, FR-3.2; Fig 4.1.1.3 VitalsCtrl).

Validates the plausible range (UC3.1 E1), saves the reading with an optional note
(UC3.2) and PPG heart rate (UC3.3), and returns the BP category and threshold alert
level. Then generates a risk score (UC9.1, docs/06 algorithm A) once the patient has
three readings, raises threshold and risk alerts (FR-9.1, FR-9.5; UC9.2, UC9.3) and
returns rule-based recommendations (FR-9.4).
"""

import logging
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, RiskLevel, UserRole
from app.core.errors import ApiError
from app.ml.risk_inputs import MIN_READINGS, existing_conditions
from app.ml.risk_model import RiskModel, RiskPrediction, get_risk_model
from app.schemas.vitals import LogReadingRequest, LogReadingResponse
from app.services.bp import alert_level, classify, plausibility_error
from app.services.escalation import (
    AlertRepository,
    Escalator,
    diagnosed_complications,
    get_alert_repository,
    get_escalator,
    plan_escalation,
)
from app.services.recommendations import recommendations
from app.services.risk import (
    NotEnoughReadingsError,
    RiskDataRepository,
    generate_risk_score,
    get_risk_data_repository,
)
from app.services.users import UserRepository, get_user_repository
from app.services.vitals import VitalsRepository, get_vitals_repository

log = logging.getLogger("careflow.vitals")

router = APIRouter(prefix="/vitals", tags=["vitals"])


@router.post("", response_model=LogReadingResponse, status_code=status.HTTP_201_CREATED)
def log_reading(
    body: LogReadingRequest,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    users: UserRepository = Depends(get_user_repository),
    vitals: VitalsRepository = Depends(get_vitals_repository),
    risk_repo: RiskDataRepository = Depends(get_risk_data_repository),
    risk_model: RiskModel | None = Depends(get_risk_model),
    audit: AuditLogger = Depends(get_audit_logger),
    alerts: AlertRepository = Depends(get_alert_repository),
    escalator: Escalator = Depends(get_escalator),
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
    risk: dict[str, object] | None = None
    risk_status = "ok"
    readings_until_risk = 0
    prediction: RiskPrediction | None = None
    score_id: str | None = None
    previous: dict[str, RiskLevel] = {}
    if risk_model is None:
        risk_status = "model_unavailable"
    else:
        # UC9.3: compare against the newest score stored before this reading.
        previous = alerts.latest_levels(user.uid)
        try:
            result = generate_risk_score(user.uid, risk_repo, risk_model)
        except NotEnoughReadingsError:
            risk_status = "not_enough_readings"
            readings_until_risk = max(
                MIN_READINGS - len(risk_repo.recent_readings(user.uid, MIN_READINGS)), 1
            )
        else:
            prediction, score_id = result.prediction, result.score_id
            risk = result.to_response()
            audit.log(
                user_id=user.uid,
                action="GENERATE_RISK_SCORE",
                details=f"Risk score after reading; overall {result.prediction.overall_level.value}"
                f"{'; reduced confidence' if result.inputs.low_confidence else ''}.",
                target_type=Collection.RISK_SCORES.value,
                target_id=result.score_id,
            )
    diagnosed = diagnosed_complications(existing_conditions(risk_repo.health_profile(user.uid)))
    if risk is not None:
        risk["diagnosed"] = sorted(c.value for c in diagnosed)

    plan = plan_escalation(
        str(profile.get("name") or "Your patient"),
        body.systolic,
        body.diastolic,
        alert,
        prediction,
        previous,
    )
    try:
        escalator.apply(
            plan,
            user.uid,
            profile.get("assignedDoctorId"),
            datetime.now(UTC),
            risk_score_id=score_id,
            reading_id=reading_id,
        )
    except Exception:
        # The reading and risk score are already saved; an alerting failure must not
        # make the patient think the reading was lost (and log it twice).
        log.exception("Escalation failed for reading %s", reading_id)
    return LogReadingResponse(
        id=reading_id,
        systolic=body.systolic,
        diastolic=body.diastolic,
        heartRate=body.heartRate,
        category=category,
        alertLevel=alert,
        risk=risk,
        riskStatus=risk_status,
        readingsUntilRisk=readings_until_risk,
        recommendations=recommendations(category, prediction, diagnosed),
        bookAppointmentPrompt=plan.book_appointment_prompt,
    )
