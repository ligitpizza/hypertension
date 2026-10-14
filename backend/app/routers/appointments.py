"""Module 7 appointments API (FR-7.1, FR-7.3, FR-7.4; UC7.1, UC7.2, UC7.5; D-53).

GET   /appointments/slots?date=YYYY-MM-DD    the patient's own doctor's slots that day
POST  /appointments                          book (checkup / follow-up)
PATCH /appointments/{id}                     reschedule (dateTime) or cancel
GET   /appointments/{id}/pre-visit-summary   patient or their doctor (UC7.5)
"""

from datetime import UTC, date, datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, Query, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import AppointmentStatus, Collection, UserRole
from app.core.errors import ApiError
from app.integrations.push import PushMessage
from app.schemas.appointments import BookRequest, ChangeRequest
from app.services.agent_context import AgentDataRepository, get_agent_data_repository
from app.services.appointment_extras import build_pre_visit_summary, when_text
from app.services.appointments import (
    ACTIVE,
    LATE_CHANGE,
    MAX_AHEAD,
    SUMMARY_DAYS,
    AppointmentDoc,
    AppointmentRepository,
    SlotTakenError,
    day_slots,
    free_slots,
    get_appointment_repository,
    is_bookable,
    next_free,
    period,
)
from app.services.medications import MYT
from app.services.notifications import Notifier, get_notifier

router = APIRouter(prefix="/appointments", tags=["appointments"])
patient_only = require_roles(UserRole.PATIENT)


def _doctor_of(repo: AppointmentRepository, uid: str) -> tuple[str, dict[str, Any]]:
    """D-53: appointments are always with the patient's assigned doctor."""
    me = repo.user(uid) or {}
    doctor_id = str(me.get("assignedDoctorId") or "").strip()
    if not doctor_id:
        raise ApiError(
            "NO_DOCTOR",
            "You don't have a doctor yet. Request one and the clinic will assign them.",
            status.HTTP_409_CONFLICT,
        )
    return doctor_id, repo.user(doctor_id) or {}


def _iso(moments: list[datetime]) -> list[str]:
    return [m.isoformat() for m in moments]


@router.get("/slots")
def slots(
    day: date = Query(alias="date"),
    user: CurrentUser = Depends(patient_only),
    repo: AppointmentRepository = Depends(get_appointment_repository),
) -> dict[str, Any]:
    now = datetime.now(UTC)
    doctor_id, doctor = _doctor_of(repo, user.uid)
    all_slots = day_slots(day)
    start = datetime.combine(day, datetime.min.time(), tzinfo=MYT)
    taken = repo.taken(doctor_id, start, start + timedelta(days=1))
    free = set(free_slots(day, taken, now))
    out: dict[str, Any] = {
        "doctor": {
            "id": doctor_id,
            "name": doctor.get("name"),
            "specialty": doctor.get("specialty"),
        },
        "date": day.isoformat(),
        "slots": [
            {"time": s.isoformat(), "period": period(s), "available": s in free} for s in all_slots
        ],
    }
    if not free:
        # UC7.1 E1: offer the nearest alternatives.
        out["alternatives"] = _iso(
            next_free(repo.taken(doctor_id, now, now + MAX_AHEAD), max(now, start))
        )
    return out


def _notify_doctor(notifier: Notifier, a: dict[str, Any], patient: str, what: str) -> None:
    if a.get("doctorId"):
        notifier.notify(
            str(a["doctorId"]),
            PushMessage(
                f"Appointment {what}",
                f"{patient}: {when_text(a['dateTime'])}.",
                {"type": "appointment", "patientId": str(a.get("patientId"))},
            ),
        )


