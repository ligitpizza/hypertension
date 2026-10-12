"""Integration tests against the Firebase Emulator Suite (Module 1 services).

Skipped unless FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST are set.
`python tasks.py test` runs them inside `firebase emulators:exec --only auth,firestore`.
"""

import os
import uuid
from datetime import UTC, datetime

import pytest

pytestmark = pytest.mark.skipif(
    not (
        os.environ.get("FIRESTORE_EMULATOR_HOST") and os.environ.get("FIREBASE_AUTH_EMULATOR_HOST")
    ),
    reason="Firebase emulators not running",
)


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
