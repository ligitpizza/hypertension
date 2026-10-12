from typing import Any

from fastapi.testclient import TestClient

from app.routers.jobs import get_oidc_verifier
from tests.conftest import InMemoryAuditLogger, MakeClient, dev_settings

SA = "careflow-scheduler@hypertension-dd85f.iam.gserviceaccount.com"


def _oidc_client(make_client: MakeClient, claims: dict[str, Any] | None) -> TestClient:
    client = make_client(
        dev_settings(
            internal_jobs_auth="oidc", jobs_oidc_audience="https://run", jobs_service_account=SA
        )
    )

    def verify(token: str, audience: str) -> dict[str, Any]:
        if claims is None or token != "good":
            raise ValueError("bad token")
        return claims

    client.app.dependency_overrides[get_oidc_verifier] = lambda: verify  # type: ignore[attr-defined]
    return client


def test_d08_heartbeat_job_writes_audit_log(client: TestClient, audit: InMemoryAuditLogger) -> None:
    res = client.post("/internal/jobs/heartbeat")
    assert res.status_code == 200
    assert res.json()["job"] == "heartbeat"
    assert audit.entries[0]["action"] == "JOB_HEARTBEAT"
    assert audit.entries[0]["userId"] == "system:scheduler"


def test_d08_unknown_job_is_404(client: TestClient) -> None:
    res = client.post("/internal/jobs/nope")
    assert res.status_code == 404
    assert res.json()["error"]["code"] == "JOB_NOT_FOUND"


def test_d08_oidc_mode_rejects_missing_token(make_client: MakeClient) -> None:
    res = _oidc_client(make_client, None).post("/internal/jobs/heartbeat")
    assert res.status_code == 401


def test_d08_oidc_mode_rejects_other_service_account(make_client: MakeClient) -> None:
    claims = {"email": "attacker@example.com", "email_verified": True}
    res = _oidc_client(make_client, claims).post(
        "/internal/jobs/heartbeat", headers={"Authorization": "Bearer good"}
    )
    assert res.status_code == 403


def test_d08_oidc_mode_accepts_scheduler(
    make_client: MakeClient, audit: InMemoryAuditLogger
) -> None:
    claims = {"email": SA, "email_verified": True}
    res = _oidc_client(make_client, claims).post(
        "/internal/jobs/heartbeat", headers={"Authorization": "Bearer good"}
    )
    assert res.status_code == 200
    assert len(audit.entries) == 1


def test_d08_jobs_not_exposed_under_api_prefix(client: TestClient) -> None:
    assert client.post("/api/v1/internal/jobs/heartbeat").status_code == 404
