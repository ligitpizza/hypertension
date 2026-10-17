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
from app.core.config import Settings, get_settings
from app.core.enums import AlertLevel, Collection, RiskLevel, UserRole
from app.core.errors import ApiError
from app.ml.risk_inputs import MIN_READINGS, existing_conditions
from app.ml.risk_model import RiskModel, RiskPrediction, get_risk_model
from app.schemas.vitals import LogReadingRequest, LogReadingResponse
from app.services.agent_context import AgentDataRepository, get_agent_data_repository
from app.services.appointment_extras import auto_book_emergency
from app.services.appointments import AppointmentRepository, get_appointment_repository
from app.services.bp import alert_level, classify, plausibility_error
from app.services.escalation import (
    AlertRepository,
    Escalator,
    diagnosed_complications,
    get_alert_repository,
    get_escalator,
    plan_escalation,
)
from app.services.notifications import Notifier, get_notifier
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
    agent: AgentDataRepository = Depends(get_agent_data_repository),
    appointments: AppointmentRepository = Depends(get_appointment_repository),
    notifier: Notifier = Depends(get_notifier),
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

    # D-37: the reading before this one decides the Mild follow-up rule; the recent ones
    # go into the doctor's emailed BP report.
    recent = risk_repo.recent_readings(user.uid, 7)
    previous_category = (
        classify(int(recent[1]["systolic"]), int(recent[1]["diastolic"]))
        if len(recent) > 1
        else None
    )
    plan = plan_escalation(
        str(profile.get("name") or "Your patient"),
        body.systolic,
        body.diastolic,
        alert,
        prediction,
        previous,
        heart_rate=body.heartRate,
        previous_category=previous_category,
        recent=recent,
    )
    try:
        escalator.apply(
            plan,
            user.uid,
            profile.get("assignedDoctorId"),
            datetime.now(UTC),
            risk_score_id=score_id,
            reading_id=reading_id,
            location=body.location.as_dict() if body.location else None,
        )
    except Exception:
        # The reading and risk score are already saved; an alerting failure must not
        # make the patient think the reading was lost (and log it twice).
        log.exception("Escalation failed for reading %s", reading_id)
    if plan.alert_level is AlertLevel.EMERGENCY:
        # docs/06 Emergency band / D-53: book the next free slot with the patient's doctor.
        try:
            booked = auto_book_emergency(
                appointments,
                notifier,
                user.uid,
                profile.get("assignedDoctorId"),
                datetime.now(UTC),
            )
            if booked:
                audit.log(
                    user_id="system:escalation",
                    action="AUTO_BOOK_EMERGENCY",
                    details="Emergency appointment booked after an Emergency-band reading.",
                    target_type=Collection.APPOINTMENTS.value,
                    target_id=booked,
                )
        except Exception:
            log.exception("Emergency auto-booking failed for reading %s", reading_id)
    if plan.agent_note:
        # D-37: the AI Health Agent's fixed advice (avoid exertion / stay calm) in the chat.
        try:
            agent.add_message(user.uid, "agent", plan.agent_note)
        except Exception:
            log.exception("Agent note failed for reading %s", reading_id)
    return LogReadingResponse(
        id=reading_id,
        systolic=body.systolic,
        diastolic=body.diastolic,
        heartRate=body.heartRate,
        category=category,
        alertLevel=plan.alert_level,
        risk=risk,
        riskStatus=risk_status,
        readingsUntilRisk=readings_until_risk,
        recommendations=recommendations(category, prediction, diagnosed),
        bookAppointmentPrompt=plan.book_appointment_prompt,
    )


# ---------------- D-78 testing aid: delete readings ----------------


@router.get("/dev-tools")
def dev_tools(
    _: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    settings: Settings = Depends(get_settings),
) -> dict[str, bool]:
    return {"enabled": settings.dev_vitals_tools}


def _rescore_after_delete(
    uid: str, vitals: VitalsRepository, risk_repo: RiskDataRepository, model: RiskModel | None
) -> bool:
    """Old scores go; a new one is made if three readings remain."""
    vitals.delete_risk_scores(uid)
    if model is None:
        return False
    try:
        generate_risk_score(uid, risk_repo, model)
    except NotEnoughReadingsError:
        return False
    return True


def _dev_enabled(settings: Settings) -> None:
    if not settings.dev_vitals_tools:
        raise ApiError("NOT_FOUND", "Not available.", status.HTTP_404_NOT_FOUND)


@router.delete("/{reading_id}")
def delete_reading(
    reading_id: str,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    settings: Settings = Depends(get_settings),
    vitals: VitalsRepository = Depends(get_vitals_repository),
    risk_repo: RiskDataRepository = Depends(get_risk_data_repository),
    model: RiskModel | None = Depends(get_risk_model),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, bool]:
    _dev_enabled(settings)
    r = vitals.reading(reading_id)
    if r is None or r.get("patientId") != user.uid:
        raise ApiError("READING_NOT_FOUND", "Reading not found.", status.HTTP_404_NOT_FOUND)
    vitals.delete_readings([reading_id])
    rescored = _rescore_after_delete(user.uid, vitals, risk_repo, model)
    audit.log(
        user_id=user.uid,
        action="DEV_DELETE_READING",
        details="Reading deleted (testing aid).",
        target_type=Collection.VITAL_READINGS.value,
        target_id=reading_id,
    )
    return {"rescored": rescored}


@router.delete("")
def clear_readings(
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    settings: Settings = Depends(get_settings),
    vitals: VitalsRepository = Depends(get_vitals_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, int]:
    _dev_enabled(settings)
    ids = vitals.reading_ids(user.uid)
    vitals.delete_readings(ids)
    vitals.delete_risk_scores(user.uid)
    audit.log(
        user_id=user.uid,
        action="DEV_CLEAR_READINGS",
        details=f"All {len(ids)} readings cleared (testing aid).",
        target_type=Collection.VITAL_READINGS.value,
        target_id=user.uid,
    )
    return {"deleted": len(ids)}
