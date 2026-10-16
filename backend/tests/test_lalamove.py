"""D-68: Lalamove API v3 sandbox courier (UC13.4, UC13.5). Lalamove's HTTP calls are mocked
with the shapes returned by the live sandbox on 2026-10-16."""

import hashlib
import hmac
import json
from datetime import UTC, datetime
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.integrations.delivery import (
    LALAMOVE_SANDBOX_URL,
    STAGE,
    Destination,
    DispatchError,
    FakeGrabClient,
    LalamoveClient,
    Place,
    build_courier_client,
    e164,
    get_courier_client,
    lalamove_signature,
)
from tests.conftest import InMemoryOrderRepository, bearer, dev_settings
from tests.test_orders import _deliver, people  # noqa: F401  (autouse: patient, doctor, staff)

NOW = datetime(2026, 10, 16, 6, 0, tzinfo=UTC)
PHARMACY = Place("Suria KLCC, Kuala Lumpur", 3.1579, 101.7123)
DEST = Destination("Ampang Point, Ampang", 3.1488, 101.7614, "Siti", "012-345 6789")


class FakeLalamoveHttp:
    """Answers like rest.sandbox.lalamove.com and records every signed call."""

    def __init__(self, monkeypatch: pytest.MonkeyPatch) -> None:
        self.calls: list[tuple[str, str, Any, dict[str, str]]] = []
        self.status = "ASSIGNING_DRIVER"
        self.fail_quote = False
        monkeypatch.setattr("app.integrations.delivery.httpx.request", self.request)

    def request(
        self, method: str, url: str, content: Any, headers: dict[str, str], timeout: float
    ) -> httpx.Response:
        path = url.removeprefix(LALAMOVE_SANDBOX_URL)
        body = json.loads(content) if content else None
        self.calls.append((method, path, body, headers))
        if method == "POST" and path == "/v3/quotations":
            if self.fail_quote:
                return httpx.Response(422, json={"errors": [{"id": "ERR_OUT_OF_SERVICE_AREA"}]})
            return httpx.Response(
                201,
                json={
                    "data": {
                        "quotationId": "3607534427947324146",
                        "expiresAt": "2026-10-16T06:00:30.00Z",
                        "stops": [{"stopId": "s1"}, {"stopId": "s2"}],
                        "priceBreakdown": {"total": "9.0", "currency": "MYR"},
                    }
                },
            )
        if method == "POST" and path == "/v3/orders":
            return httpx.Response(
                201,
                json={
                    "data": {
                        "orderId": "3607496166784815293",
                        "shareLink": "https://share.sandbox.lalamove.com?MY100",
                        "status": "ASSIGNING_DRIVER",
                    }
                },
            )
        if method == "GET":
            return httpx.Response(200, json={"data": {"status": self.status}})
        if method == "DELETE":
            return httpx.Response(204)
        return httpx.Response(404)


def client() -> LalamoveClient:
    return LalamoveClient("pk_test_key", "sk_test_secret", PHARMACY, "03-4145 0123")


def test_signature_matches_api_v3_formula() -> None:
    expected = hmac.new(
        b"sk_test_secret",
        b'1760594400000\r\nPOST\r\n/v3/quotations\r\n\r\n{"data":{}}',
        hashlib.sha256,
    ).hexdigest()
    assert (
        lalamove_signature(
            "sk_test_secret", "1760594400000", "POST", "/v3/quotations", '{"data":{}}'
        )
        == expected
    )


def test_phone_numbers_are_e164() -> None:
    assert e164("012-345 6789") == "+60123456789"
    assert e164("+60 3-4145 0123") == "+60341450123"


def test_only_sandbox_keys() -> None:
    with pytest.raises(DispatchError):
        LalamoveClient("pk_prod_x", "sk_prod_x", PHARMACY, "0341450123")


def test_selection_defaults_to_lalamove_with_simulator_fallback() -> None:
    assert build_courier_client(dev_settings()).brand == "Lalamove"
    assert isinstance(build_courier_client(dev_settings()), FakeGrabClient)
    ready = dev_settings(
        lalamove_api_key="pk_test_k",
        lalamove_api_secret="sk_test_s",
        pharmacy_address="Suria KLCC",
        pharmacy_lat=3.1579,
        pharmacy_lng=101.7123,
        pharmacy_phone="0341450123",
    )
    assert isinstance(build_courier_client(ready), LalamoveClient)
    prod = dev_settings(
        lalamove_api_key="pk_prod_k",
        lalamove_api_secret="sk_prod_s",
        pharmacy_address="Suria KLCC",
        pharmacy_lat=3.1579,
        pharmacy_lng=101.7123,
    )
    assert isinstance(build_courier_client(prod), FakeGrabClient)  # live keys refused


