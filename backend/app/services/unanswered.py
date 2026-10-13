"""Moderate -> Emergency auto-escalation (docs/06 §E "escalate to Emergency if the doctor
hasn't responded within the timeout", reference md Feature 4; D-37).

Every 15 minutes Cloud Scheduler calls /internal/jobs/escalation. An open `threshold` or
`triage` alert of severity high that the doctor has not acknowledged or dismissed within
RESPONSE_TIMEOUT raises a critical alert for the doctor and pushes the patient and family.
An escalation already raised is detected as "a critical alert of that type for the patient
since the original alert", so no extra field is needed.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import Depends

from app.core.enums import ClinicalAlertType, RiskLevel
from app.integrations.push import PushMessage
from app.services.escalation import (
    AlertRepository,
    DoctorAlert,
    EscalationPlan,
    Escalator,
    get_alert_repository,
    get_escalator,
)

RESPONSE_TIMEOUT = timedelta(hours=2)
ESCALATABLE = (ClinicalAlertType.THRESHOLD, ClinicalAlertType.TRIAGE)


@dataclass
class UnansweredAlertJob:
    alerts: AlertRepository
    escalator: Escalator

    def run(self, now: datetime | None = None) -> dict[str, Any]:
        now = now or datetime.now(UTC)
        checked = escalated = 0
        for alert in self.alerts.stale_open_alerts(RiskLevel.HIGH, now - RESPONSE_TIMEOUT):
            try:
                alert_type = ClinicalAlertType(str(alert.get("type")))
            except ValueError:
                continue
            if alert_type not in ESCALATABLE:
                continue
            checked += 1
            patient_id = str(alert["patientId"])
            created = alert.get("createdAt")
            since = created if isinstance(created, datetime) else now - RESPONSE_TIMEOUT
            if self.alerts.recent_alert_exists(
                patient_id, alert_type, since, at_least=RiskLevel.CRITICAL
            ):
                continue  # already escalated (or a crisis followed anyway)
            user = self.alerts.user(patient_id) or {}
            name = str(user.get("name") or "A patient")
            plan = EscalationPlan(
                patient_push=PushMessage(
                    "Your doctor hasn't responded yet",
                    "Your earlier alert has been escalated. If you feel worse, or have chest "
                    "pain, breathlessness, weakness or confusion, call 999 now.",
                    {"type": "escalation"},
                    urgent=True,
                ),
                doctor_alerts=[
                    DoctorAlert(
                        alert_type,
                        RiskLevel.CRITICAL,
                        f"ESCALATED: no response within 2 hours to: {alert.get('message', '')}",
                    )
                ],
                family_push=PushMessage(
                    f"{name}: alert escalated",
                    f"{name}'s doctor has not responded to a high blood pressure alert yet. "
                    "Please check on them; call 999 if they are unwell.",
                    {"type": "escalation"},
                    urgent=True,
                ),
            )
            doctor_id = alert.get("doctorId") or user.get("assignedDoctorId")
            if self.escalator.apply(plan, patient_id, doctor_id, now):
                escalated += 1
        return {"alertsChecked": checked, "alertsEscalated": escalated}


def get_unanswered_alert_job(
    alerts: AlertRepository = Depends(get_alert_repository),
    escalator: Escalator = Depends(get_escalator),
) -> UnansweredAlertJob:
    return UnansweredAlertJob(alerts, escalator)
