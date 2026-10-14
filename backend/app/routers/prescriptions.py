"""Patient-reported prescriptions (D-50).

POST   /prescriptions/reported        record one from another clinic
PUT    /prescriptions/reported/{id}   edit (own, patient-reported only)
DELETE /prescriptions/reported/{id}

Doctor-issued prescriptions stay doctor-only (Module 8); the two are told apart by `source`.
"""

from typing import Any

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, PrescriptionSource, UserRole
from app.core.errors import ApiError
from app.schemas.provider import ReportedPrescriptionRequest
from app.services.provider import ProviderRepository, get_provider_repository, medication_details

router = APIRouter(prefix="/prescriptions/reported", tags=["prescriptions"])
patient_only = require_roles(UserRole.PATIENT)


def _details(body: ReportedPrescriptionRequest) -> str:
    return medication_details(
        body.medicationName, body.dosage, body.frequency, body.duration, body.clinic
    )


def _own(repo: ProviderRepository, rx_id: str, uid: str) -> dict[str, Any]:
    rx = repo.prescription(rx_id)
    if (
        rx is None
        or rx.get("patientId") != uid
        or rx.get("source") != PrescriptionSource.PATIENT.value
    ):
        raise ApiError(
            "PRESCRIPTION_NOT_FOUND", "Prescription not found.", status.HTTP_404_NOT_FOUND
        )
    return rx


@router.post("", status_code=status.HTTP_201_CREATED)
def add_reported(
    body: ReportedPrescriptionRequest,
    user: CurrentUser = Depends(patient_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    details = _details(body)
    rx_id = repo.add_prescription(
        {
            "patientId": user.uid,
            "doctorId": None,
            "medicationDetails": details,
            "isRecurring": False,
            "source": PrescriptionSource.PATIENT.value,
        }
    )
    audit.log(
        user_id=user.uid,
        action="REPORT_PRESCRIPTION",
        details="Patient recorded a prescription from elsewhere.",
        target_type=Collection.PRESCRIPTIONS.value,
        target_id=rx_id,
    )
    return {"id": rx_id, "medicationDetails": details}


@router.put("/{rx_id}")
def edit_reported(
    rx_id: str,
    body: ReportedPrescriptionRequest,
    user: CurrentUser = Depends(patient_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    _own(repo, rx_id, user.uid)
    details = _details(body)
    repo.update_prescription(rx_id, {"medicationDetails": details})
    audit.log(
        user_id=user.uid,
        action="EDIT_REPORTED_PRESCRIPTION",
        details="Patient edited a recorded prescription.",
        target_type=Collection.PRESCRIPTIONS.value,
        target_id=rx_id,
    )
    return {"id": rx_id, "medicationDetails": details}


@router.delete("/{rx_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_reported(
    rx_id: str,
    user: CurrentUser = Depends(patient_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> None:
    _own(repo, rx_id, user.uid)
    repo.delete_prescription(rx_id)
    audit.log(
        user_id=user.uid,
        action="DELETE_REPORTED_PRESCRIPTION",
        details="Patient deleted a recorded prescription.",
        target_type=Collection.PRESCRIPTIONS.value,
        target_id=rx_id,
    )
