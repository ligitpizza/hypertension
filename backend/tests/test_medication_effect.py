"""Risk before vs after starting medication (D-44; FR-5.3 x FR-9.2, doctor view FR-8.2)."""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.services.medication_effect import medication_effect
from tests.conftest import (
    InMemoryRiskRepository,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    bearer,
    fake_risk_model,
)

P = "u-patient"
NOW = datetime(2026, 10, 14, 4, tzinfo=UTC)
START = NOW - timedelta(days=30)


@pytest.fixture(autouse=True)
def assigned(repo: InMemoryUserRepository) -> None:
    repo.users[P] = {
        "role": "patient",
        "name": "Siti",
        "assignedDoctorId": "u-doctor",
        "gender": "female",
        "dateOfBirth": datetime(1966, 5, 1, tzinfo=UTC),
    }
    repo.users["u-other"] = {"role": "patient", "name": "Ali", "assignedDoctorId": "d2"}


def add(vitals: InMemoryVitalsRepository, sys: int, dia: int, at: datetime) -> None:
    """Readings are added oldest first (the fake returns newest first)."""
    vitals.add_reading({"patientId": P, "systolic": sys, "diastolic": dia, "timestamp": at})


def on_medication(risk_repo: InMemoryRiskRepository, start: datetime = START) -> None:
    risk_repo.meds[P] = [
        {"name": "Amlodipine", "dosage": "5mg", "createdAt": start},
        {"name": "Lisinopril", "dosage": "10mg", "createdAt": start + timedelta(days=5)},
    ]


def test_no_medication(risk_repo: InMemoryRiskRepository) -> None:
    assert medication_effect(P, risk_repo, fake_risk_model(), NOW) == {"status": "no_medication"}


def test_no_readings_before_the_first_medicine(
    risk_repo: InMemoryRiskRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    on_medication(risk_repo)
    add(vitals_repo, 130, 85, START + timedelta(days=1))
    out = medication_effect(P, risk_repo, fake_risk_model(), NOW)
    assert out["status"] == "no_baseline"
    assert out["firstMedication"] == "Amlodipine 5mg" and out["daysOnMedication"] == 30


def test_no_readings_since(
    risk_repo: InMemoryRiskRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    on_medication(risk_repo)
    add(vitals_repo, 160, 100, START - timedelta(days=1))
    assert medication_effect(P, risk_repo, fake_risk_model(), NOW)["status"] == "no_followup"


def test_compares_bp_only_and_holds_other_inputs_fixed(
    risk_repo: InMemoryRiskRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    on_medication(risk_repo)
    for d in (5, 4, 3, 2):  # four before; only the latest three count
        add(vitals_repo, 150 + d, 98, START - timedelta(days=d))
    for d in (20, 10, 1):
        add(vitals_repo, 132, 84, NOW - timedelta(days=d))
    model = fake_risk_model()
    out = medication_effect(P, risk_repo, model, NOW)
    assert out["status"] == "ok" and out["early"] is False
    assert out["bpBefore"] == {"systolic": 153.0, "diastolic": 98.0}
    assert out["bpAfter"] == {"systolic": 132.0, "diastolic": 84.0}
    assert (out["readingsBefore"], out["readingsAfter"]) == (3, 3)
    assert set(out["complications"]) == {"stroke", "cad", "heartFailure", "ckd", "t2d"}
    # Fake features: age, systolic, diastolic, bmi. Each complication ran twice and only
    # the BP columns differ between the two runs.
    rows: list[Any] = next(iter(model._models.values())).rows
    before, after = rows[0][0], rows[1][0]
    assert before[0] == after[0] == 60  # age unchanged
    assert (before[1], before[2], after[1], after[2]) == (153.0, 98.0, 132.0, 84.0)


def test_early_when_under_two_weeks(
    risk_repo: InMemoryRiskRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    start = NOW - timedelta(days=5)
    on_medication(risk_repo, start)
    add(vitals_repo, 150, 95, start - timedelta(days=1))
    add(vitals_repo, 140, 90, NOW)
    out = medication_effect(P, risk_repo, fake_risk_model(), NOW)
    assert out["status"] == "ok" and out["early"] is True


def test_without_models_bp_is_still_shown(
    risk_repo: InMemoryRiskRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    on_medication(risk_repo)
    add(vitals_repo, 150, 95, START - timedelta(days=1))
    add(vitals_repo, 130, 80, NOW)
    out = medication_effect(P, risk_repo, None, NOW)
    assert out["status"] == "model_unavailable" and out["bpAfter"]["systolic"] == 130.0


def test_real_models_show_lower_risk_when_bp_falls(
    risk_repo: InMemoryRiskRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    """With the trained artifacts, a fall from stage 2 to normal-high lowers stroke risk,
    and adding the medicine itself never shows up as a rise (flag held fixed)."""
    from app.core.config import get_settings
    from app.ml.risk_model import RiskModel

    directory = get_settings().ml_artifacts_dir
    if not (directory / "stroke_model.joblib").exists():
        pytest.skip("trained models not present")
    on_medication(risk_repo)
    for d in (3, 2, 1):
        add(vitals_repo, 165, 100, START - timedelta(days=d))
    for d in (3, 2, 1):
        add(vitals_repo, 128, 82, NOW - timedelta(days=d))
    out = medication_effect(P, risk_repo, RiskModel.load(directory), NOW)
    stroke = out["complications"]["stroke"]
    assert stroke["after"] < stroke["before"]


# ---------- endpoint (FR-8.1 assigned doctor only) ----------


def url(patient: str = P) -> str:
    return f"/api/v1/provider/patients/{patient}/medication-effect"


def test_assigned_doctor_sees_the_comparison(
    client: TestClient,
    risk_repo: InMemoryRiskRepository,
    vitals_repo: InMemoryVitalsRepository,
) -> None:
    on_medication(risk_repo, datetime.now(UTC) - timedelta(days=20))
    add(vitals_repo, 150, 95, datetime.now(UTC) - timedelta(days=25))
    add(vitals_repo, 130, 80, datetime.now(UTC))
    res = client.get(url(), headers=bearer("doctor-token"))
    assert res.status_code == 200 and res.json()["status"] == "ok"


@pytest.mark.parametrize(
    ("patient", "token", "code"),
    [("u-other", "doctor-token", 403), (P, "patient-token", 403), ("nobody", "doctor-token", 404)],
)
def test_access_is_limited(client: TestClient, patient: str, token: str, code: int) -> None:
    assert client.get(url(patient), headers=bearer(token)).status_code == code
