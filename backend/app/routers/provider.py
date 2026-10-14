"""Module 8 doctor actions (FR-8.3; UC8.4, UC8.5; docs/05 endpoints).

POST /provider/patients/{id}/notes          clinical note (Fig 4.3.12.5)
PUT  /provider/patients/{id}/care-plan      the patient's single living care plan
POST /provider/patients/{id}/prescriptions  with drug interaction warning (UC8.4 E1)
GET  /provider/patients/{id}/medication-effect  risk before vs after medication (D-44)

Only the patient's assigned doctor may write (FR-8.1, NFR-2.2); every write is audited.
"""

from typing import Any

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.ml.risk_model import RiskModel, get_risk_model
from app.schemas.provider import CarePlanRequest, NoteRequest, PrescriptionRequest
from app.services.interactions import check
from app.services.medication_effect import medication_effect
from app.services.provider import (
    ProviderRepository,
    get_provider_repository,
    medication_details,
)
from app.services.risk import RiskDataRepository, get_risk_data_repository

router = APIRouter(prefix="/provider/patients", tags=["provider"])


def _assigned_patient(
    patient_id: str, doctor: CurrentUser, repo: ProviderRepository
) -> dict[str, Any]:
    patient = repo.patient(patient_id)
    if patient is None or patient.get("role") != UserRole.PATIENT.value:
        raise ApiError("PATIENT_NOT_FOUND", "Patient not found.", status.HTTP_404_NOT_FOUND)
    if patient.get("assignedDoctorId") != doctor.uid:
        raise ApiError(
            "NOT_ASSIGNED", "This patient is not assigned to you.", status.HTTP_403_FORBIDDEN
        )
    return patient


doctor_only = require_roles(UserRole.DOCTOR)


@router.post("/{patient_id}/notes", status_code=status.HTTP_201_CREATED)
def add_note(
    patient_id: str,
    body: NoteRequest,
    doctor: CurrentUser = Depends(doctor_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, str]:
    _assigned_patient(patient_id, doctor, repo)
    note_id = repo.add_note(
        {"patientId": patient_id, "doctorId": doctor.uid, "content": body.content}
    )
    audit.log(
        user_id=doctor.uid,
        action="ADD_CLINICAL_NOTE",
        details="Clinical note added.",
        target_type=Collection.CLINICAL_NOTES.value,
        target_id=note_id,
    )
    return {"id": note_id}


@router.put("/{patient_id}/care-plan")
def update_care_plan(
    patient_id: str,
    body: CarePlanRequest,
    doctor: CurrentUser = Depends(doctor_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, str]:
    _assigned_patient(patient_id, doctor, repo)
    repo.set_care_plan(
        patient_id, {"patientId": patient_id, "doctorId": doctor.uid, "content": body.content}
    )
    audit.log(
        user_id=doctor.uid,
        action="UPDATE_CARE_PLAN",
        details="Care plan updated.",
        target_type=Collection.CARE_PLANS.value,
        target_id=patient_id,
    )
    return {"id": patient_id}


@router.post("/{patient_id}/prescriptions", status_code=status.HTTP_201_CREATED)
def issue_prescription(
    patient_id: str,
    body: PrescriptionRequest,
    doctor: CurrentUser = Depends(doctor_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    _assigned_patient(patient_id, doctor, repo)
    interactions = check(body.medicationName, repo.current_medicines(patient_id))
    if interactions and not body.acknowledgeInteractions:
        raise ApiError(
            "DRUG_INTERACTION",
            "This medicine interacts with the patient's current medication.",
            status.HTTP_409_CONFLICT,
            details=[i.to_dict() for i in interactions],
        )
    details = medication_details(body.medicationName, body.dosage, body.frequency, body.duration)
    rx_id = repo.add_prescription(
        {
            "patientId": patient_id,
            "doctorId": doctor.uid,
            "medicationDetails": details,
            "isRecurring": body.isRecurring,
        }
    )
    audit.log(
        user_id=doctor.uid,
        action="ISSUE_PRESCRIPTION",
        details=f"Prescription issued{' (recurring)' if body.isRecurring else ''}"
        f"{f'; {len(interactions)} interaction warning(s) acknowledged' if interactions else ''}.",
        target_type=Collection.PRESCRIPTIONS.value,
        target_id=rx_id,
    )
    return {
        "id": rx_id,
        "medicationDetails": details,
        "interactions": [i.to_dict() for i in interactions],
    }


@router.get("/{patient_id}/medication-effect")
def get_medication_effect(
    patient_id: str,
    doctor: CurrentUser = Depends(doctor_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    risk_repo: RiskDataRepository = Depends(get_risk_data_repository),
    model: RiskModel | None = Depends(get_risk_model),
) -> dict[str, Any]:
    """D-44: the model's estimate of what the BP change since the first medicine means for
    each complication, with all other inputs (including the medication flag) held fixed."""
    _assigned_patient(patient_id, doctor, repo)
    return medication_effect(patient_id, risk_repo, model)
