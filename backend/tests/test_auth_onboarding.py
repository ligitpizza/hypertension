import json
from copy import deepcopy
from datetime import date
from typing import Any

import pytest
from fastapi.testclient import TestClient

from tests.conftest import InMemoryAuditLogger, InMemoryUserRepository, bearer

URL = "/api/v1/auth/onboarding"

VALID: dict[str, Any] = {
    "dateOfBirth": "1968-04-12",
    "gender": "male",
    "personalInfo": {
        "heightCm": 170,
        "weightKg": 82.5,
        "phone": "+60 12-345 6789",
        "emergencyContact": {"name": "Siti", "phone": "0123456789", "relationship": "Wife"},
    },
    "medicalHistory": {
        "hypertensionDiagnosedYear": 2015,
        "conditions": ["diabetes", "high_cholesterol"],
        "familyHistory": ["hypertension", "stroke"],
        "allergies": "Penicillin",
        "notes": "",
    },
    "lifestyleFactors": {
        "smokingStatus": "former",
        "alcohol": "occasional",
        "exerciseDaysPerWeek": 2,
        "saltIntake": "high",
    },
}


@pytest.fixture
def registered_patient(repo: InMemoryUserRepository) -> InMemoryUserRepository:
    repo.users["u-patient"] = {
        "email": "p@example.com",
        "name": "Ali",
        "role": "patient",
        "isActive": True,
        "onboardingComplete": False,
    }
    return repo


def _post(client: TestClient, body: dict[str, Any], token: str = "patient-token") -> Any:
    return client.post(URL, json=body, headers=bearer(token))


def test_fr_1_4_uc1_4_onboarding_saves_structured_profile(
    client: TestClient, registered_patient: InMemoryUserRepository, audit: InMemoryAuditLogger
) -> None:
    res = _post(client, VALID)
    assert res.status_code == 201
    assert res.json() == {"status": "ok", "onboardingComplete": True}

    profile = registered_patient.health_profiles["u-patient"]
    assert profile["patientId"] == "u-patient"
    # D-25: each Ch4 String field holds a JSON object.
    personal = json.loads(profile["personalInfo"])
    assert personal["heightCm"] == 170
    assert personal["emergencyContact"]["relationship"] == "Wife"
    assert json.loads(profile["medicalHistory"])["conditions"] == ["diabetes", "high_cholesterol"]
    assert json.loads(profile["lifestyleFactors"])["smokingStatus"] == "former"

    user = registered_patient.users["u-patient"]
    assert user["onboardingComplete"] is True
    assert user["gender"] == "male"
    assert user["dateOfBirth"].date() == date(1968, 4, 12)
    assert audit.actions() == ["COMPLETE_ONBOARDING"]


@pytest.mark.parametrize(
    ("path", "field"),
    [
        (["gender"], "gender"),
        (["dateOfBirth"], "dateOfBirth"),
        (["personalInfo", "heightCm"], "personalInfo.heightCm"),
        (["medicalHistory", "conditions"], "medicalHistory.conditions"),
        (["lifestyleFactors", "smokingStatus"], "lifestyleFactors.smokingStatus"),
    ],
)
def test_uc1_4_e1_missing_required_field_is_named(
    client: TestClient, registered_patient: InMemoryUserRepository, path: list[str], field: str
) -> None:
    body = deepcopy(VALID)
    target = body
    for key in path[:-1]:
        target = target[key]
    del target[path[-1]]
    res = _post(client, body)
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "VALIDATION_ERROR"
    assert res.json()["error"]["message"].startswith(field)
    assert registered_patient.users["u-patient"]["onboardingComplete"] is False


@pytest.mark.parametrize(
    "mutate",
    [
        lambda b: b["personalInfo"].update(heightCm=40),
        lambda b: b["personalInfo"].update(weightKg=1000),
        lambda b: b["personalInfo"].update(phone="abc"),
        lambda b: b.update(dateOfBirth="2999-01-01"),
        lambda b: b["medicalHistory"].update(conditions=["flu"]),
        lambda b: b["lifestyleFactors"].update(exerciseDaysPerWeek=9),
        lambda b: b.update(unexpected="x"),
    ],
)
def test_uc1_4_e1_implausible_values_are_rejected(
    client: TestClient, registered_patient: InMemoryUserRepository, mutate: Any
) -> None:
    body = deepcopy(VALID)
    mutate(body)
    assert _post(client, body).status_code == 422


def test_fr_1_4_emergency_contact_is_optional(
    client: TestClient, registered_patient: InMemoryUserRepository
) -> None:
    body = deepcopy(VALID)
    del body["personalInfo"]["emergencyContact"]
    assert _post(client, body).status_code == 201


def test_fr_1_3_only_patients_can_onboard(client: TestClient) -> None:
    assert _post(client, VALID, token="family-token").status_code == 403
    assert _post(client, VALID, token="doctor-token").status_code == 403


def test_uc1_4_onboarding_is_one_time(
    client: TestClient, registered_patient: InMemoryUserRepository
) -> None:
    assert _post(client, VALID).status_code == 201
    res = _post(client, VALID)
    assert res.status_code == 409
    assert res.json()["error"]["code"] == "ONBOARDING_ALREADY_COMPLETE"


def test_uc1_4_requires_registration_first(client: TestClient) -> None:
    res = _post(client, VALID)
    assert res.status_code == 404
    assert res.json()["error"]["code"] == "PROFILE_NOT_FOUND"


def test_uc1_2_e2_deactivated_patient_cannot_onboard(
    client: TestClient, registered_patient: InMemoryUserRepository
) -> None:
    registered_patient.users["u-patient"]["isActive"] = False
    res = _post(client, VALID)
    assert res.status_code == 403
    assert res.json()["error"]["code"] == "ACCOUNT_DEACTIVATED"
