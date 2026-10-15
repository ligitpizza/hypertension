"""D-60: admin books / edits appointments for patients; admin creates and deletes users."""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from tests.conftest import (
    FakeIdentityProvider,
    InMemoryAppointmentRepository,
    InMemoryAuditLogger,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)
from tests.test_appointments import a_future_slot

ADMIN, PATIENT = bearer("admin-token"), bearer("patient-token")
P, D, D2 = "u-patient", "u-doctor", "u-doc2"


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users.update(
        {
            "u-admin": {"role": "admin", "name": "Ada"},
            P: {"role": "patient", "name": "Siti", "assignedDoctorId": D},
            D: {"role": "doctor", "name": "Dr John"},
            D2: {"role": "doctor", "name": "Dr Lim", "specialty": "Nephrology"},
        }
    )
    for uid in (P, D, D2):
        tokens.add(uid, f"token-{uid}", "android")


def soon(minutes: int) -> datetime:
    return (datetime.now(UTC) + timedelta(minutes=minutes)).replace(second=0, microsecond=0)


def book(client: TestClient, when: datetime, doctor: str = D2, **extra: Any) -> Any:
    body = {"patientId": P, "doctorId": doctor, "dateTime": when.isoformat(), **extra}
    return client.post("/api/v1/admin/appointments", json=body, headers=ADMIN)


def test_d60_admin_books_any_doctor_any_minute(
    client: TestClient,
    appointment_repo: InMemoryAppointmentRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
    repo: InMemoryUserRepository,
) -> None:
    when = soon(17)  # not a slot, under an hour ahead: fine for the admin
    res = book(client, when, type="follow_up")
    assert res.status_code == 201
    a = appointment_repo.appointments[res.json()["id"]]
    assert (a["doctorId"], a["bookedBy"], a["type"]) == (D2, "admin", "follow_up")
    assert repo.users[P]["assignedDoctorId"] == D  # assignment unchanged
    titles = [m.title for _, m in push.sent]
    assert "Appointment booked for you" in titles and "Appointment added by admin" in titles
    assert audit.entries[-1]["action"] == "ADMIN_BOOK_APPOINTMENT"


