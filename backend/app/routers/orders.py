"""Module 13 API (FR-13.1-13.5; UC13.1-UC13.6; docs/05; D-66).

Patient   GET  /orders, GET /orders/{id}; POST /orders/{id}/confirm | skip | pay |
          pay/fake | pay/refresh | reschedule | switch-to-collection; POST /orders/dev/next-cycle
Doctor    POST /prescriptions/{id}/recurring
Pharmacy  GET  /pharmacy/queue, /pharmacy/stock, /pharmacy/patients;
          PUT  /pharmacy/prescriptions/{id}/price;
          POST /pharmacy/orders/{id}/ready | out-of-stock | collected; stock add / edit / receive
Admin     GET  /admin/deliveries; POST /admin/deliveries/{id}/dispatch | simulate-failure
Webhooks  POST /webhooks/stripe, /webhooks/grab

Orders are read through the API (not straight from Firestore) so the simulated courier
advances whenever someone looks, and totals are worked out in one place.
"""

from __future__ import annotations

import hmac
import json
import logging
from datetime import UTC, datetime, time
from time import monotonic
from typing import Any

from fastapi import APIRouter, Depends, Header, Request, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.config import Settings, get_settings
from app.core.enums import Collection, PrescriptionSource, UserRole
from app.core.errors import ApiError
from app.integrations.delivery import grab_updates, order_id_from_merchant
from app.integrations.payments import (
    CURRENCY,
    FakeGateway,
    PaymentError,
    PaymentGateway,
    WebhookSignatureError,
    get_payment_gateway,
    intent_from_stripe,
)
from app.schemas.orders import (
    CancelOrderRequest,
    CatalogEditRequest,
    CatalogItemRequest,
    ConfirmOrderRequest,
    DeliveryQuoteRequest,
    FailDeliveryRequest,
    FakePaymentRequest,
    GrabWebhook,
    OutOfStockRequest,
    PriceRequest,
    ReadyRequest,
    ReceiveStockRequest,
    RecurringRequest,
    StockEditRequest,
    StockRequest,
)
from app.services.catalog import CatalogRepository, catalog_view, get_catalog_repository
from app.services.medications import MYT
from app.services.orders import (
    AWAITING_CONFIRMATION,
    AWAITING_PAYMENT,
    CANCELLED,
    COLLECTED,
    DELIVERED,
    FAILED,
    OUT_OF_STOCK,
    PHARMACY_QUEUE,
    PREPARING,
    READY_FOR_COLLECTION,
    READY_FOR_DELIVERY,
    SKIPPED,
    OrderError,
    OrderService,
    get_order_service,
    stock_view,
    total_of,
)
from app.services.orders import order_view as _order_view

router = APIRouter(tags=["orders"])
log = logging.getLogger("careflow.orders")

patient_only = require_roles(UserRole.PATIENT)
doctor_only = require_roles(UserRole.DOCTOR)
pharmacist_only = require_roles(UserRole.PHARMACIST)
admin_only = require_roles(UserRole.ADMIN)
pharmacy_staff = require_roles(UserRole.PHARMACIST, UserRole.ADMIN)

_BAD_REQUEST = {"INVALID_METHOD", "ADDRESS_REQUIRED", "LOCATION_REQUIRED", "PHONE_REQUIRED"}


def _api(e: OrderError) -> ApiError:
    if e.code.endswith("_NOT_FOUND"):
        code = status.HTTP_404_NOT_FOUND
    elif e.code in _BAD_REQUEST:
        code = status.HTTP_400_BAD_REQUEST
    else:
        code = status.HTTP_409_CONFLICT
    return ApiError(e.code, e.message, code)


