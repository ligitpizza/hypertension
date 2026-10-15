"""Doctor assignment requests (FR-7.2, UC7.3; D-54)."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from tests.conftest import (
    InMemoryAppointmentRepository,
    InMemoryAssignmentRepository,
    InMemoryAuditLogger,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P = "u-patient"
PATIENT = bearer("patient-token")
DOCTOR = bearer("doctor-token")  # u-doctor
ADMIN = bearer("admin-token")


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users[P] = {"role": "patient", "name": "Siti", "assignedDoctorId": "u-doctor"}
    repo.users["u-doctor"] = {"role": "doctor", "name": "Dr John", "isActive": True}
    repo.users["d2"] = {"role": "doctor", "name": "Dr Aminah", "isActive": True}
    for uid in (P, "u-doctor", "d2"):
        tokens.add(uid, f"token-of-{uid}", "android")


def recipients(push: LogPushClient) -> list[str]:
    return [t[0].removeprefix("token-of-") for t, _ in push.sent]


def test_new_patient_requests_a_doctor_once(
    client: TestClient,
    repo: InMemoryUserRepository,
    assignment_repo: InMemoryAssignmentRepository,
    audit: InMemoryAuditLogger,
) -> None:
    repo.users[P]["assignedDoctorId"] = None
    res = client.post("/api/v1/assignment-requests/new-doctor", headers=PATIENT)
    assert res.status_code == 201
    [req] = assignment_repo.requests.values()
    assert req["kind"] == "new_patient" and req["status"] == "pending" and req["requestedBy"] == P
    again = client.post("/api/v1/assignment-requests/new-doctor", headers=PATIENT)
    assert again.status_code == 409 and again.json()["error"]["code"] == "REQUEST_PENDING"
    assert "REQUEST_DOCTOR" in audit.actions()


def test_a_patient_with_a_doctor_cannot_request_one(client: TestClient) -> None:
    res = client.post("/api/v1/assignment-requests/new-doctor", headers=PATIENT)
    assert res.status_code == 409 and res.json()["error"]["code"] == "HAS_DOCTOR"


def test_doctor_requests_reassignment_of_own_patient_only(
    client: TestClient, repo: InMemoryUserRepository, assignment_repo: InMemoryAssignmentRepository
) -> None:
    url = f"/api/v1/provider/patients/{P}/reassignment-request"
    bad = client.post(url, json={"proposedDoctorId": "u-doctor"}, headers=DOCTOR)
    assert bad.status_code == 422  # can't propose themselves
    res = client.post(url, json={"proposedDoctorId": "d2", "reason": "Moving away"}, headers=DOCTOR)
    assert res.status_code == 201
    [req] = assignment_repo.requests.values()
    assert (req["kind"], req["proposedDoctorId"], req["reason"]) == (
        "reassign",
        "d2",
        "Moving away",
    )
    repo.users["other"] = {"role": "patient", "assignedDoctorId": "d2"}
    res = client.post(
        "/api/v1/provider/patients/other/reassignment-request", json={}, headers=DOCTOR
    )
    assert res.status_code == 404


def test_admin_approves_moves_appointments_and_notifies_everyone(
    client: TestClient,
    repo: InMemoryUserRepository,
    assignment_repo: InMemoryAssignmentRepository,
    appointment_repo: InMemoryAppointmentRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    soon = datetime.now(UTC) + timedelta(days=3)
    appointment_repo.appointments["a1"] = {
        "patientId": P,
        "doctorId": "u-doctor",
        "dateTime": soon,
        "status": "booked",
        "type": "checkup",
    }
    later = soon + timedelta(days=1)
    appointment_repo.appointments["a2"] = {
        "patientId": P,
        "doctorId": "u-doctor",
        "dateTime": later,
        "status": "booked",
        "type": "checkup",
    }
    # The new doctor is already busy at the second time.
    appointment_repo.appointments["b1"] = {
        "patientId": "x",
        "doctorId": "d2",
        "dateTime": later,
        "status": "booked",
        "type": "checkup",
    }
    rid = client.post(
        f"/api/v1/provider/patients/{P}/reassignment-request", json={}, headers=DOCTOR
    ).json()["id"]
    res = client.post(
        f"/api/v1/admin/assignment-requests/{rid}/approve", json={"doctorId": "d2"}, headers=ADMIN
    )
    assert res.status_code == 200
    assert res.json() == {"status": "approved", "appointmentsMoved": 1, "appointmentsCancelled": 1}
    assert repo.users[P]["assignedDoctorId"] == "d2"
    assert appointment_repo.appointments["a1"]["doctorId"] == "d2"
    assert appointment_repo.appointments["a2"]["status"] == "cancelled"
    assert assignment_repo.requests[rid]["status"] == "approved"
    assert sorted(set(recipients(push))) == ["d2", "u-doctor", P]
    assert "ASSIGN_DOCTOR" in audit.actions()
    again = client.post(
        f"/api/v1/admin/assignment-requests/{rid}/approve", json={"doctorId": "d2"}, headers=ADMIN
    )
    assert again.status_code == 409


def test_admin_must_choose_an_active_doctor(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    repo.users[P]["assignedDoctorId"] = None
    rid = client.post("/api/v1/assignment-requests/new-doctor", headers=PATIENT).json()["id"]
    repo.users["d2"]["isActive"] = False
    for doctor in ("d2", P, "nobody"):
        res = client.post(
            f"/api/v1/admin/assignment-requests/{rid}/approve",
            json={"doctorId": doctor},
            headers=ADMIN,
        )
        assert res.status_code == 422


def test_admin_declines_and_the_requester_is_told(
    client: TestClient,
    repo: InMemoryUserRepository,
    assignment_repo: InMemoryAssignmentRepository,
    push: LogPushClient,
) -> None:
    repo.users[P]["assignedDoctorId"] = None
    rid = client.post("/api/v1/assignment-requests/new-doctor", headers=PATIENT).json()["id"]
    res = client.post(
        f"/api/v1/admin/assignment-requests/{rid}/decline",
        json={"reason": "Please visit the clinic first."},
        headers=ADMIN,
    )
    assert res.status_code == 200 and assignment_repo.requests[rid]["status"] == "declined"
    assert recipients(push) == [P] and push.sent[0][1].body == "Please visit the clinic first."


@pytest.mark.parametrize("token", ["patient-token", "doctor-token"])
def test_only_admins_resolve(client: TestClient, token: str) -> None:
    res = client.post(
        "/api/v1/admin/assignment-requests/r1/decline", json={}, headers=bearer(token)
    )
    assert res.status_code == 403


def test_d54_onboarding_puts_a_new_patient_in_the_admin_list(
    client: TestClient, repo: InMemoryUserRepository, assignment_repo: InMemoryAssignmentRepository
) -> None:
    from tests.test_auth_onboarding import VALID

    repo.users[P] = {"role": "patient", "name": "Siti", "onboardingComplete": False}
    res = client.post("/api/v1/auth/onboarding", json=VALID, headers=PATIENT)
    assert res.status_code == 201
    [req] = assignment_repo.requests.values()
    assert (req["patientId"], req["kind"], req["status"]) == (P, "new_patient", "pending")


def test_d54_no_request_when_the_patient_already_has_a_doctor(
    client: TestClient, repo: InMemoryUserRepository, assignment_repo: InMemoryAssignmentRepository
) -> None:
    from tests.test_auth_onboarding import VALID

    repo.users[P] = {"role": "patient", "onboardingComplete": False, "assignedDoctorId": "d2"}
    client.post("/api/v1/auth/onboarding", json=VALID, headers=PATIENT)
    assert assignment_repo.requests == {}
