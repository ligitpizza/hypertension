"""Module 12 settings (FR-12.1, FR-12.2; UC12.1-UC12.4; D-45, D-46, D-47)."""

import json
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient, PushMessage
from app.services.account_purge import AccountPurgeJob
from app.services.notifications import Notifier, pref_key
from tests.conftest import (
    FakeIdentityProvider,
    InMemoryAuditLogger,
    InMemoryProviderRepository,
    InMemoryRiskRepository,
    InMemorySettingsRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    bearer,
)

P = "u-patient"
PATIENT = bearer("patient-token")

PERSONAL = {"heightCm": 165, "weightKg": 70, "phone": "+60 12-345 6789", "emergencyContact": None}
HISTORY = {
    "hypertensionDiagnosedYear": 2020,
    "conditions": [],
    "familyHistory": ["heart_disease"],
    "allergies": "",
    "notes": "",
}
LIFESTYLE = {
    "smokingStatus": "never",
    "alcohol": "none",
    "exerciseDaysPerWeek": 3,
    "saltIntake": "moderate",
}


@pytest.fixture(autouse=True)
def patient(repo: InMemoryUserRepository, vitals_repo: InMemoryVitalsRepository) -> None:
    repo.users[P] = {
        "role": "patient",
        "name": "Siti",
        "email": "p@example.com",
        "isActive": True,
        "onboardingComplete": True,
        "gender": "female",
        "dateOfBirth": datetime(1970, 3, 1, tzinfo=UTC),
        "assignedDoctorId": "u-doctor",
    }
    repo.health_profiles[P] = {
        "patientId": P,
        "personalInfo": json.dumps(PERSONAL),
        "medicalHistory": json.dumps(HISTORY),
        "lifestyleFactors": json.dumps(LIFESTYLE),
    }
    for i, (s, d) in enumerate([(150, 95), (145, 92), (148, 94)]):
        vitals_repo.add_reading(
            {
                "patientId": P,
                "systolic": s,
                "diastolic": d,
                "timestamp": datetime.now(UTC) - timedelta(days=3 - i),
            }
        )


def health_body(**changes: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "heightCm": 165,
        "weightKg": 70,
        "medicalHistory": dict(HISTORY),
        "lifestyleFactors": dict(LIFESTYLE),
    }
    body.update(changes)
    return body


# ---------- UC12.1 personal info and contact ----------


def test_uc12_1_profile_update_rescores_when_age_or_sex_changes(
    client: TestClient,
    repo: InMemoryUserRepository,
    risk_repo: InMemoryRiskRepository,
    audit: InMemoryAuditLogger,
) -> None:
    same = {"name": "Siti Aminah", "dateOfBirth": "1970-03-01", "gender": "female"}
    res = client.put("/api/v1/settings/profile", json=same, headers=PATIENT)
    assert res.status_code == 200 and res.json()["rescored"] is False
    assert repo.users[P]["name"] == "Siti Aminah"
    res = client.put(
        "/api/v1/settings/profile", json={**same, "dateOfBirth": "1960-03-01"}, headers=PATIENT
    )
    assert res.json()["rescored"] is True and len(risk_repo.saved) == 1
    assert repo.users[P]["dateOfBirth"] == datetime(1960, 3, 1, tzinfo=UTC)
    assert audit.actions().count("UPDATE_PROFILE") == 2


@pytest.mark.parametrize(
    "body",
    [
        {"name": "S", "dateOfBirth": "1970-03-01", "gender": "female"},
        {"name": "Siti", "dateOfBirth": "2099-01-01", "gender": "female"},
        {"name": "Siti", "dateOfBirth": "1970-03-01", "gender": "robot"},
    ],
)
def test_uc12_1_e1_invalid_input_is_rejected(client: TestClient, body: dict[str, Any]) -> None:
    assert client.put("/api/v1/settings/profile", json=body, headers=PATIENT).status_code == 422


