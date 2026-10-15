"""FR-14.2 family monitoring and emergency alerts (UC15.1-UC15.3; D-06, D-62)."""

import json
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from app.integrations.sms import LogSmsClient
from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryFamilyRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P, F, D = "u-patient", "u-family", "u-doctor"
PATIENT, FAMILY = bearer("patient-token"), bearer("family-token")
HERE = {"lat": 3.139, "lng": 101.6869}


@pytest.fixture(autouse=True)
def people(
    repo: InMemoryUserRepository,
    tokens: InMemoryTokenRepository,
    family_repo: InMemoryFamilyRepository,
) -> None:
    repo.users.update(
        {
            P: {
                "role": "patient",
                "name": "Siti",
                "linkCode": "AB12CD",
                "assignedDoctorId": D,
                "onboardingComplete": True,
            },
            F: {"role": "family_member", "name": "Aisyah", "patientId": None},
            D: {"role": "doctor", "name": "Dr John"},
        }
    )
    family_repo.profiles[P] = {
        "personalInfo": json.dumps(
            {"phone": "012-3456789", "emergencyContact": {"name": "Ali", "phone": "019-8765432"}}
        )
    }
    for uid in (P, F, D):
        tokens.add(uid, f"token-{uid}", "android")


def link(client: TestClient, repo: InMemoryUserRepository) -> None:
    repo.users[F]["patientId"] = P


def titles(push: LogPushClient, uid: str) -> list[str]:
    return [m.title for toks, m in push.sent if f"token-{uid}" in toks]


# ---------- UC15.1 linking ----------


