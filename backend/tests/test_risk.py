import json
import math
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.enums import Complication, RiskLevel
from app.ml.risk_inputs import assemble
from app.ml.risk_model import ComplicationRisk, RiskPrediction, categorise
from app.services.risk import NotEnoughReadingsError, generate_risk_score
from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryRiskRepository,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    bearer,
    fake_risk_model,
)

NOW = datetime(2026, 10, 13, 9, tzinfo=UTC)
USER = {"gender": "female", "dateOfBirth": datetime(1966, 10, 20, tzinfo=UTC)}
PROFILE = {
    "personalInfo": json.dumps({"heightCm": 160, "weightKg": 64}),
    "medicalHistory": json.dumps(
        {
            "hypertensionDiagnosedYear": 2015,
            "conditions": ["diabetes", "high_cholesterol"],
            "familyHistory": ["stroke", "heart_disease"],
        }
    ),
    "lifestyleFactors": json.dumps({"smokingStatus": "former"}),
}


def reading(sys: int, dia: int, hr: int | None = None, days_ago: int = 0) -> dict[str, Any]:
    r: dict[str, Any] = {
        "patientId": "u-patient",
        "systolic": sys,
        "diastolic": dia,
        "timestamp": NOW - timedelta(days=days_ago),
    }
    if hr is not None:
        r["heartRate"] = hr
    return r


# ---------- input assembly (docs/06 algorithm A step 2) ----------


def test_fr_9_2_assembles_app_inputs() -> None:
    readings = [reading(140, 90, days_ago=0), reading(130, 80, hr=70, days_ago=1), reading(120, 70)]
    meds = [{"adherenceRate": 80.0}, {"adherenceRate": 100.0}]
    inp = assemble(USER, PROFILE, readings, meds, NOW)
    f = inp.features
    assert f["age"] == 59  # birthday on 20 Oct not reached yet
    assert f["female"] == 1
    assert (f["systolic"], f["diastolic"]) == (130, 80)  # mean of the last three
    assert f["heart_rate"] == 70  # most recent reading that has one
    assert f["bmi"] == pytest.approx(25.0)
    assert f["smoking"] == 1  # former
    assert f["family_history"] == 1  # heart disease counts, stroke alone would not
    assert f["hypertension"] == 1
    assert f["high_cholesterol"] == 1
    assert f["t2d"] == 1
    assert f["cad"] == 0
    assert (f["bp_medication"], f["medication_count"]) == (1, 2)
    assert inp.adherence_rate == 90
    assert inp.days_since_last_reading == 0
    assert inp.low_confidence is False


def test_uc9_1_e1_missing_inputs_flag_reduced_confidence() -> None:
    inp = assemble({}, None, [reading(118, 76)], [], NOW)
    assert math.isnan(inp.features["age"])
    assert math.isnan(inp.features["bmi"])
    assert set(inp.missing) == {"age", "female", "bmi", "heart_rate", "smoking"}
    assert inp.low_confidence is True
    assert inp.features["medication_count"] == 0
    assert inp.adherence_rate is None


def test_hypertension_inferred_from_stage2_readings() -> None:
    profile = {**PROFILE, "medicalHistory": json.dumps({"conditions": [], "familyHistory": []})}
    high = assemble(USER, profile, [reading(150, 95)] * 3, [], NOW)
    normal = assemble(USER, profile, [reading(118, 76)] * 3, [], NOW)
    assert high.features["hypertension"] == 1
    assert normal.features["hypertension"] == 0


def test_family_history_of_stroke_only_does_not_count() -> None:
    profile = {
        **PROFILE,
        "medicalHistory": json.dumps({"conditions": [], "familyHistory": ["stroke"]}),
    }
    assert assemble(USER, profile, [reading(120, 80)], [], NOW).features["family_history"] == 0


# ---------- categorisation (FR-9.3, D-30) ----------


@pytest.mark.parametrize(
    ("value", "level"),
    [
        (0.0, RiskLevel.LOW),
        (0.0999, RiskLevel.LOW),
        (0.1, RiskLevel.MODERATE),
        (0.2499, RiskLevel.MODERATE),
        (0.25, RiskLevel.HIGH),
        (0.4999, RiskLevel.HIGH),
        (0.5, RiskLevel.CRITICAL),
        (0.99, RiskLevel.CRITICAL),
    ],
)
def test_fr_9_3_fixed_cut_points(value: float, level: RiskLevel) -> None:
    assert categorise(value, {"moderate": 0.1, "high": 0.25, "critical": 0.5}) is level


