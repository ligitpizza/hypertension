"""D-67: GrabExpress sandbox client (UC13.4, UC13.5), with Grab's HTTP calls mocked from
the published request/response formats (developer.grab.com/docs/grab-express)."""

from datetime import UTC, datetime
from typing import Any

import httpx
import pytest

from app.integrations.delivery import (
    GRAB_OAUTH_URL,
    GRAB_SANDBOX_URL,
    Destination,
    DispatchError,
    FakeGrabClient,
    GrabExpressClient,
    Place,
    build_courier_client,
    grab_phone,
    grab_updates,
    merchant_order_id,
    order_id_from_merchant,
)
from tests.conftest import dev_settings

NOW = datetime(2026, 10, 16, 6, 0, tzinfo=UTC)
PHARMACY = Place("CareFlow Pharmacy, Jalan Genting Kelang, KL", 3.2163, 101.7266)
DEST = Destination("12 Jalan Ampang, KL", 3.1579, 101.7123, "Siti", "012-345 6789")


class FakeGrabHttp:
    """Records calls to Grab and answers like the sandbox."""

    def __init__(self, monkeypatch: pytest.MonkeyPatch) -> None:
        self.tokens = 0
        self.requests: list[tuple[str, str, Any, dict[str, str]]] = []
        self.status = "ALLOCATING"
        self.unauthorized_once = False
        monkeypatch.setattr("app.integrations.delivery.httpx.post", self.post)
        monkeypatch.setattr("app.integrations.delivery.httpx.request", self.request)

    def post(self, url: str, json: dict[str, Any], timeout: float) -> httpx.Response:
        assert url == GRAB_OAUTH_URL
        assert json["grant_type"] == "client_credentials"
        assert json["scope"] == "grab_express.partner_deliveries"
        self.tokens += 1
        return httpx.Response(200, json={"access_token": f"tok{self.tokens}", "expires_in": 604800})

    def request(
        self, method: str, url: str, json: Any, headers: dict[str, str], timeout: float
    ) -> httpx.Response:
        self.requests.append((method, url, json, headers))
        if self.unauthorized_once:
            self.unauthorized_once = False
            return httpx.Response(401, json={})
        if method == "POST":
            return httpx.Response(
                200,
                json={
                    "deliveryID": "IN-2-0BTPB1C1G8IL6W72ZHK8",
                    "merchantOrderID": json["merchantOrderID"],
                    "status": "ALLOCATING",
                    "trackingURL": "",
                    "quote": {
                        "amount": 11,
                        "estimatedTimeline": {
                            "pickup": "2026-10-16T14:15:00+08:00",
                            "dropoff": "2026-10-16T14:45:00+08:00",
                        },
                    },
                },
            )
        return httpx.Response(
            200,
            json={
                "deliveryID": url.rsplit("/", 1)[1],
                "status": self.status,
                "advanceInfo": {"failedReason": "Recipient unreachable"}
                if self.status == "FAILED"
                else None,
            },
        )


def client() -> GrabExpressClient:
    return GrabExpressClient("cid", "csecret", PHARMACY, "03-4145 0123")


def test_phone_numbers_get_the_country_code_without_plus() -> None:
    assert grab_phone("012-345 6789") == "60123456789"
    assert grab_phone("+60 12-345 6789") == "60123456789"
    assert grab_phone("0060123456789") == "60123456789"
    assert grab_phone("6591526655") == "6591526655"


def test_merchant_order_id_round_trip() -> None:
    mid = merchant_order_id("rx1_2026-10", NOW)
    assert mid.startswith("rx1_2026-10.") and order_id_from_merchant(mid) == "rx1_2026-10"


@pytest.mark.parametrize(
    ("status", "stages"),
    [
        ("ALLOCATING", ["dispatched"]),
        ("PICKING_UP", ["dispatched"]),
        ("PENDING_DROP_OFF", ["dispatched", "picked_up"]),
        ("IN_DELIVERY", ["dispatched", "picked_up", "in_transit"]),
        ("COMPLETED", ["dispatched", "picked_up", "in_transit", "delivered"]),
        ("FAILED", ["dispatched", "failed"]),
        ("CANCELLED", ["dispatched", "failed"]),
        ("RETURNED", ["dispatched", "failed"]),
    ],
)
def test_grab_statuses_map_to_tracking_stages(status: str, stages: list[str]) -> None:
    assert [u.status for u in grab_updates(status, NOW)] == stages


