"""D-50: doctor deletes own prescriptions; patients record prescriptions from elsewhere."""

from typing import Any

import pytest
from fastapi.testclient import TestClient

from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryProviderRepository,
    InMemoryUserRepository,
    bearer,
)

P = "u-patient"
PATIENT = bearer("patient-token")
DOCTOR = bearer("doctor-token")  # uid u-doctor


@pytest.fixture(autouse=True)
def assigned(repo: InMemoryUserRepository) -> None:
    repo.users[P] = {"role": "patient", "name": "Siti", "assignedDoctorId": "u-doctor"}


def issue(client: TestClient) -> str:
    res = client.post(
        f"/api/v1/provider/patients/{P}/prescriptions",
        json={"medicationName": "Losartan", "dosage": "50mg", "frequency": "Once daily"},
        headers=DOCTOR,
    )
    assert res.status_code == 201
    return str(res.json()["id"])


def report(client: TestClient, **body: Any) -> Any:
    payload = {"medicationName": "Metformin", "dosage": "500mg", "frequency": "Twice daily"}
    return client.post("/api/v1/prescriptions/reported", json={**payload, **body}, headers=PATIENT)


def test_doctor_prescriptions_are_marked_as_doctor(
    client: TestClient, provider_repo: InMemoryProviderRepository
) -> None:
    issue(client)
    assert provider_repo.prescriptions[0]["source"] == "doctor"


def test_issuing_doctor_can_delete(
    client: TestClient, provider_repo: InMemoryProviderRepository, audit: InMemoryAuditLogger
) -> None:
    rx = issue(client)
    res = client.delete(f"/api/v1/provider/patients/{P}/prescriptions/{rx}", headers=DOCTOR)
    assert res.status_code == 204 and provider_repo.prescriptions == []
    assert "DELETE_PRESCRIPTION" in audit.actions()


def test_doctor_cannot_delete_patient_reported_or_unknown(client: TestClient) -> None:
    rx = report(client).json()["id"]
    for target in (rx, "nope"):
        res = client.delete(f"/api/v1/provider/patients/{P}/prescriptions/{target}", headers=DOCTOR)
        assert res.status_code == 404


def test_patient_cannot_use_the_doctor_delete(client: TestClient) -> None:
    rx = issue(client)
    res = client.delete(f"/api/v1/provider/patients/{P}/prescriptions/{rx}", headers=PATIENT)
    assert res.status_code == 403


def test_patient_records_a_prescription_from_another_clinic(
    client: TestClient, provider_repo: InMemoryProviderRepository, audit: InMemoryAuditLogger
) -> None:
    res = report(client, clinic="Klinik Kesihatan Setapak")
    assert res.status_code == 201
    [rx] = provider_repo.prescriptions
    assert rx["source"] == "patient" and rx["doctorId"] is None and rx["isRecurring"] is False
    assert rx["medicationDetails"] == "Metformin 500mg, Twice daily, from Klinik Kesihatan Setapak"
    assert "REPORT_PRESCRIPTION" in audit.actions()


def test_patient_edits_and_deletes_only_their_own_reported(
    client: TestClient, provider_repo: InMemoryProviderRepository
) -> None:
    mine = report(client).json()["id"]
    doctors = issue(client)
    body = {"medicationName": "Metformin", "dosage": "850mg", "frequency": "Twice daily"}
    assert (
        client.put(f"/api/v1/prescriptions/reported/{mine}", json=body, headers=PATIENT).status_code
        == 200
    )
    assert provider_repo.prescription(mine)["medicationDetails"].startswith("Metformin 850mg")  # type: ignore[index]
    # A doctor's prescription can't be changed through the patient route.
    assert (
        client.put(
            f"/api/v1/prescriptions/reported/{doctors}", json=body, headers=PATIENT
        ).status_code
        == 404
    )
    assert (
        client.delete(f"/api/v1/prescriptions/reported/{doctors}", headers=PATIENT).status_code
        == 404
    )
    assert (
        client.delete(f"/api/v1/prescriptions/reported/{mine}", headers=PATIENT).status_code == 204
    )
    assert [p["source"] for p in provider_repo.prescriptions] == ["doctor"]


def test_only_patients_report(client: TestClient) -> None:
    res = client.post(
        "/api/v1/prescriptions/reported",
        json={"medicationName": "Metformin", "dosage": "500mg", "frequency": "Twice daily"},
        headers=DOCTOR,
    )
    assert res.status_code == 403
