"""Module 8 doctor actions (FR-8.3; UC8.4, UC8.5; docs/05 endpoints).

POST /provider/patients/{id}/notes          clinical note (Fig 4.3.12.5)
PUT  /provider/patients/{id}/care-plan      the patient's single living care plan
POST /provider/patients/{id}/prescriptions  with drug interaction warning (UC8.4 E1)
DELETE /provider/patients/{id}/prescriptions/{rxId}  the issuing doctor only (D-50)
GET  /provider/patients/{id}/medication-effect  risk before vs after medication (D-44)

Only the patient's assigned doctor may write (FR-8.1, NFR-2.2); every write is audited.
"""

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, PrescriptionSource, UserRole
from app.core.errors import ApiError
from app.ml.risk_model import RiskModel, get_risk_model
from app.schemas.provider import CarePlanRequest, NoteRequest, PrescriptionRequest
from app.services.catalog import (
    FREQUENCIES,
    CatalogRepository,
    get_catalog_repository,
    item_label,
    items_summary,
    items_total,
)
from app.services.interactions import check
from app.services.medication_effect import medication_effect
from app.services.medications import (
    DEFAULT_REFILL_DAYS,
    DOCTOR_SOURCE,
    MedicationRepository,
    get_medication_repository,
)
from app.services.orders import OrderService, get_order_service
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


def _catalog_items(body: PrescriptionRequest, catalog: CatalogRepository) -> list[dict[str, Any]]:
    """D-69: each requested item filled in from the catalogue (name, strength, price)."""
    items = []
    for req in body.items or []:
        c = catalog.get(req.catalogId)
        if c is None or c.get("active", True) is False:
            raise ApiError(
                "CATALOG_ITEM_NOT_FOUND",
                "A selected medicine is not in the catalogue.",
                status.HTTP_404_NOT_FOUND,
            )
        items.append(
            {
                "catalogId": req.catalogId,
                "name": c.get("name"),
                "strength": c.get("strength"),
                "form": c.get("form"),
                "dose": req.dose,
                "frequency": req.frequency,
                "quantity": req.quantity,
                "unitPrice": float(c.get("unitPrice") or 0),
            }
        )
    return items


@router.post("/{patient_id}/prescriptions", status_code=status.HTTP_201_CREATED)
def issue_prescription(
    patient_id: str,
    body: PrescriptionRequest,
    doctor: CurrentUser = Depends(doctor_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    audit: AuditLogger = Depends(get_audit_logger),
    orders: OrderService = Depends(get_order_service),
    catalog: CatalogRepository = Depends(get_catalog_repository),
    meds: MedicationRepository = Depends(get_medication_repository),
) -> dict[str, Any]:
    _assigned_patient(patient_id, doctor, repo)
    items = _catalog_items(body, catalog)
    current = repo.current_medicines(patient_id)
    interactions = []
    if items:  # every item against current medicines and the other items (UC8.4 E1)
        for n, item in enumerate(items):
            others = current + [item_label(o) for k, o in enumerate(items) if k != n]
            interactions += [i for i in check(item_label(item), others) if i not in interactions]
    else:
        interactions = check(str(body.medicationName), current)
    if interactions and not body.acknowledgeInteractions:
        raise ApiError(
            "DRUG_INTERACTION",
            "This medicine interacts with the patient's current medication.",
            status.HTTP_409_CONFLICT,
            details=[i.to_dict() for i in interactions],
        )
    details = (
        items_summary(items)
        if items
        else medication_details(
            str(body.medicationName), str(body.dosage), str(body.frequency), body.duration
        )
    )
    data: dict[str, Any] = {
        "patientId": patient_id,
        "doctorId": doctor.uid,
        "medicationDetails": details,
        "isRecurring": body.isRecurring,
        "source": PrescriptionSource.DOCTOR.value,  # D-50
    }
    if items:
        data["items"] = items
    rx_id = repo.add_prescription(data)
    order_id = None
    if items:
        # D-69: the prescribed medicines join the patient's Meds tab (locked) and an order
        # goes to the pharmacy straight away; recurring ones repeat monthly (D-66).
        doctor_doc = repo.patient(doctor.uid) or {}
        for item in items:
            meds.create(
                {
                    "patientId": patient_id,
                    "name": item_label(item),
                    "dosage": item["dose"],
                    "schedule": FREQUENCIES[item["frequency"]][1],
                    "quantityOnHand": float(item["quantity"]),
                    "refillThresholdDays": DEFAULT_REFILL_DAYS,
                    "adherenceRate": None,
                    "source": DOCTOR_SOURCE,
                    "prescriptionId": rx_id,
                    "catalogId": item["catalogId"],
                    "prescribedBy": doctor_doc.get("name"),
                }
            )
        rx = repo.prescription(rx_id)
        if rx is not None:
            order_id = orders.start_cycle(rx_id, rx, datetime.now(UTC), doctor.uid)
    elif body.isRecurring:  # UC13.1: the first monthly order starts now (D-66)
        rx = repo.prescription(rx_id)
        if rx is not None:
            order_id = orders.start_cycle(rx_id, rx, datetime.now(UTC), doctor.uid)
    audit.log(
        user_id=doctor.uid,
        action="ISSUE_PRESCRIPTION",
        details=f"Prescription issued{' (recurring)' if body.isRecurring else ''}"
        f"{f' with {len(items)} item(s)' if items else ''}"
        f"{f'; {len(interactions)} interaction warning(s) acknowledged' if interactions else ''}.",
        target_type=Collection.PRESCRIPTIONS.value,
        target_id=rx_id,
    )
    return {
        "id": rx_id,
        "medicationDetails": details,
        "items": items,
        "total": items_total(items) if items else None,
        "orderId": order_id,
        "interactions": [i.to_dict() for i in interactions],
    }


@router.delete("/{patient_id}/prescriptions/{rx_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_prescription(
    patient_id: str,
    rx_id: str,
    doctor: CurrentUser = Depends(doctor_only),
    repo: ProviderRepository = Depends(get_provider_repository),
    audit: AuditLogger = Depends(get_audit_logger),
    meds: MedicationRepository = Depends(get_medication_repository),
) -> None:
    """D-50: the doctor who issued a prescription may delete it (development use). D-69: its
    medicines leave the patient's Meds tab."""
    _assigned_patient(patient_id, doctor, repo)
    rx = repo.prescription(rx_id)
    if rx is None or rx.get("patientId") != patient_id or rx.get("doctorId") != doctor.uid:
        raise ApiError(
            "PRESCRIPTION_NOT_FOUND", "Prescription not found.", status.HTTP_404_NOT_FOUND
        )
    repo.delete_prescription(rx_id)
    for m in meds.list_for(patient_id):
        if m.data.get("prescriptionId") == rx_id:
            meds.delete(m.id)
    audit.log(
        user_id=doctor.uid,
        action="DELETE_PRESCRIPTION",
        details="Prescription deleted by the issuing doctor.",
        target_type=Collection.PRESCRIPTIONS.value,
        target_id=rx_id,
    )


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
