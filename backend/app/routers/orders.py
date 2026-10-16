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
from datetime import UTC, datetime, time
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
    ConfirmOrderRequest,
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
from app.services.medications import MYT
from app.services.orders import (
    AWAITING_PAYMENT,
    FAILED,
    OUT_OF_STOCK,
    PHARMACY_QUEUE,
    READY_FOR_DELIVERY,
    OrderError,
    OrderService,
    get_order_service,
    stock_view,
    total_of,
)
from app.services.orders import order_view as _order_view

router = APIRouter(tags=["orders"])

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


def _fresh(
    svc: OrderService, order_id: str, o: dict[str, Any], single: bool = False
) -> dict[str, Any]:
    """Applies courier progress before showing the order. Lists only do this for the
    simulator; with Grab each order is one API call, so only the order screen polls."""
    if o.get("fulfilmentStatus") == READY_FOR_DELIVERY and (single or svc.courier.poll_in_lists):
        svc.advance(order_id, o)
        o = svc.repo.order(order_id) or o
    return o


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
    if user.role == UserRole.PATIENT:  # D-67: prefill the courier contact number
        view["suggestedPhone"] = o.get("deliveryPhone") or svc.repo.profile_phone(user.uid)
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
        _view(svc, i, _fresh(svc, i, o))
        for i, o in _newest_first(svc.repo.orders_with_status(PHARMACY_QUEUE))
    ]
    needs_price = []
    for rx in svc.repo.recurring_prescriptions():
        if rx.get("monthlyPrice") is None:
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
    user: CurrentUser = Depends(pharmacist_only),
    svc: OrderService = Depends(get_order_service),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    data = {
        "name": body.name,
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
    user: CurrentUser = Depends(pharmacist_only),
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
    user: CurrentUser = Depends(pharmacist_only),
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
    """Patient lookup (Fig 4.3.13.1), limited to patients the pharmacy serves: those with a
    recurring prescription. Shows the regimen and recent orders, not clinical data."""
    term = q.strip().lower()
    by_patient: dict[str, list[dict[str, Any]]] = {}
    for rx in svc.repo.recurring_prescriptions():
        by_patient.setdefault(str(rx.get("patientId")), []).append(rx)
    out = []
    for uid, rxs in by_patient.items():
        u = svc.repo.user(uid) or {}
        hay = f"{u.get('name') or ''} {u.get('email') or ''} {uid}".lower()
        if term and term not in hay:
            continue
        orders = _newest_first(svc.repo.orders_for_patient(uid))[:5]
        out.append(
            {
                "id": uid,
                "name": u.get("name"),
                "email": u.get("email"),
                "phone": u.get("phone"),
                "regimen": [
                    {
                        "id": r["id"],
                        "medicationDetails": r.get("medicationDetails"),
                        "monthlyPrice": r.get("monthlyPrice"),
                    }
                    for r in rxs
                ],
                "recentOrders": [_view(svc, i, o) for i, o in orders],
            }
        )
    out.sort(key=lambda p: str(p["name"] or "").lower())
    return {"patients": out[:20]}


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
    data = payload.get("data") if isinstance(payload, dict) else None
    order = data.get("order") if isinstance(data, dict) else None
    ref = (order or {}).get("orderId") if isinstance(order, dict) else None
    ref = ref or (data or {}).get("orderId") if isinstance(data, dict) else ref
    found = svc.repo.order_by_courier_ref(str(ref)) if ref else None
    if found is None:
        return {"received": True, "changed": 0}
    order_id, o = found
    return {"received": True, "changed": svc.advance(order_id, o)}
