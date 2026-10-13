"""Alerts and escalation after a reading (FR-9.1, FR-9.5; UC9.2, UC9.3; docs/06 §E, §F).

`plan_escalation` is a pure decision function (unit-tested rule by rule); `Escalator`
applies the plan: patient push, doctor clinical_alerts + push, family push.

Threshold alerts (docs/06 §E, D-37):
  Mild (stage 1)      -> patient push + doctor alert (low, at most once per 24 h) with an
                         emailed BP report; booking offered. A second abnormal reading in a
                         row (follow-up still >= 130/80) is treated as Moderate.
  Moderate (stage 2)  -> patient + assigned doctor (high: BP, heart rate, risk) + family
  Emergency (crisis)  -> patient (999 wording) + doctor (critical) + family
  An unacknowledged high alert is escalated to critical after 2 h (escalation job).
Risk (UC9.2/UC9.3):
  overall level rises to High/Critical -> doctor risk_escalation alert; patient asked to
  book an appointment (FR-7.5 prompt); Critical also notifies family (FR-9.5)
  any complication up two or more levels -> doctor medication_review flag (UC9.3 step 4)
Family GPS emergency alerts with SMS (emergency_alerts) are FR-14.2 (Increment 3).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Protocol

from fastapi import Depends
from firebase_admin import firestore

from app.core.audit import AuditLogger, get_audit_logger
from app.core.enums import (
    AlertLevel,
    BpCategory,
    ClinicalAlertStatus,
    ClinicalAlertType,
    Collection,
    Complication,
    RiskLevel,
    UserRole,
)
from app.core.firebase import get_firestore
from app.integrations.email import EmailClient, EmailMessage, get_email_client
from app.integrations.push import PushMessage
from app.ml.risk_inputs import CONDITION_COLUMNS
from app.ml.risk_model import RiskPrediction
from app.services.notifications import Notifier, get_notifier

log = logging.getLogger("careflow.escalation")

# Do not repeat a doctor alert of the same type and same or higher severity for the same
# patient within this window.
DEDUPE_WINDOW = timedelta(hours=2)
# D-37: the Mild doctor alert + emailed BP report goes out at most once a day per patient.
MILD_DEDUPE_WINDOW = timedelta(hours=24)
ABNORMAL = (BpCategory.STAGE1, BpCategory.STAGE2, BpCategory.CRISIS)
_ORDER = list(RiskLevel)


@dataclass(frozen=True)
class DoctorAlert:
    type: ClinicalAlertType
    severity: RiskLevel
    message: str
    dedupe: timedelta = DEDUPE_WINDOW
    # Plain-text BP report emailed to the assigned doctor when the alert is raised (Mild).
    email_report: str | None = None


@dataclass
class EscalationPlan:
    patient_push: PushMessage | None = None
    doctor_alerts: list[DoctorAlert] = field(default_factory=list)
    family_push: PushMessage | None = None
    book_appointment_prompt: bool = False
    # Effective alert level after the follow-up rule (Mild -> Moderate), for the response.
    alert_level: AlertLevel | None = None
    # Fixed AI Health Agent note saved to the patient's chat (D-37), not a Gemini call.
    agent_note: str | None = None

    def summary(self) -> list[str]:
        out = [f"doctor:{a.type.value}:{a.severity.value}" for a in self.doctor_alerts]
        if self.patient_push:
            out.append("patient_push")
        if self.family_push:
            out.append("family_push")
        return out


def _level_index(level: RiskLevel) -> int:
    return _ORDER.index(level)


AVOID_EXERTION_NOTE = (
    "Your blood pressure is high. Please avoid heavy physical exertion and rest while you "
    "wait for your doctor to respond. If you get chest pain, breathlessness, weakness or "
    "confusion, call 999 now."
)
CALM_NOTE = (
    "Your reading is very high. Try to stay calm: sit or lie down and breathe slowly. If you "
    "have chest pain, breathlessness, weakness, confusion or blurred vision, call 999 now. "
    "Your doctor has been notified. Do not drive yourself to hospital."
)


def _risk_text(prediction: RiskPrediction | None) -> str:
    return f"; overall risk {prediction.overall_level.value}" if prediction else ""


def bp_report(
    patient_name: str,
    recent: list[dict[str, Any]],
    prediction: RiskPrediction | None,
    review_note: str,
) -> str:
    """D-37 Mild email: recent readings and the risk breakdown, plain text."""
    lines = [f"BP report for {patient_name} (CareFlow).", "", "Recent readings, newest first:"]
    for r in recent[:7]:
        when = r.get("timestamp")
        stamp = when.strftime("%d %b %Y %H:%M UTC") if isinstance(when, datetime) else "just now"
        hr = f", HR {r['heartRate']} bpm (camera estimate)" if r.get("heartRate") else ""
        lines.append(f"- {stamp}: {r['systolic']}/{r['diastolic']} mmHg{hr}")
    if prediction is not None:
        lines += ["", f"Risk assessment (model estimate): overall {prediction.overall_level.value}"]
        lines += [
            f"- {c.value}: {round(s.value * 100)}% ({s.level.value})"
            for c, s in prediction.scores.items()
        ]
    if review_note:
        lines += ["", review_note]
    lines += ["", "Open the CareFlow staff portal to review the patient's record."]
    return "\n".join(lines)


def plan_escalation(
    patient_name: str,
    systolic: int,
    diastolic: int,
    alert: AlertLevel | None,
    prediction: RiskPrediction | None,
    previous: dict[str, RiskLevel] | None,
    heart_rate: int | None = None,
    previous_category: BpCategory | None = None,
    recent: list[dict[str, Any]] | None = None,
) -> EscalationPlan:
    """Decide who to notify. `previous` maps complication value -> level of the prior score;
    `previous_category` is the BP category of the reading before this one (D-37 follow-up)."""
    plan = EscalationPlan()
    bp = f"{systolic}/{diastolic} mmHg"
    hr = f", HR {heart_rate} bpm (estimate)" if heart_rate else ""
    follow_up = alert is AlertLevel.MILD and previous_category in ABNORMAL
    if follow_up:
        alert = AlertLevel.MODERATE  # the follow-up BP is still abnormal (D-37)
    plan.alert_level = alert
    data = {"type": "bp_alert", "level": alert.value if alert else ""}

    if alert is AlertLevel.MILD:
        plan.patient_push = PushMessage(
            "Blood pressure slightly high",
            f"Your reading {bp} is in the stage 1 range. Rest and measure again later.",
            data,
        )
        levels = [s.level for s in prediction.scores.values()] if prediction else []
        levels += list((previous or {}).values())
        high = any(level in (RiskLevel.HIGH, RiskLevel.CRITICAL) for level in levels)
        review = (
            "Risk factors are present (a complication risk is High or Critical): this patient "
            "may require a medication review."
            if high
            else ""
        )
        plan.doctor_alerts.append(
            DoctorAlert(
                ClinicalAlertType.THRESHOLD,
                RiskLevel.LOW,
                f"{patient_name} is in the mild (stage 1) range: {bp}{hr}{_risk_text(prediction)}."
                + (" May require a medication review." if high else ""),
                dedupe=MILD_DEDUPE_WINDOW,
                email_report=bp_report(patient_name, recent or [], prediction, review),
            )
        )
        plan.book_appointment_prompt = True  # optional booking offered
    elif alert is AlertLevel.MODERATE:
        plan.patient_push = PushMessage(
            "High blood pressure",
            f"Your reading {bp} is high. Avoid heavy exertion and contact your doctor.",
            data,
        )
        reason = "a second abnormal reading in a row" if follow_up else "a stage 2 reading"
        plan.doctor_alerts.append(
            DoctorAlert(
                ClinicalAlertType.THRESHOLD,
                RiskLevel.HIGH,
                f"{patient_name} logged {reason}: {bp}{hr}{_risk_text(prediction)}.",
            )
        )
        plan.family_push = PushMessage(
            f"{patient_name}: high blood pressure",
            f"{patient_name} logged a high reading ({bp}). You may want to check in.",
            data,
        )
        plan.book_appointment_prompt = True
        plan.agent_note = AVOID_EXERTION_NOTE
    elif alert is AlertLevel.EMERGENCY:
        plan.patient_push = PushMessage(
            "Very high blood pressure",
            f"Your reading {bp} is very high. If you have chest pain, breathlessness, "
            "weakness or confusion, call 999 now.",
            data,
            urgent=True,
        )
        plan.doctor_alerts.append(
            DoctorAlert(
                ClinicalAlertType.THRESHOLD,
                RiskLevel.CRITICAL,
                f"EMERGENCY: {patient_name} logged a hypertensive crisis reading of "
                f"{bp}{hr}{_risk_text(prediction)}.",
            )
        )
        plan.family_push = PushMessage(
            f"{patient_name}: emergency reading",
            f"{patient_name} logged a very high reading ({bp}). Please contact them now; "
            "call 999 if they are unwell.",
            data,
            urgent=True,
        )
        plan.book_appointment_prompt = True
        plan.agent_note = CALM_NOTE

    if prediction is None:
        return plan

    overall = prediction.overall_level
    prev_overall = max(previous.values(), key=_level_index) if previous else None
    rose = prev_overall is None or _level_index(overall) > _level_index(prev_overall)
    if overall in (RiskLevel.HIGH, RiskLevel.CRITICAL) and rose:
        top = [c.value for c, s in prediction.scores.items() if s.level is overall]
        plan.doctor_alerts.append(
            DoctorAlert(
                ClinicalAlertType.RISK_ESCALATION,
                overall,
                f"{patient_name}'s risk rose to {overall.value} ({', '.join(top)}).",
            )
        )
        plan.book_appointment_prompt = True
        if plan.patient_push is None:
            plan.patient_push = PushMessage(
                "Your risk assessment changed",
                f"Your risk is now {overall.value}. Please book an appointment with your doctor.",
                {"type": "risk", "level": overall.value},
                urgent=overall is RiskLevel.CRITICAL,
            )
        if overall is RiskLevel.CRITICAL and plan.family_push is None:
            plan.family_push = PushMessage(
                f"{patient_name}: critical health risk",
                f"{patient_name}'s health risk assessment is critical. Please check on them.",
                {"type": "risk", "level": overall.value},
                urgent=True,
            )

    if previous:
        jumped = [
            c.value
            for c, s in prediction.scores.items()
            if c.value in previous and _level_index(s.level) - _level_index(previous[c.value]) >= 2
        ]
        if jumped:
            plan.doctor_alerts.append(
                DoctorAlert(
                    ClinicalAlertType.MEDICATION_REVIEW,
                    RiskLevel.HIGH,
                    f"Consider a medication review for {patient_name}: risk rose sharply "
                    f"({', '.join(jumped)}).",
                )
            )
    return plan


# ---------------- applying the plan ----------------


class AlertRepository(Protocol):
    def latest_levels(self, uid: str) -> dict[str, RiskLevel]: ...

    def family_member_ids(self, uid: str) -> list[str]: ...

    def recent_alert_exists(
        self,
        uid: str,
        alert_type: ClinicalAlertType,
        since: datetime,
        at_least: RiskLevel = RiskLevel.LOW,
    ) -> bool:
        """An alert of this type and at least this severity was raised since `since`."""
        ...

    def create_alert(self, data: dict[str, Any]) -> str: ...

    def user(self, uid: str) -> dict[str, Any] | None: ...

    def stale_open_alerts(self, severity: RiskLevel, before: datetime) -> list[dict[str, Any]]:
        """Open alerts of this severity created before `before` (with their id)."""
        ...


class FirestoreAlertRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def latest_levels(self, uid: str) -> dict[str, RiskLevel]:
        """Levels of the newest stored risk score (read before the new one is saved)."""
        query = (
            self._db.collection(Collection.RISK_SCORES.value)
            .where(filter=firestore.FieldFilter("patientId", "==", uid))
            .order_by("generatedAt", direction=firestore.Query.DESCENDING)
            .limit(1)
        )
        for doc in query.stream():
            scores = doc.to_dict().get("scores", {})
            return {k: RiskLevel(v["level"]) for k, v in scores.items()}
        return {}

    def family_member_ids(self, uid: str) -> list[str]:
        query = (
            self._db.collection(Collection.USERS.value)
            .where(filter=firestore.FieldFilter("role", "==", UserRole.FAMILY_MEMBER.value))
            .where(filter=firestore.FieldFilter("patientId", "==", uid))
        )
        return [d.id for d in query.stream()]

    def recent_alert_exists(
        self,
        uid: str,
        alert_type: ClinicalAlertType,
        since: datetime,
        at_least: RiskLevel = RiskLevel.LOW,
    ) -> bool:
        query = (
            self._db.collection(Collection.CLINICAL_ALERTS.value)
            .where(filter=firestore.FieldFilter("patientId", "==", uid))
            .where(filter=firestore.FieldFilter("type", "==", alert_type.value))
            .where(filter=firestore.FieldFilter("createdAt", ">=", since))
        )
        return any(
            _level_index(RiskLevel(d.get("severity"))) >= _level_index(at_least)
            for d in query.stream()
        )

    def create_alert(self, data: dict[str, Any]) -> str:
        _, ref = self._db.collection(Collection.CLINICAL_ALERTS.value).add(
            {**data, "createdAt": firestore.SERVER_TIMESTAMP}
        )
        return str(ref.id)

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def stale_open_alerts(self, severity: RiskLevel, before: datetime) -> list[dict[str, Any]]:
        query = (
            self._db.collection(Collection.CLINICAL_ALERTS.value)
            .where(filter=firestore.FieldFilter("status", "==", ClinicalAlertStatus.OPEN.value))
            .where(filter=firestore.FieldFilter("severity", "==", severity.value))
            .where(filter=firestore.FieldFilter("createdAt", "<=", before))
            .limit(200)
        )
        return [{**d.to_dict(), "id": d.id} for d in query.stream()]


def get_alert_repository() -> AlertRepository:
    return FirestoreAlertRepository(get_firestore())


class Escalator:
    def __init__(
        self,
        alerts: AlertRepository,
        notifier: Notifier,
        audit: AuditLogger,
        email: EmailClient | None = None,
    ) -> None:
        self._alerts = alerts
        self._notifier = notifier
        self._audit = audit
        self._email = email

    def apply(
        self,
        plan: EscalationPlan,
        patient_id: str,
        doctor_id: str | None,
        now: datetime,
        risk_score_id: str | None = None,
        reading_id: str | None = None,
    ) -> list[str]:
        """Execute the plan; returns ids of created clinical alerts."""
        created: list[str] = []
        if plan.patient_push:
            self._notifier.notify(patient_id, plan.patient_push)
        for alert in plan.doctor_alerts:
            # A milder earlier alert must never hide a more severe one (e.g. emergency
            # after a stage 2 alert); only an equal or more severe one is a duplicate.
            if self._alerts.recent_alert_exists(
                patient_id, alert.type, now - alert.dedupe, at_least=alert.severity
            ):
                continue
            data: dict[str, Any] = {
                "patientId": patient_id,
                "doctorId": doctor_id,
                "type": alert.type.value,
                "severity": alert.severity.value,
                "message": alert.message,
                "status": ClinicalAlertStatus.OPEN.value,
            }
            if risk_score_id:
                data["riskScoreId"] = risk_score_id
            if reading_id:
                data["vitalReadingId"] = reading_id
            alert_id = self._alerts.create_alert(data)
            created.append(alert_id)
            if doctor_id:
                self._notifier.notify(
                    doctor_id,
                    PushMessage(
                        "Patient alert",
                        alert.message,
                        {"type": "clinical_alert", "alertId": alert_id, "patientId": patient_id},
                        urgent=alert.severity is RiskLevel.CRITICAL,
                    ),
                )
            if doctor_id and alert.email_report:
                self._email_doctor(doctor_id, alert)
            self._audit.log(
                user_id="system:escalation",
                action="CLINICAL_ALERT",
                details=f"{alert.type.value} ({alert.severity.value})"
                f"{'' if doctor_id else '; no assigned doctor'}.",
                target_type=Collection.CLINICAL_ALERTS.value,
                target_id=alert_id,
            )
        if plan.family_push:
            for member in self._alerts.family_member_ids(patient_id):
                self._notifier.notify(member, plan.family_push)
        return created

    def _email_doctor(self, doctor_id: str, alert: DoctorAlert) -> None:
        """D-37 Mild: BP report by email. Failures never break the reading flow."""
        if self._email is None or alert.email_report is None:
            return
        doctor = self._alerts.user(doctor_id) or {}
        address = doctor.get("email")
        if not address:
            return
        text = alert.email_report
        try:
            self._email.send(
                EmailMessage(
                    to_email=str(address),
                    to_name=str(doctor.get("name") or "Doctor"),
                    subject="CareFlow: patient BP report (mild range)",
                    text=text,
                    html='<pre style="font-family:sans-serif">'
                    + text.replace("&", "&amp;").replace("<", "&lt;")
                    + "</pre>",
                )
            )
        except Exception:
            log.exception("BP report email failed")


def get_escalator(
    alerts: AlertRepository = Depends(get_alert_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
    email: EmailClient = Depends(get_email_client),
) -> Escalator:
    return Escalator(alerts, notifier, audit, email)


def diagnosed_complications(conditions: list[str]) -> set[Complication]:
    """Onboarding conditions that are already diagnosed (shown as such, not as a risk)."""
    return {Complication(CONDITION_COLUMNS[c]) for c in conditions if c in CONDITION_COLUMNS}