def test_uc12_1_contact_merges_into_personal_info(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    body = {
        "phone": "012-999 8888",
        "emergencyContact": {"name": "Ali", "phone": "0123456789", "relationship": "Son"},
    }
    assert client.put("/api/v1/settings/contact", json=body, headers=PATIENT).status_code == 200
    personal = json.loads(repo.health_profiles[P]["personalInfo"])
    assert personal["phone"] == "012-999 8888" and personal["heightCm"] == 165
    assert personal["emergencyContact"]["name"] == "Ali"
    bad = client.put("/api/v1/settings/contact", json={"phone": "abc"}, headers=PATIENT)
    assert bad.status_code == 422


# ---------- UC12.2 health profile ----------


def test_uc12_2_risk_relevant_change_rescores(
    client: TestClient, repo: InMemoryUserRepository, risk_repo: InMemoryRiskRepository
) -> None:
    body = health_body(lifestyleFactors={**LIFESTYLE, "smokingStatus": "current"})
    res = client.put("/api/v1/settings/health-profile", json=body, headers=PATIENT)
    assert res.status_code == 200 and res.json()["rescored"] is True
    assert json.loads(repo.health_profiles[P]["lifestyleFactors"])["smokingStatus"] == "current"
    # Contact details survive a health-profile edit.
    assert json.loads(repo.health_profiles[P]["personalInfo"])["phone"] == "+60 12-345 6789"
    assert len(risk_repo.saved) == 1


def test_uc12_2_other_changes_do_not_rescore(
    client: TestClient, risk_repo: InMemoryRiskRepository, audit: InMemoryAuditLogger
) -> None:
    body = health_body(medicalHistory={**HISTORY, "allergies": "Penicillin"})
    res = client.put("/api/v1/settings/health-profile", json=body, headers=PATIENT)
    assert res.json()["rescored"] is False and risk_repo.saved == []
    assert "UPDATE_HEALTH_PROFILE" in audit.actions()


def test_uc12_2_needs_onboarding(client: TestClient, repo: InMemoryUserRepository) -> None:
    repo.users[P]["onboardingComplete"] = False
    res = client.put("/api/v1/settings/health-profile", json=health_body(), headers=PATIENT)
    assert res.status_code == 409


# ---------- D-45 notification preferences ----------


def test_d45_preferences_are_saved(client: TestClient, repo: InMemoryUserRepository) -> None:
    body = {"medicationReminders": False, "healthUpdates": True}
    res = client.put("/api/v1/settings/notifications", json=body, headers=PATIENT)
    assert res.status_code == 200
    assert repo.users[P]["notificationPrefs"] == body


def test_d45_push_categories() -> None:
    assert pref_key(PushMessage("t", "b", {"type": "dose"})) == "medicationReminders"
    assert pref_key(PushMessage("t", "b", {"type": "refill"})) == "medicationReminders"
    assert pref_key(PushMessage("t", "b", {"type": "risk"})) == "healthUpdates"
    assert pref_key(PushMessage("t", "b", {"type": "bp_alert"}, urgent=True)) is None


def test_d45_muted_pushes_are_skipped_but_urgent_ones_always_arrive() -> None:
    tokens = InMemoryTokenRepository()
    tokens.add(P, "phone", "android")
    tokens.notification_prefs[P] = {"medicationReminders": False, "healthUpdates": False}
    push = LogPushClient()
    notifier = Notifier(tokens, push)
    assert notifier.notify(P, PushMessage("Time to take X", "", {"type": "dose"})) == 0
    assert notifier.notify(P, PushMessage("Reading saved", "", {"type": "reading"})) == 0
    urgent = PushMessage("Very high BP", "", {"type": "bp_alert"}, urgent=True)
    assert notifier.notify(P, urgent) == 1
    assert [m.title for _, m in push.sent] == ["Very high BP"]


# ---------- UC12.3 export (D-47) ----------


def test_uc12_3_json_export(client: TestClient, audit: InMemoryAuditLogger) -> None:
    res = client.get("/api/v1/settings/export?format=json", headers=PATIENT)
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("application/json")
    assert "attachment" in res.headers["content-disposition"]
    data = res.json()
    assert data["profile"]["name"] == "Siti"
    assert data["healthProfile"]["lifestyleFactors"]["smokingStatus"] == "never"
    assert len(data["vital_readings"]) == 3
    assert "not included" in data["note"]
    assert "EXPORT_DATA" in audit.actions()


def test_uc12_3_pdf_export(client: TestClient) -> None:
    res = client.get("/api/v1/settings/export", headers=PATIENT)
    assert res.status_code == 200 and res.headers["content-type"] == "application/pdf"
    assert res.content.startswith(b"%PDF")


def test_export_is_patient_only(client: TestClient) -> None:
    res = client.get("/api/v1/settings/export", headers=bearer("doctor-token"))
    assert res.status_code == 403


# ---------- UC12.4 delete (D-46) ----------


def test_uc12_4_e1_recurring_prescription_warns_first(
    client: TestClient, provider_repo: InMemoryProviderRepository
) -> None:
    provider_repo.prescriptions.append(
        {"patientId": P, "medicationDetails": "Amlodipine 5mg daily", "isRecurring": True}
    )
    res = client.delete("/api/v1/settings/account", headers=PATIENT)
    assert res.status_code == 409
    assert res.json()["error"]["details"]["prescriptions"] == ["Amlodipine 5mg daily"]
    ok = client.delete("/api/v1/settings/account?acknowledgeRecurring=true", headers=PATIENT)
    assert ok.status_code == 200


def test_uc12_4_deactivates_signs_out_and_schedules_purge(
    client: TestClient,
    repo: InMemoryUserRepository,
    tokens: InMemoryTokenRepository,
    identity: FakeIdentityProvider,
    audit: InMemoryAuditLogger,
) -> None:
    tokens.add(P, "phone", "android")
    res = client.delete("/api/v1/settings/account", headers=PATIENT)
    assert res.status_code == 200 and res.json()["status"] == "deactivated"
    assert repo.users[P]["isActive"] is False and repo.users[P]["deletionRequestedAt"]
    assert tokens.tokens(P) == [] and identity.revoked == [P]
    assert "REQUEST_ACCOUNT_DELETION" in audit.actions()
    # A deactivated account can't change settings any more.
    again = client.delete("/api/v1/settings/account", headers=PATIENT)
    assert again.status_code == 403


def test_d46_purge_waits_seven_days_then_runs_the_cascade(
    repo: InMemoryUserRepository,
    vitals_repo: InMemoryVitalsRepository,
    provider_repo: InMemoryProviderRepository,
    settings_repo: InMemorySettingsRepository,
) -> None:
    now = datetime(2026, 10, 14, tzinfo=UTC)
    repo.users[P].update({"isActive": False, "deletionRequestedAt": now - timedelta(days=6)})
    rx = {"patientId": P, "medicationDetails": "Amlodipine", "isRecurring": True}
    provider_repo.prescriptions.append(rx)
    provider_repo.notes.append({"patientId": P, "content": "Follow up"})
    identity, audit = FakeIdentityProvider(), InMemoryAuditLogger()
    job = AccountPurgeJob(settings_repo, identity, audit)

    assert job.run(now) == {"accountsPurged": 0}
    assert job.run(now + timedelta(days=1, minutes=1)) == {"accountsPurged": 1}
    assert P not in repo.users and P not in repo.health_profiles
    assert vitals_repo.readings == {}
    assert identity.deleted == [P]
    # Doctor-authored records are kept; the recurring prescription stops renewing.
    assert provider_repo.notes and rx["isRecurring"] is False
    assert audit.actions() == ["DELETE_ACCOUNT"]


def test_d46_reactivated_account_is_not_purged(
    repo: InMemoryUserRepository, settings_repo: InMemorySettingsRepository
) -> None:
    now = datetime(2026, 10, 14, tzinfo=UTC)
    repo.users[P].update({"isActive": True, "deletionRequestedAt": now - timedelta(days=30)})
    job = AccountPurgeJob(settings_repo, FakeIdentityProvider(), InMemoryAuditLogger())
    assert job.run(now) == {"accountsPurged": 0} and P in repo.users
