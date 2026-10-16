"""Module 13: recurring medication orders, payment and delivery (FR-13.1-13.5;
UC13.1-UC13.6; docs/06 §J; Fig 4.1.1.13; D-66).

Life of an order (`fulfilmentStatus`):

    awaiting_confirmation --skip--> skipped (until next cycle; can still be confirmed)
        --confirm(method)--> awaiting_payment --paid--> preparing
    preparing / out_of_stock --pharmacist--> ready_for_collection --> collected
                             --pharmacist--> ready_for_delivery --courier--> delivered | failed
    failed --reschedule--> ready_for_delivery (dispatched again)
           --switch-----> ready_for_collection

`paymentStatus` (pending / paid / failed) and `deliveryStatus` (dispatched / in_transit /
delivered / failed) keep their Ch4 meaning alongside it.
"""

from __future__ import annotations

import calendar
import hashlib
import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

from fastapi import Depends
from firebase_admin import firestore

from app.core.audit import SYSTEM_SCHEDULER_USER, AuditLogger, get_audit_logger
from app.core.enums import Collection, UserRole
from app.core.firebase import get_firestore
from app.integrations.delivery import CourierClient, DispatchError, get_courier_client
from app.integrations.payments import PaymentIntent
from app.integrations.push import PushMessage
from app.services.medications import MYT
from app.services.notifications import Notifier, get_notifier
from app.services.records import (
    FileStore,
    RecordRepository,
    get_file_store,
    get_record_repository,
)

log = logging.getLogger("careflow.orders")

DELIVERY_FEE = 5.0  # RM, flat (D-66)
REMINDER_AFTER = timedelta(hours=48)  # UC13.2 E1
DISPATCH_ATTEMPTS = 2  # UC13.4 E1: retry once before asking the patient

SELF_COLLECTION = "self_collection"
HOME_DELIVERY = "home_delivery"
METHODS = (SELF_COLLECTION, HOME_DELIVERY)

AWAITING_CONFIRMATION = "awaiting_confirmation"
SKIPPED = "skipped"
AWAITING_PAYMENT = "awaiting_payment"
PREPARING = "preparing"
OUT_OF_STOCK = "out_of_stock"
READY_FOR_COLLECTION = "ready_for_collection"
READY_FOR_DELIVERY = "ready_for_delivery"
COLLECTED = "collected"
DELIVERED = "delivered"
FAILED = "failed"

# The pharmacist's working queue (Fig 4.3.13.1).
PHARMACY_QUEUE = (PREPARING, OUT_OF_STOCK, READY_FOR_COLLECTION, READY_FOR_DELIVERY, FAILED)
OPEN_FOR_PRICE = (AWAITING_CONFIRMATION, SKIPPED, AWAITING_PAYMENT)


