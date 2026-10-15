"""D-61: admin detail pages for patients, doctors and pharmacists."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from tests.conftest import (
    InMemoryAnalyticsSource,
    InMemoryAuditReader,
    InMemoryUserRepository,
    bearer,
)

ADMIN = bearer("admin-token")
NOW = datetime.now(UTC)


@pytest.fixture(autouse=True)
def clinic(
    repo: InMemoryUserRepository,
    analytics: InMemoryAnalyticsSource,
    audit_reader: InMemoryAuditReader,
) -> None:
    repo.users.update(
        {
            "u-admin": {"role": "admin", "name": "Ada"},
            "d1": {"role": "doctor", "name": "Dr John", "specialty": "Cardiology"},
            "p1": {
                "role": "patient",
                "name": "Siti",
                "assignedDoctorId": "d1",
                "icNumber": "900101-14-5677",
                "gender": "female",
            },
            "p2": {"role": "patient", "name": "Ali", "assignedDoctorId": "d1"},
            "f1": {"role": "family_member", "name": "Mum", "patientId": "p1"},
            "ph": {"role": "pharmacist", "name": "Ph Tan"},
        }
    )
    a = analytics.add
    a(
        "vital_readings",
        patientId="p1",
        timestamp=NOW - timedelta(days=40),
        systolic=150,
        diastolic=95,
    )
    a(
        "vital_readings",
        patientId="p1",
        timestamp=NOW - timedelta(hours=2),
        systolic=128,
        diastolic=82,
    )
    a(
        "risk_scores",
        patientId="p1",
        generatedAt=NOW - timedelta(hours=2),
        scores={"cad": {"value": 0.4, "level": "high"}},
    )
    a("medications", patientId="p1", name="Losartan", dosage="50mg", adherenceRate=86.0)
    a(
        "appointments",
        patientId="p1",
        doctorId="d1",
        dateTime=NOW + timedelta(days=2),
        status="booked",
        type="checkup",
        bookedBy="admin",
    )
    a(
        "appointments",
        patientId="p2",
        doctorId="d1",
        dateTime=NOW - timedelta(days=3),
        status="completed",
        type="checkup",
    )
    a("health_records", patientId="p1", sharedWithDoctor=True)
    a("health_records", patientId="p1", sharedWithDoctor=False)
    a("clinical_alerts", doctorId="d1", status="open")
    audit_reader.add(NOW - timedelta(days=1), "LOGIN", "d1")
    audit_reader.add(NOW - timedelta(days=60), "LOGIN", "d1")  # older than 30 days


def get(client: TestClient, uid: str) -> dict:  # type: ignore[type-arg]
    res = client.get(f"/api/v1/admin/users/{uid}", headers=ADMIN)
    assert res.status_code == 200
    return dict(res.json())


def test_patient_detail(client: TestClient) -> None:
    body = get(client, "p1")
    assert body["user"]["role"] == "patient"
    assert body["profile"]["icNumber"] == "900101-**-**77"  # masked
    p = body["patient"]
    assert p["doctor"] == {"uid": "d1", "name": "Dr John"}
    assert (p["latestReading"]["systolic"], p["readingsLast30Days"]) == (128, 1)
    assert p["risk"]["level"] == "high"
    assert p["medications"][0]["adherenceRate"] == 86.0
    assert (
        p["appointments"][0]["bookedBy"] == "admin" and p["appointments"][0]["other"] == "Dr John"
    )
    assert p["records"] == {"total": 2, "shared": 1}
    assert p["family"] == [{"uid": "f1", "name": "Mum"}]


def test_doctor_detail(client: TestClient) -> None:
    body = get(client, "d1")
    d = body["doctor"]
    assert body["user"]["caseload"] == 2 and body["user"]["maxPatients"] == 30
    assert [(x["name"], x["riskLevel"]) for x in d["patients"]] == [("Ali", None), ("Siti", "high")]
    assert [u["other"] for u in d["upcoming"]] == ["Siti"]
    assert d["completedTotal"] == 1 and d["openAlerts"] == 1
    assert [e["action"] for e in body["activity"]] == ["LOGIN"]  # last 30 days only


def test_pharmacist_detail(client: TestClient) -> None:
    body = get(client, "ph")
    assert body["pharmacist"] == {"orders": None}
    assert "patient" not in body and "doctor" not in body


def test_unknown_and_admin_only(client: TestClient) -> None:
    assert client.get("/api/v1/admin/users/nobody", headers=ADMIN).status_code == 404
    res = client.get("/api/v1/admin/users/p1", headers=bearer("doctor-token"))
    assert res.status_code == 403