def test_d03_overall_level_is_the_highest() -> None:
    p = RiskPrediction(
        scores={
            Complication.STROKE: ComplicationRisk(0.1, RiskLevel.LOW),
            Complication.CAD: ComplicationRisk(0.4, RiskLevel.HIGH),
            Complication.CKD: ComplicationRisk(0.2, RiskLevel.MODERATE),
        },
        model_used="x",
    )
    assert p.overall_level is RiskLevel.HIGH


def test_fr_9_2_predicts_all_five_in_ch4_shape() -> None:
    model = fake_risk_model(0.3)
    p = model.predict({"age": 60, "systolic": 140, "diastolic": 90, "bmi": 27})
    assert set(p.scores) == set(Complication)
    assert all(s.level is RiskLevel.HIGH for s in p.scores.values())
    assert p.model_used.startswith("stroke:XGBoost v1; cad:")


# ---------- UC9.1 generate risk score ----------


def _seed(repo: InMemoryUserRepository, vitals: InMemoryVitalsRepository, n: int) -> None:
    repo.users["u-patient"] = {**USER, "role": "patient", "isActive": True}
    repo.health_profiles["u-patient"] = PROFILE
    for i in range(n):
        vitals.add_reading(reading(130 + i, 85))


def test_uc9_1_needs_three_readings(
    repo: InMemoryUserRepository,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
) -> None:
    _seed(repo, vitals_repo, 2)
    with pytest.raises(NotEnoughReadingsError):
        generate_risk_score("u-patient", risk_repo, fake_risk_model(), NOW)
    assert risk_repo.saved == []


def test_uc9_1_saves_ch4_risk_score_document(
    repo: InMemoryUserRepository,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
) -> None:
    _seed(repo, vitals_repo, 3)
    result = generate_risk_score("u-patient", risk_repo, fake_risk_model(0.05), NOW)
    doc = risk_repo.saved[0]
    assert set(doc) == {"patientId", "modelUsed", "scores"}  # generatedAt is a server timestamp
    assert doc["scores"]["heartFailure"] == {"value": 0.05, "level": "low", "factors": []}
    response = result.to_response()
    assert response["overallLevel"] == "low"
    assert response["lowConfidence"] is True  # no heart rate in the seeded readings
    assert response["missingInputs"] == ["heart_rate"]


# ---------- endpoints ----------