def test_dispatch_quotes_then_orders_with_signed_calls(monkeypatch: pytest.MonkeyPatch) -> None:
    http = FakeLalamoveHttp(monkeypatch)
    d = client().dispatch("rx1_2026-10", DEST, NOW)
    assert d.delivery_id == "3607496166784815293"
    assert d.tracking_url == "https://share.sandbox.lalamove.com?MY100"
    (_, qpath, quote, headers), (_, opath, order, _) = http.calls
    assert (qpath, opath) == ("/v3/quotations", "/v3/orders")
    assert headers["Market"] == "MY" and headers["Request-ID"]
    assert headers["Authorization"].startswith("hmac pk_test_key:")
    q = quote["data"]
    assert q["serviceType"] == "MOTORCYCLE"
    assert q["stops"][0]["coordinates"] == {"lat": "3.1579000", "lng": "101.7123000"}
    assert q["stops"][1]["coordinates"] == {"lat": "3.1488000", "lng": "101.7614000"}
    assert q["item"]["categories"] == ["OTHERS"]
    o = order["data"]
    assert o["quotationId"] == "3607534427947324146"
    assert o["sender"] == {"stopId": "s1", "name": "CareFlow pharmacy", "phone": "+60341450123"}
    assert o["recipients"][0]["phone"] == "+60123456789"
    assert o["recipients"][0]["name"] == "Siti"
    assert "Amlodipine" not in json.dumps(http.calls[0][2]) + json.dumps(order)


def test_signature_header_is_verifiable(monkeypatch: pytest.MonkeyPatch) -> None:
    http = FakeLalamoveHttp(monkeypatch)
    client().poll("L1", NOW, NOW)
    method, path, _, headers = http.calls[0]
    _, rest = headers["Authorization"].split(" ", 1)
    key, stamp, sig = rest.split(":")
    assert key == "pk_test_key"
    assert sig == lalamove_signature("sk_test_secret", stamp, method, path, "")


def test_quote_refused_is_a_dispatch_error(monkeypatch: pytest.MonkeyPatch) -> None:
    http = FakeLalamoveHttp(monkeypatch)
    http.fail_quote = True
    with pytest.raises(DispatchError):
        client().dispatch("o", DEST, NOW)


