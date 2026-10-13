"""Module 8 doctor actions (FR-8.3; UC8.4, UC8.4 E1, UC8.5) and interaction checks."""

import pytest
from fastapi.testclient import TestClient

from app.services.interactions import check, drug_classes
from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryProviderRepository,
    InMemoryUserRepository,
    bearer,
)

P = "u-patient"
DOCTOR = bearer("doctor-token")  # uid u-doctor


@pytest.fixture(autouse=True)
def assigned(repo: InMemoryUserRepository) -> None:
    repo.users[P] = {"role": "patient", "name": "Siti", "assignedDoctorId": "u-doctor"}
    repo.users["u-other"] = {"role": "patient", "name": "Ali", "assignedDoctorId": "d2"}


# ---------- interaction table (docs/06 §C) ----------


def test_drug_classes_match_names_case_insensitively() -> None:
    assert drug_classes("Lisinopril 10mg") == {"ace_inhibitor"}
    assert drug_classes("Vitamin D") == set()


def test_uc8_4_e1_ace_inhibitor_with_potassium_sparing_diuretic() -> None:
    [found] = check("Spironolactone", ["Lisinopril 10mg"])
    assert found.severity == "major"
    assert "potassium" in found.message


def test_critical_interactions_sort_first() -> None:
    assert [f.severity for f in check("Aliskiren", ["Lisinopril", "Paracetamol"])] == ["critical"]
    found = check("Losartan", ["Ibuprofen 400mg", "Lisinopril"])
    assert [f.severity for f in found] == ["major", "minor"]


def test_duplicate_therapy_is_flagged() -> None:
    [found] = check("Amlodipine 10mg", ["Amlodipine 5mg, once daily"])
    assert "Duplicate therapy" in found.message


def test_unrelated_combinations_are_clear() -> None:
    assert check("Amlodipine", ["Lisinopril"]) == []
    assert check("Paracetamol", ["Lisinopril"]) == []


# ---------- endpoints ----------


def notes_url(patient: str = P) -> str:
    return f"/api/v1/provider/patients/{patient}/notes"


def test_uc8_4_doctor_adds_clinical_note(
    client: TestClient, provider_repo: InMemoryProviderRepository, audit: InMemoryAuditLogger
) -> None:
    res = client.post(notes_url(), json={"content": "S: well"}, headers=DOCTOR)
    assert res.status_code == 201
    assert provider_repo.notes == [{"patientId": P, "doctorId": "u-doctor", "content": "S: well"}]
    assert "ADD_CLINICAL_NOTE" in audit.actions()


def test_uc8_5_care_plan_is_one_living_document(
    client: TestClient, provider_repo: InMemoryProviderRepository, audit: InMemoryAuditLogger
) -> None:
    for text in ("Plan v1", "Plan v2"):
        res = client.put(
            f"/api/v1/provider/patients/{P}/care-plan", json={"content": text}, headers=DOCTOR
        )
        assert res.status_code == 200
    assert provider_repo.care_plans == {
        P: {"patientId": P, "doctorId": "u-doctor", "content": "Plan v2"}
    }
    assert audit.actions().count("UPDATE_CARE_PLAN") == 2
    # D-41: every save is kept as a version.
    assert provider_repo.plan_versions[P] == [
        {"content": "Plan v1", "doctorId": "u-doctor"},
        {"content": "Plan v2", "doctorId": "u-doctor"},
    ]


RX = {
    "medicationName": "Losartan",
    "dosage": "50mg",
    "frequency": "Once daily",
    "duration": "30 days",
}
RX_URL = f"/api/v1/provider/patients/{P}/prescriptions"


def test_uc8_4_prescription_saved_with_details(
    client: TestClient, provider_repo: InMemoryProviderRepository, audit: InMemoryAuditLogger
) -> None:
    res = client.post(RX_URL, json={**RX, "isRecurring": True}, headers=DOCTOR)
    assert res.status_code == 201
    assert res.json()["medicationDetails"] == "Losartan 50mg, Once daily, for 30 days"
    assert provider_repo.prescriptions[0]["isRecurring"] is True
    assert "ISSUE_PRESCRIPTION" in audit.actions()


def test_uc8_4_e1_interaction_warns_before_saving_then_saves_when_acknowledged(
    client: TestClient, provider_repo: InMemoryProviderRepository, audit: InMemoryAuditLogger
) -> None:
    provider_repo.medications[P] = ["Lisinopril"]
    res = client.post(RX_URL, json=RX, headers=DOCTOR)
    assert res.status_code == 409
    error = res.json()["error"]
    assert error["code"] == "DRUG_INTERACTION"
    assert error["details"][0]["existingDrug"] == "Lisinopril"
    assert error["details"][0]["severity"] == "major"
    assert provider_repo.prescriptions == []

    res = client.post(RX_URL, json={**RX, "acknowledgeInteractions": True}, headers=DOCTOR)
    assert res.status_code == 201
    assert len(res.json()["interactions"]) == 1
    assert "acknowledged" in audit.entries[-1]["details"]


def test_earlier_prescriptions_count_as_current_medication(client: TestClient) -> None:
    assert client.post(RX_URL, json=RX, headers=DOCTOR).status_code == 201
    second = {**RX, "medicationName": "Lisinopril", "dosage": "10mg"}
    assert client.post(RX_URL, json=second, headers=DOCTOR).status_code == 409


@pytest.mark.parametrize(
    "path,method,body",
    [
        ("notes", "POST", {"content": "x"}),
        ("care-plan", "PUT", {"content": "x"}),
        ("prescriptions", "POST", RX),
    ],
)
def test_fr_8_1_only_the_assigned_doctor_may_write(
    client: TestClient, path: str, method: str, body: dict[str, object]
) -> None:
    res = client.request(
        method, f"/api/v1/provider/patients/u-other/{path}", json=body, headers=DOCTOR
    )
    assert res.status_code == 403
    assert res.json()["error"]["code"] == "NOT_ASSIGNED"


@pytest.mark.parametrize("token", ["patient-token", "pharmacist-token", "admin-token"])
def test_fr_1_3_other_roles_cannot_write_clinical_records(client: TestClient, token: str) -> None:
    res = client.post(notes_url(), json={"content": "x"}, headers=bearer(token))
    assert res.status_code == 403


def test_unknown_patient_is_404(client: TestClient) -> None:
    res = client.post(notes_url("nobody"), json={"content": "x"}, headers=DOCTOR)
    assert res.status_code == 404


def test_blank_note_is_rejected(client: TestClient) -> None:
    res = client.post(notes_url(), json={"content": "   "}, headers=DOCTOR)
    assert res.status_code == 422
