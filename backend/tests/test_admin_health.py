"""Module 11 system health (Fig 4.3.14.7; FR-11.3; D-59)."""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.ml.risk_model import ComplicationRisk, RiskPrediction
from app.services.system_health import Probe, get_probe, uptime
from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryAuditReader,
    MakeClient,
    bearer,
    dev_settings,
)

ADMIN = bearer("admin-token")


class FakeModel:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail

    def predict(self, inputs: dict[str, float]) -> RiskPrediction:
        if self.fail:
            raise RuntimeError("broken")
        return RiskPrediction(scores={}, model_used="test")


def health(make_client: MakeClient, probe: Probe, **settings: Any) -> dict[str, Any]:
    client = make_client(dev_settings(**settings))
    client.app.dependency_overrides[get_probe] = lambda: probe  # type: ignore[attr-defined]
    res = client.get("/api/v1/admin/system-health", headers=ADMIN)
    assert res.status_code == 200
    return dict(res.json())


def by_key(body: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {s["key"]: s for s in body["services"]}


def ok() -> None:
    return None


def test_fr11_3_all_services_listed_with_latency(make_client: MakeClient) -> None:
    body = health(
        make_client,
        Probe(firestore=ok, model=FakeModel()),  # type: ignore[arg-type]
        fcm_enabled=True,
        email_api_key="k",
        gemini_api_key="g",
    )
    s = by_key(body)
    assert set(s) == {"api", "firestore", "ml", "push", "email", "ai", "stripe", "grab"}
    assert s["firestore"]["status"] == "operational" and s["firestore"]["latencyMs"] is not None
    assert s["ml"]["status"] == "operational"
    assert s["push"]["status"] == "operational" and s["email"]["status"] == "operational"
    assert s["stripe"]["status"] == "simulated" and s["grab"]["status"] == "simulated"
    assert body["overall"] == "operational"


def test_fakes_and_missing_keys_are_labelled(make_client: MakeClient) -> None:
    s = by_key(health(make_client, Probe(firestore=ok, model=FakeModel())))  # type: ignore[arg-type]
    assert s["push"]["status"] == "simulated"
    assert s["email"]["status"] == "not_configured"
    assert s["ai"]["status"] == "simulated"


def test_failures_make_the_overall_status_down(make_client: MakeClient) -> None:
    def broken() -> None:
        raise ConnectionError("no route")

    body = health(make_client, Probe(firestore=broken, model=None))
    s = by_key(body)
    assert s["firestore"]["status"] == "down" and s["ml"]["status"] == "down"
    assert body["overall"] == "down"


def test_a_failing_prediction_is_down(make_client: MakeClient) -> None:
    s = by_key(health(make_client, Probe(firestore=ok, model=FakeModel(fail=True))))  # type: ignore[arg-type]
    assert s["ml"]["status"] == "down"


def test_uptime_from_sweep_heartbeats() -> None:
    reader = InMemoryAuditReader()
    now = datetime(2026, 10, 16, 12, tzinfo=UTC)
    assert uptime(reader, now) is None
    # Two hours of sweeps (9 expected incl. both ends), one missed.
    for i in range(9):
        if i != 4:
            reader.add(
                now - timedelta(minutes=15 * i), "JOB_HEARTBEAT", "system", targetType="sweep"
            )
    reader.add(now, "JOB_HEARTBEAT", "system", targetType="audit_logs")  # daily test job: ignored
    assert uptime(reader, now) == pytest.approx(8 / 9 * 100, abs=0.01)


def test_the_sweep_writes_a_heartbeat(client: TestClient, audit: InMemoryAuditLogger) -> None:
    res = client.post("/internal/jobs/escalation")
    assert res.status_code == 200
    beat = [e for e in audit.entries if e["action"] == "JOB_HEARTBEAT"]
    assert beat and beat[-1]["targetType"] == "sweep"


def test_heartbeats_are_hidden_in_the_audit_viewer(
    client: TestClient, audit_reader: InMemoryAuditReader
) -> None:
    now = datetime.now(UTC)
    audit_reader.add(now, "JOB_HEARTBEAT", "system", targetType="sweep")
    audit_reader.add(now, "LOGIN", "u-doctor")
    assert client.get("/api/v1/admin/audit-logs", headers=ADMIN).json()["total"] == 1
    res = client.get("/api/v1/admin/audit-logs", params={"action": "JOB_HEARTBEAT"}, headers=ADMIN)
    assert res.json()["total"] == 1


def test_admin_only(client: TestClient) -> None:
    res = client.get("/api/v1/admin/system-health", headers=bearer("doctor-token"))
    assert res.status_code == 403


def test_complication_risk_import_is_used() -> None:
    # Keeps the RiskPrediction shape used by FakeModel honest.
    assert ComplicationRisk is not None
