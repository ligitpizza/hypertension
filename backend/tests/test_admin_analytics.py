"""Module 11 analytics and hospital-wide report (FR-11.3, FR-11.4, UC11.5; D-59)."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.services.analytics import hospital, overall_level
from tests.conftest import (
    InMemoryAnalyticsSource,
    InMemoryAuditLogger,
    InMemoryAuditReader,
    InMemoryUserRepository,
    bearer,
)

ADMIN = bearer("admin-token")
NOW = datetime.now(UTC)


def score(level: str) -> dict[str, dict[str, object]]:
    return {"stroke": {"value": 0.1, "level": "low"}, "cad": {"value": 0.5, "level": level}}


@pytest.fixture(autouse=True)
def clinic(repo: InMemoryUserRepository, analytics: InMemoryAnalyticsSource) -> None:
    repo.users.update(
        {
            "d1": {"role": "doctor", "name": "Dr John", "specialty": "Cardiology"},
            "d2": {"role": "doctor", "name": "Dr Lim"},
            "ph": {"role": "pharmacist", "name": "Ph Tan"},
            "p1": {
                "role": "patient",
                "assignedDoctorId": "d1",
                "createdAt": NOW - timedelta(days=2),
            },
            "p2": {
                "role": "patient",
                "assignedDoctorId": "d2",
                "createdAt": NOW - timedelta(days=90),
            },
            "p3": {"role": "patient", "isActive": False},
        }
    )
    a = analytics.add
    # p1: high now, was low; p2: moderate; p3 is inactive (excluded from current).
    a("risk_scores", patientId="p1", generatedAt=NOW - timedelta(days=40), scores=score("low"))
    a("risk_scores", patientId="p1", generatedAt=NOW - timedelta(hours=1), scores=score("high"))
    a("risk_scores", patientId="p2", generatedAt=NOW - timedelta(days=3), scores=score("moderate"))
    a("risk_scores", patientId="p3", generatedAt=NOW - timedelta(days=3), scores=score("critical"))
    a("appointments", dateTime=NOW - timedelta(days=1), status="completed")
    a("appointments", dateTime=NOW - timedelta(days=1, hours=2), status="no_show")
    a(
        "appointments",
        dateTime=NOW - timedelta(days=2),
        status="cancelled",
        changeReason="transport",
    )
    for i in range(4):
        a("dose_logs", scheduledTime=NOW - timedelta(days=1, hours=i), status="taken")
    a("dose_logs", scheduledTime=NOW - timedelta(days=1, hours=5), status="missed")
    a("messages", sentAt=NOW - timedelta(days=1))
    a("messages", sentAt=NOW - timedelta(days=20))
    a("clinical_alerts", createdAt=NOW - timedelta(days=1), severity="critical", status="open")
    a("clinical_alerts", createdAt=NOW - timedelta(days=1), severity="high", status="dismissed")
    a("triage_outcomes", generatedAt=NOW - timedelta(days=1), outcome="contact_doctor")
    a("health_records", sharedAt=NOW - timedelta(days=1))


def test_overall_level_is_the_highest() -> None:
    assert overall_level({"scores": score("high")}) == "high"
    assert overall_level({"scores": {}}) is None


def test_fr11_4_hospital_analytics(client: TestClient) -> None:
    res = client.get("/api/v1/admin/analytics/hospital", headers=ADMIN)
    assert res.status_code == 200
    body = res.json()
    assert body["activePatients"] == 2
    assert body["risk"]["counts"] == {"low": 0, "moderate": 1, "high": 1, "critical": 0}
    trend = body["riskTrend"]
    assert len(trend) == 6 and trend[-1]["month"] == f"{(NOW + timedelta(hours=8)):%Y-%m}"
    # This month: p1 ends High, p2 Moderate, p3 Critical (the trend keeps history).
    assert sum(trend[-1][k] for k in ("low", "moderate", "high", "critical")) >= 2
    months = {c["month"]: c for c in body["consultations"]}
    assert sum(c["completed"] for c in months.values()) == 1
    assert sum(c["noShow"] for c in months.values()) == 1
    assert body["adherence"]["current"] == 80.0
    assert body["delivery"] is None  # Module 13


def test_monthly_trend_counts_each_patient_once_per_month(
    analytics: InMemoryAnalyticsSource,
) -> None:
    now = datetime(2026, 10, 16, 4, tzinfo=UTC)
    src = InMemoryAnalyticsSource(analytics._users)
    src.add(
        "risk_scores",
        patientId="x",
        generatedAt=datetime(2026, 9, 5, tzinfo=UTC),
        scores=score("low"),
    )
    src.add(
        "risk_scores",
        patientId="x",
        generatedAt=datetime(2026, 9, 25, tzinfo=UTC),
        scores=score("high"),
    )
    src.add(
        "risk_scores",
        patientId="x",
        generatedAt=datetime(2026, 10, 2, tzinfo=UTC),
        scores=score("moderate"),
    )
    trend = {t["month"]: t for t in hospital(src, now, 3)["riskTrend"]}
    assert list(trend) == ["2026-08", "2026-09", "2026-10"]
    assert trend["2026-09"]["high"] == 1 and trend["2026-09"]["low"] == 0
    assert trend["2026-10"]["moderate"] == 1


def test_fr11_3_system_analytics(client: TestClient, audit_reader: InMemoryAuditReader) -> None:
    audit_reader.add(NOW - timedelta(days=1), "LOGIN", "d1")
    audit_reader.add(NOW - timedelta(days=1), "LOG_VITAL_READING", "p1")
    audit_reader.add(NOW - timedelta(days=2), "UPDATE_CARE_PLAN", "d2")
    audit_reader.add(NOW - timedelta(days=20), "LOGIN", "ph")  # outside 7 days
    audit_reader.add(NOW - timedelta(minutes=1), "JOB_HEARTBEAT", "system", targetType="sweep")
    res = client.get("/api/v1/admin/analytics/system", headers=ADMIN)
    body = res.json()
    assert body["activeClinicians"] == 2 and body["totalClinicians"] == 3
    assert body["messagesSent"] == 1 and body["unresolvedCritical"] == 1
    assert len(body["dailyActivity"]) == 7
    assert sum(d.get("doctor", 0) for d in body["dailyActivity"]) == 2
    specialties = {s["specialty"]: s["events"] for s in body["bySpecialty"]}
    # Dr John's own event plus his patient's; Dr Lim has no specialty -> General.
    assert specialties == {"Cardiology": 2, "General": 1}
    assert body["uptime"] == 100.0


def test_uc11_5_report_pdf_is_generated_and_audited(
    client: TestClient, audit: InMemoryAuditLogger
) -> None:
    today = (NOW + timedelta(hours=8)).date()
    body = {"from": (today - timedelta(days=7)).isoformat(), "to": today.isoformat()}
    res = client.post("/api/v1/admin/reports", json=body, headers=ADMIN)
    assert res.status_code == 200 and res.headers["content-type"] == "application/pdf"
    assert res.content.startswith(b"%PDF")
    assert audit.entries[-1]["action"] == "GENERATE_REPORT"


def test_report_contents(analytics: InMemoryAnalyticsSource) -> None:
    from app.services.analytics import report_data

    data = report_data(analytics, [], NOW - timedelta(days=7), NOW + timedelta(seconds=1))
    assert data is not None
    assert data["patients"]["newRegistrations"] == 1
    assert data["appointments"]["topCancellationReasons"] == [("Transport problem", 1)]
    assert data["care"]["adherence"] == 80.0 and data["care"]["missedDoses"] == 1
    assert data["care"]["alertsRaised"] == 2 and data["care"]["alertsResolved"] == 1
    assert data["care"]["triage"] == {"contact_doctor": 1}
    assert data["usage"]["recordsShared"] == 1 and data["usage"]["messagesSent"] == 1


def test_uc11_5_e1_no_data_in_range(client: TestClient) -> None:
    body = {"from": "2020-01-01", "to": "2020-01-31"}
    res = client.post("/api/v1/admin/reports", json=body, headers=ADMIN)
    assert res.status_code == 422 and res.json()["error"]["code"] == "NO_DATA"


def test_report_needs_dates(client: TestClient) -> None:
    res = client.post("/api/v1/admin/reports", json={"from": "2026-10-01"}, headers=ADMIN)
    assert res.status_code == 422


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/api/v1/admin/analytics/hospital"),
        ("get", "/api/v1/admin/analytics/system"),
        ("post", "/api/v1/admin/reports"),
    ],
)
def test_admin_only(client: TestClient, method: str, path: str) -> None:
    res = getattr(client, method)(path, headers=bearer("doctor-token"))
    assert res.status_code in (403, 422)  # 422 only if body validation runs first
    if method == "get":
        assert res.status_code == 403
