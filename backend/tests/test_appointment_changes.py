"""D-55: patient changes need the doctor's approval, with reasons; admin oversight."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from app.services.appointment_extras import AppointmentJob
from app.services.notifications import Notifier
from tests.conftest import (
    DeliveringEmailClient,
    InMemoryAppointmentRepository,
    InMemoryAuditLogger,
    InMemoryTokenRepository,
    bearer,
)
from tests.test_appointments import PATIENT, D, P, a_future_slot
from tests.test_appointments import people as people

DOCTOR = bearer("doctor-token")
ADMIN = bearer("admin-token")


def book_one(client: TestClient, hour: int = 10) -> tuple[str, datetime]:
    slot = a_future_slot(hour)
    res = client.post("/api/v1/appointments", json={"dateTime": slot.isoformat()}, headers=PATIENT)
    return str(res.json()["id"]), slot


def url(appt_id: str, tail: str = "") -> str:
    return f"/api/v1/appointments/{appt_id}{tail}"


def test_a_reason_is_required(client: TestClient) -> None:
    appt_id, _ = book_one(client)
    assert client.patch(url(appt_id), json={"cancel": True}, headers=PATIENT).status_code == 422
    other = client.patch(url(appt_id), json={"cancel": True, "reason": "other"}, headers=PATIENT)
    assert other.status_code == 422  # "Other" needs a note


def test_cancel_is_requested_then_approved_by_the_doctor(
    client: TestClient,
    appointment_repo: InMemoryAppointmentRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    appt_id, _ = book_one(client)
    body = {"cancel": True, "reason": "schedule_conflict", "note": "Work trip"}
    res = client.patch(url(appt_id), json=body, headers=PATIENT)
    assert res.status_code == 200 and res.json()["pendingChange"] == "cancel"
    a = appointment_repo.appointments[appt_id]
    assert a["status"] == "booked" and a["pendingChange"]["reason"] == "schedule_conflict"
    assert push.sent[-1][1].title == "Cancellation requested"
    assert "Schedule conflict: Work trip" in push.sent[-1][1].body
    again = client.patch(url(appt_id), json={"cancel": True, "reason": "cost"}, headers=PATIENT)
    assert again.status_code == 409  # one request at a time
    res = client.post(url(appt_id, "/decision"), json={"approve": True}, headers=DOCTOR)
    assert res.json()["result"] == "cancelled"
    assert (a["status"], a["cancelledBy"], a["pendingChange"]) == ("cancelled", "patient", None)
    assert a["changeReason"] == "Schedule conflict: Work trip"
    assert push.sent[-1][1].title == "Cancellation approved"
    assert {"REQUEST_CANCEL_APPOINTMENT", "DECIDE_APPOINTMENT_REQUEST"} <= set(audit.actions())


def test_reschedule_holds_the_new_time_until_decided(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    appt_id, slot = book_one(client)
    new_time = slot + timedelta(hours=1)
    body = {"dateTime": new_time.isoformat(), "reason": "transport"}
    assert client.patch(url(appt_id), json=body, headers=PATIENT).status_code == 200
    a = appointment_repo.appointments[appt_id]
    assert a["dateTime"] == slot  # original kept while pending
    assert new_time in appointment_repo.taken(D, slot, slot + timedelta(days=1))
    other = client.post(
        "/api/v1/appointments", json={"dateTime": new_time.isoformat()}, headers=PATIENT
    )
    assert other.status_code == 409  # held for this patient
    client.post(url(appt_id, "/decision"), json={"approve": True}, headers=DOCTOR)
    a = appointment_repo.appointments[appt_id]  # moved: re-read
    assert (a["dateTime"], a["status"], a["pendingChange"]) == (new_time, "rescheduled", None)
    assert a["changeReason"] == "Transport problem"


def test_declined_request_keeps_the_original(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository, push: LogPushClient
) -> None:
    appt_id, _ = book_one(client)
    client.patch(url(appt_id), json={"cancel": True, "reason": "feeling_better"}, headers=PATIENT)
    client.post(
        url(appt_id, "/decision"),
        json={"approve": False, "note": "Your BP is still high, please come."},
        headers=DOCTOR,
    )
    a = appointment_repo.appointments[appt_id]
    assert a["status"] == "booked" and a["pendingChange"] is None
    assert "please come" in push.sent[-1][1].body


def test_patient_can_withdraw(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    appt_id, _ = book_one(client)
    client.patch(url(appt_id), json={"cancel": True, "reason": "cost"}, headers=PATIENT)
    assert client.patch(url(appt_id), json={"withdraw": True}, headers=PATIENT).status_code == 200
    assert appointment_repo.appointments[appt_id]["pendingChange"] is None
    assert client.patch(url(appt_id), json={"withdraw": True}, headers=PATIENT).status_code == 409


def test_within_two_hours_cancel_applies_and_reschedule_is_refused(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    soon = datetime.now(UTC) + timedelta(minutes=90)
    appointment_repo.appointments["a1"] = {
        "patientId": P,
        "doctorId": D,
        "dateTime": soon,
        "status": "booked",
        "type": "checkup",
    }
    move = {"dateTime": a_future_slot().isoformat(), "reason": "transport"}
    res = client.patch(url("a1"), json=move, headers=PATIENT)
    assert res.status_code == 409 and res.json()["error"]["code"] == "TOO_LATE"
    res = client.patch(url("a1"), json={"cancel": True, "reason": "transport"}, headers=PATIENT)
    assert res.json()["status"] == "cancelled"


def test_only_the_appointments_doctor_or_admin_decides(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    appt_id, _ = book_one(client)
    client.patch(url(appt_id), json={"cancel": True, "reason": "cost"}, headers=PATIENT)
    appointment_repo.appointments[appt_id]["doctorId"] = "someone-else"
    decide = {"approve": True}
    assert client.post(url(appt_id, "/decision"), json=decide, headers=DOCTOR).status_code == 404
    assert client.post(url(appt_id, "/decision"), json=decide, headers=PATIENT).status_code == 403
    assert client.post(url(appt_id, "/decision"), json=decide, headers=ADMIN).status_code == 200


def test_admin_cancels_with_a_reason(
    client: TestClient,
    appointment_repo: InMemoryAppointmentRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    appt_id, _ = book_one(client)
    res = client.post(
        url(appt_id, "/staff-cancel"), json={"reason": "Doctor on emergency leave"}, headers=ADMIN
    )
    assert res.status_code == 200
    a = appointment_repo.appointments[appt_id]
    assert (a["status"], a["cancelledBy"], a["changeReason"]) == (
        "cancelled",
        "admin",
        "Doctor on emergency leave",
    )
    titles = [m.title for _, m in push.sent]
    assert "Appointment cancelled" in titles and "Appointment cancelled by admin" in titles
    assert "STAFF_CANCEL_APPOINTMENT" in audit.actions()
    short = client.post(url(appt_id, "/staff-cancel"), json={"reason": "x"}, headers=ADMIN)
    assert short.status_code == 422


@pytest.mark.parametrize("kind", ["cancel", "reschedule"])
def test_requests_lapse_two_hours_before(
    appointment_repo: InMemoryAppointmentRepository, tokens: InMemoryTokenRepository, kind: str
) -> None:
    now = datetime(2026, 10, 15, 2, tzinfo=UTC)
    pending: dict[str, object] = {"kind": kind, "reason": "cost", "note": None}
    if kind == "reschedule":
        pending["dateTime"] = now + timedelta(days=2)
    appointment_repo.appointments["a"] = {
        "patientId": P,
        "doctorId": D,
        "dateTime": now + timedelta(minutes=100),
        "status": "booked",
        "type": "checkup",
        "pendingChange": pending,
    }
    push = LogPushClient()
    j = AppointmentJob(appointment_repo, Notifier(tokens, push), DeliveringEmailClient())
    assert j.run(now)["appointmentRequestsLapsed"] == 1
    a = appointment_repo.appointments["a"]
    assert a["pendingChange"] is None
    if kind == "cancel":
        assert a["status"] == "cancelled" and a["cancelledBy"] == "system"
        assert push.sent[0][1].title == "Appointment cancelled"
    else:
        assert a["status"] == "booked" and push.sent[0][1].title == "Appointment unchanged"


def test_audit_entries_say_which_time(client: TestClient, audit: InMemoryAuditLogger) -> None:
    appt_id, _ = book_one(client)
    client.patch(url(appt_id), json={"cancel": True, "reason": "cost"}, headers=PATIENT)
    book, request = [e for e in audit.entries if "APPOINTMENT" in e["action"]]
    assert "10:00 AM" in book["details"] and book["targetId"] == appt_id
    assert request["action"] == "REQUEST_CANCEL_APPOINTMENT" and "Cost" in request["details"]
