"""Module 7 appointments API (FR-7.1, FR-7.3, FR-7.4; UC7.1, UC7.2, UC7.5; D-53).

GET   /appointments/slots?date=YYYY-MM-DD    the patient's own doctor's slots that day
POST  /appointments                          book (checkup / follow-up)
PATCH /appointments/{id}                     reschedule (dateTime) or cancel
POST  /appointments/{id}/outcome             doctor or admin: completed | no_show (D-56)
GET   /appointments/{id}/pre-visit-summary   patient, their doctor or admin (UC7.5)
"""

from datetime import UTC, date, datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, Query, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import AppointmentStatus, Collection, UserRole
from app.core.errors import ApiError
from app.integrations.push import PushMessage
from app.schemas.appointments import (
    BookRequest,
    ChangeRequest,
    DecisionRequest,
    OutcomeRequest,
    StaffCancelRequest,
)
from app.services.agent_context import AgentDataRepository, get_agent_data_repository
from app.services.appointment_extras import build_pre_visit_summary, when_text
from app.services.appointments import (
    ACTIVE,
    CHANGE_CUTOFF,
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
    reason_text,
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
    active = repo.active_for_patient(user.uid)
    if active:
        # D-56: one active appointment at a time (the emergency auto-booking is exempt).
        current = min(active, key=lambda d: d.data["dateTime"])
        raise ApiError(
            "ACTIVE_APPOINTMENT",
            f"You already have an appointment on {when_text(current.data['dateTime'])}. "
            "You can book another once it is over, or reschedule it instead.",
            status.HTTP_409_CONFLICT,
            details={
                "appointmentId": current.id,
                "dateTime": current.data["dateTime"].astimezone(UTC).isoformat(),
            },
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
        details=f"{body.type} appointment booked for {when_text(moment)} (MYT).",
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


def _patient_name(repo: AppointmentRepository, uid: str) -> str:
    return str((repo.user(uid) or {}).get("name") or "A patient")


def _push(notifier: Notifier, uid: str | None, title: str, body: str, appt_id: str) -> None:
    if uid:
        notifier.notify(
            uid, PushMessage(title, body, {"type": "appointment", "appointmentId": appt_id})
        )


def _apply_cancel(repo: AppointmentRepository, appt_id: str, reason: str, by: str) -> None:
    repo.update(
        appt_id,
        {
            "status": AppointmentStatus.CANCELLED.value,
            "cancelledBy": by,
            "changeReason": reason,
            "pendingChange": None,
        },
    )


@router.patch("/{appointment_id}")
def change(
    appointment_id: str,
    body: ChangeRequest,
    user: CurrentUser = Depends(patient_only),
    repo: AppointmentRepository = Depends(get_appointment_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """UC7.2 / D-55: the patient asks; the doctor decides (or it lapses 2 h before)."""
    now = datetime.now(UTC)
    appt = _own(repo, appointment_id, user.uid)
    a = appt.data
    if a.get("status") not in ACTIVE or a["dateTime"] <= now:
        raise ApiError(
            "APPOINTMENT_CLOSED",
            "This appointment can no longer be changed.",
            status.HTTP_409_CONFLICT,
        )
    name = _patient_name(repo, user.uid)
    when = when_text(a["dateTime"])
    pending = a.get("pendingChange")

    if body.withdraw:
        if not pending:
            raise ApiError(
                "NO_REQUEST", "There is no request to withdraw.", status.HTTP_409_CONFLICT
            )
        repo.update(appointment_id, {"pendingChange": None})
        _push(
            notifier,
            a.get("doctorId"),
            "Request withdrawn",
            f"{name}: {when} stays as booked.",
            appointment_id,
        )
        audit.log(
            user_id=user.uid,
            action="WITHDRAW_APPOINTMENT_REQUEST",
            details=f"Withdrew the {pending.get('kind')} request for {when} (MYT).",
            target_type=Collection.APPOINTMENTS.value,
            target_id=appointment_id,
        )
        return {"id": appointment_id, "status": a["status"], "pendingChange": None}

    if pending:
        raise ApiError(
            "CHANGE_PENDING",
            "You already asked to change this appointment. Wait for your doctor or withdraw it.",
            status.HTTP_409_CONFLICT,
        )
    if body.reason is None:
        raise ApiError(
            "REASON_REQUIRED", "Please choose a reason.", status.HTTP_422_UNPROCESSABLE_CONTENT
        )
    if body.reason == "other" and not body.note:
        raise ApiError(
            "REASON_REQUIRED", "Please tell us the reason.", status.HTTP_422_UNPROCESSABLE_CONTENT
        )
    reason = reason_text(body.reason, body.note)
    soon = a["dateTime"] - now <= CHANGE_CUTOFF

    if body.cancel:
        if soon:
            # Too close for the doctor to decide: a patient who can't come is cancelled.
            _apply_cancel(repo, appointment_id, reason, "patient")
            _push(
                notifier,
                a.get("doctorId"),
                "Appointment cancelled",
                f"{name}: {when}. Reason: {reason}",
                appointment_id,
            )
            audit.log(
                user_id=user.uid,
                action="CANCEL_APPOINTMENT",
                details=f"Cancelled {when} (MYT) within 2 hours. Reason: {reason}",
                target_type=Collection.APPOINTMENTS.value,
                target_id=appointment_id,
            )
            return {"id": appointment_id, "status": AppointmentStatus.CANCELLED.value}
        request: dict[str, Any] = {
            "kind": "cancel",
            "reason": body.reason,
            "note": body.note,
            "requestedAt": now,
        }
        repo.update(appointment_id, {"pendingChange": request})
        _push(
            notifier,
            a.get("doctorId"),
            "Cancellation requested",
            f"{name}: {when}. Reason: {reason}",
            appointment_id,
        )
        action, details = (
            "REQUEST_CANCEL_APPOINTMENT",
            f"Asked to cancel {when} (MYT). Reason: {reason}",
        )
    else:
        if body.dateTime is None:
            raise ApiError(
                "NOTHING_TO_CHANGE",
                "Choose a new time or cancel.",
                status.HTTP_422_UNPROCESSABLE_CONTENT,
            )
        if soon:
            raise ApiError(
                "TOO_LATE",
                "It's less than 2 hours before your appointment, so it can't be moved. "
                "You can cancel instead.",
                status.HTTP_409_CONFLICT,
            )
        moment = body.dateTime.astimezone(UTC)
        if not is_bookable(moment, now):
            raise ApiError(
                "INVALID_SLOT",
                "Please choose one of the available times.",
                status.HTTP_422_UNPROCESSABLE_CONTENT,
            )
        request = {
            "kind": "reschedule",
            "dateTime": moment,
            "reason": body.reason,
            "note": body.note,
            "requestedAt": now,
        }
        try:
            repo.request_reschedule(appointment_id, str(a["doctorId"]), request)
        except SlotTakenError as exc:
            raise ApiError(
                "SLOT_TAKEN",
                "That time was just taken. Please choose another.",
                status.HTTP_409_CONFLICT,
            ) from exc
        _push(
            notifier,
            a.get("doctorId"),
            "Reschedule requested",
            f"{name}: {when} -> {when_text(moment)}. Reason: {reason}",
            appointment_id,
        )
        action = "REQUEST_RESCHEDULE_APPOINTMENT"
        details = f"Asked to move {when} -> {when_text(moment)} (MYT). Reason: {reason}"
    audit.log(
        user_id=user.uid,
        action=action,
        details=details + (" (within 24 hours)" if a["dateTime"] - now < LATE_CHANGE else ""),
        target_type=Collection.APPOINTMENTS.value,
        target_id=appointment_id,
    )
    return {"id": appointment_id, "status": a["status"], "pendingChange": request["kind"]}


def _staff_appointment(
    repo: AppointmentRepository, appointment_id: str, user: CurrentUser
) -> AppointmentDoc:
    """The appointment's own doctor, or any admin (D-55)."""
    appt = repo.get(appointment_id)
    if appt is None or (user.role is UserRole.DOCTOR and appt.data.get("doctorId") != user.uid):
        raise ApiError("APPOINTMENT_NOT_FOUND", "Appointment not found.", status.HTTP_404_NOT_FOUND)
    return appt


@router.post("/{appointment_id}/decision")
def decide(
    appointment_id: str,
    body: DecisionRequest,
    user: CurrentUser = Depends(require_roles(UserRole.DOCTOR, UserRole.ADMIN)),
    repo: AppointmentRepository = Depends(get_appointment_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """D-55: approve or decline the patient's pending cancel/reschedule."""
    appt = _staff_appointment(repo, appointment_id, user)
    a = appt.data
    pending = a.get("pendingChange")
    if not isinstance(pending, dict) or a.get("status") not in ACTIVE:
        raise ApiError("NO_REQUEST", "There is no request to decide.", status.HTTP_409_CONFLICT)
    kind = str(pending.get("kind"))
    reason = reason_text(str(pending.get("reason")), pending.get("note"))
    when = when_text(a["dateTime"])
    patient_id = str(a["patientId"])
    note = f" {body.note}" if body.note else ""
    if not body.approve:
        repo.update(appointment_id, {"pendingChange": None})
        _push(
            notifier,
            patient_id,
            "Request declined",
            f"Your appointment on {when} stays as booked.{note}",
            appointment_id,
        )
        result = "declined"
    elif kind == "cancel":
        _apply_cancel(repo, appointment_id, reason, "patient")
        _push(
            notifier,
            patient_id,
            "Cancellation approved",
            f"Your appointment on {when} is cancelled.{note}",
            appointment_id,
        )
        result = "cancelled"
    else:
        moment: datetime = pending["dateTime"]
        try:
            repo.book(
                {
                    **a,
                    "dateTime": moment,
                    "status": AppointmentStatus.RESCHEDULED.value,
                    "changeReason": reason,
                    "pendingChange": None,
                },
                exclude_id=appointment_id,
            )
        except SlotTakenError as exc:
            raise ApiError(
                "SLOT_TAKEN", "That time is no longer free.", status.HTTP_409_CONFLICT
            ) from exc
        _push(
            notifier,
            patient_id,
            "Reschedule approved",
            f"Your appointment moved to {when_text(moment)}.{note}",
            appointment_id,
        )
        result = "rescheduled"
    if user.role is UserRole.ADMIN and a.get("doctorId"):
        _push(
            notifier,
            str(a["doctorId"]),
            f"Admin {result} a {kind} request",
            f"{_patient_name(repo, patient_id)}: {when}.",
            appointment_id,
        )
    audit.log(
        user_id=user.uid,
        action="DECIDE_APPOINTMENT_REQUEST",
        details=f"{kind} request for {when} (MYT) {result}. Reason given: {reason}.{note}",
        target_type=Collection.APPOINTMENTS.value,
        target_id=appointment_id,
    )
    return {"id": appointment_id, "result": result}


@router.post("/{appointment_id}/staff-cancel")
def staff_cancel(
    appointment_id: str,
    body: StaffCancelRequest,
    user: CurrentUser = Depends(require_roles(UserRole.DOCTOR, UserRole.ADMIN)),
    repo: AppointmentRepository = Depends(get_appointment_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """D-55: the doctor or the admin cancels, with a reason; both sides are told."""
    appt = _staff_appointment(repo, appointment_id, user)
    a = appt.data
    if a.get("status") not in ACTIVE:
        raise ApiError(
            "APPOINTMENT_CLOSED", "This appointment is not active.", status.HTTP_409_CONFLICT
        )
    by = "admin" if user.role is UserRole.ADMIN else "doctor"
    _apply_cancel(repo, appointment_id, body.reason, by)
    when = when_text(a["dateTime"])
    _push(
        notifier,
        str(a["patientId"]),
        "Appointment cancelled",
        f"Your appointment on {when} was cancelled by the clinic: {body.reason} "
        "Please book a new time.",
        appointment_id,
    )
    if by == "admin":
        _push(
            notifier,
            a.get("doctorId"),
            "Appointment cancelled by admin",
            f"{_patient_name(repo, str(a['patientId']))}: {when}. {body.reason}",
            appointment_id,
        )
    audit.log(
        user_id=user.uid,
        action="STAFF_CANCEL_APPOINTMENT",
        details=f"{by} cancelled {when} (MYT): {body.reason}",
        target_type=Collection.APPOINTMENTS.value,
        target_id=appointment_id,
    )
    return {"id": appointment_id, "status": AppointmentStatus.CANCELLED.value}


@router.post("/{appointment_id}/outcome")
def record_outcome(
    appointment_id: str,
    body: OutcomeRequest,
    user: CurrentUser = Depends(require_roles(UserRole.DOCTOR, UserRole.ADMIN)),
    repo: AppointmentRepository = Depends(get_appointment_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """D-56: from its start time, the doctor (or admin) marks the visit Completed or
    No-show. Either ends it, so the patient can book again."""
    appt = _staff_appointment(repo, appointment_id, user)
    a = appt.data
    if a.get("status") not in ACTIVE:
        raise ApiError(
            "APPOINTMENT_CLOSED", "This appointment is not active.", status.HTTP_409_CONFLICT
        )
    if datetime.now(UTC) < a["dateTime"]:
        raise ApiError(
            "NOT_STARTED",
            "You can record the outcome once the appointment has started.",
            status.HTTP_409_CONFLICT,
        )
    new_status = (
        AppointmentStatus.COMPLETED if body.outcome == "completed" else AppointmentStatus.NO_SHOW
    )
    repo.update(
        appointment_id,
        {"status": new_status.value, "pendingChange": None, "updatedAt": datetime.now(UTC)},
    )
    label = "completed" if new_status is AppointmentStatus.COMPLETED else "no-show"
    audit.log(
        user_id=user.uid,
        action=(
            "COMPLETE_APPOINTMENT"
            if new_status is AppointmentStatus.COMPLETED
            else "NO_SHOW_APPOINTMENT"
        ),
        details=f"Appointment {when_text(a['dateTime'])} (MYT) marked {label}"
        + (f": {body.note}" if body.note else "."),
        target_type=Collection.APPOINTMENTS.value,
        target_id=appointment_id,
    )
    return {"id": appointment_id, "status": new_status.value}


@router.get("/{appointment_id}/pre-visit-summary")
def pre_visit_summary(
    appointment_id: str,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT, UserRole.DOCTOR, UserRole.ADMIN)),
    repo: AppointmentRepository = Depends(get_appointment_repository),
    data: AgentDataRepository = Depends(get_agent_data_repository),
) -> dict[str, Any]:
    appt = repo.get(appointment_id)
    # D-55: the admin opens appointments from the overview, so it sees the summary too.
    allowed = appt is not None and (
        user.role is UserRole.ADMIN
        or appt.data.get("patientId") == user.uid
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
