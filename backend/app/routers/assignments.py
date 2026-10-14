"""Doctor assignment requests API (FR-7.2, UC7.3; D-54).

POST /assignment-requests/new-doctor                     patient without a doctor asks for one
POST /provider/patients/{id}/reassignment-request        the patient's doctor asks to hand over
POST /admin/assignment-requests/{id}/approve             admin chooses the doctor
POST /admin/assignment-requests/{id}/decline             admin declines
"""

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import (
    AppointmentStatus,
    AssignmentRequestKind,
    AssignmentRequestStatus,
    Collection,
    UserRole,
)
from app.core.errors import ApiError
from app.integrations.push import PushMessage
from app.schemas.assignments import ApproveRequest, DeclineRequest, ReassignRequest
from app.services.appointment_extras import when_text
from app.services.appointments import (
    AppointmentRepository,
    SlotTakenError,
    get_appointment_repository,
)
from app.services.assignments import AssignmentRepository, get_assignment_repository
from app.services.notifications import Notifier, get_notifier

router = APIRouter(tags=["assignments"])


def _no_duplicate(repo: AssignmentRepository, patient_id: str) -> None:
    if repo.has_pending(patient_id):
        raise ApiError(
            "REQUEST_PENDING",
            "A doctor request for this patient is already waiting for the admin.",
            status.HTTP_409_CONFLICT,
        )