def test_uc9_1_vitals_returns_progress_before_three_readings(
    client: TestClient, repo: InMemoryUserRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    _seed(repo, vitals_repo, 0)
    res = client.post(
        "/api/v1/vitals", json={"systolic": 128, "diastolic": 82}, headers=bearer("patient-token")
    )
    body = res.json()
    assert body["risk"] is None
    assert body["riskStatus"] == "not_enough_readings"
    assert body["readingsUntilRisk"] == 2


def test_fr_9_2_third_reading_generates_and_audits_a_risk_score(
    client: TestClient,
    repo: InMemoryUserRepository,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
    audit: InMemoryAuditLogger,
) -> None:
    _seed(repo, vitals_repo, 2)
    res = client.post(
        "/api/v1/vitals",
        json={"systolic": 150, "diastolic": 95, "heartRate": 80},
        headers=bearer("patient-token"),
    )
    body = res.json()
    assert body["riskStatus"] == "ok"
    assert body["risk"]["overallLevel"] == "high"
    assert body["risk"]["scoreId"] == "risk1"
    assert set(body["risk"]["scores"]) == {c.value for c in Complication}
    assert "GENERATE_RISK_SCORE" in audit.actions()
    assert len(risk_repo.saved) == 1


def test_reading_is_saved_even_without_models(
    make_client: Any, repo: InMemoryUserRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    from app.ml.risk_model import get_risk_model

    _seed(repo, vitals_repo, 3)
    client: TestClient = make_client()
    client.app.dependency_overrides[get_risk_model] = lambda: None  # type: ignore[attr-defined]
    res = client.post(
        "/api/v1/vitals", json={"systolic": 120, "diastolic": 80}, headers=bearer("patient-token")
    )
    assert res.status_code == 201
    assert res.json()["riskStatus"] == "model_unavailable"
    assert len(vitals_repo.readings) == 4


def test_rescore_rules(
    client: TestClient, repo: InMemoryUserRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    _seed(repo, vitals_repo, 3)
    assert (
        client.post("/api/v1/risk-score/u-patient", headers=bearer("patient-token")).status_code
        == 201
    )
    assert (
        client.post("/api/v1/risk-score/u-other", headers=bearer("patient-token")).status_code
        == 403
    )
    assert (
        client.post("/api/v1/risk-score/u-patient", headers=bearer("admin-token")).status_code
        == 201
    )
    assert (
        client.post("/api/v1/risk-score/u-patient", headers=bearer("doctor-token")).status_code
        == 403
    )


def test_rescore_needs_three_readings(
    client: TestClient, repo: InMemoryUserRepository, vitals_repo: InMemoryVitalsRepository
) -> None:
    _seed(repo, vitals_repo, 1)
    res = client.post("/api/v1/risk-score/u-patient", headers=bearer("patient-token"))
    assert res.status_code == 409
    assert res.json()["error"]["code"] == "NOT_ENOUGH_READINGS"


# ---------- D-40 contributing factors ----------


def test_d40_top_factors_keep_only_inputs_that_raised_the_estimate() -> None:
    from app.ml.risk_model import top_factors

    names = ["age", "systolic", "medication_count", "smoking", "bmi"]
    contrib = [0.08, 0.30, -0.40, 0.01, 0.05]
    # medication_count lowered it; smoking is below the 0.02 noise floor.
    assert top_factors(contrib, names) == ("systolic", "age", "bmi")
    assert top_factors([0.5, 0.4, 0.3, 0.2], ["a", "b", "c", "d"]) == ("a", "b", "c")  # top 3
    assert top_factors([-0.1, 0.0], ["a", "b"]) == ()


def test_d40_real_models_explain_a_hypertensive_patient() -> None:
    """Uses the committed trained artifacts (ml/artifacts); skipped if absent."""
    from app.core.config import get_settings
    from app.ml.risk_model import RiskModel

    directory = get_settings().ml_artifacts_dir
    if not (directory / "stroke_model.joblib").exists():
        pytest.skip("trained models not present")
    model = RiskModel.load(directory)
    inputs: dict[str, float] = {
        "age": 68,
        "female": 0,
        "systolic": 168,
        "diastolic": 98,
        "heart_rate": 84,
        "bmi": 31,
        "smoking": 2,
        "family_history": 1,
        "hypertension": 1,
        "high_cholesterol": 1,
        "bp_medication": 0,
        "medication_count": 0,
        "stroke": 0,
        "cad": 0,
        "heartFailure": 0,
        "ckd": 0,
        "t2d": 0,
    }
    prediction = model.predict(inputs)
    for c, score in prediction.scores.items():
        assert len(score.factors) <= 3
        assert set(score.factors) <= set(model._features[c])
    stroke = prediction.scores[Complication.STROKE].factors
    assert stroke and stroke[0] in {"age", "systolic", "hypertension", "smoking"}


def test_d40_low_risk_complications_are_not_explained() -> None:
    """Near-zero risks get no factors (Ping, 2026-10-14): they were noise."""
    from app.core.config import get_settings
    from app.ml.risk_model import RiskModel

    directory = get_settings().ml_artifacts_dir
    if not (directory / "stroke_model.joblib").exists():
        pytest.skip("trained models not present")
    model = RiskModel.load(directory)
    young: dict[str, float] = {
        "age": 16,
        "female": 0,
        "systolic": 89,
        "diastolic": 59,
        "heart_rate": 66,
        "bmi": 22,
        "smoking": 0,
        "family_history": 0,
        "hypertension": 0,
        "high_cholesterol": 0,
        "bp_medication": 0,
        "medication_count": 0,
        "stroke": 0,
        "cad": 0,
        "heartFailure": 0,
        "ckd": 0,
        "t2d": 0,
    }
    for score in model.predict(young).scores.values():
        if score.level is RiskLevel.LOW:
            assert score.factors == ()
