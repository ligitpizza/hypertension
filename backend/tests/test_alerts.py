"""Module 9 alerts, escalation, recommendations and deterioration
(FR-9.1, FR-9.4, FR-9.5, FR-9.6; UC9.2, UC9.3; D-32, D-33)."""

import json
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.enums import AlertLevel, BpCategory, ClinicalAlertType, Complication, RiskLevel
from app.integrations.push import LogPushClient, PushMessage
from app.ml.risk_model import ComplicationRisk, RiskPrediction
from app.services.deterioration import deteriorating, slope_per_day, worsening_complications
from app.services.escalation import diagnosed_complications, plan_escalation
from app.services.notifications import Notifier
from app.services.recommendations import DISCLAIMER, recommendations
from tests.conftest import (
    InMemoryAlertRepository,
    InMemoryAuditLogger,
    InMemoryDeteriorationRepository,
    InMemoryRiskRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    bearer,
)

NOW = datetime(2026, 10, 13, 9, tzinfo=UTC)


def prediction(**levels: RiskLevel) -> RiskPrediction:
    """All complications LOW unless given, e.g. prediction(stroke=RiskLevel.HIGH)."""
    return RiskPrediction(
        scores={c: ComplicationRisk(0.5, levels.get(c.value, RiskLevel.LOW)) for c in Complication},
        model_used="XGBoost v1",
    )


def prev(**levels: RiskLevel) -> dict[str, RiskLevel]:
    return {c.value: levels.get(c.value, RiskLevel.LOW) for c in Complication}


# ---------- FR-9.1 threshold alerts (docs/06 §E) ----------


def test_fr_9_1_normal_reading_notifies_nobody() -> None:
    plan = plan_escalation("Ali", 118, 76, None, None, None)
    assert plan.summary() == []
    assert not plan.book_appointment_prompt


def test_fr_9_1_mild_notifies_patient_only() -> None:
    plan = plan_escalation("Ali", 135, 85, AlertLevel.MILD, None, None)
    assert plan.summary() == ["patient_push"]


def test_fr_9_1_moderate_alerts_doctor_and_family() -> None:
    plan = plan_escalation("Ali", 150, 95, AlertLevel.MODERATE, None, None)
    assert plan.summary() == ["doctor:threshold:high", "patient_push", "family_push"]
    assert plan.book_appointment_prompt


def test_fr_9_1_emergency_is_critical_urgent_and_mentions_999() -> None:
    plan = plan_escalation("Ali", 185, 125, AlertLevel.EMERGENCY, None, None)
    assert plan.summary() == ["doctor:threshold:critical", "patient_push", "family_push"]
    assert plan.patient_push is not None and plan.patient_push.urgent
    assert "999" in plan.patient_push.body
    assert plan.family_push is not None and "999" in plan.family_push.body


# ---------- FR-9.5 / UC9.2 / UC9.3 risk escalation ----------


def test_uc9_2_first_high_score_alerts_doctor_and_prompts_booking() -> None:
    plan = plan_escalation("Ali", 125, 80, None, prediction(stroke=RiskLevel.HIGH), None)
    assert plan.summary() == ["doctor:risk_escalation:high", "patient_push"]
    assert plan.book_appointment_prompt
    assert "stroke" in plan.doctor_alerts[0].message


def test_uc9_3_unchanged_high_level_does_not_re_alert() -> None:
    plan = plan_escalation(
        "Ali",
        125,
        80,
        None,
        prediction(stroke=RiskLevel.HIGH),
        prev(cad=RiskLevel.HIGH, stroke=RiskLevel.MODERATE),
    )
    assert plan.doctor_alerts == []


def test_fr_9_5_critical_also_notifies_family() -> None:
    plan = plan_escalation(
        "Ali", 125, 80, None, prediction(ckd=RiskLevel.CRITICAL), prev(ckd=RiskLevel.HIGH)
    )
    assert plan.summary() == ["doctor:risk_escalation:critical", "patient_push", "family_push"]