@router.post("/assignment-requests/new-doctor", status_code=status.HTTP_201_CREATED)
def request_doctor(
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    repo: AssignmentRepository = Depends(get_assignment_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    me = repo.user(user.uid) or {}
    if str(me.get("assignedDoctorId") or "").strip():
        raise ApiError("HAS_DOCTOR", "You already have a doctor.", status.HTTP_409_CONFLICT)
    _no_duplicate(repo, user.uid)
    request_id = repo.create(
        {
            "patientId": user.uid,
            "requestedBy": user.uid,
            "kind": AssignmentRequestKind.NEW_PATIENT.value,
            "status": AssignmentRequestStatus.PENDING.value,
        }
    )
    audit.log(
        user_id=user.uid,
        action="REQUEST_DOCTOR",
        details="Patient asked to be assigned a doctor.",
        target_type=Collection.DOCTOR_ASSIGNMENT_REQUESTS.value,
        target_id=request_id,
    )
    return {"id": request_id, "status": AssignmentRequestStatus.PENDING.value}


@router.post(
    "/provider/patients/{patient_id}/reassignment-request", status_code=status.HTTP_201_CREATED
)
def request_reassignment(
    patient_id: str,
    body: ReassignRequest,
    doctor: CurrentUser = Depends(require_roles(UserRole.DOCTOR)),
    repo: AssignmentRepository = Depends(get_assignment_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    patient = repo.user(patient_id)
    if patient is None or patient.get("assignedDoctorId") != doctor.uid:
        raise ApiError("PATIENT_NOT_FOUND", "Patient not found.", status.HTTP_404_NOT_FOUND)
    if body.proposedDoctorId:
        proposed = repo.user(body.proposedDoctorId) or {}
        if proposed.get("role") != UserRole.DOCTOR.value or body.proposedDoctorId == doctor.uid:
            raise ApiError(
                "INVALID_DOCTOR", "Choose another doctor.", status.HTTP_422_UNPROCESSABLE_CONTENT
            )
    _no_duplicate(repo, patient_id)
    request_id = repo.create(
        {
            "patientId": patient_id,
            "requestedBy": doctor.uid,
            "kind": AssignmentRequestKind.REASSIGN.value,
            "proposedDoctorId": body.proposedDoctorId,
            "reason": body.reason,
            "status": AssignmentRequestStatus.PENDING.value,
        }
    )
    audit.log(
        user_id=doctor.uid,
        action="REQUEST_REASSIGNMENT",
        details="Doctor asked for a patient to be reassigned.",
        target_type=Collection.DOCTOR_ASSIGNMENT_REQUESTS.value,
        target_id=request_id,
    )
    return {"id": request_id, "status": AssignmentRequestStatus.PENDING.value}


def _pending(repo: AssignmentRepository, request_id: str) -> dict[str, Any]:
    req = repo.request(request_id)
    if req is None:
        raise ApiError("REQUEST_NOT_FOUND", "Request not found.", status.HTTP_404_NOT_FOUND)
    if req.get("status") != AssignmentRequestStatus.PENDING.value:
        raise ApiError(
            "REQUEST_CLOSED", "This request was already handled.", status.HTTP_409_CONFLICT
        )
    return req


@router.post("/admin/assignment-requests/{request_id}/approve")
def approve(
    request_id: str,
    body: ApproveRequest,
    admin: CurrentUser = Depends(require_roles(UserRole.ADMIN)),
    repo: AssignmentRepository = Depends(get_assignment_repository),
    appointments: AppointmentRepository = Depends(get_appointment_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    req = _pending(repo, request_id)
    doctor = repo.user(body.doctorId) or {}
    if doctor.get("role") != UserRole.DOCTOR.value or doctor.get("isActive") is False:
        raise ApiError(
            "INVALID_DOCTOR", "Choose an active doctor.", status.HTTP_422_UNPROCESSABLE_CONTENT
        )
    patient_id = str(req["patientId"])
    patient = repo.user(patient_id) or {}
    old_doctor = str(patient.get("assignedDoctorId") or "") or None
    if old_doctor == body.doctorId:
        raise ApiError(
            "SAME_DOCTOR",
            "The patient already has this doctor.",
            status.HTTP_422_UNPROCESSABLE_CONTENT,
        )
    repo.set_doctor(patient_id, body.doctorId)

    # Future appointments follow the patient to the new doctor; a clash is cancelled.
    moved = cancelled = 0
    for a in appointments.upcoming_for_patient(patient_id, datetime.now(UTC)):
        try:
            appointments.book({**a.data, "doctorId": body.doctorId}, exclude_id=a.id)
            moved += 1
        except SlotTakenError:
            appointments.update(a.id, {"status": AppointmentStatus.CANCELLED.value})
            cancelled += 1
            notifier.notify(
                patient_id,
                PushMessage(
                    "Please rebook your appointment",
                    f"Your appointment on {when_text(a.data['dateTime'])} was cancelled "
                    f"because {doctor.get('name')} is not free then.",
                    {"type": "appointment", "appointmentId": a.id},
                ),
            )
    repo.resolve(
        request_id,
        {
            "status": AssignmentRequestStatus.APPROVED.value,
            "resolvedBy": admin.uid,
            "assignedDoctorId": body.doctorId,
        },
    )
    name = str(doctor.get("name") or "your new doctor")
    notifier.notify(
        patient_id,
        PushMessage(
            "Your doctor",
            f"{name} is now your doctor. You can message them and book appointments.",
            {"type": "assignment"},
        ),
    )
    notifier.notify(
        body.doctorId,
        PushMessage(
            "New patient",
            f"{patient.get('name') or 'A patient'} has been assigned to you.",
            {"type": "assignment", "patientId": patient_id},
        ),
    )
    if old_doctor:
        notifier.notify(
            old_doctor,
            PushMessage(
                "Patient reassigned",
                f"{patient.get('name') or 'A patient'} is now cared for by {name}.",
                {"type": "assignment", "patientId": patient_id},
            ),
        )
    audit.log(
        user_id=admin.uid,
        action="ASSIGN_DOCTOR",
        details=f"Doctor assigned ({req.get('kind')}); {moved} appointment(s) moved, "
        f"{cancelled} cancelled.",
        target_type=Collection.USERS.value,
        target_id=patient_id,
    )
    return {"status": "approved", "appointmentsMoved": moved, "appointmentsCancelled": cancelled}


@router.post("/admin/assignment-requests/{request_id}/decline")
def decline(
    request_id: str,
    body: DeclineRequest,
    admin: CurrentUser = Depends(require_roles(UserRole.ADMIN)),
    repo: AssignmentRepository = Depends(get_assignment_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, str]:
    req = _pending(repo, request_id)
    repo.resolve(
        request_id,
        {
            "status": AssignmentRequestStatus.DECLINED.value,
            "resolvedBy": admin.uid,
            "reason": body.reason or req.get("reason"),
        },
    )
    notifier.notify(
        str(req["requestedBy"]),
        PushMessage(
            "Doctor request declined",
            body.reason or "The clinic could not make this change. Please contact them.",
            {"type": "assignment"},
        ),
    )
    audit.log(
        user_id=admin.uid,
        action="DECLINE_ASSIGNMENT",
        details="Doctor assignment request declined.",
        target_type=Collection.DOCTOR_ASSIGNMENT_REQUESTS.value,
        target_id=request_id,
    )
    return {"status": "declined"}
