"""Symptom checker triage (FR-14.3; UC14.1 E1, UC14.3, UC14.4; docs/06 §D; D-10, D-36).

Objective 1: every rule row and boundary of the fixed triage table is unit-tested.
"""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.enums import RiskLevel, TriageOutcome, TriageSeverity
from app.services.triage import classify
from tests.conftest import (
    InMemoryAlertRepository,
    InMemoryAuditLogger,
    InMemoryRiskRepository,
    InMemoryTriageRepository,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    bearer,
)

MILD, MODERATE, SEVERE = TriageSeverity.MILD, TriageSeverity.MODERATE, TriageSeverity.SEVERE
HOME = TriageOutcome.MONITOR_AT_HOME
DOCTOR = TriageOutcome.CONTACT_DOCTOR
ER = TriageOutcome.SEEK_EMERGENCY_CARE


def outcome(
    severity: TriageSeverity = MILD,
    red_flags: list[str] | None = None,
    bp: tuple[int, int] | None = None,
    hr: int | None = None,
    risk: list[RiskLevel] | None = None,
) -> TriageOutcome:
    sys_, dia = bp if bp else (None, None)
    return classify(severity, red_flags or [], sys_, dia, hr, risk or []).outcome


# ---------- rule 1: crisis BP (boundaries 179/180, 119/120) ----------


@pytest.mark.parametrize(
    "bp,expected",
    [((180, 80), ER), ((179, 80), DOCTOR), ((130, 120), ER), ((130, 119), DOCTOR)],
)
def test_rule1_crisis_bp_boundaries(bp: tuple[int, int], expected: TriageOutcome) -> None:
    assert outcome(bp=bp) is expected


def test_rule1_wins_even_with_mild_symptoms() -> None:
    assert outcome(MILD, bp=(185, 125)) is ER


# ---------- rule 2: severe + (red flag or systolic >= 160) ----------


@pytest.mark.parametrize("bp,expected", [((160, 85), ER), ((159, 85), DOCTOR)])
def test_rule2_severe_with_systolic_160_boundary(
    bp: tuple[int, int], expected: TriageOutcome
) -> None:
    assert outcome(SEVERE, bp=bp) is expected


def test_rule2_severe_with_red_flag() -> None:
    assert outcome(SEVERE, ["Chest Pain"], bp=(120, 80)) is ER


def test_severe_without_red_flag_or_high_bp_is_not_emergency() -> None:
    assert outcome(SEVERE, bp=(125, 82)) is HOME


# ---------- rule 3: any red flag ----------


@pytest.mark.parametrize(
    "flag",
    [
        "Chest Pain",
        "Shortness of Breath",
        "Sudden Weakness or Numbness",
        "Confusion or Difficulty Speaking",
        "Vision Loss",
        "Severe Headache",
    ],
)
def test_rule3_any_red_flag_symptom_is_emergency(flag: str) -> None:
    assert outcome(MILD, [flag], bp=(118, 76)) is ER


def test_rule3_red_flag_without_any_bp() -> None:
    assert outcome(MILD, ["Chest Pain"]) is ER


# ---------- rule 4: high BP (boundaries 139/140, 89/90) ----------


@pytest.mark.parametrize(
    "bp,expected",
    [((140, 80), DOCTOR), ((139, 80), HOME), ((130, 90), DOCTOR), ((130, 89), HOME)],
)
def test_rule4_high_bp_boundaries(bp: tuple[int, int], expected: TriageOutcome) -> None:
    assert outcome(bp=bp) is expected


# ---------- D-39: low BP (boundaries 89/90 systolic, 59/60 diastolic) ----------


@pytest.mark.parametrize(
    "bp,expected",
    [((89, 60), DOCTOR), ((90, 60), HOME), ((110, 59), DOCTOR), ((110, 60), HOME)],
)
def test_d39_low_bp_boundaries(bp: tuple[int, int], expected: TriageOutcome) -> None:
    assert outcome(bp=bp) is expected


def test_d39_low_bp_reason_and_emergency_rules_still_win() -> None:
    decision = classify(MILD, [], 110, 50, 72, [])
    assert decision.outcome is DOCTOR and "is low" in decision.reason
    assert outcome(MILD, ["Chest Pain"], bp=(85, 55)) is ER


# ---------- rule 5: moderate severity or High/Critical risk ----------