@router.post("", status_code=status.HTTP_201_CREATED)
def book(
    body: BookRequest,
    user: CurrentUser = Depends(patient_only),
    repo: AppointmentRepository = Depends(get_appointment_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    now = datetime.now(UTC)
    doctor_id, doctor = _doctor_of(repo, user.uid)
    moment = body.dateTime.astimezone(UTC)
    if not is_bookable(moment, now):
        raise ApiError(
            "INVALID_SLOT",
            "Please choose one of the available times.",
            status.HTTP_422_UNPROCESSABLE_CONTENT,
        )
    data = {
        "patientId": user.uid,
        "doctorId": doctor_id,
        "dateTime": moment,
        "status": AppointmentStatus.BOOKED.value,
        "type": body.type,
    }
    try:
        appt_id = repo.book(data)
    except SlotTakenError as exc:
        alternatives = next_free(repo.taken(doctor_id, now, now + MAX_AHEAD), now)
        raise ApiError(
            "SLOT_TAKEN",
            "That time was just taken. Please choose another.",
            status.HTTP_409_CONFLICT,
            details={"alternatives": _iso(alternatives)},
        ) from exc
    me = repo.user(user.uid) or {}
    _notify_doctor(notifier, data, str(me.get("name") or "A patient"), "booked")
    audit.log(
        user_id=user.uid,
        action="BOOK_APPOINTMENT",
        details=f"{body.type} appointment booked.",
        target_type=Collection.APPOINTMENTS.value,
        target_id=appt_id,
    )
    return {
        "id": appt_id,
        "dateTime": moment.isoformat(),
        "status": data["status"],
        "type": body.type,
        "doctor": {
            "id": doctor_id,
            "name": doctor.get("name"),
            "specialty": doctor.get("specialty"),
        },
    }


def _own(repo: AppointmentRepository, appointment_id: str, uid: str) -> AppointmentDoc:
    appt = repo.get(appointment_id)
    if appt is None or appt.data.get("patientId") != uid:
        raise ApiError("APPOINTMENT_NOT_FOUND", "Appointment not found.", status.HTTP_404_NOT_FOUND)
    return appt


@router.patch("/{appointment_id}")
def change(
    appointment_id: str,
    body: ChangeRequest,
    user: CurrentUser = Depends(patient_only),
    repo: AppointmentRepository = Depends(get_appointment_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """UC7.2. The < 24 h warning (E1) is shown by the app before calling this."""
    now = datetime.now(UTC)
    appt = _own(repo, appointment_id, user.uid)
    if appt.data.get("status") not in ACTIVE or appt.data["dateTime"] <= now:
        raise ApiError(
            "APPOINTMENT_CLOSED",
            "This appointment can no longer be changed.",
            status.HTTP_409_CONFLICT,
        )
    me = repo.user(user.uid) or {}
    name = str(me.get("name") or "A patient")
    if body.cancel:
        repo.update(appointment_id, {"status": AppointmentStatus.CANCELLED.value})
        _notify_doctor(notifier, appt.data, name, "cancelled")
        action, result = "CANCEL_APPOINTMENT", AppointmentStatus.CANCELLED.value
        moment = appt.data["dateTime"]
    else:
        if body.dateTime is None:
            raise ApiError(
                "NOTHING_TO_CHANGE",
                "Choose a new time or cancel.",
                status.HTTP_422_UNPROCESSABLE_CONTENT,
            )
        moment = body.dateTime.astimezone(UTC)
        if not is_bookable(moment, now):
            raise ApiError(
                "INVALID_SLOT",
                "Please choose one of the available times.",
                status.HTTP_422_UNPROCESSABLE_CONTENT,
            )
        moved = {**appt.data, "dateTime": moment, "status": AppointmentStatus.RESCHEDULED.value}
        try:
            repo.book(moved, exclude_id=appointment_id)
        except SlotTakenError as exc:
            raise ApiError(
                "SLOT_TAKEN",
                "That time was just taken. Please choose another.",
                status.HTTP_409_CONFLICT,
            ) from exc
        _notify_doctor(notifier, moved, name, "rescheduled")
        action, result = "RESCHEDULE_APPOINTMENT", AppointmentStatus.RESCHEDULED.value
    audit.log(
        user_id=user.uid,
        action=action,
        details=f"Appointment {result}"
        f"{' within 24 hours' if appt.data['dateTime'] - now < LATE_CHANGE else ''}.",
        target_type=Collection.APPOINTMENTS.value,
        target_id=appointment_id,
    )
    return {"id": appointment_id, "status": result, "dateTime": moment.isoformat()}


@router.get("/{appointment_id}/pre-visit-summary")
def pre_visit_summary(
    appointment_id: str,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT, UserRole.DOCTOR)),
    repo: AppointmentRepository = Depends(get_appointment_repository),
    data: AgentDataRepository = Depends(get_agent_data_repository),
) -> dict[str, Any]:
    appt = repo.get(appointment_id)
    allowed = appt is not None and (
        appt.data.get("patientId") == user.uid
        or (user.role is UserRole.DOCTOR and appt.data.get("doctorId") == user.uid)
    )
    if appt is None or not allowed:
        raise ApiError("APPOINTMENT_NOT_FOUND", "Appointment not found.", status.HTTP_404_NOT_FOUND)
    now = datetime.now(UTC)
    patient_id = str(appt.data["patientId"])
    summary = build_pre_visit_summary(
        {**appt.data, "id": appt.id},
        data.readings_since(patient_id, now - timedelta(days=SUMMARY_DAYS)),
        data.latest_risk(patient_id),
        data.medications(patient_id),
        data.care_plan(patient_id),
        now,
    )
    return summary
