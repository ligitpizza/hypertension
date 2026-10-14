"""Feature 4 Mild / Moderate / Emergency band actions (docs/06 §E; reference md; D-37)."""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.enums import AlertLevel, BpCategory, Complication, RiskLevel
from app.integrations.email import ConsoleEmailClient
from app.integrations.push import LogPushClient
from app.ml.risk_model import ComplicationRisk, RiskPrediction
from app.services.escalation import (
    AVOID_EXERTION_NOTE,
    CALM_NOTE,
    MILD_DEDUPE_WINDOW,
    plan_escalation,
)
from app.services.unanswered import UnansweredAlertJob
from tests.conftest import (
    InMemoryAgentDataRepository,
    InMemoryAlertRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P = "u-patient"
PATIENT = bearer("patient-token")


def prediction(level: RiskLevel = RiskLevel.LOW) -> RiskPrediction:
    return RiskPrediction(
        scores={
            c: ComplicationRisk(0.3, level if c is Complication.CKD else RiskLevel.LOW)
            for c in Complication
        },
        model_used="XGBoost v1",
    )


# ---------- planner ----------


def test_mild_doctor_report_is_low_daily_and_emailed() -> None:
    plan = plan_escalation("Ali", 135, 85, AlertLevel.MILD, prediction(), None, heart_rate=70)
    [alert] = plan.doctor_alerts
    assert alert.severity is RiskLevel.LOW
    assert alert.dedupe == MILD_DEDUPE_WINDOW == timedelta(hours=24)
    assert alert.email_report is not None and "135/85" not in alert.email_report  # recent=[]
    assert "mild (stage 1)" in alert.message and "HR 70" in alert.message
    assert "medication review" not in alert.message
    assert plan.book_appointment_prompt  # optional booking offered
    assert plan.alert_level is AlertLevel.MILD


def test_mild_with_high_risk_flags_medication_review() -> None:
    plan = plan_escalation("Ali", 135, 85, AlertLevel.MILD, prediction(RiskLevel.HIGH), None)
    # A High risk score also raises its own risk_escalation alert; check the Mild one.
    [alert] = [a for a in plan.doctor_alerts if a.type.value == "threshold"]
    assert "medication review" in alert.message
    assert alert.email_report is not None and "medication review" in alert.email_report


def test_mild_report_lists_recent_readings() -> None:
    now = datetime(2026, 10, 13, 9, tzinfo=UTC)
    recent = [{"systolic": 135, "diastolic": 85, "timestamp": now, "heartRate": 70}]
    plan = plan_escalation("Ali", 135, 85, AlertLevel.MILD, None, None, recent=recent)
    report = plan.doctor_alerts[0].email_report or ""
    assert "13 Oct 2026 09:00 UTC: 135/85 mmHg, HR 70 bpm (camera estimate)" in report


@pytest.mark.parametrize(
    "previous,expected",
    [
        (BpCategory.STAGE1, AlertLevel.MODERATE),
        (BpCategory.STAGE2, AlertLevel.MODERATE),
        (BpCategory.CRISIS, AlertLevel.MODERATE),
        (BpCategory.ELEVATED, AlertLevel.MILD),
        (BpCategory.NORMAL, AlertLevel.MILD),
        (None, AlertLevel.MILD),
    ],
)
def test_mild_follow_up_still_abnormal_escalates_to_moderate(
    previous: BpCategory | None, expected: AlertLevel
) -> None:
    plan = plan_escalation("Ali", 135, 85, AlertLevel.MILD, None, None, previous_category=previous)
    assert plan.alert_level is expected
    if expected is AlertLevel.MODERATE:
        assert plan.doctor_alerts[0].severity is RiskLevel.HIGH
        assert "second abnormal reading in a row" in plan.doctor_alerts[0].message
        assert plan.agent_note == AVOID_EXERTION_NOTE


def test_moderate_message_has_bp_heart_rate_and_risk() -> None:
    plan = plan_escalation(
        "Ali", 150, 95, AlertLevel.MODERATE, prediction(RiskLevel.HIGH), None, heart_rate=88
    )
    msg = plan.doctor_alerts[0].message
    assert "150/95 mmHg" in msg and "HR 88" in msg and "overall risk high" in msg
    assert plan.agent_note == AVOID_EXERTION_NOTE


def test_emergency_agent_note_is_calm_and_mentions_999() -> None:
    plan = plan_escalation("Ali", 186, 122, AlertLevel.EMERGENCY, None, None)
    assert plan.agent_note == CALM_NOTE
    assert "stay calm" in CALM_NOTE and "999" in CALM_NOTE


# ---------- through POST /vitals ----------


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users[P] = {
        "name": "Siti",
        "role": "patient",
        "isActive": True,
        "assignedDoctorId": "u-doctor",
    }
    repo.users["u-doctor"] = {"name": "Dr John", "role": "doctor", "email": "john@clinic.test"}
    repo.users["u-family"] = {"role": "family_member", "patientId": P}
    for uid in (P, "u-doctor", "u-family"):
        tokens.add(uid, f"token-of-{uid}", "android")


def log(client: TestClient, sys: int, dia: int) -> dict[str, Any]:
    res = client.post("/api/v1/vitals", json={"systolic": sys, "diastolic": dia}, headers=PATIENT)
    assert res.status_code == 201
    body: dict[str, Any] = res.json()
    return body


def test_d37_mild_reading_emails_the_doctor_once_a_day(
    client: TestClient, emails: ConsoleEmailClient, alerts_repo: InMemoryAlertRepository
) -> None:
    first = log(client, 135, 85)
    assert first["alertLevel"] == "mild"
    assert first["bookAppointmentPrompt"] is True
    log(client, 118, 76)  # normal in between, so the next one is not a follow-up
    log(client, 136, 84)
    reports = [m for m in emails.sent if m.subject.startswith("CareFlow: patient BP report")]
    assert len(reports) == 1
    assert reports[0].to_email == "john@clinic.test"
    assert "135/85" in reports[0].text
    threshold = [a["severity"] for a in alerts_repo.alerts if a["type"] == "threshold"]
    assert threshold == ["low"]  # the risk score may add its own risk_escalation alert


def test_d37_second_abnormal_reading_in_a_row_is_moderate(
    client: TestClient, alerts_repo: InMemoryAlertRepository, push: LogPushClient
) -> None:
    log(client, 135, 85)
    second = log(client, 134, 86)
    assert second["alertLevel"] == "moderate"
    assert [a["severity"] for a in alerts_repo.alerts] == ["low", "high"]
    titles = [m.title for _, m in push.sent]
    assert "High blood pressure" in titles  # patient
    assert any(t.endswith(": high blood pressure") for t in titles)  # family


def test_d37_agent_notes_go_to_the_chat(
    client: TestClient, agent_repo: InMemoryAgentDataRepository
) -> None:
    log(client, 150, 95)
    log(client, 186, 122)
    notes = [m["text"] for m in agent_repo.messages if m["role"] == "agent"]
    assert notes == [AVOID_EXERTION_NOTE, CALM_NOTE]


# ---------- through POST /triage ----------


def triage(client: TestClient, **body: Any) -> dict[str, Any]:
    if "vitalReadingId" not in body:  # D-38: the checker always logs a fresh BP first
        body["vitalReadingId"] = log(client, 118, 76)["id"]
    payload = {"severity": "mild", "heartRate": 72, **body}
    res = client.post("/api/v1/triage", json=payload, headers=PATIENT)
    assert res.status_code == 201
    out: dict[str, Any] = res.json()
    return out


def test_d37_triage_contact_doctor_notifies_family_and_advises_rest(
    client: TestClient, push: LogPushClient, agent_repo: InMemoryAgentDataRepository
) -> None:
    assert (
        triage(client, symptoms=["dizziness"], severity="moderate")["outcome"] == "contact_doctor"
    )
    family = [m for tokens, m in push.sent if tokens == ["token-of-u-family"]]
    assert family and family[0].title == "Siti: symptom report"
    assert agent_repo.messages[-1]["text"] == AVOID_EXERTION_NOTE


def test_d37_triage_emergency_family_push_is_urgent_and_agent_calms(
    client: TestClient, push: LogPushClient, agent_repo: InMemoryAgentDataRepository
) -> None:
    assert triage(client, symptoms=["chest_pain"])["outcome"] == "seek_emergency_care"
    family = [m for tokens, m in push.sent if tokens == ["token-of-u-family"]]
    assert family[0].urgent and "999" in family[0].body
    assert agent_repo.messages[-1]["text"] == CALM_NOTE


def test_d37_triage_mild_band_reports_to_doctor_by_email(
    client: TestClient, emails: ConsoleEmailClient, alerts_repo: InMemoryAlertRepository
) -> None:
    reading = log(client, 135, 85)  # mild reading already sends today's report
    emails.sent.clear()
    alerts_repo.alerts.clear()
    body = triage(client, symptoms=["headache"], vitalReadingId=reading["id"])
    assert body["outcome"] == "monitor_at_home"
    [alert] = alerts_repo.alerts
    assert alert["type"] == "threshold" and alert["severity"] == "low"
    assert "symptom check: Headache" in alert["message"]
    assert emails.sent and "Symptom checker report" in emails.sent[0].text


# ---------- 2-hour unanswered escalation job ----------


def stale(alerts: InMemoryAlertRepository, hours: float, **kw: Any) -> None:
    alerts.alerts.append(
        {
            "patientId": P,
            "doctorId": "u-doctor",
            "type": "threshold",
            "severity": "high",
            "message": "Siti logged a stage 2 reading of 150/95 mmHg.",
            "status": "open",
            "createdAt": datetime.now(UTC) - timedelta(hours=hours),
            **kw,
        }
    )


def test_d37_unanswered_high_alert_escalates_once(
    client: TestClient, alerts_repo: InMemoryAlertRepository, push: LogPushClient
) -> None:
    stale(alerts_repo, 3)
    first = client.post("/internal/jobs/escalation").json()
    assert first["alertsChecked"] == 1 and first["alertsEscalated"] == 1
    critical = [a for a in alerts_repo.alerts if a["severity"] == "critical"]
    assert len(critical) == 1 and critical[0]["message"].startswith("ESCALATED: no response")
    titles = {m.title for _, m in push.sent}
    assert {"Your doctor hasn't responded yet", "Patient alert", "Siti: alert escalated"} <= titles
    again = client.post("/internal/jobs/escalation").json()
    assert again["alertsEscalated"] == 0


@pytest.mark.parametrize(
    "hours,extra",
    [
        (1, {}),  # not yet 2 hours
        (3, {"status": "acknowledged"}),  # the doctor responded
        (3, {"type": "risk_escalation"}),  # only threshold / triage alerts escalate
        (3, {"severity": "low"}),  # mild reports do not escalate
    ],
)
def test_d37_alerts_that_do_not_escalate(
    alerts_repo: InMemoryAlertRepository, hours: float, extra: dict[str, Any], client: TestClient
) -> None:
    stale(alerts_repo, hours, **extra)
    assert client.post("/internal/jobs/escalation").json()["alertsEscalated"] == 0


def test_job_unit_uses_given_time(alerts_repo: InMemoryAlertRepository) -> None:
    class NoEscalator:
        def apply(self, *a: Any, **k: Any) -> list[str]:
            return ["x"]

    stale(alerts_repo, 2.5)
    job = UnansweredAlertJob(alerts_repo, NoEscalator())  # type: ignore[arg-type]
    assert job.run(datetime.now(UTC) - timedelta(hours=1))["alertsChecked"] == 0
    assert job.run()["alertsChecked"] == 1