class OrderError(Exception):
    """A rule of the order flow was broken; `code` maps to the API error code."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


# ---------------- helpers ----------------


def add_month(moment: datetime) -> datetime:
    """Same day next month (clamped to the month's last day), in Malaysia time."""
    local = moment.astimezone(MYT)
    year, month = (local.year + 1, 1) if local.month == 12 else (local.year, local.month + 1)
    day = min(local.day, calendar.monthrange(year, month)[1])
    return local.replace(year=year, month=month, day=day).astimezone(UTC)


def order_id_for(rx_id: str, cycle: datetime) -> str:
    """One order per recurring prescription per month (D-66)."""
    return f"{rx_id}_{cycle.astimezone(MYT):%Y-%m}"


def order_ref(order_id: str) -> str:
    """Short reference shown to people, e.g. CF-3A9F1C."""
    return "CF-" + hashlib.sha256(order_id.encode()).hexdigest()[:6].upper()


def total_of(order: dict[str, Any]) -> float | None:
    amount = order.get("amount")
    if amount is None:
        return None
    fee = order.get("deliveryFee") or 0.0
    return round(float(amount) + float(fee), 2)


def _iso(v: Any) -> str | None:
    return v.isoformat() if isinstance(v, datetime) else None


def order_view(
    order_id: str, o: dict[str, Any], events: list[dict[str, Any]] | None = None
) -> dict[str, Any]:
    view = {
        "id": order_id,
        "ref": order_ref(order_id),
        "patientId": o.get("patientId"),
        "patientName": o.get("patientName"),
        "prescriptionId": o.get("prescriptionId"),
        "pharmacistId": o.get("pharmacistId"),
        "medicationDetails": o.get("medicationDetails"),
        "method": o.get("method"),
        "paymentStatus": o.get("paymentStatus"),
        "deliveryStatus": o.get("deliveryStatus"),
        "fulfilmentStatus": o.get("fulfilmentStatus"),
        "amount": o.get("amount"),
        "deliveryFee": o.get("deliveryFee") or 0.0,
        "total": total_of(o),
        "deliveryAddress": o.get("deliveryAddress"),
        "courierRef": o.get("courierRef"),
        "failureReason": o.get("failureReason"),
        "stockItemId": o.get("stockItemId"),
        "cycleDate": _iso(o.get("cycleDate")),
        "createdAt": _iso(o.get("createdAt")),
        "confirmedAt": _iso(o.get("confirmedAt")),
        "paidAt": _iso(o.get("paidAt")),
        "readyAt": _iso(o.get("readyAt")),
        "dispatchedAt": _iso(o.get("dispatchedAt")),
        "etaAt": _iso(o.get("etaAt")),
        "receiptRecordId": o.get("receiptRecordId"),
    }
    if events is not None:
        view["events"] = [
            {
                "status": e.get("status"),
                "location": e.get("location"),
                "timestamp": _iso(e.get("timestamp")),
            }
            for e in sorted(
                events, key=lambda e: e.get("timestamp") or datetime.min.replace(tzinfo=UTC)
            )
        ]
    return view


def stock_view(stock_id: str, s: dict[str, Any]) -> dict[str, Any]:
    units = int(s.get("units") or 0)
    low_at = int(s.get("lowStockAt") or 50)
    expiry = s.get("expiryDate")
    return {
        "id": stock_id,
        "name": s.get("name"),
        "units": units,
        "lowStockAt": low_at,
        "low": units < low_at,
        "expiryDate": expiry.astimezone(MYT).date().isoformat()
        if isinstance(expiry, datetime)
        else None,
    }


# ---------------- repository ----------------


class OrderRepository(Protocol):
    def user(self, uid: str) -> dict[str, Any] | None: ...

    def staff(self, role: str) -> list[str]:
        """Uids of active staff with [role] (pharmacists to notify, admins to flag)."""
        ...

    def prescription(self, rx_id: str) -> dict[str, Any] | None: ...

    def update_prescription(self, rx_id: str, data: dict[str, Any]) -> None: ...

    def recurring_prescriptions(self) -> list[dict[str, Any]]:
        """Every prescription with isRecurring == true, each with its "id"."""
        ...

    def order(self, order_id: str) -> dict[str, Any] | None: ...

    def create_order(self, order_id: str, data: dict[str, Any]) -> bool:
        """Creates the order unless it already exists; True if created."""
        ...

    def update_order(self, order_id: str, data: dict[str, Any]) -> None: ...

    def orders_for_patient(self, uid: str) -> list[tuple[str, dict[str, Any]]]: ...

    def orders_for_prescription(self, rx_id: str) -> list[tuple[str, dict[str, Any]]]: ...

    def orders_with_status(self, statuses: tuple[str, ...]) -> list[tuple[str, dict[str, Any]]]: ...

    def home_deliveries(self) -> list[tuple[str, dict[str, Any]]]: ...

    def add_transaction(self, tx_id: str, data: dict[str, Any]) -> None: ...

    def events(self, order_id: str) -> list[dict[str, Any]]: ...

    def add_event(self, data: dict[str, Any]) -> None: ...

    def stock(self) -> list[tuple[str, dict[str, Any]]]: ...

    def stock_item(self, stock_id: str) -> dict[str, Any] | None: ...

    def add_stock(self, data: dict[str, Any]) -> str: ...

    def update_stock(self, stock_id: str, data: dict[str, Any]) -> None: ...

    def take_stock(self, stock_id: str, units: int) -> bool:
        """Atomically deducts [units]; False (and no change) if not enough are left."""
        ...


def _pairs(query: Any) -> list[tuple[str, dict[str, Any]]]:
    return [(d.id, dict(d.to_dict())) for d in query.stream()]


class FirestoreOrderRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _col(self, c: Collection) -> Any:
        return self._db.collection(c.value)

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._col(Collection.USERS).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def staff(self, role: str) -> list[str]:
        q = self._col(Collection.USERS).where(filter=firestore.FieldFilter("role", "==", role))
        return [uid for uid, u in _pairs(q) if u.get("isActive", True) is not False]

    def prescription(self, rx_id: str) -> dict[str, Any] | None:
        snap = self._col(Collection.PRESCRIPTIONS).document(rx_id).get()
        return {**snap.to_dict(), "id": snap.id} if snap.exists else None

    def update_prescription(self, rx_id: str, data: dict[str, Any]) -> None:
        self._col(Collection.PRESCRIPTIONS).document(rx_id).update(data)

    def recurring_prescriptions(self) -> list[dict[str, Any]]:
        q = self._col(Collection.PRESCRIPTIONS).where(
            filter=firestore.FieldFilter("isRecurring", "==", True)
        )
        return [{**d, "id": i} for i, d in _pairs(q)]

    def order(self, order_id: str) -> dict[str, Any] | None:
        snap = self._col(Collection.MEDICATION_ORDERS).document(order_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def create_order(self, order_id: str, data: dict[str, Any]) -> bool:
        from google.api_core.exceptions import AlreadyExists

        try:
            self._col(Collection.MEDICATION_ORDERS).document(order_id).create(data)
        except AlreadyExists:
            return False
        return True

    def update_order(self, order_id: str, data: dict[str, Any]) -> None:
        self._col(Collection.MEDICATION_ORDERS).document(order_id).update(data)

    def orders_for_patient(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        return _pairs(
            self._col(Collection.MEDICATION_ORDERS).where(
                filter=firestore.FieldFilter("patientId", "==", uid)
            )
        )

    def orders_for_prescription(self, rx_id: str) -> list[tuple[str, dict[str, Any]]]:
        return _pairs(
            self._col(Collection.MEDICATION_ORDERS).where(
                filter=firestore.FieldFilter("prescriptionId", "==", rx_id)
            )
        )

    def orders_with_status(self, statuses: tuple[str, ...]) -> list[tuple[str, dict[str, Any]]]:
        return _pairs(
            self._col(Collection.MEDICATION_ORDERS).where(
                filter=firestore.FieldFilter("fulfilmentStatus", "in", list(statuses))
            )
        )

    def home_deliveries(self) -> list[tuple[str, dict[str, Any]]]:
        return _pairs(
            self._col(Collection.MEDICATION_ORDERS).where(
                filter=firestore.FieldFilter("method", "==", HOME_DELIVERY)
            )
        )

    def add_transaction(self, tx_id: str, data: dict[str, Any]) -> None:
        self._col(Collection.PAYMENT_TRANSACTIONS).document(tx_id).set(data)

    def events(self, order_id: str) -> list[dict[str, Any]]:
        q = self._col(Collection.DELIVERY_TRACKING_EVENTS).where(
            filter=firestore.FieldFilter("orderId", "==", order_id)
        )
        return [d for _, d in _pairs(q)]

    def add_event(self, data: dict[str, Any]) -> None:
        self._col(Collection.DELIVERY_TRACKING_EVENTS).add(data)

    def stock(self) -> list[tuple[str, dict[str, Any]]]:
        return _pairs(self._col(Collection.MEDICATION_STOCK))

    def stock_item(self, stock_id: str) -> dict[str, Any] | None:
        snap = self._col(Collection.MEDICATION_STOCK).document(stock_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def add_stock(self, data: dict[str, Any]) -> str:
        _, ref = self._col(Collection.MEDICATION_STOCK).add(data)
        return str(ref.id)

    def update_stock(self, stock_id: str, data: dict[str, Any]) -> None:
        self._col(Collection.MEDICATION_STOCK).document(stock_id).update(data)

    def take_stock(self, stock_id: str, units: int) -> bool:
        ref = self._col(Collection.MEDICATION_STOCK).document(stock_id)

        @firestore.transactional  # type: ignore[untyped-decorator]
        def _take(tx: Any) -> bool:
            snap = ref.get(transaction=tx)
            left = int((snap.to_dict() or {}).get("units") or 0) if snap.exists else 0
            if not snap.exists or left < units:
                return False
            tx.update(ref, {"units": left - units, "updatedAt": firestore.SERVER_TIMESTAMP})
            return True

        return bool(_take(self._db.transaction()))


def get_order_repository() -> OrderRepository:
    return FirestoreOrderRepository(get_firestore())


# ---------------- service ----------------


@dataclass
class OrderService:
    repo: OrderRepository
    notifier: Notifier
    courier: CourierClient
    audit: AuditLogger
    # Saves the payment receipt to health records: (order id, order, charge id) -> record id.
    receipts: Callable[[str, dict[str, Any], str], str] | None = None

    # ----- notifications -----

    def _push(self, uid: str, title: str, body: str, order_id: str) -> None:
        self.notifier.notify(uid, PushMessage(title, body, {"type": "order", "orderId": order_id}))

    def _push_role(self, role: UserRole, title: str, body: str, order_id: str) -> None:
        for uid in self.repo.staff(role.value):
            self._push(uid, title, body, order_id)

    def _order(self, order_id: str) -> dict[str, Any]:
        o = self.repo.order(order_id)
        if o is None:
            raise OrderError("ORDER_NOT_FOUND", "Order not found.")
        return o

    # ----- UC13.1 / UC13.2: the monthly cycle -----

    def start_cycle(
        self, rx_id: str, rx: dict[str, Any], cycle: datetime, actor: str
    ) -> str | None:
        """Creates this cycle's order (pending payment) and prompts the patient."""
        order_id = order_id_for(rx_id, cycle)
        patient = self.repo.user(str(rx["patientId"])) or {}
        price = rx.get("monthlyPrice")
        created = self.repo.create_order(
            order_id,
            {
                "patientId": rx["patientId"],
                "patientName": patient.get("name"),
                "prescriptionId": rx_id,
                "pharmacistId": None,
                "method": None,  # D-66: chosen by the patient on confirmation
                "paymentStatus": "pending",
                "deliveryStatus": None,
                "fulfilmentStatus": AWAITING_CONFIRMATION,
                "cycleDate": cycle,
                "medicationDetails": rx.get("medicationDetails"),
                "amount": float(price) if price is not None else None,
                "deliveryFee": 0.0,
                "createdAt": datetime.now(UTC),
                "reminderSentAt": None,
            },
        )
        if not created:
            return None
        self.audit.log(
            user_id=actor,
            action="ORDER_CYCLE_STARTED",
            details="Monthly order created for a recurring prescription.",
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )
        self._push(
            str(rx["patientId"]),
            "Confirm this month's order",
            f"Your monthly refill ({rx.get('medicationDetails')}) is ready to confirm.",
            order_id,
        )
        if price is None:
            self._push_role(
                UserRole.PHARMACIST,
                "Recurring prescription needs a price",
                "A monthly order is waiting for its price.",
                order_id,
            )
        return order_id

    def latest_cycle(self, rx_id: str) -> datetime | None:
        cycles: list[datetime] = [
            o["cycleDate"]
            for _, o in self.repo.orders_for_prescription(rx_id)
            if isinstance(o.get("cycleDate"), datetime)
        ]
        return max(cycles) if cycles else None

    def start_next_cycle_now(self, rx_id: str, rx: dict[str, Any], actor: str) -> str | None:
        """D-66 testing aid: the next month's order, created today."""
        last = self.latest_cycle(rx_id)
        cycle = add_month(last) if last else datetime.now(UTC)
        return self.start_cycle(rx_id, rx, cycle, actor)

    def run(self, now: datetime | None = None) -> dict[str, Any]:
        """Runs in the 15-minute sweep: new cycles, 48 h reminders, simulated courier."""
        now = now or datetime.now(UTC)
        created = 0
        for rx in self.repo.recurring_prescriptions():
            last = self.latest_cycle(rx["id"])
            due = now if last is None else add_month(last)
            if due <= now and self.start_cycle(rx["id"], rx, due, SYSTEM_SCHEDULER_USER):
                created += 1
        reminded = 0
        for order_id, o in self.repo.orders_with_status((AWAITING_CONFIRMATION,)):
            made = o.get("createdAt")
            if o.get("reminderSentAt") or not isinstance(made, datetime):
                continue
            if now - made >= REMINDER_AFTER:
                self._push(
                    str(o["patientId"]),
                    "Reminder: confirm your monthly order",
                    "Your medication refill is still waiting for confirmation.",
                    order_id,
                )
                self.repo.update_order(order_id, {"reminderSentAt": now})
                reminded += 1
        moved = 0
        for order_id, o in self.repo.orders_with_status((READY_FOR_DELIVERY,)):
            moved += self.advance(order_id, o, now)
        return {"ordersCreated": created, "orderReminders": reminded, "deliveryUpdates": moved}

    # ----- UC13.2 A1 skip / UC13.3 confirm -----

    def skip(self, order_id: str, uid: str) -> None:
        o = self._order(order_id)
        if o.get("fulfilmentStatus") not in (AWAITING_CONFIRMATION, AWAITING_PAYMENT):
            raise OrderError("ORDER_NOT_OPEN", "This order can no longer be skipped.")
        self.repo.update_order(
            order_id, {"fulfilmentStatus": SKIPPED, "method": None, "deliveryFee": 0.0}
        )
        self.audit.log(
            user_id=uid,
            action="ORDER_SKIPPED",
            details="Patient skipped this month's order.",
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )

    def confirm(self, order_id: str, uid: str, method: str, address: str | None) -> dict[str, Any]:
        o = self._order(order_id)
        if o.get("fulfilmentStatus") not in (AWAITING_CONFIRMATION, SKIPPED, AWAITING_PAYMENT):
            raise OrderError("ORDER_NOT_OPEN", "This order has already been paid.")
        if o.get("amount") is None:
            raise OrderError(
                "ORDER_NOT_PRICED",
                "The pharmacy hasn't priced this medicine yet. We'll notify you when it's ready.",
            )
        if method not in METHODS:
            raise OrderError("INVALID_METHOD", "Choose self-collection or home delivery.")
        address = (address or "").strip()
        if method == HOME_DELIVERY and not address:
            raise OrderError("ADDRESS_REQUIRED", "Enter the delivery address.")
        update = {
            "method": method,
            "deliveryFee": DELIVERY_FEE if method == HOME_DELIVERY else 0.0,
            "deliveryAddress": address if method == HOME_DELIVERY else None,
            "fulfilmentStatus": AWAITING_PAYMENT,
            "confirmedAt": datetime.now(UTC),
        }
        self.repo.update_order(order_id, update)
        self.audit.log(
            user_id=uid,
            action="ORDER_CONFIRMED",
            details=f"Patient confirmed the monthly order ({method}).",
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )
        return {**o, **update}

    # ----- UC13.3 payment -----

    def record_payment(self, order_id: str, intent: PaymentIntent) -> str:
        """Applies a payment result (webhook or app refresh); safe to repeat."""
        o = self._order(order_id)
        if o.get("paymentStatus") == "paid":
            return "paid"
        now = datetime.now(UTC)
        if intent.status == "pending":
            return "pending"
        amount = round(intent.amount_sen / 100, 2)
        if intent.status == "failed":
            self.repo.add_transaction(
                f"{intent.id}_failed",
                {
                    "orderId": order_id,
                    "stripeChargeId": intent.charge_id or intent.id,
                    "amount": amount,
                    "status": "failed",
                    "processedAt": now,
                },
            )
            self.repo.update_order(order_id, {"paymentStatus": "failed"})
            return "failed"
        self.repo.add_transaction(
            intent.charge_id or intent.id,
            {
                "orderId": order_id,
                "stripeChargeId": intent.charge_id or intent.id,
                "amount": amount,
                "status": "succeeded",
                "processedAt": now,
            },
        )
        self.repo.update_order(
            order_id,
            {"paymentStatus": "paid", "fulfilmentStatus": PREPARING, "paidAt": now},
        )
        if self.receipts is not None:
            try:
                record_id = self.receipts(order_id, o, intent.charge_id or intent.id)
                self.repo.update_order(order_id, {"receiptRecordId": record_id})
            except Exception:  # the payment stands even if the receipt can't be saved
                log.exception("Receipt for %s not saved", order_id)
        self.audit.log(
            user_id=str(o.get("patientId")),
            action="ORDER_PAID",
            details=f"Payment of RM{amount:.2f} succeeded.",
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )
        self._push_role(
            UserRole.PHARMACIST,
            "New paid order",
            f"{o.get('patientName') or 'A patient'}: {o.get('medicationDetails')}",
            order_id,
        )
        return "paid"

    # ----- UC13.6 pharmacist -----

    def set_price(self, rx_id: str, price: float, uid: str) -> int:
        rx = self.repo.prescription(rx_id)
        if rx is None:
            raise OrderError("PRESCRIPTION_NOT_FOUND", "Prescription not found.")
        self.repo.update_prescription(rx_id, {"monthlyPrice": round(price, 2)})
        updated = 0
        for order_id, o in self.repo.orders_for_prescription(rx_id):
            if o.get("fulfilmentStatus") in OPEN_FOR_PRICE and o.get("paymentStatus") != "paid":
                was_unpriced = o.get("amount") is None
                self.repo.update_order(order_id, {"amount": round(price, 2)})
                updated += 1
                if was_unpriced:
                    self._push(
                        str(o["patientId"]),
                        "Your monthly order is ready to confirm",
                        "The pharmacy has priced your refill.",
                        order_id,
                    )
        self.audit.log(
            user_id=uid,
            action="SET_PRESCRIPTION_PRICE",
            details=f"Monthly price set to RM{price:.2f}.",
            target_type=Collection.PRESCRIPTIONS.value,
            target_id=rx_id,
        )
        return updated

    def mark_ready(self, order_id: str, uid: str, stock_id: str, units: int) -> dict[str, Any]:
        o = self._order(order_id)
        if o.get("fulfilmentStatus") not in (PREPARING, OUT_OF_STOCK):
            raise OrderError(
                "ORDER_NOT_PREPARING", "Only paid orders being prepared can be marked ready."
            )
        if self.repo.stock_item(stock_id) is None:
            raise OrderError("STOCK_NOT_FOUND", "Stock item not found.")
        if not self.repo.take_stock(stock_id, units):
            raise OrderError(
                "INSUFFICIENT_STOCK",
                "Not enough units in stock. Add stock or mark the order out of stock.",
            )
        now = datetime.now(UTC)
        delivery = o.get("method") == HOME_DELIVERY
        update: dict[str, Any] = {
            "fulfilmentStatus": READY_FOR_DELIVERY if delivery else READY_FOR_COLLECTION,
            "pharmacistId": uid,
            "readyAt": now,
            "stockItemId": stock_id,
            "failureReason": None,
        }
        self.repo.update_order(order_id, update)
        o = {**o, **update}
        self.audit.log(
            user_id=uid,
            action="ORDER_READY",
            details=f"Order marked {'ready for delivery' if delivery else 'ready for collection'}"
            f"; {units} unit(s) taken from stock.",
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )
        if delivery:
            return self.dispatch(order_id, o, uid, now)
        self._push(
            str(o["patientId"]),
            "Ready for collection",
            "Your medication is ready. Show your collection slip at the pharmacy.",
            order_id,
        )
        return o

    def out_of_stock(self, order_id: str, uid: str, note: str | None) -> None:
        o = self._order(order_id)
        if o.get("fulfilmentStatus") != PREPARING:
            raise OrderError("ORDER_NOT_PREPARING", "Only orders being prepared can be flagged.")
        self.repo.update_order(
            order_id,
            {"fulfilmentStatus": OUT_OF_STOCK, "pharmacistId": uid, "failureReason": note or None},
        )
        self.audit.log(
            user_id=uid,
            action="ORDER_OUT_OF_STOCK",
            details="Pharmacist flagged an order as out of stock."
            + (f" Note: {note}" if note else ""),
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )
        self._push_role(
            UserRole.ADMIN,
            "Medicine out of stock",
            f"An order for {o.get('medicationDetails')} can't be filled.",
            order_id,
        )
        self._push(
            str(o["patientId"]),
            "Your order is delayed",
            "The pharmacy is waiting for stock of your medicine. We'll let you know when "
            "it's ready.",
            order_id,
        )

    def collected(self, order_id: str, uid: str) -> None:
        o = self._order(order_id)
        if o.get("fulfilmentStatus") != READY_FOR_COLLECTION:
            raise OrderError("ORDER_NOT_READY", "This order isn't waiting for collection.")
        self.repo.update_order(order_id, {"fulfilmentStatus": COLLECTED})
        self.audit.log(
            user_id=uid,
            action="ORDER_COLLECTED",
            details="Patient collected the order.",
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )

    # ----- UC13.4 / UC13.5 delivery -----

    def dispatch(
        self, order_id: str, o: dict[str, Any], actor: str, now: datetime | None = None
    ) -> dict[str, Any]:
        now = now or datetime.now(UTC)
        reason = "The courier could not be booked."
        for _ in range(DISPATCH_ATTEMPTS):
            try:
                d = self.courier.dispatch(order_id, str(o.get("deliveryAddress") or ""), now)
            except DispatchError as exc:
                reason = str(exc) or reason
                continue
            update = {
                "fulfilmentStatus": READY_FOR_DELIVERY,
                "deliveryStatus": "dispatched",
                "courierRef": d.delivery_id,
                "dispatchedAt": now,
                "etaAt": d.eta,
                "failureReason": None,
            }
            self.repo.update_order(order_id, update)
            self.repo.add_event(
                {"orderId": order_id, "status": "dispatched", "location": None, "timestamp": now}
            )
            self.audit.log(
                user_id=actor,
                action="ORDER_DISPATCHED",
                details=f"Dispatched via {self.courier.name} ({d.delivery_id}).",
                target_type=Collection.MEDICATION_ORDERS.value,
                target_id=order_id,
            )
            self._push(
                str(o["patientId"]),
                "Your order is on its way",
                "A courier has been booked for your medication.",
                order_id,
            )
            return {**o, **update}
        return self.fail_delivery(order_id, o, reason, actor, now)

    def fail_delivery(
        self, order_id: str, o: dict[str, Any], reason: str, actor: str, now: datetime | None = None
    ) -> dict[str, Any]:
        """FR-13.5: record the failure and ask the patient to reschedule or switch."""
        now = now or datetime.now(UTC)
        update = {"fulfilmentStatus": FAILED, "deliveryStatus": "failed", "failureReason": reason}
        self.repo.update_order(order_id, update)
        self.repo.add_event(
            {"orderId": order_id, "status": "failed", "location": None, "timestamp": now}
        )
        self.audit.log(
            user_id=actor,
            action="ORDER_DELIVERY_FAILED",
            details=f"Delivery failed: {reason}",
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )
        self._push(
            str(o["patientId"]),
            "Delivery problem",
            "We couldn't deliver your medication. Reschedule or switch to self-collection.",
            order_id,
        )
        return {**o, **update}

    def courier_update(
        self,
        order_id: str,
        o: dict[str, Any],
        status: str,
        at: datetime,
        location: str | None,
    ) -> bool:
        """One courier status (simulator or Grab webhook). Returns True if it was new."""
        if o.get("fulfilmentStatus") != READY_FOR_DELIVERY:
            return False
        since = o.get("dispatchedAt")
        seen = {
            e.get("status")
            for e in self.repo.events(order_id)
            if not isinstance(since, datetime)
            or (isinstance(e.get("timestamp"), datetime) and e["timestamp"] >= since)
        }
        if status in seen:
            return False
        if status == "failed":
            self.fail_delivery(
                order_id, o, location or "The courier reported a failure.", "courier", at
            )
            return True
        self.repo.add_event(
            {"orderId": order_id, "status": status, "location": location, "timestamp": at}
        )
        update: dict[str, Any] = {}
        if status == "in_transit":
            update["deliveryStatus"] = "in_transit"
        elif status == "delivered":
            update = {"deliveryStatus": "delivered", "fulfilmentStatus": DELIVERED}
        if update:
            self.repo.update_order(order_id, update)
            o.update(update)
        title, body = {
            "picked_up": ("Courier picked up your order", "Your medication is with the courier."),
            "in_transit": ("Out for delivery", "Your medication is on the way."),
            "delivered": ("Delivered", "Your medication has been delivered."),
        }.get(status, ("Delivery update", status.replace("_", " ")))
        self._push(str(o["patientId"]), title, body, order_id)
        return True

    def advance(self, order_id: str, o: dict[str, Any], now: datetime | None = None) -> int:
        """Applies the simulated courier's progress (D-66: ~1 min per stage)."""
        now = now or datetime.now(UTC)
        since = o.get("dispatchedAt")
        if (
            not self.courier.simulated
            or o.get("fulfilmentStatus") != READY_FOR_DELIVERY
            or not isinstance(since, datetime)
        ):
            return 0
        moved = 0
        for u in self.courier.updates_since_dispatch(since, now):
            if self.courier_update(order_id, o, u.status, u.at, u.location):
                moved += 1
        return moved

    def reschedule(self, order_id: str, uid: str) -> dict[str, Any]:
        o = self._order(order_id)
        if o.get("fulfilmentStatus") != FAILED:
            raise OrderError("ORDER_NOT_FAILED", "Only a failed delivery can be rescheduled.")
        o = {**o, "fulfilmentStatus": READY_FOR_DELIVERY}
        return self.dispatch(order_id, o, uid)

    def switch_to_collection(self, order_id: str, uid: str) -> None:
        o = self._order(order_id)
        if o.get("fulfilmentStatus") != FAILED:
            raise OrderError("ORDER_NOT_FAILED", "Only a failed delivery can be switched.")
        self.repo.update_order(
            order_id,
            {
                "method": SELF_COLLECTION,
                "fulfilmentStatus": READY_FOR_COLLECTION,
                "readyAt": datetime.now(UTC),
            },
        )
        self.audit.log(
            user_id=uid,
            action="ORDER_SWITCHED_TO_COLLECTION",
            details="Patient switched a failed delivery to self-collection.",
            target_type=Collection.MEDICATION_ORDERS.value,
            target_id=order_id,
        )


def get_order_service(
    repo: OrderRepository = Depends(get_order_repository),
    notifier: Notifier = Depends(get_notifier),
    courier: CourierClient = Depends(get_courier_client),
    audit: AuditLogger = Depends(get_audit_logger),
    records: RecordRepository = Depends(get_record_repository),
    files: FileStore = Depends(get_file_store),
) -> OrderService:
    from app.services.receipts import store_receipt

    def receipts(order_id: str, order: dict[str, Any], charge_id: str) -> str:
        return store_receipt(records, files, order_id, order, charge_id)

    return OrderService(repo, notifier, courier, audit, receipts)