def test_simulator_unless_grab_and_pharmacy_are_configured() -> None:
    assert isinstance(build_courier_client(dev_settings()), FakeGrabClient)
    no_pharmacy = dev_settings(courier="grab", grab_client_id="cid", grab_client_secret="s")
    assert isinstance(build_courier_client(no_pharmacy), FakeGrabClient)
    ready = dev_settings(
        courier="grab",
        grab_client_id="cid",
        grab_client_secret="s",
        pharmacy_address="CareFlow Pharmacy",
        pharmacy_lat=3.2,
        pharmacy_lng=101.7,
        pharmacy_phone="0341450123",
    )
    real = build_courier_client(ready)
    assert isinstance(real, GrabExpressClient) and not real.simulated


def test_dispatch_books_a_sandbox_delivery_without_health_data(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    grab = FakeGrabHttp(monkeypatch)
    d = client().dispatch("rx1_2026-10", DEST, NOW)
    assert d.delivery_id == "IN-2-0BTPB1C1G8IL6W72ZHK8"
    assert d.eta == datetime(2026, 10, 16, 6, 45, tzinfo=UTC)
    method, url, body, headers = grab.requests[0]
    assert (method, url) == ("POST", f"{GRAB_SANDBOX_URL}/v1/deliveries")
    assert headers["Authorization"] == "Bearer tok1"
    assert body["serviceType"] == "INSTANT" and body["paymentMethod"] == "CASHLESS"
    assert body["origin"]["coordinates"] == {"latitude": 3.2163, "longitude": 101.7266}
    assert body["destination"]["coordinates"] == {"latitude": 3.1579, "longitude": 101.7123}
    assert body["recipient"] == {"firstName": "Siti", "phone": "60123456789", "smsEnabled": True}
    assert body["sender"]["phone"] == "60341450123"
    assert order_id_from_merchant(body["merchantOrderID"]) == "rx1_2026-10"
    # The medicine never reaches Grab.
    assert body["packages"][0]["name"] == "Pharmacy parcel"
    assert "Amlodipine" not in str(body)


def test_token_is_reused_and_renewed_after_401(monkeypatch: pytest.MonkeyPatch) -> None:
    grab = FakeGrabHttp(monkeypatch)
    c = client()
    c.dispatch("rx1_2026-10", DEST, NOW)
    c.poll("IN-1", NOW, NOW)
    assert grab.tokens == 1
    grab.unauthorized_once = True
    c.poll("IN-1", NOW, NOW)
    assert grab.tokens == 2
    assert grab.requests[-1][3]["Authorization"] == "Bearer tok2"


def test_poll_reads_grab_status_and_failure_reason(monkeypatch: pytest.MonkeyPatch) -> None:
    grab = FakeGrabHttp(monkeypatch)
    c = client()
    grab.status = "PENDING_DROP_OFF"
    assert [u.status for u in c.poll("IN-1", NOW, NOW)] == ["dispatched", "picked_up"]
    assert grab.requests[-1][:2] == ("GET", f"{GRAB_SANDBOX_URL}/v1/deliveries/IN-1")
    grab.status = "FAILED"
    failed = c.poll("IN-1", NOW, NOW)[-1]
    assert failed.status == "failed" and failed.location == "Recipient unreachable"


def test_dispatch_needs_location_and_phone(monkeypatch: pytest.MonkeyPatch) -> None:
    FakeGrabHttp(monkeypatch)
    no_gps = Destination("12 Jalan Ampang", None, None, "Siti", "0123456789")
    with pytest.raises(DispatchError, match="location"):
        client().dispatch("o", no_gps, NOW)
    no_phone = Destination("12 Jalan Ampang", 3.1, 101.7, "Siti", "")
    with pytest.raises(DispatchError, match="contact number"):
        client().dispatch("o", no_phone, NOW)


def test_grab_outage_is_a_dispatch_error_and_polls_quietly(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def down(*a: Any, **k: Any) -> Any:
        raise httpx.ConnectError("down")

    monkeypatch.setattr("app.integrations.delivery.httpx.post", down)
    with pytest.raises(DispatchError):
        client().dispatch("o", DEST, NOW)
    assert client().poll("IN-1", NOW, NOW) == []


def test_empty_pharmacy_coordinates_mean_unset(monkeypatch: pytest.MonkeyPatch) -> None:
    """deploy-backend passes PHARMACY_LAT= when it isn't configured; that must not crash."""
    from app.core.config import Settings

    monkeypatch.setenv("PHARMACY_LAT", "")
    monkeypatch.setenv("PHARMACY_LNG", "")
    s = Settings(_env_file=None)
    assert s.pharmacy_lat is None and isinstance(build_courier_client(s), FakeGrabClient)
