"""D-78: admin center (staff requests), doctor prescription management, dev BP deletion."""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from tests.conftest import (
    InMemoryOrderRepository,
    InMemoryProviderRepository,
    InMemoryRiskRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    MakeClient,
    bearer,
    dev_settings,
)

P, D, PH, A = "u-patient", "u-doctor", "u-pharm", "u-admin"
PATIENT, DOCTOR, PHARM, ADMIN = (
    bearer("patient-token"),
    bearer("doctor-token"),
    bearer("pharmacist-token"),
    bearer("admin-token"),
)


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users.update(
        {
            P: {"role": "patient", "name": "Siti", "assignedDoctorId": D},
            D: {"role": "doctor", "name": "Dr Tan"},
            PH: {"role": "pharmacist", "name": "Aisyah"},
            A: {"role": "admin", "name": "Admin Lee"},
        }
    )
    for uid in (D, PH, A):
        tokens.add(uid, f"token-{uid}", "web")


def titles(push: LogPushClient, uid: str) -> list[str]:
    return [m.title for toks, m in push.sent if f"token-{uid}" in toks]


# ---- admin center ----


def test_d78_staff_send_requests_and_the_admin_replies(
    client: TestClient, push: LogPushClient
) -> None:
    body = {"category": "stock", "subject": "Amlodipine supplier late", "details": "Two weeks."}
    res = client.post("/api/v1/staff-requests", json=body, headers=PHARM)
    assert res.status_code == 201, res.text
    rid = res.json()["id"]
    assert res.json()["status"] == "open" and res.json()["requesterName"] == "Aisyah"
    assert "New staff request from Aisyah" in titles(push, A)

    client.post(
        "/api/v1/staff-requests",
        json={"category": "leave", "subject": "Leave on Friday", "details": "Family event."},
        headers=DOCTOR,
    )
    # Each requester sees only their own; the admin sees all.
    assert len(client.get("/api/v1/staff-requests", headers=PHARM).json()["requests"]) == 1
    assert len(client.get("/api/v1/staff-requests", headers=ADMIN).json()["requests"]) == 2

    upd = client.patch(
        f"/api/v1/staff-requests/{rid}",
        json={"status": "in_progress", "reply": "Ordered from a second supplier."},
        headers=ADMIN,
    )
    assert upd.status_code == 200
    assert upd.json()["reply"] == "Ordered from a second supplier."
    assert upd.json()["repliedBy"] == "Admin Lee"
    assert "Admin updated your request: Amlodipine supplier late" in titles(push, PH)
    mine = client.get("/api/v1/staff-requests", headers=PHARM).json()["requests"][0]
    assert mine["status"] == "in_progress"


def test_d78_request_rules(client: TestClient) -> None:
    good = {"category": "it", "subject": "Printer", "details": "Broken."}
    assert client.post("/api/v1/staff-requests", json=good, headers=PATIENT).status_code == 403
    assert client.post("/api/v1/staff-requests", json=good, headers=ADMIN).status_code == 403
    bad = {**good, "category": "holiday"}
    assert client.post("/api/v1/staff-requests", json=bad, headers=DOCTOR).status_code == 422
    assert (
        client.patch("/api/v1/staff-requests/x", json={"status": "done"}, headers=ADMIN).status_code
        == 404
    )
    rid = client.post("/api/v1/staff-requests", json=good, headers=DOCTOR).json()["id"]
    assert (
        client.patch(
            f"/api/v1/staff-requests/{rid}", json={"status": "done"}, headers=DOCTOR
        ).status_code
        == 403
    )
    assert client.patch(f"/api/v1/staff-requests/{rid}", json={}, headers=ADMIN).status_code == 422


# ---- prescription management ----


