"""FR-14.2 family monitoring and emergency alerts (UC15.1-UC15.3; D-06, D-62).

POST   /family/link-requests                 family: request a link with the patient's code
DELETE /family/link-requests/{id}            family: withdraw a pending request
POST   /family/link-requests/{id}/approve    patient: approve (sets users.patientId)
POST   /family/link-requests/{id}/reject     patient: reject
DELETE /family/link                          family: stop following the patient
DELETE /family/members/{uid}                 patient: remove a linked family member
POST   /emergency/sos                        patient: SOS -> family alerts with GPS, doctor push
PUT    /emergency/location                   patient: refresh the location of open alerts
POST   /emergency/alerts/{id}/acknowledge    family: "I've seen it"; the patient is told

Reads (requests, alerts, the linked patient's vitals) are Firestore reads under the rules.
"""

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, FamilyLinkStatus, UserRole
from app.core.errors import ApiError
from app.integrations.push import PushMessage
from app.schemas.family import LinkRequest, LocationUpdate, SosRequest
from app.services.family import (
    EmergencyAlerts,
    FamilyRepository,
    get_emergency_alerts,
    get_family_repository,
    normalise_code,
)
from app.services.notifications import Notifier, get_notifier

router = APIRouter(tags=["family"])
family_only = require_roles(UserRole.FAMILY_MEMBER)
patient_only = require_roles(UserRole.PATIENT)


def _name(repo: FamilyRepository, uid: str, fallback: str) -> str:
    return str((repo.user(uid) or {}).get("name") or fallback)


def _request(repo: FamilyRepository, request_id: str) -> dict[str, Any]:
    r = repo.get_request(request_id)
    if r is None:
        raise ApiError("REQUEST_NOT_FOUND", "Request not found.", status.HTTP_404_NOT_FOUND)
    return r


def _pending_only(r: dict[str, Any]) -> None:
    if r.get("status") != FamilyLinkStatus.PENDING.value:
        raise ApiError(
            "REQUEST_CLOSED", "This request was already answered.", status.HTTP_409_CONFLICT
        )


# ---------------- linking (UC15.1, D-06) ----------------