def test_moderate_overall_risk_raises_nothing() -> None:
    plan = plan_escalation("Ali", 125, 80, None, prediction(cad=RiskLevel.MODERATE), prev())
    assert plan.summary() == []


def test_uc9_3_step4_two_level_jump_flags_medication_review() -> None:
    plan = plan_escalation(
        "Ali", 125, 80, None, prediction(t2d=RiskLevel.HIGH), prev(t2d=RiskLevel.LOW)
    )
    types = [a.type for a in plan.doctor_alerts]
    assert types == [ClinicalAlertType.RISK_ESCALATION, ClinicalAlertType.MEDICATION_REVIEW]


def test_threshold_and_risk_alerts_combine_with_one_patient_push() -> None:
    plan = plan_escalation(
        "Ali",
        150,
        95,
        AlertLevel.MODERATE,
        prediction(stroke=RiskLevel.HIGH),
        prev(stroke=RiskLevel.MODERATE),
    )
    assert [a.type.value for a in plan.doctor_alerts] == ["threshold", "risk_escalation"]
    assert plan.patient_push is not None and plan.patient_push.title == "High blood pressure"


# ---------- FR-9.4 recommendations ----------


def test_fr_9_4_bp_tip_first_disclaimer_last() -> None:
    tips = recommendations(BpCategory.NORMAL, None)
    assert "normal range" in tips[0]
    assert tips[-1] == DISCLAIMER


def test_fr_9_4_crisis_tip_points_to_999() -> None:
    assert "999" in recommendations(BpCategory.CRISIS, None)[0]


def test_fr_9_4_high_risk_adds_booking_and_focus_tips_but_skips_diagnosed() -> None:
    tips = recommendations(
        BpCategory.STAGE1,
        prediction(stroke=RiskLevel.HIGH, t2d=RiskLevel.CRITICAL),
        {Complication.T2D},
    )
    joined = " ".join(tips)
    assert "critical" in joined  # overall level tip
    assert "stroke warning signs" in joined
    assert "blood sugar" not in joined  # already diagnosed with diabetes


def test_diagnosed_complications_map_onboarding_conditions() -> None:
    assert diagnosed_complications(["diabetes", "high_cholesterol", "heart_disease"]) == {
        Complication.T2D,
        Complication.CAD,
    }


# ---------- push delivery (D-33) ----------


class RejectingPush(LogPushClient):
    def send(self, tokens: list[str], message: PushMessage) -> list[str]:
        super().send(tokens, message)
        return [t for t in tokens if t.startswith("stale")]


class BrokenPush:
    def send(self, tokens: list[str], message: PushMessage) -> list[str]:
        raise RuntimeError("FCM down")


def test_d33_invalid_tokens_are_removed() -> None:
    tokens = InMemoryTokenRepository()
    tokens.add("u1", "stale-token-1", "android")
    tokens.add("u1", "good-token-1", "android")
    sent = Notifier(tokens, RejectingPush()).notify("u1", PushMessage("t", "b"))
    assert sent == 1
    assert tokens.tokens("u1") == ["good-token-1"]


def test_d33_push_failure_never_raises() -> None:
    tokens = InMemoryTokenRepository()
    tokens.add("u1", "good-token-1", "android")
    assert Notifier(tokens, BrokenPush()).notify("u1", PushMessage("t", "b")) == 0


def test_d33_register_and_remove_device_token(
    client: TestClient, tokens: InMemoryTokenRepository
) -> None:
    body = {"token": "fcm-token-abcdef", "platform": "android"}
    assert (
        client.post(
            "/api/v1/devices/fcm-token", json=body, headers=bearer("patient-token")
        ).status_code
        == 204
    )
    assert tokens.tokens("u-patient") == ["fcm-token-abcdef"]
    res = client.request(
        "DELETE", "/api/v1/devices/fcm-token", json=body, headers=bearer("patient-token")
    )
    assert res.status_code == 204
    assert tokens.tokens("u-patient") == []


def test_d33_device_token_requires_sign_in(client: TestClient) -> None:
    res = client.post(
        "/api/v1/devices/fcm-token", json={"token": "fcm-token-abcdef", "platform": "android"}
    )
    assert res.status_code == 401


