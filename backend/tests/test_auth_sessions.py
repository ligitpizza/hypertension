from fastapi.testclient import TestClient

from app.core.rate_limit import RateLimiter
from tests.conftest import InMemoryAuditLogger, InMemoryUserRepository, bearer

SESSION = "/api/v1/auth/session-events"
FAILED = "/api/v1/auth/login-failed"


def _seed(repo: InMemoryUserRepository, uid: str, role: str, active: bool = True) -> None:
    repo.users[uid] = {"role": role, "isActive": active, "onboardingComplete": True}


def test_fr_1_5_login_is_audited(
    client: TestClient, repo: InMemoryUserRepository, audit: InMemoryAuditLogger
) -> None:
    _seed(repo, "u-patient", "patient")
    res = client.post(
        SESSION, json={"event": "LOGIN", "app": "patient"}, headers=bearer("patient-token")
    )
    assert res.status_code == 200
    assert res.json() == {"status": "ok", "role": "patient", "onboardingComplete": True}
    assert audit.entries[-1]["action"] == "LOGIN"
    assert audit.entries[-1]["userId"] == "u-patient"


def test_fr_1_5_uc1_3_logout_is_audited(client: TestClient, audit: InMemoryAuditLogger) -> None:
    res = client.post(
        SESSION, json={"event": "LOGOUT", "app": "staff"}, headers=bearer("doctor-token")
    )
    assert res.status_code == 200
    assert audit.actions() == ["LOGOUT"]


def test_uc1_2_e2_deactivated_account_is_blocked(
    client: TestClient, repo: InMemoryUserRepository, audit: InMemoryAuditLogger
) -> None:
    _seed(repo, "u-patient", "patient", active=False)
    res = client.post(
        SESSION, json={"event": "LOGIN", "app": "patient"}, headers=bearer("patient-token")
    )
    assert res.status_code == 403
    assert res.json()["error"]["code"] == "ACCOUNT_DEACTIVATED"
    assert "contact support" in res.json()["error"]["message"].lower()
    assert audit.actions() == ["LOGIN_BLOCKED"]


def test_d63_family_member_signs_in_to_the_careflow_app(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    _seed(repo, "u-family", "family_member")
    res = client.post(
        SESSION, json={"event": "LOGIN", "app": "patient"}, headers=bearer("family-token")
    )
    assert res.status_code == 200


def test_staff_cannot_use_the_careflow_app(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    _seed(repo, "u-doctor", "doctor")
    res = client.post(
        SESSION, json={"event": "LOGIN", "app": "patient"}, headers=bearer("doctor-token")
    )
    assert res.status_code == 403
    assert res.json()["error"]["code"] == "WRONG_APP"


def test_fr_1_3_patient_cannot_use_staff_portal(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    _seed(repo, "u-patient", "patient")
    res = client.post(
        SESSION, json={"event": "LOGIN", "app": "staff"}, headers=bearer("patient-token")
    )
    assert res.status_code == 403


def test_fr_1_2_every_staff_role_can_use_staff_portal(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    for uid, role, token in [
        ("u-doctor", "doctor", "doctor-token"),
        ("u-pharm", "pharmacist", "pharmacist-token"),
        ("u-admin", "admin", "admin-token"),
    ]:
        _seed(repo, uid, role)
        res = client.post(SESSION, json={"event": "LOGIN", "app": "staff"}, headers=bearer(token))
        assert res.status_code == 200, role


def test_fr_1_2_login_without_profile_is_404(client: TestClient) -> None:
    res = client.post(
        SESSION, json={"event": "LOGIN", "app": "patient"}, headers=bearer("patient-token")
    )
    assert res.status_code == 404


def test_d27_failed_login_stores_email_domain_only(
    client: TestClient, audit: InMemoryAuditLogger
) -> None:
    res = client.post(
        FAILED,
        json={"email": "Someone@Gmail.com", "reason": "invalid_credentials", "app": "patient"},
    )
    assert res.status_code == 202
    entry = audit.entries[0]
    assert entry["action"] == "LOGIN_FAILED"
    assert entry["userId"] == "anonymous"
    assert "emailDomain=gmail.com" in entry["details"]
    assert "someone" not in entry["details"].lower()


def test_d27_failed_login_reports_are_rate_limited(
    client: TestClient, limiter: RateLimiter, audit: InMemoryAuditLogger
) -> None:
    body = {"email": "x@y.com", "reason": "invalid_credentials", "app": "staff"}
    codes = [client.post(FAILED, json=body).status_code for _ in range(5)]
    assert codes == [202, 202, 202, 429, 429]
    assert len(audit.entries) == 3


def test_d27_unknown_failure_reason_is_rejected(client: TestClient) -> None:
    res = client.post(FAILED, json={"email": "x@y.com", "reason": "hacked", "app": "staff"})
    assert res.status_code == 422


def test_rate_limiter_window_expires() -> None:
    limiter = RateLimiter(max_events=1, window_seconds=60)
    assert limiter.allow("ip", now=0)
    assert not limiter.allow("ip", now=30)
    assert limiter.allow("ip", now=61)
    assert limiter.allow("other-ip", now=30)