def _view(
    svc: OrderService,
    order_id: str,
    o: dict[str, Any],
    events: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """The order plus the courier's name for the app ("delivered by Lalamove", D-68)."""
    return {**_order_view(order_id, o, events), "courierBrand": svc.courier.brand}


def _not_found() -> ApiError:
    return ApiError("ORDER_NOT_FOUND", "Order not found.", status.HTTP_404_NOT_FOUND)


def _own_order(svc: OrderService, order_id: str, uid: str) -> dict[str, Any]:
    o = svc.repo.order(order_id)
    if o is None or o.get("patientId") != uid:
        raise _not_found()
    return o


# A real courier is asked from lists at most once per order in this window.
LIST_POLL_EVERY = 20.0
_last_list_poll: dict[str, float] = {}


def _fresh(
    svc: OrderService, order_id: str, o: dict[str, Any], single: bool = False
) -> dict[str, Any]:
    """Applies courier progress before showing the order. Each poll of a real courier is an
    API call, so lists (pharmacy queue, admin deliveries) poll each order at most every
    20 s; the order screen always does."""
    if o.get("fulfilmentStatus") != READY_FOR_DELIVERY:
        return o
    if not (single or svc.courier.poll_in_lists):
        now = monotonic()
        if now - _last_list_poll.get(order_id, -LIST_POLL_EVERY) < LIST_POLL_EVERY:
            return o
        _last_list_poll[order_id] = now
    svc.advance(order_id, o)
    return svc.repo.order(order_id) or o


def _newest_first(pairs: list[tuple[str, dict[str, Any]]]) -> list[tuple[str, dict[str, Any]]]:
    floor = datetime.min.replace(tzinfo=UTC)

    def key(p: tuple[str, dict[str, Any]]) -> datetime:
        v = p[1].get("cycleDate")
        return v if isinstance(v, datetime) else floor

    return sorted(pairs, key=key, reverse=True)


# ---------------- patient ----------------


@router.get("/orders")
def list_orders(
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    out = []
    for order_id, o in _newest_first(svc.repo.orders_for_patient(user.uid)):
        out.append(_view(svc, order_id, _fresh(svc, order_id, o)))
    return {"orders": out}


@router.get("/orders/{order_id}")
def get_order(
    order_id: str,
    user: CurrentUser = Depends(
        require_roles(UserRole.PATIENT, UserRole.PHARMACIST, UserRole.ADMIN)
    ),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    o = svc.repo.order(order_id)
    if o is None or (user.role == UserRole.PATIENT and o.get("patientId") != user.uid):
        raise _not_found()
    o = _fresh(svc, order_id, o, single=True)
    view = _view(svc, order_id, o, svc.repo.events(order_id))
    if user.role == UserRole.PATIENT:  # D-67/D-69: prefill the checkout from the profile
        view["suggestedPhone"] = o.get("deliveryPhone") or svc.repo.profile_phone(user.uid)
        me = svc.repo.user(user.uid) or {}
        view["suggestedAddress"] = me.get("address")
        view["suggestedLat"] = me.get("addressLat")
        view["suggestedLng"] = me.get("addressLng")
    return view


@router.post("/orders/{order_id}/confirm")
def confirm_order(
    order_id: str,
    body: ConfirmOrderRequest,
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    _own_order(svc, order_id, user.uid)
    try:
        o = svc.confirm(
            order_id,
            user.uid,
            body.method,
            body.deliveryAddress,
            body.deliveryLat,
            body.deliveryLng,
            body.deliveryPhone,
        )
    except OrderError as e:
        raise _api(e) from e
    return _view(svc, order_id, o)


@router.post("/orders/{order_id}/delivery-quote")
def delivery_quote(
    order_id: str,
    body: DeliveryQuoteRequest,
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    """D-71: the courier's fee for this drop-off, shown before the patient confirms (the
    backend quotes again on confirmation)."""
    o = _own_order(svc, order_id, user.uid)
    fee = svc.delivery_quote(
        {
            **o,
            "deliveryAddress": body.deliveryAddress,
            "deliveryLat": body.lat,
            "deliveryLng": body.lng,
        }
    )
    return {"deliveryFee": fee, "courier": svc.courier.brand}


@router.post("/orders/{order_id}/skip", status_code=status.HTTP_204_NO_CONTENT)
def skip_order(
    order_id: str,
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
) -> None:
    _own_order(svc, order_id, user.uid)
    try:
        svc.skip(order_id, user.uid)
    except OrderError as e:
        raise _api(e) from e


@router.post("/orders/{order_id}/pay")
def start_payment(
    order_id: str,
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
    gateway: PaymentGateway = Depends(get_payment_gateway),
) -> dict[str, Any]:
    """UC13.3: a PaymentIntent for the order total; the app opens Stripe's PaymentSheet
    with the client secret (or the simulated card form in fake mode)."""
    o = _own_order(svc, order_id, user.uid)
    if o.get("fulfilmentStatus") != AWAITING_PAYMENT or o.get("paymentStatus") == "paid":
        raise ApiError("ORDER_NOT_PAYABLE", "Confirm the order first.", status.HTTP_409_CONFLICT)
    total = total_of(o)
    if total is None:
        raise ApiError("ORDER_NOT_PRICED", "This order has no price yet.", status.HTTP_409_CONFLICT)
    amount_sen = round(total * 100)
    intent = None
    existing = o.get("paymentIntentId")
    if existing:  # UC13.3 E1: a retry reuses the same intent while the amount is unchanged
        try:
            old = gateway.retrieve(str(existing))
            if old.status != "succeeded" and old.amount_sen == amount_sen:
                intent = old
        except PaymentError:
            intent = None
    try:
        if intent is None:
            intent = gateway.create_intent(amount_sen, {"orderId": order_id})
    except PaymentError as e:
        raise ApiError(
            "PAYMENT_UNAVAILABLE",
            "Payments are unavailable right now. Please try again shortly.",
            status.HTTP_503_SERVICE_UNAVAILABLE,
        ) from e
    svc.repo.update_order(order_id, {"paymentIntentId": intent.id})
    return {
        "mode": gateway.mode,
        "paymentIntentId": intent.id,
        "clientSecret": intent.client_secret,
        "publishableKey": gateway.publishable_key,
        "amount": total,
        "currency": CURRENCY,
    }


def _settle(svc: OrderService, order_id: str, gateway: PaymentGateway) -> dict[str, Any]:
    o = svc.repo.order(order_id) or {}
    intent_id = o.get("paymentIntentId")
    if not intent_id:
        raise ApiError("PAYMENT_NOT_STARTED", "Start the payment first.", status.HTTP_409_CONFLICT)
    try:
        intent = gateway.retrieve(str(intent_id))
    except PaymentError as e:
        raise ApiError(
            "PAYMENT_UNAVAILABLE",
            "Couldn't check the payment.",
            status.HTTP_503_SERVICE_UNAVAILABLE,
        ) from e
    result = svc.record_payment(order_id, intent)
    return {
        "result": result,
        "message": intent.decline_message if result == "failed" else None,
        "order": _view(svc, order_id, svc.repo.order(order_id) or o),
    }


@router.post("/orders/{order_id}/pay/fake")
def pay_fake(
    order_id: str,
    body: FakePaymentRequest,
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
    gateway: PaymentGateway = Depends(get_payment_gateway),
) -> dict[str, Any]:
    """Fake mode only: Stripe test card 4242... succeeds, 4000 0000 0000 0002 declines."""
    if not isinstance(gateway, FakeGateway):
        raise ApiError("NOT_FOUND", "Not available.", status.HTTP_404_NOT_FOUND)
    o = _own_order(svc, order_id, user.uid)
    if not o.get("paymentIntentId"):
        raise ApiError("PAYMENT_NOT_STARTED", "Start the payment first.", status.HTTP_409_CONFLICT)
    try:
        gateway.pay(str(o["paymentIntentId"]), body.cardNumber)
    except PaymentError as e:
        raise ApiError("PAYMENT_NOT_STARTED", str(e), status.HTTP_409_CONFLICT) from e
    return _settle(svc, order_id, gateway)


@router.post("/orders/{order_id}/pay/refresh")
def refresh_payment(
    order_id: str,
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
    gateway: PaymentGateway = Depends(get_payment_gateway),
) -> dict[str, Any]:
    """Called when the app returns from the PaymentSheet, in case the webhook is late."""
    _own_order(svc, order_id, user.uid)
    return _settle(svc, order_id, gateway)


@router.post("/orders/{order_id}/reschedule")
def reschedule_delivery(
    order_id: str,
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    _own_order(svc, order_id, user.uid)
    try:
        return _view(svc, order_id, svc.reschedule(order_id, user.uid))
    except OrderError as e:
        raise _api(e) from e


@router.post("/orders/{order_id}/switch-to-collection", status_code=status.HTTP_204_NO_CONTENT)
def switch_to_collection(
    order_id: str,
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
) -> None:
    _own_order(svc, order_id, user.uid)
    try:
        svc.switch_to_collection(order_id, user.uid)
    except OrderError as e:
        raise _api(e) from e


@router.post("/orders/dev/next-cycle")
def dev_next_cycle(
    user: CurrentUser = Depends(patient_only),
    svc: OrderService = Depends(get_order_service),
    settings: Settings = Depends(get_settings),
) -> dict[str, Any]:
    """D-66 testing aid: start next month's order for each recurring prescription now."""
    if not settings.dev_order_tools:
        raise ApiError("NOT_FOUND", "Not available.", status.HTTP_404_NOT_FOUND)
    created = []
    for rx in svc.repo.recurring_prescriptions():
        if rx.get("patientId") == user.uid:
            order_id = svc.start_next_cycle_now(rx["id"], rx, user.uid)
            if order_id:
                created.append(order_id)
    return {"created": created}


# ---------------- doctor: UC13.1 ----------------


@router.post("/prescriptions/{rx_id}/recurring")
def set_recurring(
    rx_id: str,
    body: RecurringRequest,
    doctor: CurrentUser = Depends(doctor_only),
    svc: OrderService = Depends(get_order_service),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    rx = svc.repo.prescription(rx_id)
    patient = svc.repo.user(str(rx.get("patientId"))) if rx else None
    if (
        rx is None
        or rx.get("source", PrescriptionSource.DOCTOR.value) != PrescriptionSource.DOCTOR.value
        or patient is None
        or patient.get("assignedDoctorId") != doctor.uid
    ):
        raise ApiError(
            "PRESCRIPTION_NOT_FOUND", "Prescription not found.", status.HTTP_404_NOT_FOUND
        )
    svc.repo.update_prescription(rx_id, {"isRecurring": body.isRecurring})
    audit.log(
        user_id=doctor.uid,
        action="SET_RECURRING",
        details=f"Prescription {'flagged' if body.isRecurring else 'no longer'} recurring.",
        target_type=Collection.PRESCRIPTIONS.value,
        target_id=rx_id,
    )
    order_id = None
    if body.isRecurring and svc.latest_cycle(rx_id) is None:
        order_id = svc.start_cycle(
            rx_id, {**rx, "isRecurring": True}, datetime.now(UTC), doctor.uid
        )
    return {"id": rx_id, "isRecurring": body.isRecurring, "orderId": order_id}


# ---------------- pharmacist: UC13.6 ----------------


@router.get("/pharmacy/queue")
def pharmacy_queue(
    _: CurrentUser = Depends(pharmacy_staff),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    orders = [
        _view(svc, i, fresh)
        for i, o in _newest_first(svc.repo.orders_with_status(PHARMACY_QUEUE))
        # A delivery the courier has just completed leaves the queue straight away.
        if (fresh := _fresh(svc, i, o)).get("fulfilmentStatus") in PHARMACY_QUEUE
    ]
    needs_price = []
    for rx in svc.repo.recurring_prescriptions():
        # Catalogue prescriptions carry their own prices (D-69).
        if rx.get("monthlyPrice") is None and not rx.get("items"):
            patient = svc.repo.user(str(rx.get("patientId"))) or {}
            needs_price.append(
                {
                    "id": rx["id"],
                    "patientId": rx.get("patientId"),
                    "patientName": patient.get("name"),
                    "medicationDetails": rx.get("medicationDetails"),
                }
            )
    return {"orders": orders, "needsPrice": needs_price}


@router.put("/pharmacy/prescriptions/{rx_id}/price")
def set_price(
    rx_id: str,
    body: PriceRequest,
    user: CurrentUser = Depends(pharmacist_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    try:
        updated = svc.set_price(rx_id, body.monthlyPrice, user.uid)
    except OrderError as e:
        raise _api(e) from e
    return {"id": rx_id, "monthlyPrice": round(body.monthlyPrice, 2), "ordersUpdated": updated}


@router.post("/pharmacy/orders/{order_id}/ready")
def mark_ready(
    order_id: str,
    body: ReadyRequest,
    user: CurrentUser = Depends(pharmacist_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    try:
        return _view(
            svc, order_id, svc.mark_ready(order_id, user.uid, body.stockItemId, body.units)
        )
    except OrderError as e:
        raise _api(e) from e


@router.post("/pharmacy/orders/{order_id}/out-of-stock", status_code=status.HTTP_204_NO_CONTENT)
def mark_out_of_stock(
    order_id: str,
    body: OutOfStockRequest,
    user: CurrentUser = Depends(pharmacist_only),
    svc: OrderService = Depends(get_order_service),
) -> None:
    try:
        svc.out_of_stock(order_id, user.uid, body.note)
    except OrderError as e:
        raise _api(e) from e


@router.post("/pharmacy/orders/{order_id}/cancel", status_code=status.HTTP_204_NO_CONTENT)
def cancel_order(
    order_id: str,
    body: CancelOrderRequest,
    user: CurrentUser = Depends(pharmacy_staff),
    svc: OrderService = Depends(get_order_service),
) -> None:
    """D-74: pharmacists and admins cancel an unpaid order with a reason."""
    role = user.role.value if user.role else "staff"
    try:
        svc.cancel(order_id, user.uid, role, body.reason)
    except OrderError as e:
        raise _api(e) from e


@router.post("/pharmacy/orders/{order_id}/collected", status_code=status.HTTP_204_NO_CONTENT)
def mark_collected(
    order_id: str,
    user: CurrentUser = Depends(pharmacist_only),
    svc: OrderService = Depends(get_order_service),
) -> None:
    try:
        svc.collected(order_id, user.uid)
    except OrderError as e:
        raise _api(e) from e


def _expiry(d: Any) -> datetime:
    return datetime.combine(d, time.min, tzinfo=MYT).astimezone(UTC)


@router.get("/pharmacy/stock")
def list_stock(
    _: CurrentUser = Depends(pharmacy_staff),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    items = [stock_view(i, s) for i, s in svc.repo.stock()]
    items.sort(key=lambda s: str(s["name"]).lower())
    return {"items": items}


@router.post("/pharmacy/stock", status_code=status.HTTP_201_CREATED)
def add_stock(
    body: StockRequest,
    user: CurrentUser = Depends(pharmacy_staff),
    svc: OrderService = Depends(get_order_service),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    data = {
        "name": body.name,
        "catalogId": body.catalogId,
        "units": body.units,
        "expiryDate": _expiry(body.expiryDate),
        "lowStockAt": body.lowStockAt,
        "updatedAt": datetime.now(UTC),
    }
    stock_id = svc.repo.add_stock(data)
    audit.log(
        user_id=user.uid,
        action="ADD_STOCK_ITEM",
        details=f"Stock item added: {body.name} ({body.units} units).",
        target_type=Collection.MEDICATION_STOCK.value,
        target_id=stock_id,
    )
    return stock_view(stock_id, data)


def _stock_or_404(svc: OrderService, stock_id: str) -> dict[str, Any]:
    s = svc.repo.stock_item(stock_id)
    if s is None:
        raise ApiError("STOCK_NOT_FOUND", "Stock item not found.", status.HTTP_404_NOT_FOUND)
    return s


@router.patch("/pharmacy/stock/{stock_id}")
def edit_stock(
    stock_id: str,
    body: StockEditRequest,
    user: CurrentUser = Depends(pharmacy_staff),
    svc: OrderService = Depends(get_order_service),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    s = _stock_or_404(svc, stock_id)
    update: dict[str, Any] = {
        k: v for k, v in body.model_dump(exclude_none=True).items() if k != "expiryDate"
    }
    if body.expiryDate is not None:
        update["expiryDate"] = _expiry(body.expiryDate)
    update["updatedAt"] = datetime.now(UTC)
    svc.repo.update_stock(stock_id, update)
    audit.log(
        user_id=user.uid,
        action="EDIT_STOCK_ITEM",
        details=f"Stock item edited: {', '.join(k for k in update if k != 'updatedAt')}.",
        target_type=Collection.MEDICATION_STOCK.value,
        target_id=stock_id,
    )
    return stock_view(stock_id, {**s, **update})


@router.post("/pharmacy/stock/{stock_id}/receive")
def receive_stock(
    stock_id: str,
    body: ReceiveStockRequest,
    user: CurrentUser = Depends(pharmacy_staff),
    svc: OrderService = Depends(get_order_service),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """'New Stock': add units; the item keeps its earliest expiry while old units remain."""
    s = _stock_or_404(svc, stock_id)
    units = int(s.get("units") or 0)
    new_expiry = _expiry(body.expiryDate)
    old_expiry = s.get("expiryDate")
    expiry = (
        min(old_expiry, new_expiry)
        if units > 0 and isinstance(old_expiry, datetime)
        else new_expiry
    )
    update = {"units": units + body.units, "expiryDate": expiry, "updatedAt": datetime.now(UTC)}
    svc.repo.update_stock(stock_id, update)
    audit.log(
        user_id=user.uid,
        action="RECEIVE_STOCK",
        details=f"{body.units} units received.",
        target_type=Collection.MEDICATION_STOCK.value,
        target_id=stock_id,
    )
    return stock_view(stock_id, {**s, **update})


@router.get("/pharmacy/patients")
def lookup_patients(
    q: str = "",
    _: CurrentUser = Depends(pharmacist_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    """Patients tab and lookup (Fig 4.3.13.1; D-70: every patient). Lists account details,
    the recurring regimen and order counts; the dispensing view has the rest."""
    term = q.strip().lower()
    regimen: dict[str, list[dict[str, Any]]] = {}
    for rx in svc.repo.recurring_prescriptions():
        regimen.setdefault(str(rx.get("patientId")), []).append(rx)
    orders: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    for i, o in svc.repo.all_orders():
        orders.setdefault(str(o.get("patientId")), []).append((i, o))
    out = []
    for uid, u in svc.repo.patients():
        hay = f"{u.get('name') or ''} {u.get('email') or ''} {u.get('icNumber') or ''} {uid}"
        if term and term not in hay.lower():
            continue
        mine = _newest_first(orders.get(uid, []))
        out.append(
            {
                "id": uid,
                "name": u.get("name"),
                "email": u.get("email"),
                "phone": u.get("phone"),
                "gender": u.get("gender"),
                "age": _age(u.get("dateOfBirth")),
                "isActive": u.get("isActive", True) is not False,
                "orderCount": len(mine),
                "activeOrders": sum(
                    1
                    for _, o in mine
                    if o.get("fulfilmentStatus") not in (DELIVERED, COLLECTED, SKIPPED)
                ),
                "regimen": [
                    {
                        "id": r["id"],
                        "medicationDetails": r.get("medicationDetails"),
                        "monthlyPrice": r.get("monthlyPrice"),
                    }
                    for r in regimen.get(uid, [])
                ],
                "recentOrders": [_view(svc, i, o) for i, o in mine[:5]],
            }
        )
    out.sort(key=lambda p: str(p["name"] or "").lower())
    return {"patients": out[:200]}


# ---------------- admin: FR-11.4 delivery oversight ----------------


@router.get("/admin/deliveries")
def admin_deliveries(
    _: CurrentUser = Depends(admin_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    seen: dict[str, dict[str, Any]] = {}
    for i, o in svc.repo.home_deliveries():
        if o.get("paymentStatus") == "paid":
            seen[i] = o
    for i, o in svc.repo.orders_with_status((OUT_OF_STOCK,)):
        seen[i] = o
    rows = [_view(svc, i, _fresh(svc, i, o)) for i, o in _newest_first(list(seen.items()))]
    # "simulated": the admin may fail a delivery on purpose (simulator or sandbox driver).
    return {"orders": rows, "courier": svc.courier.name, "simulated": svc.courier.demo_failures}


@router.post("/admin/deliveries/{order_id}/dispatch")
def admin_dispatch(
    order_id: str,
    user: CurrentUser = Depends(admin_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    """Manual dispatch (Fig 4.3.14.4): a failed delivery, or one stuck before dispatch."""
    o = svc.repo.order(order_id)
    if o is None:
        raise _not_found()
    stuck = o.get("fulfilmentStatus") == READY_FOR_DELIVERY and not o.get("dispatchedAt")
    if o.get("fulfilmentStatus") != FAILED and not stuck:
        raise ApiError(
            "ORDER_NOT_DISPATCHABLE",
            "Only failed or undispatched deliveries can be dispatched manually.",
            status.HTTP_409_CONFLICT,
        )
    return _view(
        svc,
        order_id,
        svc.dispatch(order_id, {**o, "fulfilmentStatus": READY_FOR_DELIVERY}, user.uid),
    )


@router.post("/admin/deliveries/{order_id}/simulate-failure")
def admin_simulate_failure(
    order_id: str,
    body: FailDeliveryRequest,
    user: CurrentUser = Depends(admin_only),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    """Demo of FR-13.5 with the simulator or a sandbox courier without drivers (D-68)."""
    if not svc.courier.demo_failures:
        raise ApiError("NOT_FOUND", "Not available.", status.HTTP_404_NOT_FOUND)
    o = svc.repo.order(order_id)
    if o is None or o.get("fulfilmentStatus") != READY_FOR_DELIVERY or not o.get("dispatchedAt"):
        raise ApiError(
            "ORDER_NOT_IN_DELIVERY", "This order isn't out for delivery.", status.HTTP_409_CONFLICT
        )
    return _view(svc, order_id, svc.fail_delivery(order_id, o, body.reason, user.uid))


# ---------------- webhooks ----------------


@router.post("/webhooks/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: str | None = Header(default=None),
    svc: OrderService = Depends(get_order_service),
    gateway: PaymentGateway = Depends(get_payment_gateway),
) -> dict[str, Any]:
    payload = await request.body()
    try:
        event = gateway.parse_webhook(payload, stripe_signature)
    except (WebhookSignatureError, json.JSONDecodeError) as e:
        raise ApiError("BAD_SIGNATURE", "Webhook not verified.", status.HTTP_400_BAD_REQUEST) from e
    if event.get("type") not in ("payment_intent.succeeded", "payment_intent.payment_failed"):
        return {"received": True, "handled": False}
    obj = event.get("data", {}).get("object", {})
    order_id = (obj.get("metadata") or {}).get("orderId")
    if not order_id or svc.repo.order(str(order_id)) is None:
        return {"received": True, "handled": False}
    try:
        result = svc.record_payment(str(order_id), intent_from_stripe(obj))
    except OrderError:
        return {"received": True, "handled": False}
    return {"received": True, "handled": True, "result": result}


@router.post("/webhooks/grab")
def grab_webhook(
    body: GrabWebhook,
    authorization: str | None = Header(default=None),
    svc: OrderService = Depends(get_order_service),
    settings: Settings = Depends(get_settings),
) -> dict[str, Any]:
    """GrabExpress tracking webhook (UC13.5; D-67). Grab sends the token key configured for
    this endpoint in the Authorization header; anything else is refused."""
    secret = settings.grab_webhook_secret
    sent = (authorization or "").removeprefix("Bearer ").strip()
    if not secret or not sent or not hmac.compare_digest(secret, sent):
        raise ApiError("FORBIDDEN", "Webhook not verified.", status.HTTP_403_FORBIDDEN)
    order_id = order_id_from_merchant(body.merchantOrderID)
    o = svc.repo.order(order_id)
    if o is None or o.get("courierRef") != body.deliveryID:
        # An old attempt (rescheduled since) or an unknown order: acknowledge and ignore.
        return {"received": True, "changed": 0}
    changed = 0
    for u in grab_updates(body.status, datetime.now(UTC), body.failedReason):
        if svc.courier_update(order_id, o, u.status, u.at, u.location):
            changed += 1
    return {"received": True, "changed": changed}


@router.post("/webhooks/lalamove")
async def lalamove_webhook(
    request: Request,
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    """Lalamove order webhook (UC13.5; D-68). Only the Lalamove order id is taken from the
    payload; the status is then read from Lalamove with a signed request, so a forged call
    can't change an order. Lalamove needs a 200 reply, also for its set-up test call."""
    try:
        payload = await request.json()
    except ValueError:
        return {"received": True, "changed": 0}
    event = payload.get("eventType") if isinstance(payload, dict) else None
    found = None
    refs = _order_ids(payload)
    for ref in refs:
        found = svc.repo.order_by_courier_ref(ref)
        if found is not None:
            break
    # Ids only (no personal data), so the real payload shape can be checked in the logs.
    log.info("Lalamove webhook %s, ids %s, matched %s", event, refs[:3], found is not None)
    if found is None:
        return {"received": True, "changed": 0}
    order_id, o = found
    return {"received": True, "changed": svc.advance(order_id, o)}


def _order_ids(payload: Any, depth: int = 0) -> list[str]:
    """Every value under a key named orderId (any case, any depth) in a Lalamove webhook."""
    if depth > 5:
        return []
    found: list[str] = []
    if isinstance(payload, dict):
        for k, v in payload.items():
            if str(k).lower() == "orderid" and isinstance(v, str | int) and str(v):
                found.append(str(v))
            else:
                found += _order_ids(v, depth + 1)
    elif isinstance(payload, list):
        for v in payload:
            found += _order_ids(v, depth + 1)
    return found


# ---------------- D-69: pharmacist patient view ----------------


def _age(dob: Any) -> int | None:
    if not isinstance(dob, datetime):
        return None
    today = datetime.now(UTC).astimezone(MYT).date()
    born = dob.astimezone(MYT).date()
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


@router.get("/pharmacy/patients/{patient_id}")
def pharmacy_patient(
    patient_id: str,
    user: CurrentUser = Depends(pharmacist_only),
    svc: OrderService = Depends(get_order_service),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """Dispensing details for a patient (D-69, D-70: any patient): profile, allergies and
    conditions, medicines, prescriptions and orders. No readings, risk, notes or files."""
    from app.services.settings import parse_profile_field

    u = svc.repo.user(patient_id)  # D-70: any patient
    if u is None or u.get("role") != UserRole.PATIENT.value:
        raise ApiError("PATIENT_NOT_FOUND", "Patient not found.", status.HTTP_404_NOT_FOUND)
    profile = svc.repo.health_profile(patient_id) or {}
    history = parse_profile_field(profile.get("medicalHistory"))
    meds = svc.medications.list_for(patient_id) if svc.medications else []
    orders = _newest_first(svc.repo.orders_for_patient(patient_id))
    prescriptions = sorted(
        svc.repo.prescriptions_for(patient_id),
        key=lambda r: r.get("issuedAt") or datetime.min.replace(tzinfo=UTC),
        reverse=True,
    )
    audit.log(
        user_id=user.uid,
        action="VIEW_PATIENT_DISPENSING",
        details="Pharmacist opened a patient's dispensing details.",
        target_type=Collection.USERS.value,
        target_id=patient_id,
    )
    return {
        "id": patient_id,
        "name": u.get("name"),
        "email": u.get("email"),
        "phone": svc.repo.profile_phone(patient_id),
        "gender": u.get("gender"),
        "age": _age(u.get("dateOfBirth")),
        "address": u.get("address"),
        "allergies": history.get("allergies") or "",
        "conditions": history.get("conditions") or [],
        "medications": [
            {
                "id": m.id,
                "name": m.data.get("name"),
                "dosage": m.data.get("dosage"),
                "schedule": m.data.get("schedule"),
                "quantityOnHand": m.data.get("quantityOnHand"),
                "source": m.data.get("source") or "patient",
                "prescribedBy": m.data.get("prescribedBy"),
            }
            for m in meds
        ],
        "prescriptions": [
            {
                "id": r["id"],
                "medicationDetails": r.get("medicationDetails"),
                "items": r.get("items") or [],
                "isRecurring": bool(r.get("isRecurring")),
                "source": r.get("source"),
                "issuedAt": r["issuedAt"].isoformat()
                if isinstance(r.get("issuedAt"), datetime)
                else None,
            }
            for r in prescriptions
        ],
        "orders": [_view(svc, i, o) for i, o in orders],
    }


# ---------------- D-69: medication catalogue ----------------


@router.get("/catalog")
def list_catalog(
    _: CurrentUser = Depends(require_roles(UserRole.DOCTOR, UserRole.PHARMACIST, UserRole.ADMIN)),
    catalog: CatalogRepository = Depends(get_catalog_repository),
) -> dict[str, Any]:
    items = [catalog_view(i, c) for i, c in catalog.all()]
    items.sort(key=lambda c: (str(c["name"]).lower(), str(c["strength"])))
    return {"items": items}


@router.post("/catalog", status_code=status.HTTP_201_CREATED)
def add_catalog_item(
    body: CatalogItemRequest,
    user: CurrentUser = Depends(pharmacy_staff),
    catalog: CatalogRepository = Depends(get_catalog_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    data = {
        "name": body.name,
        "strength": body.strength,
        "form": body.form,
        "unitLabel": body.form,
        "drugClass": body.drugClass,
        "unitPrice": round(body.unitPrice, 2),
        "active": True,
        "updatedAt": datetime.now(UTC),
    }
    item_id = catalog.create(data)
    audit.log(
        user_id=user.uid,
        action="ADD_CATALOG_ITEM",
        details=f"Catalogue medicine added: {body.name} {body.strength}.",
        target_type=Collection.MEDICATION_CATALOG.value,
        target_id=item_id,
    )
    return catalog_view(item_id, data)


@router.patch("/catalog/{item_id}")
def edit_catalog_item(
    item_id: str,
    body: CatalogEditRequest,
    user: CurrentUser = Depends(pharmacy_staff),
    catalog: CatalogRepository = Depends(get_catalog_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    c = catalog.get(item_id)
    if c is None:
        raise ApiError("CATALOG_ITEM_NOT_FOUND", "Medicine not found.", status.HTTP_404_NOT_FOUND)
    update: dict[str, Any] = {"updatedAt": datetime.now(UTC)}
    if body.unitPrice is not None:
        update["unitPrice"] = round(body.unitPrice, 2)
    if body.active is not None:
        update["active"] = body.active
    for field in ("name", "strength", "drugClass", "form"):  # D-70
        value = getattr(body, field)
        if value is not None:
            update[field] = value
            if field == "form":
                update["unitLabel"] = value
    catalog.update(item_id, update)
    audit.log(
        user_id=user.uid,
        action="EDIT_CATALOG_ITEM",
        details="Catalogue medicine updated"
        + (f"; price RM{body.unitPrice:.2f}" if body.unitPrice is not None else "")
        + ("" if body.active is None else f"; {'active' if body.active else 'inactive'}")
        + ".",
        target_type=Collection.MEDICATION_CATALOG.value,
        target_id=item_id,
    )
    return catalog_view(item_id, {**c, **update})


# ---------------- D-70: order tracking and inventory CRUD ----------------

ORDER_GROUPS: dict[str, tuple[str, ...]] = {
    "awaiting_patient": (AWAITING_CONFIRMATION, AWAITING_PAYMENT, SKIPPED),
    "in_pharmacy": (PREPARING, OUT_OF_STOCK, READY_FOR_COLLECTION),
    "out_for_delivery": (READY_FOR_DELIVERY,),
    "completed": (DELIVERED, COLLECTED),
    "failed": (FAILED,),
    "cancelled": (CANCELLED,),  # D-74
}


@router.get("/orders-overview")
def orders_overview(
    group: str = "all",
    q: str = "",
    _: CurrentUser = Depends(pharmacy_staff),
    svc: OrderService = Depends(get_order_service),
) -> dict[str, Any]:
    """Every order with its status for pharmacists and admins (D-70 Tracking / Orders tabs),
    newest first; [group] narrows to one stage, [q] matches patient, medicine or ref."""
    wanted = ORDER_GROUPS.get(group)
    term = q.strip().lower()
    rows = []
    counts = {g: 0 for g in ORDER_GROUPS}
    for i, o in _newest_first(svc.repo.all_orders()):
        o = _fresh(svc, i, o)
        status_ = o.get("fulfilmentStatus")
        for g, members in ORDER_GROUPS.items():
            if status_ in members:
                counts[g] += 1
        if wanted is not None and status_ not in wanted:
            continue
        view = _view(svc, i, o)
        hay = f"{view['ref']} {o.get('patientName') or ''} {o.get('medicationDetails') or ''}"
        if term and term not in hay.lower():
            continue
        rows.append(view)
    return {"orders": rows[:300], "counts": counts}


@router.delete("/pharmacy/stock/{stock_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_stock(
    stock_id: str,
    user: CurrentUser = Depends(admin_only),
    svc: OrderService = Depends(get_order_service),
    audit: AuditLogger = Depends(get_audit_logger),
) -> None:
    """D-70: only admins delete stock items."""
    s = _stock_or_404(svc, stock_id)
    svc.repo.delete_stock(stock_id)
    audit.log(
        user_id=user.uid,
        action="DELETE_STOCK_ITEM",
        details=f"Stock item deleted: {s.get('name')}.",
        target_type=Collection.MEDICATION_STOCK.value,
        target_id=stock_id,
    )


# ---------------- D-72: courier settings (read-only) ----------------


@router.get("/admin/courier")
def courier_settings(
    _: CurrentUser = Depends(admin_only),
    svc: OrderService = Depends(get_order_service),
    settings: Settings = Depends(get_settings),
) -> dict[str, Any]:
    """The delivery partner as configured on the server (keys stay in Secret Manager)."""
    courier = svc.courier
    return {
        "provider": courier.brand,
        "name": courier.name,
        "simulated": courier.simulated,
        "sandbox": not courier.simulated,
        "pickupAddress": settings.pharmacy_address or None,
        "pickupLat": settings.pharmacy_lat,
        "pickupLng": settings.pharmacy_lng,
        "pickupPhone": settings.pharmacy_phone or None,
        "webhookUrl": f"{settings.public_base_url}/api/v1/webhooks/"
        + ("grab" if courier.brand == "Grab" else "lalamove"),
        "keysConfigured": not courier.simulated,
    }
