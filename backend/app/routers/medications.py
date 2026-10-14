"""Module 5 medication API (FR-5.1, FR-5.3, FR-5.4; UC5.1, UC5.2, UC5.5, UC5.6; D-43).

POST   /medications               add (duplicate + interaction warnings first)
PUT    /medications/{id}          edit (same checks, excluding itself)
DELETE /medications/{id}
POST   /medications/{id}/doses    confirm a dose: taken dose_log, stock, adherence, refill push
"""

from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, DoseStatus, UserRole
from app.core.errors import ApiError
from app.integrations.push import PushMessage
from app.schemas.medications import DoseRequest, MedicationRequest
from app.services.interactions import check
from app.services.medications import (
    DEFAULT_REFILL_DAYS,
    MYT,
    MedicationDoc,
    MedicationRepository,
    ScheduleError,
    below_threshold,
    dose_id,
    format_schedule,
    get_medication_repository,
    parse_schedule,
    refresh_adherence,
)
from app.services.notifications import Notifier, get_notifier

router = APIRouter(prefix="/medications", tags=["medications"])
EARLY_CONFIRM = timedelta(hours=1)
LATE_CONFIRM = timedelta(hours=26)
patient_only = require_roles(UserRole.PATIENT)


def _owned(repo: MedicationRepository, medication_id: str, uid: str) -> MedicationDoc:
    med = repo.get(medication_id)
    if med is None or med.data.get("patientId") != uid:
        raise ApiError("MEDICATION_NOT_FOUND", "Medication not found.", status.HTTP_404_NOT_FOUND)
    return med


def _validated(body: MedicationRequest) -> dict[str, Any]:
    try:
        times = parse_schedule(body.schedule)
    except ScheduleError as exc:
        raise ApiError("INVALID_SCHEDULE", str(exc), status.HTTP_422_UNPROCESSABLE_CONTENT) from exc
    data: dict[str, Any] = {
        "name": body.name,
        "dosage": body.dosage,
        "schedule": format_schedule(times),
        "refillThresholdDays": body.refillThresholdDays or DEFAULT_REFILL_DAYS,
    }
    if body.quantityOnHand is not None:
        data["quantityOnHand"] = body.quantityOnHand
    return data


def _warnings(
    body: MedicationRequest, others: list[MedicationDoc], times_text: str
) -> dict[str, Any] | None:
    """UC5.1 E1 duplicate / conflicting schedule, UC5.6 interactions."""
    name = body.name.strip().lower()
    duplicates = [
        f"{m.data.get('name')} {m.data.get('dosage', '')}".strip()
        for m in others
        if str(m.data.get("name", "")).strip().lower() == name
    ]
    interactions = check(
        body.name, [f"{m.data.get('name')} {m.data.get('dosage', '')}" for m in others]
    )
    if not duplicates and not interactions:
        return None
    return {
        "duplicates": duplicates,
        "interactions": [i.to_dict() for i in interactions],
        "schedule": times_text,
    }


def _check_or_raise(
    body: MedicationRequest, others: list[MedicationDoc], data: dict[str, Any]
) -> list[dict[str, str]]:
    found = _warnings(body, others, data["schedule"])
    if found and not body.acknowledgeWarnings:
        raise ApiError(
            "MEDICATION_WARNINGS",
            "Please review these warnings before saving.",
            status.HTTP_409_CONFLICT,
            details=found,
        )
    return found["interactions"] if found else []