def test_d78_doctor_lists_their_prescriptions_with_order_status(
    client: TestClient,
    provider_repo: InMemoryProviderRepository,
    order_repo: InMemoryOrderRepository,
) -> None:
    now = datetime.now(UTC)
    provider_repo.prescriptions += [
        {
            "id": "rx1",
            "patientId": P,
            "doctorId": D,
            "medicationDetails": "Amlodipine 5mg x30",
            "items": [{"catalogId": "a", "quantity": 30, "unitPrice": 0.3}],
            "isRecurring": True,
            "issuedAt": now - timedelta(days=2),
        },
        {
            "id": "rx2",
            "patientId": P,
            "doctorId": D,
            "medicationDetails": "Losartan",
            "isRecurring": False,
            "issuedAt": now,
        },
        {"id": "rx3", "patientId": P, "doctorId": "someone-else", "medicationDetails": "x"},
    ]
    order_repo.create_order(
        "rx1_2026-10",
        {
            "prescriptionId": "rx1",
            "patientId": P,
            "fulfilmentStatus": "awaiting_payment",
            "paymentStatus": "pending",
        },
    )
    rows = client.get("/api/v1/provider/prescriptions", headers=DOCTOR).json()["prescriptions"]
    assert [r["id"] for r in rows] == ["rx2", "rx1"]
    rx1 = rows[1]
    assert rx1["patientName"] == "Siti" and rx1["isRecurring"] is True
    assert rx1["total"] == pytest.approx(9.0)
    assert rx1["latestOrder"]["status"] == "awaiting_payment"
    assert rx1["latestOrder"]["ref"].startswith("CF-")
    assert rows[0]["latestOrder"] is None
    assert client.get("/api/v1/provider/prescriptions", headers=PHARM).status_code == 403


# ---- dev BP deletion ----


def _readings(vitals_repo: InMemoryVitalsRepository, n: int) -> None:
    for i in range(n):
        vitals_repo.readings[f"r{i}"] = {
            "patientId": P,
            "systolic": 130 + i,
            "diastolic": 85,
            "timestamp": datetime.now(UTC) - timedelta(hours=i),
        }


def test_d78_dev_tools_are_off_by_default(
    client: TestClient, vitals_repo: InMemoryVitalsRepository
) -> None:
    _readings(vitals_repo, 1)
    assert client.get("/api/v1/vitals/dev-tools", headers=PATIENT).json() == {"enabled": False}
    assert client.delete("/api/v1/vitals/r0", headers=PATIENT).status_code == 404
    assert client.delete("/api/v1/vitals", headers=PATIENT).status_code == 404
    assert "r0" in vitals_repo.readings


def test_d78_delete_one_rescores_and_clear_all_removes_scores(
    make_client: MakeClient,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
) -> None:
    client = make_client(dev_settings(dev_vitals_tools=True))
    assert client.get("/api/v1/vitals/dev-tools", headers=PATIENT).json() == {"enabled": True}
    _readings(vitals_repo, 4)
    vitals_repo.readings["theirs"] = {"patientId": "u-other", "systolic": 120, "diastolic": 80}
    risk_repo.saved.append({"patientId": P, "scores": {}})
    res = client.delete("/api/v1/vitals/r0", headers=PATIENT)
    assert res.status_code == 200 and res.json() == {"rescored": True}
    assert "r0" not in vitals_repo.readings
    assert len([d for d in risk_repo.saved if d["patientId"] == P]) == 1  # the new score
    assert client.delete("/api/v1/vitals/theirs", headers=PATIENT).status_code == 404

    assert client.delete("/api/v1/vitals", headers=PATIENT).json() == {"deleted": 3}
    assert list(vitals_repo.readings) == ["theirs"]
    assert not [d for d in risk_repo.saved if d["patientId"] == P]


def test_d78_below_three_readings_the_score_is_removed(
    make_client: MakeClient,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
) -> None:
    client = make_client(dev_settings(dev_vitals_tools=True))
    _readings(vitals_repo, 3)
    risk_repo.saved.append({"patientId": P, "scores": {}})
    body: dict[str, Any] = client.delete("/api/v1/vitals/r1", headers=PATIENT).json()
    assert body == {"rescored": False}
    assert not risk_repo.saved