def test_sandbox_has_no_driver_so_the_clock_moves_the_stages(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    http = FakeLalamoveHttp(monkeypatch)
    c = client()
    assert [u.status for u in c.poll("L1", NOW, NOW)] == ["dispatched"]
    later = [u.status for u in c.poll("L1", NOW, NOW + STAGE * 2)]
    assert later == ["dispatched", "picked_up", "in_transit"]
    # A real status further along wins.
    http.status = "COMPLETED"
    assert c.poll("L1", NOW, NOW)[-1].status == "delivered"


def test_rejected_fails_but_sandbox_expiry_does_not(monkeypatch: pytest.MonkeyPatch) -> None:
    http = FakeLalamoveHttp(monkeypatch)
    c = client()
    http.status = "REJECTED"
    assert c.poll("L1", NOW, NOW)[-1].status == "failed"
    http.status = "EXPIRED"
    assert [u.status for u in c.poll("L1", NOW, NOW)] == ["dispatched"]


def test_cancel_is_best_effort(monkeypatch: pytest.MonkeyPatch) -> None:
    http = FakeLalamoveHttp(monkeypatch)
    client().cancel("L1")
    assert http.calls[-1][:2] == ("DELETE", "/v3/orders/L1")

    def down(*a: Any, **k: Any) -> Any:
        raise httpx.ConnectError("down")

    monkeypatch.setattr("app.integrations.delivery.httpx.request", down)
    client().cancel("L1")  # no exception


# ---------------- through the API ----------------


class RecordingCourier(FakeGrabClient):
    def __init__(self) -> None:
        super().__init__("Lalamove")
        self.cancelled: list[str] = []

    def cancel(self, delivery_id: str) -> None:
        self.cancelled.append(delivery_id)


def _home_order(client: TestClient, order_repo: InMemoryOrderRepository) -> str:
    return _deliver(client, order_repo)


def test_order_views_name_the_courier_and_admin_failure_cancels_the_booking(
    make_client: Any, order_repo: InMemoryOrderRepository
) -> None:
    courier = RecordingCourier()
    c = make_client()
    c.app.dependency_overrides[get_courier_client] = lambda: courier
    oid = _home_order(c, order_repo)
    view = c.get(f"/api/v1/orders/{oid}", headers=bearer("patient-token")).json()
    assert view["courierBrand"] == "Lalamove"
    ref = order_repo.orders[oid]["courierRef"]
    c.post(
        f"/api/v1/admin/deliveries/{oid}/simulate-failure",
        json={},
        headers=bearer("admin-token"),
    )
    assert courier.cancelled == [ref]


def test_lalamove_webhook_rereads_the_status(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = _home_order(client, order_repo)
    o = order_repo.orders[oid]
    o["dispatchedAt"] -= STAGE * 5
    for e in order_repo.tracking:
        e["timestamp"] = o["dispatchedAt"]
    payload = {
        "eventType": "ORDER_STATUS_CHANGED",
        "data": {"order": {"orderId": o["courierRef"], "status": "COMPLETED"}},
    }
    res = client.post("/api/v1/webhooks/lalamove", json=payload)
    assert res.status_code == 200 and res.json()["changed"] == 3
    assert order_repo.orders[oid]["fulfilmentStatus"] == "delivered"
    # Unknown orders and Lalamove's set-up test call still get 200.
    unknown = {"data": {"order": {"orderId": "nope", "status": "COMPLETED"}}}
    assert client.post("/api/v1/webhooks/lalamove", json=unknown).json()["changed"] == 0
    assert client.post("/api/v1/webhooks/lalamove", content=b"").status_code == 200


@pytest.mark.parametrize(
    "shape",
    [
        lambda ref: {"eventType": "ORDER_STATUS_CHANGED", "data": {"order": {"orderId": ref}}},
        lambda ref: {"eventType": "ORDER_STATUS_CHANGED", "data": {"orderId": ref}},
        lambda ref: {"data": {"order": {"OrderID": int(ref)}}},
    ],
)
def test_webhook_finds_the_order_id_in_any_shape(
    shape: Any, client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = _home_order(client, order_repo)
    o = order_repo.orders[oid]
    o["courierRef"] = "3607496166784815549"
    o["dispatchedAt"] -= STAGE * 5
    res = client.post("/api/v1/webhooks/lalamove", json=shape("3607496166784815549"))
    assert res.json()["changed"] == 3
    assert order_repo.orders[oid]["fulfilmentStatus"] == "delivered"


class SlowCourier(FakeGrabClient):
    """A real-courier stand-in: polling is an API call, so lists must throttle it."""

    poll_in_lists = False

    def __init__(self) -> None:
        super().__init__("Lalamove")
        self.polls = 0

    def poll(self, delivery_id: str, dispatched_at: datetime, now: datetime) -> Any:
        self.polls += 1
        return super().poll(delivery_id, dispatched_at, now)


def test_pharmacy_queue_polls_a_real_courier_but_throttled(
    make_client: Any, order_repo: InMemoryOrderRepository, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.routers import orders as orders_router

    courier = SlowCourier()
    c = make_client()
    c.app.dependency_overrides[get_courier_client] = lambda: courier
    oid = _home_order(c, order_repo)
    order_repo.orders[oid]["dispatchedAt"] -= STAGE * 5
    monkeypatch.setattr(orders_router, "_last_list_poll", {})
    pharm = bearer("pharmacist-token")
    queue = c.get("/api/v1/pharmacy/queue", headers=pharm).json()["orders"]
    assert courier.polls == 1
    assert order_repo.orders[oid]["fulfilmentStatus"] == "delivered"
    assert queue == []  # delivered orders leave the queue
    c.get("/api/v1/admin/deliveries", headers=bearer("admin-token"))
    assert courier.polls == 1  # already final, no more calls


# ---------------- D-71: delivery fee from the courier's quote ----------------


def test_lalamove_quote_is_the_quotation_total(monkeypatch: pytest.MonkeyPatch) -> None:
    http = FakeLalamoveHttp(monkeypatch)
    assert client().quote(DEST) == 9.0
    assert http.calls[-1][1] == "/v3/quotations"  # a quote books nothing
    assert client().quote(Destination("x", None, None, "Siti", "0123")) is None
    http.fail_quote = True
    assert client().quote(DEST) is None


class QuotingCourier(FakeGrabClient):
    def __init__(self, fee: float | None) -> None:
        super().__init__("Lalamove")
        self.fee = fee
        self.asked: list[tuple[float | None, float | None]] = []

    def quote(self, dest: Destination) -> float | None:
        self.asked.append((dest.lat, dest.lng))
        return self.fee


def _confirm_home(c: TestClient, order_repo: InMemoryOrderRepository) -> dict[str, Any]:
    from tests.test_orders import HOME, PATIENT, priced_order

    oid = priced_order(c, order_repo)
    preview = c.post(
        f"/api/v1/orders/{oid}/delivery-quote",
        json={"deliveryAddress": HOME["deliveryAddress"], "lat": 3.1579, "lng": 101.7123},
        headers=PATIENT,
    ).json()
    res = c.post(
        f"/api/v1/orders/{oid}/confirm", json={"method": "home_delivery", **HOME}, headers=PATIENT
    )
    return {"preview": preview, "order": res.json()}


def test_d71_checkout_charges_the_courier_quote(
    make_client: Any, order_repo: InMemoryOrderRepository
) -> None:
    courier = QuotingCourier(13.2)
    c = make_client()
    c.app.dependency_overrides[get_courier_client] = lambda: courier
    out = _confirm_home(c, order_repo)
    assert out["preview"] == {"deliveryFee": 13.2, "courier": "Lalamove"}
    assert out["order"]["deliveryFee"] == 13.2
    assert out["order"]["total"] == 28.2  # RM15 medicine + RM13.20 courier
    assert courier.asked[-1] == (3.1579, 101.7123)  # re-quoted on confirm, not trusted


def test_d71_flat_fee_when_the_courier_cannot_quote(
    make_client: Any, order_repo: InMemoryOrderRepository
) -> None:
    c = make_client()
    c.app.dependency_overrides[get_courier_client] = lambda: QuotingCourier(None)
    out = _confirm_home(c, order_repo)
    assert out["preview"]["deliveryFee"] == 5.0 and out["order"]["deliveryFee"] == 5.0
