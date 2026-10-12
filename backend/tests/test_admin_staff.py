from fastapi.testclient import TestClient

from app.core.enums import UserRole
from app.integrations.email import ConsoleEmailClient, get_email_client
from app.routers.admin import staff_setup_email
from tests.conftest import (
    FailingEmailClient,
    FakeIdentityProvider,
    InMemoryAuditLogger,
    InMemoryUserRepository,
    bearer,
)

URL = "/api/v1/admin/staff"
DOCTOR = {"name": "Dr Tan", "email": "Tan@Hospital.my", "role": "doctor", "specialty": "Cardiology"}


def test_fr_1_6_uc1_5_admin_creates_doctor_account(
    client: TestClient,
    identity: FakeIdentityProvider,
    repo: InMemoryUserRepository,
    emails: ConsoleEmailClient,
    audit: InMemoryAuditLogger,
) -> None:
    res = client.post(URL, json=DOCTOR, headers=bearer("admin-token"))
    assert res.status_code == 201
    body = res.json()
    assert body["role"] == "doctor"
    assert body["emailSent"] is True
    assert body["setupLink"] is None

    uid = body["uid"]
    assert identity.claims[uid] == "doctor"
    assert repo.users[uid] == {
        "email": "tan@hospital.my",
        "name": "Dr Tan",
        "role": "doctor",
        "isActive": True,
        "specialty": "Cardiology",
    }
    # UC1.5 step 5: setup link emailed.
    assert len(emails.sent) == 1
    assert emails.sent[0].to_email == "tan@hospital.my"
    assert "https://example.test/reset" in emails.sent[0].text
    assert audit.entries[0]["action"] == "CREATE_STAFF_ACCOUNT"
    assert audit.entries[0]["userId"] == "u-admin"
    assert audit.entries[0]["targetId"] == uid


def test_fr_1_6_pharmacist_and_admin_have_no_specialty(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    for i, role in enumerate(("pharmacist", "admin")):
        body = {"name": "Staff X", "email": f"s{i}@h.my", "role": role, "specialty": "ignored"}
        res = client.post(URL, json=body, headers=bearer("admin-token"))
        assert res.status_code == 201
        assert "specialty" not in repo.users[res.json()["uid"]]


def test_uc1_5_e1_duplicate_email_is_rejected(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    body = {**DOCTOR, "email": "taken@example.com"}
    res = client.post(URL, json=body, headers=bearer("admin-token"))
    assert res.status_code == 409
    assert res.json()["error"]["code"] == "EMAIL_ALREADY_REGISTERED"
    assert repo.users == {}


def test_uc1_5_email_failure_returns_setup_link_to_admin(
    make_client: object, audit: InMemoryAuditLogger
) -> None:
    client: TestClient = make_client()  # type: ignore[operator]
    client.app.dependency_overrides[get_email_client] = lambda: FailingEmailClient()  # type: ignore[attr-defined]
    res = client.post(URL, json=DOCTOR, headers=bearer("admin-token"))
    assert res.status_code == 201
    assert res.json()["emailSent"] is False
    assert res.json()["setupLink"].startswith("https://example.test/reset")
    assert "not delivered" in audit.entries[0]["details"]


def test_fr_1_6_only_admin_can_create_staff(client: TestClient) -> None:
    for token in ("doctor-token", "pharmacist-token", "patient-token", "family-token"):
        assert client.post(URL, json=DOCTOR, headers=bearer(token)).status_code == 403, token
    assert client.post(URL, json=DOCTOR).status_code == 401


def test_fr_1_6_staff_endpoint_cannot_create_patient_or_family(client: TestClient) -> None:
    for role in ("patient", "family_member"):
        body = {**DOCTOR, "role": role}
        assert client.post(URL, json=body, headers=bearer("admin-token")).status_code == 422


def test_uc1_5_invalid_email_is_rejected(client: TestClient) -> None:
    body = {**DOCTOR, "email": "not-an-email"}
    assert client.post(URL, json=body, headers=bearer("admin-token")).status_code == 422


def test_uc1_5_setup_email_escapes_html() -> None:
    msg = staff_setup_email("<script>x</script>", "a@b.my", UserRole.ADMIN, "https://l?a=1&b=2")
    assert "<script>" not in msg.html
    assert "&amp;b=2" in msg.html
    assert "Administrator" in msg.text


def test_uc1_5_fake_email_returns_link_to_admin(make_client: object) -> None:
    """With INTEGRATIONS_MODE=fake nothing is delivered, so the admin must get the link."""
    client: TestClient = make_client()  # type: ignore[operator]
    client.app.dependency_overrides[get_email_client] = lambda: ConsoleEmailClient()  # type: ignore[attr-defined]
    res = client.post(URL, json={**DOCTOR, "email": "fake@h.my"}, headers=bearer("admin-token"))
    assert res.status_code == 201
    assert res.json()["emailSent"] is False
    assert res.json()["setupLink"].startswith("https://example.test/reset")