def test_rule5_moderate_severity() -> None:
    assert outcome(MODERATE, bp=(120, 78)) is DOCTOR


@pytest.mark.parametrize(
    "level,expected",
    [
        (RiskLevel.CRITICAL, DOCTOR),
        (RiskLevel.HIGH, DOCTOR),
        (RiskLevel.MODERATE, HOME),
        (RiskLevel.LOW, HOME),
    ],
)
def test_rule5_risk_level(level: RiskLevel, expected: TriageOutcome) -> None:
    assert outcome(bp=(120, 78), risk=[RiskLevel.LOW, level]) is expected


# ---------- rule 6: heart rate (boundaries 120/121, 45/44) ----------


@pytest.mark.parametrize(
    "hr,expected", [(121, DOCTOR), (120, HOME), (44, DOCTOR), (45, HOME), (None, HOME)]
)
def test_rule6_heart_rate_boundaries(hr: int | None, expected: TriageOutcome) -> None:
    assert outcome(bp=(120, 78), hr=hr) is expected


# ---------- rule 7: otherwise ----------


def test_rule7_otherwise_monitor_at_home() -> None:
    assert outcome(MILD, bp=(118, 76), hr=72, risk=[RiskLevel.LOW]) is HOME


def test_rules_apply_top_down() -> None:
    # Crisis BP beats everything; red flag beats high-BP "contact doctor".
    decision = classify(MODERATE, ["Chest Pain"], 150, 95, 130, [RiskLevel.HIGH])
    assert decision.outcome is ER
    assert "Chest Pain" in decision.reason


# ---------- POST /triage (D-38: heart rate and a fresh BP are compulsory) ----------

P = "u-patient"
PATIENT = bearer("patient-token")
NOW = datetime.now(UTC)


@pytest.fixture(autouse=True)
def patient(repo: InMemoryUserRepository) -> None:
    repo.users[P] = {"name": "Siti", "role": "patient", "assignedDoctorId": "u-doctor"}


def add_reading(
    vitals: InMemoryVitalsRepository, sys: int, dia: int, ago: timedelta = timedelta(0), **kw: Any
) -> str:
    return vitals.add_reading(
        {"patientId": P, "systolic": sys, "diastolic": dia, "timestamp": NOW - ago, **kw}
    )


def post(
    client: TestClient,
    vitals: InMemoryVitalsRepository,
    bp: tuple[int, int] = (118, 76),
    hr: int = 72,
    **body: Any,
) -> Any:
    """Like the app: log the BP entered in the checker, then submit triage with its id."""
    rid = add_reading(vitals, *bp)
    return client.post(
        "/api/v1/triage",
        json={"severity": "mild", "heartRate": hr, "vitalReadingId": rid, **body},
        headers=PATIENT,
    )


def test_uc14_3_saves_outcome_and_returns_result(
    client: TestClient,
    vitals_repo: InMemoryVitalsRepository,
    triage_repo: InMemoryTriageRepository,
    alerts_repo: InMemoryAlertRepository,
    audit: InMemoryAuditLogger,
) -> None:
    res = post(client, vitals_repo, hr=74, symptoms=["headache", "nausea"])
    assert res.status_code == 201
    body = res.json()
    assert body["outcome"] == "monitor_at_home"
    assert body["systolic"] == 118 and body["heartRate"] == 74
    assert body["missingInputs"] == ["risk_score"]
    assert body["doctorNotified"] is False
    assert triage_repo.saved == [
        {
            "patientId": P,
            "symptoms": ["headache", "nausea"],
            "severity": "mild",
            "outcome": "monitor_at_home",
            "vitalReadingId": "r1",
        }
    ]
    assert alerts_repo.alerts == []
    assert "TRIAGE" in audit.actions()


def test_uc14_4_contact_doctor_alerts_the_doctor(
    client: TestClient,
    vitals_repo: InMemoryVitalsRepository,
    alerts_repo: InMemoryAlertRepository,
) -> None:
    body = post(client, vitals_repo, bp=(150, 92), symptoms=["dizziness"]).json()
    assert body["outcome"] == "contact_doctor"
    assert body["doctorNotified"] is True
    [alert] = [a for a in alerts_repo.alerts if a["type"] == "triage"]
    assert alert["severity"] == "high"
    assert alert["doctorId"] == "u-doctor"
    assert "Dizziness" in alert["message"] and "150/92" in alert["message"]
    assert "HR 72" in alert["message"]


