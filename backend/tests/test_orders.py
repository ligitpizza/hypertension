"""Module 13: recurring orders, payment and delivery (FR-13.1-13.5; UC13.1-UC13.6; D-66)."""

import hashlib
import hmac
import json
import time
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.delivery import STAGE, FakeGrabClient
from app.integrations.payments import (
    PaymentError,
    StripeGateway,
    WebhookSignatureError,
    intent_from_stripe,
    verify_stripe_signature,
)
from app.integrations.push import LogPushClient
from app.services.orders import add_month, order_id_for
from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryFileStore,
    InMemoryOrderRepository,
    InMemoryProviderRepository,
    InMemoryRecordRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
    dev_settings,
)

P, D, PH, A = "u-patient", "u-doctor", "u-pharm", "u-admin"
# D-67: home delivery needs the address, the phone's location and a contact number.
HOME = {
    "deliveryAddress": "12 Jalan Ampang, KL",
    "deliveryLat": 3.1579,
    "deliveryLng": 101.7123,
    "deliveryPhone": "012-345 6789",
}
PATIENT, DOCTOR, PHARM, ADMIN = (
    bearer("patient-token"),
    bearer("doctor-token"),
    bearer("pharmacist-token"),
    bearer("admin-token"),
)


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users.update(
        {
            P: {"role": "patient", "name": "Siti", "assignedDoctorId": D},
            D: {"role": "doctor", "name": "Dr Tan"},
            PH: {"role": "pharmacist", "name": "Ahmad"},
            A: {"role": "admin", "name": "Admin"},
        }
    )
    for uid in (P, PH, A):
        tokens.add(uid, f"token-{uid}", "android")


def titles(push: LogPushClient, uid: str) -> list[str]:
    return [m.title for toks, m in push.sent if f"token-{uid}" in toks]


def issue(client: TestClient, recurring: bool = True) -> str:
    res = client.post(
        f"/api/v1/provider/patients/{P}/prescriptions",
        json={
            "medicationName": "Amlodipine",
            "dosage": "5mg",
            "frequency": "once daily",
            "isRecurring": recurring,
        },
        headers=DOCTOR,
    )
    assert res.status_code == 201, res.text
    return str(res.json()["id"])


def only_order(order_repo: InMemoryOrderRepository) -> str:
    assert len(order_repo.orders) == 1
    return next(iter(order_repo.orders))


def priced_order(client: TestClient, order_repo: InMemoryOrderRepository) -> str:
    rx = issue(client)
    assert (
        client.put(
            f"/api/v1/pharmacy/prescriptions/{rx}/price", json={"monthlyPrice": 15}, headers=PHARM
        ).status_code
        == 200
    )
    return only_order(order_repo)


def paid_order(
    client: TestClient,
    order_repo: InMemoryOrderRepository,
    method: str = "self_collection",
) -> str:
    oid = priced_order(client, order_repo)
    body: dict[str, Any] = {"method": method}
    if method == "home_delivery":
        body.update(HOME)
    assert (
        client.post(f"/api/v1/orders/{oid}/confirm", json=body, headers=PATIENT).status_code == 200
    )
    assert client.post(f"/api/v1/orders/{oid}/pay", headers=PATIENT).status_code == 200
    res = client.post(
        f"/api/v1/orders/{oid}/pay/fake",
        json={"cardNumber": "4242 4242 4242 4242"},
        headers=PATIENT,
    )
    assert res.json()["result"] == "paid"
    return oid


def add_stock(client: TestClient, units: int = 100) -> str:
    res = client.post(
        "/api/v1/pharmacy/stock",
        json={"name": "Amlodipine 5mg", "units": units, "expiryDate": "2027-06-30"},
        headers=PHARM,
    )
    assert res.status_code == 201, res.text
    return str(res.json()["id"])


# ---------------- UC13.1 / UC13.2 cycle ----------------


def test_uc13_1_recurring_prescription_starts_an_unpriced_order(
    client: TestClient, order_repo: InMemoryOrderRepository, push: LogPushClient
) -> None:
    rx = issue(client)
    oid = only_order(order_repo)
    assert oid.startswith(f"{rx}_")
    o = order_repo.orders[oid]
    assert o["paymentStatus"] == "pending"
    assert o["fulfilmentStatus"] == "awaiting_confirmation"
    assert o["method"] is None and o["amount"] is None
    assert "Confirm this month's order" in titles(push, P)
    assert "Recurring prescription needs a price" in titles(push, PH)
    queue = client.get("/api/v1/pharmacy/queue", headers=PHARM).json()
    assert [r["id"] for r in queue["needsPrice"]] == [rx]