@router.post("/family/link-requests", status_code=status.HTTP_201_CREATED)
def request_link(
    body: LinkRequest,
    user: CurrentUser = Depends(family_only),
    repo: FamilyRepository = Depends(get_family_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    me = repo.user(user.uid) or {}
    if me.get("patientId"):
        raise ApiError(
            "ALREADY_LINKED",
            "You already follow a patient. Unlink first to follow someone else.",
            status.HTTP_409_CONFLICT,
        )
    if repo.pending_for_member(user.uid):
        raise ApiError(
            "REQUEST_PENDING",
            "You already have a request waiting for approval.",
            status.HTTP_409_CONFLICT,
        )
    patient_id = repo.patient_by_code(normalise_code(body.code))
    if patient_id is None:
        raise ApiError(
            "INVALID_CODE",
            "No patient has this link code. Check it with your family member.",
            status.HTTP_404_NOT_FOUND,
        )
    request_id = repo.create_request(
        {
            "familyMemberId": user.uid,
            # D-62: shown to the patient, who cannot read an unlinked user's document.
            "familyMemberName": str(me.get("name") or "A family member"),
            "patientId": patient_id,
            "status": FamilyLinkStatus.PENDING.value,
        }
    )
    name = str(me.get("name") or "A family member")
    notifier.notify(
        patient_id,
        PushMessage(
            "Family link request",
            f"{name} would like to follow your health. Open CareFlow to approve or reject.",
            {"type": "family_request", "requestId": request_id},
        ),
    )
    audit.log(
        user_id=user.uid,
        action="REQUEST_FAMILY_LINK",
        details="Family member asked to follow a patient.",
        target_type=Collection.FAMILY_LINK_REQUESTS.value,
        target_id=request_id,
    )
    return {"id": request_id, "status": FamilyLinkStatus.PENDING.value}


@router.delete("/family/link-requests/{request_id}", status_code=status.HTTP_204_NO_CONTENT)
def withdraw_link_request(
    request_id: str,
    user: CurrentUser = Depends(family_only),
    repo: FamilyRepository = Depends(get_family_repository),
) -> None:
    r = _request(repo, request_id)
    if r.get("familyMemberId") != user.uid:
        raise ApiError("REQUEST_NOT_FOUND", "Request not found.", status.HTTP_404_NOT_FOUND)
    _pending_only(r)
    repo.update_request(request_id, {"status": FamilyLinkStatus.REJECTED.value})


def _decide(
    request_id: str,
    approve: bool,
    user: CurrentUser,
    repo: FamilyRepository,
    notifier: Notifier,
    audit: AuditLogger,
) -> dict[str, Any]:
    r = _request(repo, request_id)
    if r.get("patientId") != user.uid:
        raise ApiError("REQUEST_NOT_FOUND", "Request not found.", status.HTTP_404_NOT_FOUND)
    _pending_only(r)
    member = str(r["familyMemberId"])
    new_status = FamilyLinkStatus.APPROVED if approve else FamilyLinkStatus.REJECTED
    if approve and (repo.user(member) or {}).get("patientId"):
        raise ApiError(
            "ALREADY_LINKED", "This person already follows someone else.", status.HTTP_409_CONFLICT
        )
    repo.update_request(request_id, {"status": new_status.value, "decidedAt": datetime.now(UTC)})
    if approve:
        repo.update_user(member, {"patientId": user.uid})
    patient = _name(repo, user.uid, "The patient")
    notifier.notify(
        member,
        PushMessage(
            "Link approved" if approve else "Link request declined",
            f"You can now follow {patient}'s health in CareFlow."
            if approve
            else f"{patient} declined your request to follow their health.",
            {"type": "family_link", "status": new_status.value},
        ),
    )
    audit.log(
        user_id=user.uid,
        action="APPROVE_FAMILY_LINK" if approve else "REJECT_FAMILY_LINK",
        details=f"Patient {'approved' if approve else 'rejected'} a family link request.",
        target_type=Collection.FAMILY_LINK_REQUESTS.value,
        target_id=request_id,
    )
    return {"id": request_id, "status": new_status.value}


@router.post("/family/link-requests/{request_id}/approve")
def approve_link(
    request_id: str,
    user: CurrentUser = Depends(patient_only),
    repo: FamilyRepository = Depends(get_family_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    return _decide(request_id, True, user, repo, notifier, audit)


@router.post("/family/link-requests/{request_id}/reject")
def reject_link(
    request_id: str,
    user: CurrentUser = Depends(patient_only),
    repo: FamilyRepository = Depends(get_family_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    return _decide(request_id, False, user, repo, notifier, audit)


@router.delete("/family/link", status_code=status.HTTP_204_NO_CONTENT)
def unlink_self(
    user: CurrentUser = Depends(family_only),
    repo: FamilyRepository = Depends(get_family_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> None:
    patient_id = (repo.user(user.uid) or {}).get("patientId")
    if not patient_id:
        raise ApiError("NOT_LINKED", "You don't follow anyone.", status.HTTP_409_CONFLICT)
    repo.update_user(user.uid, {"patientId": None})
    notifier.notify(
        str(patient_id),
        PushMessage(
            "Family member unlinked",
            f"{_name(repo, user.uid, 'A family member')} no longer follows your health.",
            {"type": "family_link", "status": "unlinked"},
        ),
    )
    audit.log(
        user_id=user.uid,
        action="UNLINK_FAMILY",
        details="Family member stopped following the patient.",
        target_type=Collection.USERS.value,
        target_id=str(patient_id),
    )


@router.delete("/family/members/{member_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(
    member_id: str,
    user: CurrentUser = Depends(patient_only),
    repo: FamilyRepository = Depends(get_family_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> None:
    member = repo.user(member_id) or {}
    if member.get("patientId") != user.uid:
        raise ApiError("MEMBER_NOT_FOUND", "Family member not found.", status.HTTP_404_NOT_FOUND)
    repo.update_user(member_id, {"patientId": None})
    notifier.notify(
        member_id,
        PushMessage(
            "Link removed",
            f"{_name(repo, user.uid, 'The patient')} removed your access to their health data.",
            {"type": "family_link", "status": "removed"},
        ),
    )
    audit.log(
        user_id=user.uid,
        action="REMOVE_FAMILY_MEMBER",
        details="Patient removed a linked family member.",
        target_type=Collection.USERS.value,
        target_id=member_id,
    )


# ---------------- emergencies (UC15.2, UC15.3, SOS Fig 4.3.9.1) ----------------


@router.post("/emergency/sos")
def sos(
    body: SosRequest,
    user: CurrentUser = Depends(patient_only),
    repo: FamilyRepository = Depends(get_family_repository),
    emergency: EmergencyAlerts = Depends(get_emergency_alerts),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    me = repo.user(user.uid) or {}
    name = str(me.get("name") or "Your patient")
    created: list[str] = []
    if body.notifyFamily:
        created = emergency.raise_alerts(
            user.uid,
            "sos",
            body.location.as_dict() if body.location else None,
            datetime.now(UTC),
        )
    doctor = me.get("assignedDoctorId")
    if doctor:
        notifier.notify(
            str(doctor),
            PushMessage(
                "Patient SOS",
                f"{name} pressed the SOS button in CareFlow.",
                {"type": "sos", "patientId": user.uid},
                urgent=True,
            ),
        )
    audit.log(
        user_id=user.uid,
        action="SOS",
        details=f"SOS pressed; {len(created)} family member(s) alerted"
        f"{'' if body.notifyFamily else ' (family notification off)'}.",
    )
    return {"familyAlerted": len(created), "doctorNotified": bool(doctor)}


@router.put("/emergency/location")
def update_location(
    body: LocationUpdate,
    user: CurrentUser = Depends(patient_only),
    emergency: EmergencyAlerts = Depends(get_emergency_alerts),
) -> dict[str, Any]:
    return {
        "updated": emergency.update_location(user.uid, body.location.as_dict(), datetime.now(UTC))
    }


@router.get("/emergency/open")
def open_alerts(
    user: CurrentUser = Depends(patient_only),
    emergency: EmergencyAlerts = Depends(get_emergency_alerts),
) -> dict[str, Any]:
    """The patient app asks this when opened: refresh the location only if an alert is open."""
    return {"open": emergency.open_since(user.uid, datetime.now(UTC))}


@router.post("/emergency/alerts/{alert_id}/acknowledge")
def acknowledge(
    alert_id: str,
    user: CurrentUser = Depends(family_only),
    repo: FamilyRepository = Depends(get_family_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    alert = repo.get_alert(alert_id)
    if alert is None or alert.get("familyMemberId") != user.uid:
        raise ApiError("ALERT_NOT_FOUND", "Alert not found.", status.HTTP_404_NOT_FOUND)
    if alert.get("acknowledgedAt") is None:
        now = datetime.now(UTC)
        repo.update_alert(alert_id, {"acknowledgedAt": now})
        notifier.notify(
            str(alert["patientId"]),
            PushMessage(
                "Your family saw your alert",
                f"{_name(repo, user.uid, 'A family member')} has seen your emergency alert.",
                {"type": "emergency_ack", "alertId": alert_id},
            ),
        )
        audit.log(
            user_id=user.uid,
            action="ACKNOWLEDGE_EMERGENCY",
            details="Family member acknowledged an emergency alert.",
            target_type=Collection.EMERGENCY_ALERTS.value,
            target_id=alert_id,
        )
    return {"id": alert_id, "acknowledged": True}