def test_uc14_4_emergency_is_a_critical_alert(
    client: TestClient, vitals_repo: InMemoryVitalsRepository, alerts_repo: InMemoryAlertRepository
) -> None:
    body = post(
        client, vitals_repo, symptoms=["chest_pain", "dizziness"], severity="moderate"
    ).json()
    assert body["outcome"] == "seek_emergency_care"
    assert [s["isRedFlag"] for s in body["symptoms"]] == [True, False]
    [alert] = alerts_repo.alerts
    assert alert["severity"] == "critical"
    assert alert["message"].startswith("URGENT triage")


def test_crisis_bp_entered_in_the_checker_is_an_emergency(
    client: TestClient, vitals_repo: InMemoryVitalsRepository
) -> None:
    body = post(client, vitals_repo, bp=(186, 122), symptoms=["fatigue"]).json()
    assert body["outcome"] == "seek_emergency_care"


def test_high_risk_score_makes_contact_doctor(
    client: TestClient, vitals_repo: InMemoryVitalsRepository, risk_repo: InMemoryRiskRepository
) -> None:
    risk_repo.saved.append({"patientId": P, "scores": {"stroke": {"value": 0.3, "level": "high"}}})
    assert post(client, vitals_repo, symptoms=["fatigue"]).json()["outcome"] == "contact_doctor"


def test_d38_heart_rate_and_reading_are_compulsory(
    client: TestClient, vitals_repo: InMemoryVitalsRepository
) -> None:
    rid = add_reading(vitals_repo, 118, 76)
    for body in (
        {"symptoms": ["fatigue"], "severity": "mild", "vitalReadingId": rid},  # no heart rate
        {"symptoms": ["fatigue"], "severity": "mild", "heartRate": 72},  # no BP reading
    ):
        res = client.post("/api/v1/triage", json=body, headers=PATIENT)
        assert res.status_code == 422
        assert res.json()["error"]["code"] == "VALIDATION_ERROR"


def test_d38_reading_must_be_fresh(
    client: TestClient, vitals_repo: InMemoryVitalsRepository
) -> None:
    rid = add_reading(vitals_repo, 118, 76, ago=timedelta(hours=2))
    res = client.post(
        "/api/v1/triage",
        json={"symptoms": ["fatigue"], "severity": "mild", "heartRate": 72, "vitalReadingId": rid},
        headers=PATIENT,
    )
    assert res.status_code == 409
    assert res.json()["error"]["code"] == "READING_TOO_OLD"


def test_someone_elses_reading_is_rejected(
    client: TestClient, vitals_repo: InMemoryVitalsRepository
) -> None:
    rid = vitals_repo.add_reading({"patientId": "u-other", "systolic": 120, "diastolic": 80})
    res = client.post(
        "/api/v1/triage",
        json={"symptoms": ["fatigue"], "severity": "mild", "heartRate": 72, "vitalReadingId": rid},
        headers=PATIENT,
    )
    assert res.status_code == 404


@pytest.mark.parametrize(
    "body,code",
    [
        ({"symptoms": []}, "VALIDATION_ERROR"),
        ({"symptoms": ["not_a_symptom"]}, "UNKNOWN_SYMPTOM"),
        ({"symptoms": ["fatigue"], "severity": "extreme"}, "VALIDATION_ERROR"),
        ({"symptoms": ["fatigue"], "heartRate": 400}, "VALIDATION_ERROR"),
    ],
)
def test_invalid_submissions(
    client: TestClient, vitals_repo: InMemoryVitalsRepository, body: dict[str, Any], code: str
) -> None:
    rid = add_reading(vitals_repo, 118, 76)
    payload = {"severity": "mild", "heartRate": 72, "vitalReadingId": rid, **body}
    res = client.post("/api/v1/triage", json=payload, headers=PATIENT)
    assert res.status_code == 422
    assert res.json()["error"]["code"] == code


@pytest.mark.parametrize("token", ["doctor-token", "family-token"])
def test_only_patients_submit(client: TestClient, token: str) -> None:
    res = client.post(
        "/api/v1/triage",
        json={"symptoms": ["fatigue"], "severity": "mild", "heartRate": 72, "vitalReadingId": "r"},
        headers=bearer(token),
    )
    assert res.status_code == 403
