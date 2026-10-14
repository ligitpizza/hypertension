"""Integration tests against the Firebase Emulator Suite (Module 1 services).

Skipped unless FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST are set.
`python tasks.py test` runs them inside `firebase emulators:exec --only auth,firestore`.
"""

import uuid
from datetime import UTC, datetime

import pytest

from tests.conftest import EMULATORS_STARTED

# conftest fills in emulator addresses as a production guard, so check what was really set.
pytestmark = pytest.mark.skipif(not EMULATORS_STARTED, reason="Firebase emulators not running")


@pytest.fixture(scope="module")
def services():  # type: ignore[no-untyped-def]
    from app.core.firebase import get_firestore
    from app.services.identity import FirebaseIdentityProvider
    from app.services.users import FirestoreUserRepository

    return FirebaseIdentityProvider(), FirestoreUserRepository(get_firestore())


def test_fr_1_6_identity_provider_creates_user_with_role_claim(services) -> None:  # type: ignore[no-untyped-def]
    from firebase_admin import auth

    from app.core.enums import UserRole
    from app.services.identity import EmailAlreadyRegisteredError

    identity, _ = services
    email = f"staff-{uuid.uuid4().hex[:8]}@careflow.test"
    uid = identity.create_user(email=email, display_name="Staff Test")
    identity.set_role(uid, UserRole.PHARMACIST)
    assert auth.get_user(uid).custom_claims == {"role": "pharmacist"}
    assert identity.password_setup_link(email).startswith("http")
    with pytest.raises(EmailAlreadyRegisteredError):
        identity.create_user(email=email, display_name="Duplicate")


def test_fr_1_4_repository_round_trip(services) -> None:  # type: ignore[no-untyped-def]
    _, repo = services
    uid = f"it-{uuid.uuid4().hex[:8]}"
    code = f"T{uuid.uuid4().hex[:5].upper()}"
    repo.create_user(uid, {"email": "x@careflow.test", "role": "patient", "linkCode": code})
    user = repo.get_user(uid)
    assert user is not None
    assert user["role"] == "patient"
    assert "createdAt" in user
    assert repo.link_code_exists(code)
    assert not repo.link_code_exists("ZZZZZZ")

    from google.api_core.exceptions import AlreadyExists

    with pytest.raises(AlreadyExists):  # create() never overwrites an existing profile
        repo.create_user(uid, {"role": "doctor"})

    dob = datetime(1970, 1, 1, tzinfo=UTC)
    repo.complete_onboarding(
        uid,
        {"patientId": uid, "personalInfo": "{}", "medicalHistory": "{}", "lifestyleFactors": "{}"},
        {"onboardingComplete": True, "dateOfBirth": dob, "gender": "female"},
    )
    user = repo.get_user(uid)
    assert user is not None
    assert user["onboardingComplete"] is True
    assert user["gender"] == "female"


def test_fr_9_2_risk_score_end_to_end_with_trained_models(services) -> None:  # type: ignore[no-untyped-def]
    """Real Firestore queries + real ml/artifacts models (UC9.1)."""
    import json as _json
    from datetime import timedelta

    from firebase_admin import firestore

    from app.core.config import get_settings
    from app.core.firebase import get_firestore
    from app.ml.risk_model import RiskModel
    from app.services.risk import FirestoreRiskDataRepository, generate_risk_score

    artifacts = get_settings().ml_artifacts_dir
    if not (artifacts / "feature_map.json").exists():
        pytest.skip("trained models not present")
    db = get_firestore()
    uid = f"risk-{uuid.uuid4().hex[:8]}"
    db.collection("users").document(uid).set(
        {"role": "patient", "gender": "male", "dateOfBirth": datetime(1955, 5, 5, tzinfo=UTC)}
    )
    db.collection("health_profiles").document(uid).set(
        {
            "patientId": uid,
            "personalInfo": _json.dumps({"heightCm": 172, "weightKg": 90}),
            "medicalHistory": _json.dumps(
                {"hypertensionDiagnosedYear": 2010, "conditions": ["diabetes"], "familyHistory": []}
            ),
            "lifestyleFactors": _json.dumps({"smokingStatus": "current"}),
        }
    )
    base = datetime.now(UTC)
    for i, (s, d) in enumerate([(150, 95), (145, 92), (155, 98)]):
        db.collection("vital_readings").add(
            {
                "patientId": uid,
                "systolic": s,
                "diastolic": d,
                "heartRate": 82,
                "timestamp": base - timedelta(hours=i),
            }
        )
    result = generate_risk_score(uid, FirestoreRiskDataRepository(db), RiskModel.load(artifacts))
    saved = db.collection("risk_scores").document(result.score_id).get().to_dict()
    assert saved["patientId"] == uid
    assert set(saved["scores"]) == {"stroke", "cad", "heartFailure", "ckd", "t2d"}
    assert all(0 <= v["value"] <= 1 for v in saved["scores"].values())
    assert isinstance(saved["generatedAt"], datetime)
    assert "XGBoost v1" in saved["modelUsed"]
    assert result.inputs.low_confidence is False
    assert result.prediction.overall_level.value in {"moderate", "high", "critical"}
    _ = firestore  # imported for parity with production code paths
