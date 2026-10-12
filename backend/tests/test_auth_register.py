import re

from fastapi.testclient import TestClient

from app.services.users import LINK_CODE_ALPHABET
from tests.conftest import FakeIdentityProvider, InMemoryAuditLogger, InMemoryUserRepository, bearer

URL = "/api/v1/auth/register-profile"


def test_fr_1_1_uc1_1_patient_registration_creates_profile_and_role(
    client: TestClient,
    repo: InMemoryUserRepository,
    identity: FakeIdentityProvider,
    audit: InMemoryAuditLogger,
) -> None:
    res = client.post(URL, json={"name": "Ali", "role": "patient"}, headers=bearer("norole-token"))
    assert res.status_code == 200
    assert res.json() == {"uid": "u-new", "role": "patient", "onboardingComplete": False}

    doc = repo.users["u-new"]
    assert doc["email"] == "n@example.com"
    assert doc["role"] == "patient"
    assert doc["isActive"] is True
    assert doc["onboardingComplete"] is False
    assert doc["assignedDoctorId"] is None
    assert re.fullmatch(f"[{LINK_CODE_ALPHABET}]{{6}}", doc["linkCode"])  # D-06
    assert identity.claims["u-new"] == "patient"
    assert audit.actions() == ["REGISTER_ACCOUNT"]


def test_fr_1_1_family_member_registration_has_pending_link(
    client: TestClient, repo: InMemoryUserRepository, identity: FakeIdentityProvider
) -> None:
    res = client.post(
        URL, json={"name": "Siti", "role": "family_member"}, headers=bearer("norole-token")
    )
    assert res.status_code == 200
    assert res.json()["onboardingComplete"] is None
    doc = repo.users["u-new"]
    assert doc["patientId"] is None
    assert "linkCode" not in doc
    assert "onboardingComplete" not in doc
    assert identity.claims["u-new"] == "family_member"


def test_fr_1_6_staff_roles_cannot_self_register(client: TestClient) -> None:
    for role in ("doctor", "pharmacist", "admin"):
        res = client.post(URL, json={"name": "X Y", "role": role}, headers=bearer("norole-token"))
        assert res.status_code == 422, role


def test_fr_1_1_registration_requires_auth(client: TestClient) -> None:
    assert client.post(URL, json={"name": "Ali", "role": "patient"}).status_code == 401


def test_fr_1_1_retry_with_same_role_is_idempotent(
    client: TestClient, repo: InMemoryUserRepository, audit: InMemoryAuditLogger
) -> None:
    body = {"name": "Ali", "role": "patient"}
    first = client.post(URL, json=body, headers=bearer("norole-token"))
    second = client.post(URL, json=body, headers=bearer("norole-token"))
    assert first.status_code == second.status_code == 200
    assert len(repo.users) == 1
    assert audit.actions() == ["REGISTER_ACCOUNT"]


def test_uc1_1_e1_existing_account_with_other_role_is_rejected(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    client.post(URL, json={"name": "Ali", "role": "patient"}, headers=bearer("norole-token"))
    res = client.post(
        URL, json={"name": "Ali", "role": "family_member"}, headers=bearer("norole-token")
    )
    assert res.status_code == 409
    assert res.json()["error"]["code"] == "ALREADY_REGISTERED"


def test_fr_1_6_staff_account_cannot_register_as_patient(client: TestClient) -> None:
    res = client.post(URL, json={"name": "Dr X", "role": "patient"}, headers=bearer("doctor-token"))
    assert res.status_code == 409


def test_d06_link_code_retries_on_collision(
    client: TestClient, repo: InMemoryUserRepository, monkeypatch: object
) -> None:
    import app.routers.auth as auth_router

    codes = iter(["AAAAAA", "BBBBBB"])
    repo.taken_link_codes.add("AAAAAA")
    monkeypatch.setattr(auth_router, "new_link_code", lambda: next(codes))  # type: ignore[attr-defined]
    client.post(URL, json={"name": "Ali", "role": "patient"}, headers=bearer("norole-token"))
    assert repo.users["u-new"]["linkCode"] == "BBBBBB"


def test_uc1_1_name_is_required(client: TestClient) -> None:
    res = client.post(URL, json={"name": "", "role": "patient"}, headers=bearer("norole-token"))
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "VALIDATION_ERROR"
