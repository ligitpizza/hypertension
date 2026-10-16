"""Medication catalogue (D-69): the medicines a doctor can prescribe, with unit prices.

Seeded from firebase/seed/medication_catalog.json (indicative demo prices); pharmacists
and admins can change prices and add medicines. Prescriptions copy the price at issue
time, so a later price change never alters an existing order.
"""

from __future__ import annotations

from typing import Any, Protocol

from app.core.enums import Collection
from app.core.firebase import get_firestore

# Prescription frequencies -> default reminder times (MYT) for the patient's Meds tab.
FREQUENCIES: dict[str, tuple[str, str]] = {
    "once_daily": ("Once daily", "08:00"),
    "twice_daily": ("Twice daily", "08:00,20:00"),
    "three_times_daily": ("Three times daily", "08:00,14:00,20:00"),
    "at_night": ("At night", "21:00"),
    "as_needed": ("As needed", "as_needed"),
}


def catalog_view(item_id: str, c: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": item_id,
        "name": c.get("name"),
        "strength": c.get("strength"),
        "form": c.get("form"),
        "unitLabel": c.get("unitLabel") or c.get("form") or "unit",
        "drugClass": c.get("drugClass"),
        "unitPrice": float(c.get("unitPrice") or 0),
        "active": c.get("active", True) is not False,
    }


def item_label(item: dict[str, Any]) -> str:
    """'Amlodipine 5mg'."""
    return f"{item.get('name')} {item.get('strength') or ''}".strip()


def items_summary(items: list[dict[str, Any]]) -> str:
    """prescriptions.medicationDetails for a consolidated prescription (one line)."""
    parts = []
    for i in items:
        freq = FREQUENCIES.get(str(i.get("frequency")), (str(i.get("frequency")), ""))[0]
        parts.append(f"{item_label(i)} {i.get('dose')}, {freq.lower()} x{i.get('quantity')}")
    return "; ".join(parts)


def items_total(items: list[dict[str, Any]]) -> float:
    return round(
        sum(float(i.get("unitPrice") or 0) * int(i.get("quantity") or 0) for i in items), 2
    )


class CatalogRepository(Protocol):
    def all(self) -> list[tuple[str, dict[str, Any]]]: ...

    def get(self, item_id: str) -> dict[str, Any] | None: ...

    def create(self, data: dict[str, Any]) -> str: ...

    def update(self, item_id: str, data: dict[str, Any]) -> None: ...


class FirestoreCatalogRepository:
    def __init__(self, db: Any) -> None:
        self._col = db.collection(Collection.MEDICATION_CATALOG.value)

    def all(self) -> list[tuple[str, dict[str, Any]]]:
        return [(d.id, dict(d.to_dict())) for d in self._col.stream()]

    def get(self, item_id: str) -> dict[str, Any] | None:
        snap = self._col.document(item_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def create(self, data: dict[str, Any]) -> str:
        _, ref = self._col.add(data)
        return str(ref.id)

    def update(self, item_id: str, data: dict[str, Any]) -> None:
        self._col.document(item_id).update(data)


def get_catalog_repository() -> CatalogRepository:
    return FirestoreCatalogRepository(get_firestore())