@router.post("", status_code=status.HTTP_201_CREATED)
def add_medication(
    body: MedicationRequest,
    user: CurrentUser = Depends(patient_only),
    repo: MedicationRepository = Depends(get_medication_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    data = _validated(body)
    interactions = _check_or_raise(body, repo.list_for(user.uid), data)
    med_id = repo.create({**data, "patientId": user.uid, "adherenceRate": None})
    audit.log(
        user_id=user.uid,
        action="ADD_MEDICATION",
        details=f"Medication added{'; interaction warning acknowledged' if interactions else ''}.",
        target_type=Collection.MEDICATIONS.value,
        target_id=med_id,
    )
    return {"id": med_id, **data}


@router.put("/{medication_id}")
def edit_medication(
    medication_id: str,
    body: MedicationRequest,
    user: CurrentUser = Depends(patient_only),
    repo: MedicationRepository = Depends(get_medication_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    _owned(repo, medication_id, user.uid)
    data = _validated(body)
    others = [m for m in repo.list_for(user.uid) if m.id != medication_id]
    _check_or_raise(body, others, data)
    repo.update(medication_id, data)
    audit.log(
        user_id=user.uid,
        action="EDIT_MEDICATION",
        details="Medication edited.",
        target_type=Collection.MEDICATIONS.value,
        target_id=medication_id,
    )
    return {"id": medication_id, **data}


@router.delete("/{medication_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_medication(
    medication_id: str,
    user: CurrentUser = Depends(patient_only),
    repo: MedicationRepository = Depends(get_medication_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> None:
    _owned(repo, medication_id, user.uid)
    repo.delete(medication_id)
    audit.log(
        user_id=user.uid,
        action="DELETE_MEDICATION",
        details="Medication deleted.",
        target_type=Collection.MEDICATIONS.value,
        target_id=medication_id,
    )


@router.post("/{medication_id}/doses", status_code=status.HTTP_201_CREATED)
def confirm_dose(
    medication_id: str,
    body: DoseRequest,
    user: CurrentUser = Depends(patient_only),
    repo: MedicationRepository = Depends(get_medication_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """UC5.3 step 3: the patient confirms a dose (scheduled slot, or now for as-needed)."""
    med = _owned(repo, medication_id, user.uid)
    now = datetime.now(UTC)
    times = parse_schedule(str(med.data.get("schedule", "as_needed")))
    if body.scheduledTime is not None:
        slot = body.scheduledTime.astimezone(UTC)
        local = slot.astimezone(MYT).time().replace(second=0, microsecond=0)
        valid = times is not None and local in times
        # A dose may be confirmed up to an hour early, and late until the next day.
        if not valid or slot > now + EARLY_CONFIRM or slot < now - LATE_CONFIRM:
            raise ApiError(
                "INVALID_DOSE_TIME",
                "That is not one of your recent dose times.",
                status.HTTP_422_UNPROCESSABLE_CONTENT,
            )
    else:
        slot = now  # as-needed / extra dose
    created = repo.log_dose(
        dose_id(medication_id, slot),
        {
            "medicationId": medication_id,
            "scheduledTime": slot,
            "status": DoseStatus.TAKEN.value,
            "confirmedAt": now,
        },
    )
    if not created:
        raise ApiError(
            "DOSE_ALREADY_LOGGED", "This dose is already recorded.", status.HTTP_409_CONFLICT
        )

    quantity = med.data.get("quantityOnHand")
    threshold = float(med.data.get("refillThresholdDays") or DEFAULT_REFILL_DAYS)
    update: dict[str, Any] = {}
    if isinstance(quantity, int | float):
        new_quantity = max(float(quantity) - 1, 0)
        update["quantityOnHand"] = new_quantity
        # UC5.2: push once, when the supply crosses below the threshold.
        if below_threshold(new_quantity, times, threshold) and not below_threshold(
            float(quantity), times, threshold
        ):
            notifier.notify(
                user.uid,
                PushMessage(
                    f"Refill needed: {med.data.get('name')}",
                    f"About {int(new_quantity)} doses left. "
                    "Ask your doctor or pharmacy for a refill.",
                    {"type": "refill", "medicationId": medication_id},
                ),
            )
    if update:
        repo.update(medication_id, update)
    rate = refresh_adherence(repo, medication_id, now) if times is not None else None
    audit.log(
        user_id=user.uid,
        action="CONFIRM_DOSE",
        details="Dose confirmed as taken.",
        target_type=Collection.DOSE_LOGS.value,
        target_id=dose_id(medication_id, slot),
    )
    return {
        "medicationId": medication_id,
        "scheduledTime": slot.isoformat(),
        "adherenceRate": rate,
        "quantityOnHand": update.get("quantityOnHand", quantity),
    }
