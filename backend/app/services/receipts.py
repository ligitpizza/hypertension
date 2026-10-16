"""Payment receipt saved to the patient's health records (docs/06 §J step 4, D-66)."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.services.medications import MYT
from app.services.orders import HOME_DELIVERY, order_ref
from app.services.records import FileStore, RecordRepository, storage_path
from app.services.settings import _latin1


def receipt_pdf(order_id: str, order: dict[str, Any], charge_id: str, paid_at: datetime) -> bytes:
    from fpdf import FPDF

    pdf = FPDF()
    pdf.add_page()
    width = pdf.epw

    def line(text: object, size: int = 11, style: str = "") -> None:
        pdf.set_font("Helvetica", style, size)
        pdf.multi_cell(width, 6 if size <= 11 else 9, _latin1(text), new_x="LMARGIN", new_y="NEXT")

    amount = float(order.get("amount") or 0)
    fee = float(order.get("deliveryFee") or 0)
    line("CareFlow payment receipt", 16, "B")
    line(f"Order {order_ref(order_id)}")
    line(f"Paid {paid_at.astimezone(MYT):%d %b %Y, %H:%M} (Malaysia time)")
    line(f"Payment reference: {charge_id}")
    pdf.ln(3)
    line(f"Medication: {order.get('medicationDetails')}")
    line(f"Monthly supply: RM{amount:.2f}")
    if order.get("method") == HOME_DELIVERY:
        line(f"Home delivery: RM{fee:.2f}")
    else:
        line("Self-collection: RM0.00")
    line(f"Total paid: RM{amount + fee:.2f}", 12, "B")
    pdf.ln(3)
    line("Processed securely by Stripe (test mode). CareFlow never sees card details.", 9)
    return bytes(pdf.output())


def store_receipt(
    records: RecordRepository,
    files: FileStore,
    order_id: str,
    order: dict[str, Any],
    charge_id: str,
) -> str:
    """Saves the receipt as a health record (category "other"); returns the record id."""
    record_id = f"receipt_{order_id}"
    patient_id = str(order["patientId"])
    now = datetime.now(UTC)
    data = receipt_pdf(order_id, order, charge_id, now)
    path = storage_path(patient_id, record_id)
    files.write(path, data, "application/pdf")
    records.create(
        record_id,
        {
            "patientId": patient_id,
            "fileUrl": path,
            "fileName": f"CareFlow receipt {order_ref(order_id)}.pdf",
            "contentType": "application/pdf",
            "sizeBytes": len(data),
            "category": "other",
            "uploadedAt": now,
            "sharedWithDoctor": False,
        },
    )
    return record_id