# ---------- end to end through POST /vitals ----------


def _seed_patient(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users["u-patient"] = {
        "name": "Siti",
        "role": "patient",
        "isActive": True,
        "gender": "female",
        "dateOfBirth": datetime(1966, 10, 20, tzinfo=UTC),
        "assignedDoctorId": "u-doctor",
    }
    repo.health_profiles["u-patient"] = {
        "medicalHistory": json.dumps({"conditions": ["diabetes"]}),
    }
    repo.users["u-family"] = {"role": "family_member", "patientId": "u-patient"}
    for uid in ("u-patient", "u-doctor", "u-family"):
        tokens.add(uid, f"token-of-{uid}", "android")


def _log(client: TestClient, sys: int, dia: int) -> dict[str, Any]:
    res = client.post(
        "/api/v1/vitals", json={"systolic": sys, "diastolic": dia}, headers=bearer("patient-token")
    )
    assert res.status_code == 201
    body: dict[str, Any] = res.json()
    return body


def _recipients(push: LogPushClient) -> list[str]:
    return [tokens[0].removeprefix("token-of-") for tokens, _ in push.sent]


def test_uc9_2_emergency_reading_alerts_everyone(
    client: TestClient,
    repo: InMemoryUserRepository,
    tokens: InMemoryTokenRepository,
    push: LogPushClient,
    alerts_repo: InMemoryAlertRepository,
    audit: InMemoryAuditLogger,
) -> None:
    _seed_patient(repo, tokens)
    body = _log(client, 185, 122)
    assert body["alertLevel"] == "emergency"
    assert body["bookAppointmentPrompt"] is True
    assert "999" in body["recommendations"][0]
    assert body["recommendations"][-1] == DISCLAIMER
    assert _recipients(push) == ["u-patient", "u-doctor", "u-family"]
    alert = alerts_repo.alerts[0]
    assert alert["type"] == "threshold" and alert["severity"] == "critical"
    assert alert["doctorId"] == "u-doctor" and alert["status"] == "open"
    assert alert["vitalReadingId"] == body["id"]
    assert "CLINICAL_ALERT" in audit.actions()


def test_doctor_alert_is_deduplicated_within_two_hours(
    client: TestClient,
    repo: InMemoryUserRepository,
    tokens: InMemoryTokenRepository,
    alerts_repo: InMemoryAlertRepository,
) -> None:
    _seed_patient(repo, tokens)
    _log(client, 150, 95)
    _log(client, 155, 96)
    assert [a["type"] for a in alerts_repo.alerts] == ["threshold"]


def test_unassigned_patient_still_records_the_alert(
    client: TestClient,
    repo: InMemoryUserRepository,
    tokens: InMemoryTokenRepository,
    push: LogPushClient,
    alerts_repo: InMemoryAlertRepository,
) -> None:
    _seed_patient(repo, tokens)
    repo.users["u-patient"]["assignedDoctorId"] = None
    _log(client, 150, 95)
    assert alerts_repo.alerts[0]["doctorId"] is None
    assert "u-doctor" not in _recipients(push)


def test_uc9_2_risk_rising_to_high_after_third_reading(
    client: TestClient,
    repo: InMemoryUserRepository,
    tokens: InMemoryTokenRepository,
    alerts_repo: InMemoryAlertRepository,
    risk_repo: InMemoryRiskRepository,
) -> None:
    _seed_patient(repo, tokens)
    _log(client, 120, 78)
    _log(client, 121, 79)
    body = _log(client, 122, 79)
    assert body["risk"]["overallLevel"] == "high"
    assert body["risk"]["diagnosed"] == ["t2d"]
    assert body["bookAppointmentPrompt"] is True
    assert [a["type"] for a in alerts_repo.alerts] == ["risk_escalation"]
    assert alerts_repo.alerts[0]["riskScoreId"] == "risk1"
    # The next reading at the same level does not escalate again.
    _log(client, 121, 78)
    assert len(alerts_repo.alerts) == 1
    assert len(risk_repo.saved) == 2


# ---------- FR-9.6 deterioration ----------


def _series(values: list[float], days_apart: float = 5) -> list[tuple[datetime, float]]:
    start = NOW - timedelta(days=days_apart * (len(values) - 1))
    return [(start + timedelta(days=days_apart * i), v) for i, v in enumerate(values)]


def test_fr_9_6_slope_is_per_day() -> None:
    assert slope_per_day(_series([0.10, 0.11, 0.12], days_apart=1)) == pytest.approx(0.01)


def test_fr_9_6_steady_rise_is_deterioration() -> None:
    assert deteriorating(_series([0.10, 0.12, 0.13, 0.16]))


@pytest.mark.parametrize(
    "values,days_apart",
    [
        ([0.10, 0.10, 0.11], 5),  # too shallow
        ([0.20, 0.16, 0.12], 5),  # improving
        ([0.10, 0.20], 10),  # too few scores
        ([0.10, 0.15, 0.20], 1),  # spans under 7 days
    ],
)
def test_fr_9_6_not_deterioration(values: list[float], days_apart: float) -> None:
    assert not deteriorating(_series(values, days_apart))


def _scores(stroke: float) -> dict[str, Any]:
    return {c.value: {"value": stroke if c is Complication.STROKE else 0.05} for c in Complication}


def test_fr_9_6_only_the_worsening_complication_is_reported() -> None:
    rows = [(t, _scores(v)) for t, v in _series([0.10, 0.14, 0.18, 0.22])]
    assert worsening_complications(rows) == [Complication.STROKE]


def test_fr_9_6_job_alerts_doctor_once_per_week(
    client: TestClient,
    deterioration_repo: InMemoryDeteriorationRepository,
    alerts_repo: InMemoryAlertRepository,
    tokens: InMemoryTokenRepository,
    push: LogPushClient,
) -> None:
    now = datetime.now(UTC)
    deterioration_repo.patients = [
        ("u-patient", {"name": "Siti", "assignedDoctorId": "u-doctor"}),
        ("u-other", {"name": "Ah Kow", "assignedDoctorId": "u-doctor"}),
    ]
    deterioration_repo.scores["u-patient"] = [
        (now - timedelta(days=d), _scores(v)) for d, v in [(20, 0.10), (12, 0.15), (2, 0.22)]
    ]
    deterioration_repo.scores["u-other"] = [
        (now - timedelta(days=d), _scores(0.10)) for d in (20, 12, 2)
    ]
    tokens.add("u-doctor", "token-of-u-doctor", "web")

    res = client.post("/internal/jobs/deterioration")
    assert res.status_code == 200
    assert res.json() == {
        "job": "deterioration",
        "status": "ok",
        "patientsScanned": 2,
        "alertsRaised": 1,
    }
    assert alerts_repo.alerts[0]["type"] == "deterioration"
    assert "stroke" in alerts_repo.alerts[0]["message"]
    assert _recipients(push) == ["u-doctor"]

    again = client.post("/internal/jobs/deterioration").json()
    assert again["alertsRaised"] == 0


class BrokenAlertRepository(InMemoryAlertRepository):
    def recent_alert_exists(self, uid: str, alert_type: ClinicalAlertType, since: Any) -> bool:
        raise RuntimeError("The query requires an index.")


def test_alerting_failure_still_saves_and_reports_the_reading(
    client: TestClient,
    repo: InMemoryUserRepository,
    tokens: InMemoryTokenRepository,
    risk_repo: InMemoryRiskRepository,
    vitals_repo: InMemoryVitalsRepository,
) -> None:
    from app.services.escalation import get_alert_repository

    _seed_patient(repo, tokens)
    broken = BrokenAlertRepository(risk_repo, repo)
    client.app.dependency_overrides[get_alert_repository] = lambda: broken  # type: ignore[attr-defined]
    body = _log(client, 150, 95)
    assert body["alertLevel"] == "moderate"
    assert len(vitals_repo.readings) == 1