def test_d60_limits_patient_own_plus_emergency_plus_admin(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    # The patient's own booking and an emergency auto-booking.
    own = client.post(
        "/api/v1/appointments", json={"dateTime": a_future_slot(10).isoformat()}, headers=PATIENT
    )
    assert own.status_code == 201
    appointment_repo.appointments["emg"] = {
        "patientId": P,
        "doctorId": D,
        "dateTime": a_future_slot(15),
        "status": "booked",
        "type": "emergency",
    }
    # The admin can still add one...
    assert book(client, soon(120)).status_code == 201
    # ...but only one active admin-assigned visit.
    res = book(client, soon(300))
    assert res.json()["error"]["code"] == "ADMIN_LIMIT"


def test_d60_patient_limit_ignores_admin_and_emergency(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    assert book(client, soon(120)).status_code == 201
    appointment_repo.appointments["emg"] = {
        "patientId": P,
        "doctorId": D,
        "dateTime": a_future_slot(15),
        "status": "booked",
        "type": "emergency",
    }
    res = client.post(
        "/api/v1/appointments", json={"dateTime": a_future_slot(10).isoformat()}, headers=PATIENT
    )
    assert res.status_code == 201


def test_d60_no_double_booking_within_30_minutes(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    when = soon(240)
    appointment_repo.appointments["x"] = {
        "patientId": "other",
        "doctorId": D2,
        "dateTime": when - timedelta(minutes=20),
        "status": "booked",
        "type": "checkup",
    }
    res = book(client, when)
    assert res.status_code == 409 and res.json()["error"]["code"] == "DOCTOR_BUSY"
    assert book(client, when + timedelta(minutes=15)).status_code == 201  # 35 min apart


def test_admin_time_and_people_are_validated(client: TestClient) -> None:
    assert book(client, soon(10) + timedelta(seconds=30)).json()["error"]["code"] == "INVALID_TIME"
    assert book(client, soon(-3 * 24 * 60)).json()["error"]["code"] == "INVALID_TIME"
    assert book(client, soon(60), doctor=P).json()["error"]["code"] == "DOCTOR_NOT_FOUND"
    res = client.post(
        "/api/v1/admin/appointments",
        json={"patientId": D, "doctorId": D2, "dateTime": soon(60).isoformat()},
        headers=ADMIN,
    )
    assert res.json()["error"]["code"] == "PATIENT_NOT_FOUND"


def test_d60_admin_edits_time_doctor_type_instantly(
    client: TestClient,
    appointment_repo: InMemoryAppointmentRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    res = client.post(
        "/api/v1/appointments", json={"dateTime": a_future_slot(10).isoformat()}, headers=PATIENT
    )
    appt_id = res.json()["id"]
    appointment_repo.appointments[appt_id]["pendingChange"] = {"kind": "cancel", "reason": "cost"}
    new_time = soon(500)
    res = client.patch(
        f"/api/v1/admin/appointments/{appt_id}",
        json={"dateTime": new_time.isoformat(), "doctorId": D2, "type": "follow_up"},
        headers=ADMIN,
    )
    assert res.status_code == 200 and res.json()["changed"] is True
    a = appointment_repo.appointments[appt_id]
    assert (a["dateTime"], a["doctorId"], a["type"]) == (new_time, D2, "follow_up")
    assert a["status"] == "rescheduled" and a["pendingChange"] is None
    recipients = [toks[0] for toks, _ in push.sent[-3:]]
    # The patient, the new doctor and the previous doctor are all told.
    assert sorted(recipients) == sorted(f"token-{u}" for u in (P, D, D2))
    assert audit.entries[-1]["action"] == "ADMIN_EDIT_APPOINTMENT"


def test_edit_only_type_and_closed_ones(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    appt_id = book(client, soon(120)).json()["id"]
    res = client.patch(
        f"/api/v1/admin/appointments/{appt_id}", json={"type": "emergency"}, headers=ADMIN
    )
    assert appointment_repo.appointments[appt_id]["type"] == "emergency"
    assert appointment_repo.appointments[appt_id]["status"] == "booked"
    appointment_repo.appointments[appt_id]["status"] = "completed"
    res = client.patch(
        f"/api/v1/admin/appointments/{appt_id}", json={"type": "checkup"}, headers=ADMIN
    )
    assert res.json()["error"]["code"] == "APPOINTMENT_CLOSED"


@pytest.mark.parametrize("token", ["doctor-token", "patient-token"])
def test_admin_only(client: TestClient, token: str) -> None:
    body = {"patientId": P, "doctorId": D2, "dateTime": soon(60).isoformat()}
    assert (
        client.post("/api/v1/admin/appointments", json=body, headers=bearer(token)).status_code
        == 403
    )
    assert client.post("/api/v1/admin/patients", json={}, headers=bearer(token)).status_code in (
        403,
        422,
    )
    assert client.delete("/api/v1/admin/users/u-doc2", headers=bearer(token)).status_code == 403


# ---------- users ----------


def test_d60_admin_creates_a_patient_account(
    client: TestClient,
    repo: InMemoryUserRepository,
    identity: FakeIdentityProvider,
    audit: InMemoryAuditLogger,
) -> None:
    body = {"name": "Mei Ling", "email": "mei@example.com", "icNumber": "900101-14-5677"}
    res = client.post("/api/v1/admin/patients", json=body, headers=ADMIN)
    assert res.status_code == 201
    uid = res.json()["uid"]
    u = repo.users[uid]
    assert u["role"] == "patient" and u["onboardingComplete"] is False
    assert u["icNumber"] == "900101-14-5677" and u["linkCode"]
    assert identity.claims[uid] == "patient"
    assert audit.entries[-1]["action"] == "CREATE_PATIENT_ACCOUNT"
    # The same IC cannot be used twice (D-51), nor the same email.
    again = client.post(
        "/api/v1/admin/patients", json={**body, "email": "x@example.com"}, headers=ADMIN
    )
    assert again.json()["error"]["code"] == "IC_IN_USE"
    dup = client.post(
        "/api/v1/admin/patients",
        json={**body, "email": "taken@example.com", "icNumber": "900101-14-5679"},
        headers=ADMIN,
    )
    assert dup.json()["error"]["code"] == "EMAIL_ALREADY_REGISTERED"


def test_d60_delete_a_patient_permanently(
    client: TestClient,
    repo: InMemoryUserRepository,
    identity: FakeIdentityProvider,
    audit: InMemoryAuditLogger,
) -> None:
    res = client.delete(f"/api/v1/admin/users/{P}", headers=ADMIN)
    assert res.status_code == 204
    assert P not in repo.users and P in identity.deleted
    assert audit.entries[-1]["action"] == "DELETE_USER"


def test_doctor_with_patients_or_visits_cannot_be_deleted(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    res = client.delete(f"/api/v1/admin/users/{D}", headers=ADMIN)
    assert res.json()["error"]["code"] == "DOCTOR_IN_USE"  # Siti is assigned
    book(client, soon(120))  # Dr Lim now has an upcoming visit
    res = client.delete(f"/api/v1/admin/users/{D2}", headers=ADMIN)
    assert res.json()["error"]["code"] == "DOCTOR_IN_USE"


def test_not_yourself_and_not_the_last_admin(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    res = client.delete("/api/v1/admin/users/u-admin", headers=ADMIN)
    assert res.json()["error"]["code"] == "CANNOT_DELETE_SELF"
    repo.users["u-admin2"] = {"role": "admin", "name": "Ben", "isActive": False}
    assert client.delete("/api/v1/admin/users/u-admin2", headers=ADMIN).status_code == 204