def test_non_recurring_prescription_makes_no_order(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    issue(client, recurring=False)
    assert order_repo.orders == {}


def test_uc13_1_doctor_toggles_recurring_later(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    rx = issue(client, recurring=False)
    res = client.post(
        f"/api/v1/prescriptions/{rx}/recurring", json={"isRecurring": True}, headers=DOCTOR
    )
    assert res.status_code == 200 and res.json()["orderId"]
    # Toggling again doesn't start a second order this month.
    client.post(
        f"/api/v1/prescriptions/{rx}/recurring", json={"isRecurring": False}, headers=DOCTOR
    )
    client.post(f"/api/v1/prescriptions/{rx}/recurring", json={"isRecurring": True}, headers=DOCTOR)
    assert len(order_repo.orders) == 1


def test_only_the_assigned_doctor_toggles_recurring(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    rx = issue(client, recurring=False)
    repo.users[P]["assignedDoctorId"] = "someone-else"
    res = client.post(
        f"/api/v1/prescriptions/{rx}/recurring", json={"isRecurring": True}, headers=DOCTOR
    )
    assert res.status_code == 404


def test_price_unblocks_the_order_and_tells_the_patient(
    client: TestClient, order_repo: InMemoryOrderRepository, push: LogPushClient
) -> None:
    rx = issue(client)
    oid = only_order(order_repo)
    res = client.post(
        f"/api/v1/orders/{oid}/confirm", json={"method": "self_collection"}, headers=PATIENT
    )
    assert res.status_code == 409 and res.json()["error"]["code"] == "ORDER_NOT_PRICED"
    res = client.put(
        f"/api/v1/pharmacy/prescriptions/{rx}/price", json={"monthlyPrice": 12.5}, headers=PHARM
    )
    assert res.json()["ordersUpdated"] == 1
    assert order_repo.orders[oid]["amount"] == 12.5
    assert "Your monthly order is ready to confirm" in titles(push, P)


def test_price_is_pharmacist_only_and_at_least_rm2(client: TestClient) -> None:
    rx = issue(client)
    url = f"/api/v1/pharmacy/prescriptions/{rx}/price"
    assert client.put(url, json={"monthlyPrice": 10}, headers=DOCTOR).status_code == 403
    assert client.put(url, json={"monthlyPrice": 1.5}, headers=PHARM).status_code == 422


def test_monthly_cycle_and_48h_reminder(
    order_repo: InMemoryOrderRepository,
    provider_repo: InMemoryProviderRepository,
    tokens: InMemoryTokenRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    from app.services.notifications import Notifier
    from app.services.orders import OrderService

    provider_repo.prescriptions.append(
        {"id": "rx9", "patientId": P, "isRecurring": True, "medicationDetails": "Losartan 50mg"}
    )
    svc = OrderService(order_repo, Notifier(tokens, push), FakeGrabClient(), audit)
    start = datetime(2026, 1, 31, 2, tzinfo=UTC)  # 10:00 Malaysia time
    assert svc.run(start)["ordersCreated"] == 1  # first cycle for an existing prescription
    assert svc.run(start + timedelta(days=1))["ordersCreated"] == 0
    first = order_id_for("rx9", start)
    order_repo.orders[first]["createdAt"] = start
    assert svc.run(start + timedelta(hours=47))["orderReminders"] == 0
    assert svc.run(start + timedelta(hours=48))["orderReminders"] == 1
    assert svc.run(start + timedelta(hours=60))["orderReminders"] == 0  # once only
    # Next cycle: same day next month, clamped to 28 Feb.
    feb = add_month(start)
    assert feb.astimezone(UTC).day == 28
    assert svc.run(feb - timedelta(minutes=1))["ordersCreated"] == 0
    assert svc.run(feb)["ordersCreated"] == 1
    assert order_id_for("rx9", feb) in order_repo.orders


def test_uc13_2_a1_skip_then_change_of_mind(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = priced_order(client, order_repo)
    assert client.post(f"/api/v1/orders/{oid}/skip", headers=PATIENT).status_code == 204
    assert order_repo.orders[oid]["fulfilmentStatus"] == "skipped"
    res = client.post(
        f"/api/v1/orders/{oid}/confirm", json={"method": "self_collection"}, headers=PATIENT
    )
    assert res.json()["fulfilmentStatus"] == "awaiting_payment"


def test_dev_next_cycle_is_off_by_default(
    client: TestClient, make_client: Any, order_repo: InMemoryOrderRepository
) -> None:
    issue(client)
    assert client.post("/api/v1/orders/dev/next-cycle", headers=PATIENT).status_code == 404
    dev = make_client(dev_settings(dev_order_tools=True))
    res = dev.post("/api/v1/orders/dev/next-cycle", headers=PATIENT)
    assert len(res.json()["created"]) == 1 and len(order_repo.orders) == 2


# ---------------- UC13.3 confirm + pay ----------------


def test_uc13_3_home_delivery_needs_an_address_and_adds_the_fee(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = priced_order(client, order_repo)
    url = f"/api/v1/orders/{oid}/confirm"
    res = client.post(url, json={"method": "home_delivery"}, headers=PATIENT)
    assert res.json()["error"]["code"] == "ADDRESS_REQUIRED"
    no_gps = {"method": "home_delivery", "deliveryAddress": "12 Jalan Ampang"}
    res = client.post(url, json=no_gps, headers=PATIENT)
    assert res.json()["error"]["code"] == "LOCATION_REQUIRED"
    res = client.post(
        url, json={**no_gps, "deliveryLat": 3.15, "deliveryLng": 101.71}, headers=PATIENT
    )
    assert res.json()["error"]["code"] == "PHONE_REQUIRED"
    res = client.post(url, json={"method": "home_delivery", **HOME}, headers=PATIENT)
    assert res.json()["total"] == 20.0 and res.json()["deliveryFee"] == 5.0
    assert res.json()["deliveryLat"] == 3.1579 and res.json()["deliveryPhone"] == "012-345 6789"


def test_d67_contact_number_is_prefilled_from_the_profile(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = priced_order(client, order_repo)
    order_repo.phones[P] = "0123456789"
    assert client.get(f"/api/v1/orders/{oid}", headers=PATIENT).json()["suggestedPhone"] == (
        "0123456789"
    )
    assert "suggestedPhone" not in client.get(f"/api/v1/orders/{oid}", headers=PHARM).json()


def test_patients_only_see_their_own_orders(
    client: TestClient, order_repo: InMemoryOrderRepository, repo: InMemoryUserRepository
) -> None:
    oid = priced_order(client, order_repo)
    order_repo.orders[oid]["patientId"] = "u-other"
    assert client.get(f"/api/v1/orders/{oid}", headers=PATIENT).status_code == 404
    assert client.get("/api/v1/orders", headers=PATIENT).json()["orders"] == []
    assert client.get(f"/api/v1/orders/{oid}", headers=PHARM).status_code == 200


def test_uc13_3_payment_writes_transaction_receipt_and_notifies_pharmacist(
    client: TestClient,
    order_repo: InMemoryOrderRepository,
    record_repo: InMemoryRecordRepository,
    file_store: InMemoryFileStore,
    push: LogPushClient,
) -> None:
    oid = paid_order(client, order_repo)
    o = order_repo.orders[oid]
    assert o["paymentStatus"] == "paid" and o["fulfilmentStatus"] == "preparing"
    (tx,) = order_repo.transactions.values()
    assert tx["orderId"] == oid and tx["amount"] == 15.0 and tx["status"] == "succeeded"
    assert tx["stripeChargeId"].startswith("ch_fake_")
    record = record_repo.records[o["receiptRecordId"]]
    assert record["category"] == "other" and record["contentType"] == "application/pdf"
    assert file_store.files[record["fileUrl"]][0].startswith(b"%PDF")
    assert "New paid order" in titles(push, PH)
    # Paying twice is refused.
    assert client.post(f"/api/v1/orders/{oid}/pay", headers=PATIENT).status_code == 409


def test_uc13_3_e1_declined_card_can_retry(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = priced_order(client, order_repo)
    client.post(
        f"/api/v1/orders/{oid}/confirm", json={"method": "self_collection"}, headers=PATIENT
    )
    first = client.post(f"/api/v1/orders/{oid}/pay", headers=PATIENT).json()
    assert first["mode"] == "fake" and first["amount"] == 15.0
    res = client.post(
        f"/api/v1/orders/{oid}/pay/fake", json={"cardNumber": "4000000000000002"}, headers=PATIENT
    ).json()
    assert res["result"] == "failed" and res["message"] == "Your card was declined."
    assert order_repo.orders[oid]["paymentStatus"] == "failed"
    again = client.post(f"/api/v1/orders/{oid}/pay", headers=PATIENT).json()
    assert again["paymentIntentId"] == first["paymentIntentId"]  # same intent reused
    res = client.post(
        f"/api/v1/orders/{oid}/pay/fake", json={"cardNumber": "4242424242424242"}, headers=PATIENT
    ).json()
    assert res["result"] == "paid"
    statuses = sorted(t["status"] for t in order_repo.transactions.values())
    assert statuses == ["failed", "succeeded"]


def test_fake_card_form_is_unavailable_with_real_stripe(
    make_client: Any, order_repo: InMemoryOrderRepository
) -> None:
    from app.integrations.payments import get_payment_gateway

    client = make_client()
    client.app.dependency_overrides[get_payment_gateway] = lambda: StripeGateway(
        "sk_test_x", "pk_test_x", "whsec_x"
    )
    oid = priced_order(client, order_repo)
    res = client.post(
        f"/api/v1/orders/{oid}/pay/fake", json={"cardNumber": "4242424242424242"}, headers=PATIENT
    )
    assert res.status_code == 404


# ---------------- Stripe adapter ----------------


def test_only_stripe_test_keys_are_accepted() -> None:
    with pytest.raises(PaymentError):
        StripeGateway("sk_live_x", "pk_live_x", "whsec")
    StripeGateway("sk_test_x", "pk_test_x", "whsec")


def _sign(payload: bytes, secret: str, stamp: int) -> str:
    sig = hmac.new(secret.encode(), f"{stamp}.".encode() + payload, hashlib.sha256).hexdigest()
    return f"t={stamp},v1={sig}"


def test_stripe_signature_verification() -> None:
    body, secret, now = b'{"id":"evt"}', "whsec_test", int(time.time())
    verify_stripe_signature(body, _sign(body, secret, now), secret, now)
    for bad in (None, "t=1", _sign(body, "other", now), _sign(b"tampered", secret, now)):
        with pytest.raises(WebhookSignatureError):
            verify_stripe_signature(body, bad, secret, now)
    with pytest.raises(WebhookSignatureError):  # replayed too late
        verify_stripe_signature(body, _sign(body, secret, now - 600), secret, now)


def test_stripe_intent_mapping() -> None:
    ok = intent_from_stripe(
        {"id": "pi_1", "status": "succeeded", "latest_charge": "ch_1", "amount": 2000}
    )
    assert ok.status == "succeeded" and ok.charge_id == "ch_1" and ok.amount_sen == 2000
    declined = intent_from_stripe(
        {
            "id": "pi_1",
            "status": "requires_payment_method",
            "last_payment_error": {"message": "Your card was declined."},
        }
    )
    assert declined.status == "failed" and declined.decline_message == "Your card was declined."
    assert intent_from_stripe({"id": "pi_1", "status": "requires_payment_method"}).status == (
        "pending"
    )


def test_stripe_webhook_marks_the_order_paid(
    make_client: Any, order_repo: InMemoryOrderRepository
) -> None:
    from app.integrations.payments import get_payment_gateway

    client = make_client()
    oid = priced_order(client, order_repo)
    client.post(
        f"/api/v1/orders/{oid}/confirm", json={"method": "self_collection"}, headers=PATIENT
    )
    secret = "whsec_test"
    client.app.dependency_overrides[get_payment_gateway] = lambda: StripeGateway(
        "sk_test_x", "pk_test_x", secret
    )
    event = {
        "type": "payment_intent.succeeded",
        "data": {
            "object": {
                "id": "pi_123",
                "status": "succeeded",
                "latest_charge": "ch_123",
                "amount": 1500,
                "metadata": {"orderId": oid},
            }
        },
    }
    body = json.dumps(event).encode()
    res = client.post(
        "/api/v1/webhooks/stripe",
        content=body,
        headers={"Stripe-Signature": _sign(body, secret, int(time.time()))},
    )
    assert res.json() == {"received": True, "handled": True, "result": "paid"}
    assert order_repo.orders[oid]["paymentStatus"] == "paid"
    assert order_repo.transactions["ch_123"]["amount"] == 15.0
    # Stripe retries deliveries: a repeat changes nothing.
    client.post(
        "/api/v1/webhooks/stripe",
        content=body,
        headers={"Stripe-Signature": _sign(body, secret, int(time.time()))},
    )
    assert len(order_repo.transactions) == 1
    bad = client.post("/api/v1/webhooks/stripe", content=body, headers={"Stripe-Signature": "x"})
    assert bad.status_code == 400


# ---------------- UC13.6 pharmacist ----------------


def test_uc13_6_ready_for_collection_takes_stock(
    client: TestClient, order_repo: InMemoryOrderRepository, push: LogPushClient
) -> None:
    oid = paid_order(client, order_repo)
    stock = add_stock(client, units=40)
    queue = client.get("/api/v1/pharmacy/queue", headers=PHARM).json()
    assert [o["id"] for o in queue["orders"]] == [oid]
    res = client.post(
        f"/api/v1/pharmacy/orders/{oid}/ready",
        json={"stockItemId": stock, "units": 30},
        headers=PHARM,
    )
    assert res.json()["fulfilmentStatus"] == "ready_for_collection"
    assert order_repo.orders[oid]["pharmacistId"] == PH
    item = client.get("/api/v1/pharmacy/stock", headers=PHARM).json()["items"][0]
    assert item["units"] == 10 and item["low"] is True
    assert "Ready for collection" in titles(push, P)
    assert client.post(f"/api/v1/pharmacy/orders/{oid}/collected", headers=PHARM).status_code == 204
    assert order_repo.orders[oid]["fulfilmentStatus"] == "collected"


def test_not_enough_stock_is_refused(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = paid_order(client, order_repo)
    stock = add_stock(client, units=5)
    res = client.post(
        f"/api/v1/pharmacy/orders/{oid}/ready",
        json={"stockItemId": stock, "units": 30},
        headers=PHARM,
    )
    assert res.json()["error"]["code"] == "INSUFFICIENT_STOCK"
    assert order_repo.stock_items[stock]["units"] == 5


def test_uc13_6_e1_out_of_stock_flags_admin_and_tells_patient(
    client: TestClient,
    order_repo: InMemoryOrderRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    oid = paid_order(client, order_repo)
    res = client.post(
        f"/api/v1/pharmacy/orders/{oid}/out-of-stock",
        json={"note": "Supplier delay"},
        headers=PHARM,
    )
    assert res.status_code == 204
    assert order_repo.orders[oid]["fulfilmentStatus"] == "out_of_stock"
    assert "Medicine out of stock" in titles(push, A)
    assert "Your order is delayed" in titles(push, P)
    assert any(e["action"] == "ORDER_OUT_OF_STOCK" for e in audit.entries)
    flagged = client.get("/api/v1/admin/deliveries", headers=ADMIN).json()["orders"]
    assert [o["id"] for o in flagged] == [oid]
    # Stock arrives: the order can still be finished.
    stock = add_stock(client)
    res = client.post(
        f"/api/v1/pharmacy/orders/{oid}/ready",
        json={"stockItemId": stock, "units": 30},
        headers=PHARM,
    )
    assert res.json()["fulfilmentStatus"] == "ready_for_collection"


def test_stock_management(client: TestClient) -> None:
    stock = add_stock(client, units=0)
    res = client.post(
        f"/api/v1/pharmacy/stock/{stock}/receive",
        json={"units": 200, "expiryDate": "2027-01-31"},
        headers=PHARM,
    )
    assert res.json()["units"] == 200 and res.json()["expiryDate"] == "2027-01-31"
    res = client.post(
        f"/api/v1/pharmacy/stock/{stock}/receive",
        json={"units": 100, "expiryDate": "2028-01-31"},
        headers=PHARM,
    )
    assert res.json()["units"] == 300 and res.json()["expiryDate"] == "2027-01-31"  # earliest
    res = client.patch(f"/api/v1/pharmacy/stock/{stock}", json={"lowStockAt": 500}, headers=PHARM)
    assert res.json()["low"] is True
    assert client.get("/api/v1/pharmacy/stock", headers=ADMIN).status_code == 200
    # D-70: admins also manage stock, and only admins delete it.
    res = client.post(
        "/api/v1/pharmacy/stock",
        json={"name": "Xyz 1mg", "units": 1, "expiryDate": "2027-01-01"},
        headers=ADMIN,
    )
    assert res.status_code == 201
    assert client.delete(f"/api/v1/pharmacy/stock/{stock}", headers=PHARM).status_code == 403
    assert client.delete(f"/api/v1/pharmacy/stock/{stock}", headers=ADMIN).status_code == 204
    assert client.get("/api/v1/pharmacy/stock", headers=PATIENT).status_code == 403


def test_patient_lookup_covers_every_patient(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    repo.users["u-x"] = {"role": "patient", "name": "No orders yet"}
    issue(client)
    found = client.get("/api/v1/pharmacy/patients?q=siti", headers=PHARM).json()["patients"]
    assert [p["id"] for p in found] == [P]
    assert len(found[0]["regimen"]) == 1
    # D-70: patients without an order are listed too; staff never are.
    other = client.get("/api/v1/pharmacy/patients?q=no orders", headers=PHARM).json()
    assert [p["id"] for p in other["patients"]] == ["u-x"]
    assert client.get("/api/v1/pharmacy/patients?q=tan", headers=PHARM).json()["patients"] == []


# ---------------- UC13.4 / UC13.5 delivery ----------------


def _deliver(client: TestClient, order_repo: InMemoryOrderRepository) -> str:
    oid = paid_order(client, order_repo, "home_delivery")
    stock = add_stock(client)
    res = client.post(
        f"/api/v1/pharmacy/orders/{oid}/ready",
        json={"stockItemId": stock, "units": 30},
        headers=PHARM,
    )
    body = res.json()
    assert body["fulfilmentStatus"] == "ready_for_delivery"
    assert body["deliveryStatus"] == "dispatched" and body["courierRef"].startswith("GRB-")
    return oid


def test_uc13_4_dispatch_and_uc13_5_simulated_tracking(
    client: TestClient, order_repo: InMemoryOrderRepository, push: LogPushClient
) -> None:
    oid = _deliver(client, order_repo)
    assert "Your order is on its way" in titles(push, P)
    o = order_repo.orders[oid]
    # Pretend the courier left 2.5 stages ago.
    o["dispatchedAt"] -= STAGE * 2.5
    for e in order_repo.tracking:
        e["timestamp"] = o["dispatchedAt"]
    view = client.get(f"/api/v1/orders/{oid}", headers=PATIENT).json()
    assert [e["status"] for e in view["events"]] == ["dispatched", "picked_up", "in_transit"]
    assert view["deliveryStatus"] == "in_transit"
    assert "Out for delivery" in titles(push, P)
    o["dispatchedAt"] -= STAGE
    view = client.get(f"/api/v1/orders/{oid}", headers=PATIENT).json()
    assert view["fulfilmentStatus"] == "delivered" and view["deliveryStatus"] == "delivered"
    assert "Delivered" in titles(push, P)
    # Reading again adds nothing.
    client.get(f"/api/v1/orders/{oid}", headers=PATIENT)
    assert len(order_repo.events(oid)) == 4


def test_fr13_5_failed_delivery_then_reschedule(
    client: TestClient, order_repo: InMemoryOrderRepository, push: LogPushClient
) -> None:
    oid = _deliver(client, order_repo)
    res = client.post(f"/api/v1/admin/deliveries/{oid}/simulate-failure", json={}, headers=ADMIN)
    assert res.json()["fulfilmentStatus"] == "failed"
    assert "Delivery problem" in titles(push, P)
    res = client.post(f"/api/v1/orders/{oid}/reschedule", headers=PATIENT)
    assert res.json()["fulfilmentStatus"] == "ready_for_delivery"
    assert res.json()["deliveryStatus"] == "dispatched"
    assert [e["status"] for e in order_repo.events(oid)] == ["dispatched", "failed", "dispatched"]


def test_fr13_5_failed_delivery_switched_to_collection(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = _deliver(client, order_repo)
    client.post(f"/api/v1/admin/deliveries/{oid}/simulate-failure", json={}, headers=ADMIN)
    res = client.post(f"/api/v1/orders/{oid}/switch-to-collection", headers=PATIENT)
    assert res.status_code == 204
    o = order_repo.orders[oid]
    assert o["method"] == "self_collection" and o["fulfilmentStatus"] == "ready_for_collection"


def test_uc13_4_e1_dispatch_retries_then_fails(
    make_client: Any, order_repo: InMemoryOrderRepository
) -> None:
    from app.integrations.delivery import DispatchError, get_courier_client

    calls: list[str] = []

    class Down(FakeGrabClient):
        def dispatch(self, order_id: str, dest: Any, now: datetime) -> Any:
            calls.append(order_id)
            raise DispatchError("No riders available.")

    client = make_client()
    client.app.dependency_overrides[get_courier_client] = lambda: Down()
    oid = paid_order(client, order_repo, "home_delivery")
    stock = add_stock(client)
    res = client.post(
        f"/api/v1/pharmacy/orders/{oid}/ready",
        json={"stockItemId": stock, "units": 30},
        headers=PHARM,
    )
    assert res.json()["fulfilmentStatus"] == "failed"
    assert res.json()["failureReason"] == "No riders available."
    assert len(calls) == 2  # one retry


def test_admin_delivery_oversight(client: TestClient, order_repo: InMemoryOrderRepository) -> None:
    oid = _deliver(client, order_repo)
    res = client.get("/api/v1/admin/deliveries", headers=ADMIN).json()
    assert res["simulated"] is True and [o["id"] for o in res["orders"]] == [oid]
    assert client.get("/api/v1/admin/deliveries", headers=PHARM).status_code == 403
    # Manual dispatch only for failed / undispatched orders.
    assert client.post(f"/api/v1/admin/deliveries/{oid}/dispatch", headers=ADMIN).status_code == 409
    client.post(f"/api/v1/admin/deliveries/{oid}/simulate-failure", json={}, headers=ADMIN)
    res = client.post(f"/api/v1/admin/deliveries/{oid}/dispatch", headers=ADMIN)
    assert res.json()["deliveryStatus"] == "dispatched"


def test_d67_grab_webhook_needs_the_token_and_maps_statuses(
    make_client: Any, order_repo: InMemoryOrderRepository, push: LogPushClient
) -> None:
    client = make_client(dev_settings(grab_webhook_secret="s3cret"))
    oid = _deliver(client, order_repo)
    ref = order_repo.orders[oid]["courierRef"]
    body = {
        "deliveryID": ref,
        "merchantOrderID": f"{oid}.1760000000",
        "status": "IN_DELIVERY",
        "timestamp": 1760000000,
        "driver": {"name": "Ali", "currentLat": 3.1, "currentLng": 101.7},
    }
    assert client.post("/api/v1/webhooks/grab", json=body).status_code == 403
    bad = {"Authorization": "nope"}
    assert client.post("/api/v1/webhooks/grab", json=body, headers=bad).status_code == 403
    ok = {"Authorization": "s3cret"}
    res = client.post("/api/v1/webhooks/grab", json=body, headers=ok)
    assert res.json()["changed"] == 2  # picked_up, in_transit (dispatched already recorded)
    assert order_repo.orders[oid]["deliveryStatus"] == "in_transit"
    res = client.post("/api/v1/webhooks/grab", json={**body, "status": "COMPLETED"}, headers=ok)
    assert order_repo.orders[oid]["fulfilmentStatus"] == "delivered"
    # A stale delivery id (an earlier attempt) is acknowledged but ignored.
    old = {**body, "deliveryID": "IN-OLD", "status": "FAILED"}
    assert client.post("/api/v1/webhooks/grab", json=old, headers=ok).json()["changed"] == 0
    assert order_repo.orders[oid]["fulfilmentStatus"] == "delivered"


def test_d67_grab_failure_webhook_asks_the_patient(
    make_client: Any, order_repo: InMemoryOrderRepository, push: LogPushClient
) -> None:
    client = make_client(dev_settings(grab_webhook_secret="s3cret"))
    oid = _deliver(client, order_repo)
    body = {
        "deliveryID": order_repo.orders[oid]["courierRef"],
        "merchantOrderID": f"{oid}.1",
        "status": "FAILED",
        "failedReason": "Recipient unreachable",
    }
    client.post("/api/v1/webhooks/grab", json=body, headers={"Authorization": "Bearer s3cret"})
    o = order_repo.orders[oid]
    assert o["fulfilmentStatus"] == "failed" and o["failureReason"] == "Recipient unreachable"
    assert "Delivery problem" in titles(push, P)


def test_sweep_runs_the_order_job(client: TestClient, order_repo: InMemoryOrderRepository) -> None:
    oid = _deliver(client, order_repo)
    order_repo.orders[oid]["dispatchedAt"] -= STAGE * 5
    res = client.post("/internal/jobs/escalation")
    assert res.json()["deliveryUpdates"] == 3
    assert order_repo.orders[oid]["fulfilmentStatus"] == "delivered"
