"""Prescription management (D-78, doctor only).

GET /provider/prescriptions   every prescription this doctor issued, with the patient,
                              medicines, total and the latest order's status.

Editing, stopping the monthly repeat and deleting reuse the existing endpoints.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends

from app.core.auth import CurrentUser, require_roles
from app.core.enums import UserRole
from app.services.catalog import items_total
from app.services.orders import OrderRepository, get_order_repository, order_ref
from app.services.provider import ProviderRepository, get_provider_repository

router = APIRouter(prefix="/provider/prescriptions", tags=["provider"])


def _iso(v: Any) -> str | None:
    return v.isoformat() if isinstance(v, datetime) else None


@router.get("")
def my_prescriptions(
    doctor: CurrentUser = Depends(require_roles(UserRole.DOCTOR)),
    repo: ProviderRepository = Depends(get_provider_repository),
    orders: OrderRepository = Depends(get_order_repository),
) -> dict[str, Any]:
    names: dict[str, str] = {}
    out: list[dict[str, Any]] = []
    for rx_id, rx in repo.prescriptions_by_doctor(doctor.uid):
        pid = str(rx.get("patientId"))
        if pid not in names:
            names[pid] = str((repo.patient(pid) or {}).get("name") or "Patient")
        cycles = sorted(orders.orders_for_prescription(rx_id), key=lambda p: p[0])
        latest = None
        if cycles:
            oid, o = cycles[-1]
            latest = {
                "id": oid,
                "ref": order_ref(oid),
                "status": o.get("fulfilmentStatus"),
                "paymentStatus": o.get("paymentStatus"),
            }
        items = list(rx.get("items") or [])
        out.append(
            {
                "id": rx_id,
                "patientId": pid,
                "patientName": names[pid],
                "medicationDetails": rx.get("medicationDetails"),
                "items": items,
                "total": items_total(items) if items else rx.get("monthlyPrice"),
                "isRecurring": bool(rx.get("isRecurring")),
                "issuedAt": _iso(rx.get("issuedAt")),
                "latestOrder": latest,
            }
        )
    out.sort(key=lambda r: str(r["issuedAt"] or ""), reverse=True)
    return {"prescriptions": out}