def test_uc15_1_link_request_then_patient_approves(
    client: TestClient,
    repo: InMemoryUserRepository,
    family_repo: InMemoryFamilyRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    res = client.post("/api/v1/family/link-requests", json={"code": "ab12-cd"}, headers=FAMILY)
    assert res.status_code == 201
    rid = res.json()["id"]
    assert family_repo.requests[rid]["status"] == "pending"
    assert family_repo.requests[rid]["familyMemberName"] == "Aisyah"
    assert "Family link request" in titles(push, P)
    assert repo.users[F]["patientId"] is None  # E1: pending until approved
    res = client.post(f"/api/v1/family/link-requests/{rid}/approve", headers=PATIENT)
    assert res.json()["status"] == "approved"
    assert repo.users[F]["patientId"] == P
    assert "Link approved" in titles(push, F)
    assert audit.actions()[-1] == "APPROVE_FAMILY_LINK"


def test_link_rules(client: TestClient, repo: InMemoryUserRepository) -> None:
    res = client.post("/api/v1/family/link-requests", json={"code": "ZZZZZZ"}, headers=FAMILY)
    assert res.json()["error"]["code"] == "INVALID_CODE"
    client.post("/api/v1/family/link-requests", json={"code": "AB12CD"}, headers=FAMILY)
    again = client.post("/api/v1/family/link-requests", json={"code": "AB12CD"}, headers=FAMILY)
    assert again.json()["error"]["code"] == "REQUEST_PENDING"
    repo.users[F]["patientId"] = P
    linked = client.post("/api/v1/family/link-requests", json={"code": "AB12CD"}, headers=FAMILY)
    assert linked.json()["error"]["code"] == "ALREADY_LINKED"
    # Patients cannot use the family endpoint.
    res = client.post("/api/v1/family/link-requests", json={"code": "AB12CD"}, headers=PATIENT)
    assert res.status_code == 403


def test_reject_and_withdraw(
    client: TestClient, repo: InMemoryUserRepository, family_repo: InMemoryFamilyRepository
) -> None:
    rid = client.post(
        "/api/v1/family/link-requests", json={"code": "AB12CD"}, headers=FAMILY
    ).json()["id"]
    client.post(f"/api/v1/family/link-requests/{rid}/reject", headers=PATIENT)
    assert family_repo.requests[rid]["status"] == "rejected"
    assert repo.users[F]["patientId"] is None
    res = client.post(f"/api/v1/family/link-requests/{rid}/approve", headers=PATIENT)
    assert res.json()["error"]["code"] == "REQUEST_CLOSED"
    rid2 = client.post(
        "/api/v1/family/link-requests", json={"code": "AB12CD"}, headers=FAMILY
    ).json()["id"]
    assert client.delete(f"/api/v1/family/link-requests/{rid2}", headers=FAMILY).status_code == 204
    assert family_repo.requests[rid2]["status"] == "rejected"


def test_only_the_patient_decides(client: TestClient, repo: InMemoryUserRepository) -> None:
    rid = client.post(
        "/api/v1/family/link-requests", json={"code": "AB12CD"}, headers=FAMILY
    ).json()["id"]
    repo.users["u-other"] = {"role": "patient", "name": "Other"}
    res = client.post(f"/api/v1/family/link-requests/{rid}/approve", headers=FAMILY)
    assert res.status_code == 403


def test_d62_unlink_by_either_side(
    client: TestClient, repo: InMemoryUserRepository, push: LogPushClient
) -> None:
    link(client, repo)
    assert client.delete("/api/v1/family/link", headers=FAMILY).status_code == 204
    assert repo.users[F]["patientId"] is None
    assert "Family member unlinked" in titles(push, P)
    link(client, repo)
    assert client.delete(f"/api/v1/family/members/{F}", headers=PATIENT).status_code == 204
    assert repo.users[F]["patientId"] is None
    assert "Link removed" in titles(push, F)
    res = client.delete(f"/api/v1/family/members/{F}", headers=PATIENT)
    assert res.status_code == 404


# ---------- UC15.2 / UC15.3 emergencies ----------


def emergency_reading(client: TestClient, location: dict[str, float] | None = HERE) -> Any:
    body: dict[str, Any] = {"systolic": 190, "diastolic": 125}
    if location:
        body["location"] = location
    return client.post("/api/v1/vitals", json=body, headers=PATIENT)


def test_fr14_2_emergency_reading_alerts_family_with_gps_and_sms(
    client: TestClient,
    repo: InMemoryUserRepository,
    family_repo: InMemoryFamilyRepository,
    push: LogPushClient,
    sms: LogSmsClient,
) -> None:
    link(client, repo)
    assert emergency_reading(client).status_code == 201
    ((alert_id, alert),) = family_repo.alerts.items()
    assert alert["familyMemberId"] == F and alert["trigger"] == "emergency_reading"
    assert alert["gpsLocation"] == HERE and alert["patientPhone"] == "012-3456789"
    family_push = [m for toks, m in push.sent if f"token-{F}" in toks][-1]
    assert family_push.urgent and family_push.data["alertId"] == alert_id
    assert sms.sent and sms.sent[-1][0] == "019-8765432"
    assert "maps.google.com/?q=3.139000,101.686900" in sms.sent[-1][1]
    # The reading itself never stores the location (D-62).
    assert "location" not in str(repo.users[P])


def test_repeated_emergency_updates_location_instead_of_spamming(
    client: TestClient, repo: InMemoryUserRepository, family_repo: InMemoryFamilyRepository
) -> None:
    link(client, repo)
    emergency_reading(client)
    emergency_reading(client, {"lat": 3.2, "lng": 101.7})
    assert len(family_repo.alerts) == 1
    assert next(iter(family_repo.alerts.values()))["gpsLocation"] == {"lat": 3.2, "lng": 101.7}


def test_uc15_2_e1_no_family_linked_is_logged(
    client: TestClient, family_repo: InMemoryFamilyRepository, audit: InMemoryAuditLogger
) -> None:
    emergency_reading(client)
    assert family_repo.alerts == {}
    entry = next(e for e in audit.entries if e["action"] == "EMERGENCY_ALERT")
    assert "none linked" in entry["details"]


def test_sos_alerts_family_and_doctor_every_time(
    client: TestClient,
    repo: InMemoryUserRepository,
    family_repo: InMemoryFamilyRepository,
    push: LogPushClient,
) -> None:
    link(client, repo)
    res = client.post("/api/v1/emergency/sos", json={"location": HERE}, headers=PATIENT)
    assert res.json() == {"familyAlerted": 1, "doctorNotified": True}
    assert "Patient SOS" in titles(push, D)
    client.post("/api/v1/emergency/sos", json={}, headers=PATIENT)
    assert len(family_repo.alerts) == 2  # SOS is never suppressed
    assert list(family_repo.alerts.values())[-1]["gpsLocation"] is None
    res = client.post("/api/v1/emergency/sos", json={"notifyFamily": False}, headers=PATIENT)
    assert res.json()["familyAlerted"] == 0 and len(family_repo.alerts) == 2


def test_d62_location_refresh_only_for_open_alerts(
    client: TestClient, repo: InMemoryUserRepository, family_repo: InMemoryFamilyRepository
) -> None:
    link(client, repo)
    assert client.get("/api/v1/emergency/open", headers=PATIENT).json()["open"] == 0
    client.post("/api/v1/emergency/sos", json={"location": HERE}, headers=PATIENT)
    assert client.get("/api/v1/emergency/open", headers=PATIENT).json()["open"] == 1
    moved = {"lat": 3.15, "lng": 101.7}
    res = client.put("/api/v1/emergency/location", json={"location": moved}, headers=PATIENT)
    assert res.json()["updated"] == 1
    alert = next(iter(family_repo.alerts.values()))
    assert alert["gpsLocation"] == moved and alert["locationUpdatedAt"] is not None
    # Older than an hour: no longer refreshed.
    alert_id = next(iter(family_repo.alerts))
    family_repo.alerts[alert_id]["sentAt"] = datetime.now(UTC) - timedelta(hours=2)
    res = client.put("/api/v1/emergency/location", json={"location": HERE}, headers=PATIENT)
    assert res.json()["updated"] == 0


def test_uc15_3_family_acknowledges_and_patient_is_told(
    client: TestClient,
    repo: InMemoryUserRepository,
    family_repo: InMemoryFamilyRepository,
    push: LogPushClient,
) -> None:
    link(client, repo)
    client.post("/api/v1/emergency/sos", json={"location": HERE}, headers=PATIENT)
    alert_id = next(iter(family_repo.alerts))
    res = client.post(f"/api/v1/emergency/alerts/{alert_id}/acknowledge", headers=FAMILY)
    assert res.status_code == 200
    assert family_repo.alerts[alert_id]["acknowledgedAt"] is not None
    assert "Your family saw your alert" in titles(push, P)
    # Acknowledged alerts stop refreshing.
    res = client.put("/api/v1/emergency/location", json={"location": HERE}, headers=PATIENT)
    assert res.json()["updated"] == 0


def test_only_the_recipient_acknowledges(
    client: TestClient, repo: InMemoryUserRepository, family_repo: InMemoryFamilyRepository
) -> None:
    link(client, repo)
    client.post("/api/v1/emergency/sos", json={}, headers=PATIENT)
    alert_id = next(iter(family_repo.alerts))
    family_repo.alerts[alert_id]["familyMemberId"] = "someone-else"
    res = client.post(f"/api/v1/emergency/alerts/{alert_id}/acknowledge", headers=FAMILY)
    assert res.status_code == 404


def test_location_is_validated(client: TestClient) -> None:
    res = client.post(
        "/api/v1/emergency/sos", json={"location": {"lat": 120, "lng": 0}}, headers=PATIENT
    )
    assert res.status_code == 422
