import pytest
from fastapi.testclient import TestClient

from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    bearer,
)

URL = "/api/v1/vitals"


@pytest.fixture
def patient(repo: InMemoryUserRepository) -> InMemoryUserRepository:
    repo.users["u-patient"] = {"role": "patient", "isActive": True, "onboardingComplete": True}
    return repo


def test_fr_3_1_uc3_1_logs_reading_with_category_and_alert(
    client: TestClient,
    patient: InMemoryUserRepository,
    vitals_repo: InMemoryVitalsRepository,
    audit: InMemoryAuditLogger,
) -> None:
    res = client.post(URL, json={"systolic": 145, "diastolic": 92}, headers=bearer("patient-token"))
    assert res.status_code == 201
    body = res.json()
    assert body["category"] == "stage2"
    assert body["alertLevel"] == "moderate"
    assert body["heartRate"] is None
    saved = vitals_repo.readings[body["id"]]
    assert saved == {"patientId": "u-patient", "systolic": 145, "diastolic": 92}
    assert audit.entries[0]["action"] == "LOG_VITAL_READING"
    assert audit.entries[0]["targetId"] == body["id"]


def test_uc3_2_note_and_uc3_3_heart_rate_are_saved(
    client: TestClient, patient: InMemoryUserRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    res = client.post(
        URL,
        json={"systolic": 118, "diastolic": 76, "heartRate": 72, "note": "  after walk  "},
        headers=bearer("patient-token"),
    )
    assert res.status_code == 201
    assert res.json()["category"] == "normal"
    assert res.json()["alertLevel"] is None
    saved = vitals_repo.readings[res.json()["id"]]
    assert saved["heartRate"] == 72
    assert saved["note"] == "after walk"


def test_uc3_2_blank_note_is_not_stored(
    client: TestClient, patient: InMemoryUserRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    res = client.post(
        URL, json={"systolic": 118, "diastolic": 76, "note": "   "}, headers=bearer("patient-token")
    )
    assert "note" not in vitals_repo.readings[res.json()["id"]]


@pytest.mark.parametrize(
    "body",
    [
        {"systolic": 400, "diastolic": 80},
        {"systolic": 80, "diastolic": 90},
        {"systolic": 120, "diastolic": 30},
        {"systolic": 120, "diastolic": 80, "heartRate": 300},
    ],
)
def test_uc3_1_e1_out_of_range_is_rejected(
    client: TestClient,
    patient: InMemoryUserRepository,
    vitals_repo: InMemoryVitalsRepository,
    body: dict[str, int],
) -> None:
    res = client.post(URL, json=body, headers=bearer("patient-token"))
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "READING_OUT_OF_RANGE"
    assert vitals_repo.readings == {}


def test_fr_1_3_only_patients_log_readings(client: TestClient) -> None:
    for token in ("doctor-token", "family-token", "admin-token"):
        res = client.post(URL, json={"systolic": 120, "diastolic": 80}, headers=bearer(token))
        assert res.status_code == 403, token
    assert client.post(URL, json={"systolic": 120, "diastolic": 80}).status_code == 401


def test_uc1_2_e2_deactivated_patient_cannot_log(
    client: TestClient, patient: InMemoryUserRepository
) -> None:
    patient.users["u-patient"]["isActive"] = False
    res = client.post(URL, json={"systolic": 120, "diastolic": 80}, headers=bearer("patient-token"))
    assert res.status_code == 403
    assert res.json()["error"]["code"] == "ACCOUNT_DEACTIVATED"


def test_reading_requires_registration(client: TestClient) -> None:
    res = client.post(URL, json={"systolic": 120, "diastolic": 80}, headers=bearer("patient-token"))
    assert res.status_code == 404


def test_missing_values_are_validation_errors(
    client: TestClient, patient: InMemoryUserRepository
) -> None:
    res = client.post(URL, json={"systolic": 120}, headers=bearer("patient-token"))
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "VALIDATION_ERROR"
