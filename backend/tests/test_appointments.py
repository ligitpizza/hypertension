"""Module 7 appointments (FR-7.1, FR-7.3, FR-7.4; UC7.1, UC7.2, UC7.4, UC7.5; D-53)."""

from datetime import UTC, date, datetime, time, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from app.services.appointment_extras import (
    AppointmentJob,
    auto_book_emergency,
    build_pre_visit_summary,
)
from app.services.appointments import day_slots, is_bookable, next_free, period
from app.services.medications import MYT
from app.services.notifications import Notifier
from tests.conftest import (
    DeliveringEmailClient,
    InMemoryAppointmentRepository,
    InMemoryAuditLogger,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P = "u-patient"
D = "u-doctor"
PATIENT = bearer("patient-token")


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users[P] = {"role": "patient", "name": "Siti", "email": "s@x.my", "assignedDoctorId": D}
    repo.users[D] = {"role": "doctor", "name": "Dr John", "specialty": "Cardiology"}
    tokens.add(P, "token-of-patient", "android")
    tokens.add(D, "token-of-doctor", "web")


def myt(y: int, m: int, d: int, hh: int, mm: int = 0) -> datetime:
    return datetime(y, m, d, hh, mm, tzinfo=MYT).astimezone(UTC)


def next_weekday(after: date) -> date:
    day = after + timedelta(days=1)
    while day.weekday() > 4:
        day += timedelta(days=1)
    return day


def a_future_slot(hour: int = 10) -> datetime:
    """A real slot on the next working day (always bookable)."""
    today = datetime.now(UTC).astimezone(MYT).date()
    day = next_weekday(today)
    return datetime.combine(day, time(hour, 0), tzinfo=MYT).astimezone(UTC)


# ---------- slot rules ----------


def test_d53_working_day_slots() -> None:
    slots = day_slots(date(2026, 10, 15))  # Thursday
    local = [s.astimezone(MYT).strftime("%H:%M") for s in slots]
    assert local[0] == "09:00" and local[-1] == "20:30"
    assert "13:00" not in local and "13:30" not in local and "14:00" in local  # lunch
    assert len(local) == 22  # 24 half-hours 09:00-21:00 minus lunch
    assert day_slots(date(2026, 10, 17)) == []  # Saturday


def test_d53_bookable_window_and_periods() -> None:
    now = myt(2026, 10, 15, 9, 10)
    assert not is_bookable(myt(2026, 10, 15, 9, 30), now)  # under 1 hour ahead
    assert is_bookable(myt(2026, 10, 15, 10, 30), now)
    assert not is_bookable(myt(2026, 10, 15, 10, 15), now)  # not a slot start
    assert not is_bookable(myt(2026, 12, 31, 10), now)  # beyond 60 days
    assert [period(myt(2026, 10, 15, h)) for h in (9, 14, 19)] == [
        "morning",
        "afternoon",
        "evening",
    ]


def test_uc7_1_e1_nearest_alternatives_skip_taken_slots() -> None:
    now = myt(2026, 10, 15, 19, 10)  # Thursday evening
    taken = {myt(2026, 10, 15, 20, 30)}
    # Thursday 20:30 taken; then Friday from 09:00.
    assert next_free(taken, now) == [
        myt(2026, 10, 16, 9),
        myt(2026, 10, 16, 9, 30),
        myt(2026, 10, 16, 10),
    ]


# ---------- API ----------


def test_slots_list_the_assigned_doctors_day(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    slot = a_future_slot(10)
    appointment_repo.appointments["x"] = {
        "patientId": "someone",
        "doctorId": D,
        "dateTime": slot,
        "status": "booked",
        "type": "checkup",
    }
    day = slot.astimezone(MYT).date().isoformat()
    res = client.get(f"/api/v1/appointments/slots?date={day}", headers=PATIENT)
    assert res.status_code == 200
    body = res.json()
    assert body["doctor"] == {"id": D, "name": "Dr John", "specialty": "Cardiology"}
    by_time = {s["time"]: s for s in body["slots"]}
    assert by_time[slot.isoformat()]["available"] is False
    assert by_time[(slot + timedelta(minutes=30)).isoformat()]["available"] is True


def test_weekend_has_no_slots_and_offers_alternatives(client: TestClient) -> None:
    today = datetime.now(UTC).astimezone(MYT).date()
    saturday = today + timedelta(days=(5 - today.weekday()) % 7 or 7)
    body = client.get(f"/api/v1/appointments/slots?date={saturday}", headers=PATIENT).json()
    assert body["slots"] == [] and len(body["alternatives"]) == 3


def test_uc7_1_book_with_the_assigned_doctor(
    client: TestClient,
    appointment_repo: InMemoryAppointmentRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    slot = a_future_slot(10)
    res = client.post(
        "/api/v1/appointments",
        json={"dateTime": slot.isoformat(), "type": "follow_up"},
        headers=PATIENT,
    )
    assert res.status_code == 201
    [appt] = appointment_repo.appointments.values()
    assert appt["doctorId"] == D and appt["status"] == "booked" and appt["type"] == "follow_up"
    assert [m.title for _, m in push.sent] == ["Appointment booked"]
    assert "BOOK_APPOINTMENT" in audit.actions()


def test_uc7_1_e1_taken_slot_offers_alternatives(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    slot = a_future_slot(10)
    appointment_repo.appointments["x"] = {
        "patientId": "someone",
        "doctorId": D,
        "dateTime": slot,
        "status": "booked",
        "type": "checkup",
    }
    res = client.post("/api/v1/appointments", json={"dateTime": slot.isoformat()}, headers=PATIENT)
    assert res.status_code == 409
    assert len(res.json()["error"]["details"]["alternatives"]) == 3


@pytest.mark.parametrize("bad", ["2020-01-06T02:00:00Z", "2099-01-05T02:00:00Z"])
def test_invalid_times_are_rejected(client: TestClient, bad: str) -> None:
    res = client.post("/api/v1/appointments", json={"dateTime": bad}, headers=PATIENT)
    assert res.status_code == 422


def test_emergency_type_cannot_be_chosen_by_the_patient(client: TestClient) -> None:
    body = {"dateTime": a_future_slot().isoformat(), "type": "emergency"}
    assert client.post("/api/v1/appointments", json=body, headers=PATIENT).status_code == 422


def test_d54_no_doctor_yet(client: TestClient, repo: InMemoryUserRepository) -> None:
    repo.users[P]["assignedDoctorId"] = None
    res = client.post(
        "/api/v1/appointments", json={"dateTime": a_future_slot().isoformat()}, headers=PATIENT
    )
    assert res.status_code == 409 and res.json()["error"]["code"] == "NO_DOCTOR"


def test_uc7_2_reschedule_and_cancel_notify_the_doctor(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository, push: LogPushClient
) -> None:
    slot = a_future_slot(10)
    appt_id = client.post(
        "/api/v1/appointments", json={"dateTime": slot.isoformat()}, headers=PATIENT
    ).json()["id"]
    later = slot + timedelta(hours=1)
    res = client.patch(
        f"/api/v1/appointments/{appt_id}", json={"dateTime": later.isoformat()}, headers=PATIENT
    )
    assert res.status_code == 200 and res.json()["status"] == "rescheduled"
    assert appointment_repo.appointments[appt_id]["dateTime"] == later
    res = client.patch(f"/api/v1/appointments/{appt_id}", json={"cancel": True}, headers=PATIENT)
    assert res.json()["status"] == "cancelled"
    assert [m.title for _, m in push.sent] == [
        "Appointment booked",
        "Appointment rescheduled",
        "Appointment cancelled",
    ]
    # A cancelled appointment can't be changed again.
    again = client.patch(f"/api/v1/appointments/{appt_id}", json={"cancel": True}, headers=PATIENT)
    assert again.status_code == 409


def test_only_the_owner_changes_an_appointment(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    appointment_repo.appointments["x"] = {
        "patientId": "someone",
        "doctorId": D,
        "dateTime": a_future_slot(),
        "status": "booked",
        "type": "checkup",
    }
    res = client.patch("/api/v1/appointments/x", json={"cancel": True}, headers=PATIENT)
    assert res.status_code == 404


# ---------- UC7.5 pre-visit summary ----------


def test_uc7_5_summary_flags_data_gaps() -> None:
    now = datetime(2026, 10, 15, tzinfo=UTC)
    readings = [
        {"systolic": 150, "diastolic": 95, "heartRate": 80, "timestamp": now - timedelta(days=9)},
        {"systolic": 140, "diastolic": 90, "timestamp": now - timedelta(days=10)},
    ]
    meds = [{"name": "Losartan", "dosage": "50mg", "schedule": "08:00", "adherenceRate": 60.0}]
    s = build_pre_visit_summary({"id": "a1"}, readings, None, meds, None, now)
    assert s["vitals"]["averageSystolic"] == 145 and s["vitals"]["highest"] == "150/95"
    assert "No blood pressure reading in the last 7 days." in s["dataGaps"]
    assert "No risk assessment yet (needs three readings)." in s["dataGaps"]
    assert s["openItems"] == ["Low adherence: Losartan 50mg"]
    empty = build_pre_visit_summary({"id": "a1"}, [], None, [], None, now)
    assert "No blood pressure readings in the last 14 days." in empty["dataGaps"]


def test_uc7_5_summary_endpoint_for_patient_and_their_doctor_only(
    client: TestClient, appointment_repo: InMemoryAppointmentRepository
) -> None:
    appointment_repo.appointments["a1"] = {
        "patientId": P,
        "doctorId": D,
        "dateTime": a_future_slot(),
        "status": "booked",
        "type": "checkup",
    }
    for token in ("patient-token", "doctor-token"):
        res = client.get("/api/v1/appointments/a1/pre-visit-summary", headers=bearer(token))
        assert res.status_code == 200 and "dataGaps" in res.json()
    appointment_repo.appointments["a2"] = {
        **appointment_repo.appointments["a1"],
        "doctorId": "other",
    }
    res = client.get("/api/v1/appointments/a2/pre-visit-summary", headers=bearer("doctor-token"))
    assert res.status_code == 404


# ---------- UC7.4 reminders, completion; emergency auto-booking ----------


def job(appointment_repo: InMemoryAppointmentRepository, tokens: InMemoryTokenRepository) -> Any:
    push = LogPushClient()
    email = DeliveringEmailClient()
    return AppointmentJob(appointment_repo, Notifier(tokens, push), email), push, email


def test_uc7_4_reminders_24h_and_1h_once_each(
    appointment_repo: InMemoryAppointmentRepository, tokens: InMemoryTokenRepository
) -> None:
    now = datetime(2026, 10, 15, 2, 0, tzinfo=UTC)
    appointment_repo.appointments["a1"] = {
        "patientId": P,
        "doctorId": D,
        "dateTime": now + timedelta(hours=24, minutes=5),
        "status": "booked",
        "type": "checkup",
    }
    appointment_repo.appointments["a2"] = {
        "patientId": P,
        "doctorId": D,
        "dateTime": now + timedelta(hours=1, minutes=10),
        "status": "cancelled",
        "type": "checkup",
    }
    j, push, email = job(appointment_repo, tokens)
    assert j.run(now)["appointmentReminders"] == 1
    assert push.sent[0][1].title == "Appointment tomorrow"
    assert "Dr John" in push.sent[0][1].body
    assert len(email.sent) == 1 and "reminder" in email.sent[0].text
    # Next sweep (15 min later) does not remind the same appointment again.
    assert j.run(now + timedelta(minutes=15))["appointmentReminders"] == 0


def test_past_appointments_are_completed(
    appointment_repo: InMemoryAppointmentRepository, tokens: InMemoryTokenRepository
) -> None:
    now = datetime(2026, 10, 15, 12, tzinfo=UTC)
    appointment_repo.appointments["a1"] = {
        "patientId": P,
        "doctorId": D,
        "dateTime": now - timedelta(hours=3),
        "status": "booked",
        "type": "checkup",
    }
    j, _, _ = job(appointment_repo, tokens)
    assert j.run(now)["appointmentsCompleted"] == 1
    assert appointment_repo.appointments["a1"]["status"] == "completed"


def test_emergency_auto_booking_once(
    appointment_repo: InMemoryAppointmentRepository, tokens: InMemoryTokenRepository
) -> None:
    now = myt(2026, 10, 15, 19, 10)  # first slot at least 1 h ahead: 20:30
    push = LogPushClient()
    notifier = Notifier(tokens, push)
    first = auto_book_emergency(appointment_repo, notifier, P, D, now)
    assert first is not None
    appt = appointment_repo.appointments[first]
    assert appt["type"] == "emergency" and appt["dateTime"] == myt(2026, 10, 15, 20, 30)
    assert "999" in push.sent[0][1].body and push.sent[0][1].urgent
    assert auto_book_emergency(appointment_repo, notifier, P, D, now) is None  # not twice
    assert auto_book_emergency(appointment_repo, notifier, "x", None, now) is None  # no doctor
