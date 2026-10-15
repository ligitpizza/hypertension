"""Module 11 user management (FR-11.1, UC11.1; D-59)."""

from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from tests.conftest import (
    FakeIdentityProvider,
    InMemoryAuditLogger,
    InMemoryUserRepository,
    bearer,
)

ADMIN = bearer("admin-token")


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository) -> None:
    repo.users.update(
        {
            "u-admin": {
                "role": "admin",
                "name": "Ada Admin",
                "email": "a@example.com",
                "createdAt": datetime(2026, 9, 1, tzinfo=UTC),
            },
            "u-doctor": {
                "role": "doctor",
                "name": "Dr John",
                "email": "d@example.com",
                "specialty": "Cardiology",
                "createdAt": datetime(2026, 9, 2, tzinfo=UTC),
            },
            "u-patient": {
                "role": "patient",
                "name": "Siti",
                "email": "s@example.com",
                "assignedDoctorId": "u-doctor",
                "createdAt": datetime(2026, 10, 1, tzinfo=UTC),
            },
            "u-p2": {
                "role": "patient",
                "name": "Ali",
                "email": "ali@example.com",
                "assignedDoctorId": "u-doctor",
                "isActive": False,
                "createdAt": datetime(2026, 10, 2, tzinfo=UTC),
            },
        }
    )


def test_fr11_1_lists_users_newest_first_with_caseload(client: TestClient) -> None:
    res = client.get("/api/v1/admin/users", headers=ADMIN)
    assert res.status_code == 200
    users = res.json()["users"]
    assert [u["uid"] for u in users] == ["u-p2", "u-patient", "u-doctor", "u-admin"]
    doctor = next(u for u in users if u["uid"] == "u-doctor")
    # Only active patients count; default limit 30 (D-59).
    assert doctor["caseload"] == 1 and doctor["maxPatients"] == 30
    assert next(u for u in users if u["uid"] == "u-p2")["isActive"] is False


def test_uc11_1_search_and_role_filter(client: TestClient) -> None:
    res = client.get("/api/v1/admin/users", params={"role": "patient"}, headers=ADMIN)
    assert {u["uid"] for u in res.json()["users"]} == {"u-patient", "u-p2"}
    res = client.get("/api/v1/admin/users", params={"q": "JOHN"}, headers=ADMIN)
    assert [u["uid"] for u in res.json()["users"]] == ["u-doctor"]
    res = client.get("/api/v1/admin/users", params={"q": "ali@"}, headers=ADMIN)
    assert [u["uid"] for u in res.json()["users"]] == ["u-p2"]


@pytest.mark.parametrize("token", ["doctor-token", "patient-token", "pharmacist-token"])
def test_admin_only(client: TestClient, token: str) -> None:
    assert client.get("/api/v1/admin/users", headers=bearer(token)).status_code == 403
    res = client.patch("/api/v1/admin/users/u-p2", json={"isActive": True}, headers=bearer(token))
    assert res.status_code == 403


def test_uc11_1_edit_doctor_details_is_logged(
    client: TestClient, repo: InMemoryUserRepository, audit: InMemoryAuditLogger
) -> None:
    body = {"name": "Dr John Tan", "specialty": "General Practice", "maxPatients": 25}
    res = client.patch("/api/v1/admin/users/u-doctor", json=body, headers=ADMIN)
    assert res.status_code == 200
    assert res.json()["maxPatients"] == 25 and res.json()["name"] == "Dr John Tan"
    assert repo.users["u-doctor"]["specialty"] == "General Practice"
    assert audit.entries[-1]["action"] == "EDIT_USER"
    assert "maxPatients" in audit.entries[-1]["details"]


def test_specialty_and_limit_are_for_doctors_only(client: TestClient) -> None:
    res = client.patch("/api/v1/admin/users/u-patient", json={"maxPatients": 5}, headers=ADMIN)
    assert res.json()["error"]["code"] == "NOT_A_DOCTOR"


def test_role_cannot_be_changed(client: TestClient) -> None:
    res = client.patch("/api/v1/admin/users/u-patient", json={"role": "admin"}, headers=ADMIN)
    assert res.status_code == 422


def test_uc11_1_deactivate_blocks_login_and_signs_out(
    client: TestClient,
    repo: InMemoryUserRepository,
    identity: FakeIdentityProvider,
    audit: InMemoryAuditLogger,
) -> None:
    body = {"isActive": False, "reason": "Left the clinic"}
    res = client.patch("/api/v1/admin/users/u-doctor", json=body, headers=ADMIN)
    assert res.status_code == 200 and res.json()["isActive"] is False
    assert repo.users["u-doctor"]["isActive"] is False
    assert "u-doctor" in identity.disabled and "u-doctor" in identity.revoked
    assert audit.entries[-1]["action"] == "DEACTIVATE_ACCOUNT"
    assert "Left the clinic" in audit.entries[-1]["details"]


def test_reactivate_also_cancels_a_pending_deletion(
    client: TestClient,
    repo: InMemoryUserRepository,
    identity: FakeIdentityProvider,
    audit: InMemoryAuditLogger,
) -> None:
    repo.users["u-p2"]["deletionRequestedAt"] = datetime(2026, 10, 10, tzinfo=UTC)
    identity.disabled.add("u-p2")
    res = client.patch("/api/v1/admin/users/u-p2", json={"isActive": True}, headers=ADMIN)
    assert res.json()["isActive"] is True and res.json()["deletionRequested"] is False
    assert "deletionRequestedAt" not in repo.users["u-p2"]
    assert "u-p2" not in identity.disabled
    assert audit.entries[-1]["action"] == "REACTIVATE_ACCOUNT"


def test_uc11_1_e1_the_last_admin_cannot_be_deactivated(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    res = client.patch("/api/v1/admin/users/u-admin", json={"isActive": False}, headers=ADMIN)
    assert res.status_code == 409 and res.json()["error"]["code"] == "LAST_ADMIN"
    assert repo.users["u-admin"].get("isActive") is not False
    # With a second active admin it is allowed.
    repo.users["u-admin2"] = {"role": "admin", "name": "Ben", "email": "b@example.com"}
    res = client.patch("/api/v1/admin/users/u-admin", json={"isActive": False}, headers=ADMIN)
    assert res.status_code == 200


def test_unknown_user(client: TestClient) -> None:
    res = client.patch("/api/v1/admin/users/nobody", json={"name": "Xx"}, headers=ADMIN)
    assert res.status_code == 404
