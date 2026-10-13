"""POST /triage: symptom checker submission (FR-14.3; UC14.1, UC14.3, UC14.4; D-36).

The app sends the selected symptom ids and severity, plus the camera heart rate and the
id of a reading logged in the same session when the patient entered a BP. The server
gathers the latest vitals and risk, applies the rule table, saves `triage_outcomes`
and notifies the assigned doctor for contact_doctor / seek_emergency_care.
"""

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import (
    ClinicalAlertType,
    Collection,
    RiskLevel,
    TriageOutcome,
    TriageSeverity,
    UserRole,
)
from app.core.errors import ApiError
from app.services.bp import HEART_RATE_MAX, HEART_RATE_MIN
from app.services.escalation import DoctorAlert, EscalationPlan, Escalator, get_escalator
from app.services.triage import TriageRepository, classify, gather_inputs, get_triage_repository
from app.services.users import UserRepository, get_user_repository

router = APIRouter(prefix="/triage", tags=["triage"])


class TriageRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    symptoms: list[str] = Field(min_length=1, max_length=14)
    severity: TriageSeverity
    heartRate: int | None = Field(default=None, ge=HEART_RATE_MIN, le=HEART_RATE_MAX)  # noqa: N815
    vitalReadingId: str | None = Field(default=None, max_length=128)  # noqa: N815


_ALERT_SEVERITY = {
    TriageOutcome.CONTACT_DOCTOR: RiskLevel.HIGH,
    TriageOutcome.SEEK_EMERGENCY_CARE: RiskLevel.CRITICAL,
}


@router.post("", status_code=status.HTTP_201_CREATED)
def submit(
    body: TriageRequest,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    repo: TriageRepository = Depends(get_triage_repository),
    users: UserRepository = Depends(get_user_repository),
    escalator: Escalator = Depends(get_escalator),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    ids = list(dict.fromkeys(body.symptoms))
    catalog = repo.symptoms(ids)
    unknown = [i for i in ids if i not in catalog]
    if unknown:
        raise ApiError(
            "UNKNOWN_SYMPTOM",
            f"Unknown symptom: {', '.join(unknown)}.",
            status.HTTP_422_UNPROCESSABLE_CONTENT,
        )
    now = datetime.now(UTC)
    try:
        inputs = gather_inputs(repo, user.uid, body.vitalReadingId, body.heartRate, now)
    except LookupError as exc:
        raise ApiError("READING_NOT_FOUND", str(exc), status.HTTP_404_NOT_FOUND) from exc

    red_flags = [catalog[i].name for i in ids if catalog[i].is_red_flag]
    decision = classify(
        body.severity,
        red_flags,
        inputs.systolic,
        inputs.diastolic,
        inputs.heart_rate,
        inputs.risk_levels,
    )
    data: dict[str, Any] = {
        "patientId": user.uid,
        "symptoms": ids,  # references to symptom_catalog ids (docs/04 rule 3)
        "severity": body.severity.value,
        "outcome": decision.outcome.value,
    }
    if inputs.reading_id:
        data["vitalReadingId"] = inputs.reading_id
    outcome_id = repo.save_outcome(data)
    audit.log(
        user_id=user.uid,
        action="TRIAGE",
        details=f"Symptom checker outcome {decision.outcome.value} ({body.severity.value}).",
        target_type=Collection.TRIAGE_OUTCOMES.value,
        target_id=outcome_id,
    )

    # UC14.4: notify the assigned doctor for Moderate (contact) and Emergency outcomes.
    if decision.outcome in _ALERT_SEVERITY:
        profile = users.get_user(user.uid) or {}
        names = ", ".join(catalog[i].name for i in ids)
        bp = (
            f"BP {inputs.systolic}/{inputs.diastolic} mmHg"
            if inputs.systolic is not None
            else "no recent BP"
        )
        hr = f", HR {inputs.heart_rate} bpm (estimate)" if inputs.heart_rate else ""
        risk = (
            max(inputs.risk_levels, key=list(RiskLevel).index).value
            if inputs.risk_levels
            else "none"
        )
        label = (
            "URGENT triage: seek emergency care"
            if decision.outcome is TriageOutcome.SEEK_EMERGENCY_CARE
            else "Triage: contact doctor"
        )
        plan = EscalationPlan(
            doctor_alerts=[
                DoctorAlert(
                    ClinicalAlertType.TRIAGE,
                    _ALERT_SEVERITY[decision.outcome],
                    f"{label}. {profile.get('name') or 'Patient'} reported {names} "
                    f"({body.severity.value}); {bp}{hr}; overall risk {risk}.",
                )
            ]
        )
        escalator.apply(
            plan,
            user.uid,
            profile.get("assignedDoctorId"),
            now,
            reading_id=inputs.reading_id,
        )

    return {
        "id": outcome_id,
        "outcome": decision.outcome.value,
        "reason": decision.reason,
        "severity": body.severity.value,
        "symptoms": [
            {"id": i, "name": catalog[i].name, "isRedFlag": catalog[i].is_red_flag} for i in ids
        ],
        "systolic": inputs.systolic,
        "diastolic": inputs.diastolic,
        "heartRate": inputs.heart_rate,
        "missingInputs": inputs.missing,
        "doctorNotified": decision.outcome in _ALERT_SEVERITY,
    }
