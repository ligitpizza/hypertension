"""Courier adapter (FR-13.4, UC13.4, UC13.5; D-11, D-66, D-67).

Two implementations of one interface:
- `GrabExpressClient`: GrabExpress sandbox (`partner-api.grab.com/grab-express-sandbox`),
  used when Grab credentials and the pharmacy location are configured. Access needs a
  Grab partner project (requested 2026-10-16).
- `FakeGrabClient`: simulator; the parcel moves dispatched -> picked_up -> in_transit ->
  delivered about one minute per stage.

Grab only receives a generic "Pharmacy parcel" and the patient's first name and contact
number; the medicine never leaves CareFlow (D-67).
"""

from __future__ import annotations

import logging
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

import httpx

from app.core.config import Settings, get_settings

log = logging.getLogger("careflow.delivery")

STAGE = timedelta(minutes=1)
# Courier statuses in order (delivery_tracking_events.status, docs/04).
STAGES = ("dispatched", "picked_up", "in_transit", "delivered")
FAKE_LOCATIONS = {
    "dispatched": "CareFlow pharmacy",
    "picked_up": "CareFlow pharmacy",
    "in_transit": "On the way",
    "delivered": None,
}

GRAB_OAUTH_URL = "https://partner-api.grab.com/grabid/v1/oauth2/token"
GRAB_SANDBOX_URL = "https://partner-api.grab.com/grab-express-sandbox"
GRAB_SCOPE = "grab_express.partner_deliveries"
DEFAULT_ETA = timedelta(minutes=45)


@dataclass(frozen=True)
class Place:
    address: str
    lat: float
    lng: float


@dataclass(frozen=True)
class Destination:
    address: str
    lat: float | None
    lng: float | None
    first_name: str
    phone: str


@dataclass(frozen=True)
class Dispatch:
    delivery_id: str
    eta: datetime
    tracking_url: str | None = None


@dataclass(frozen=True)
class CourierUpdate:
    status: str
    at: datetime
    location: str | None = None


class DispatchError(Exception):
    pass


class CourierClient(Protocol):
    name: str
    simulated: bool
    # Whether polling is cheap enough to run for every order in a list.
    poll_in_lists: bool

    def dispatch(self, order_id: str, dest: Destination, now: datetime) -> Dispatch: ...

    def poll(self, delivery_id: str, dispatched_at: datetime, now: datetime) -> list[CourierUpdate]:
        """Statuses the courier has reached so far, oldest first."""
        ...


# ---------------- simulator ----------------


class FakeGrabClient:
    name = "Grab (simulated)"
    simulated = True
    poll_in_lists = True

    def dispatch(self, order_id: str, dest: Destination, now: datetime) -> Dispatch:
        if not dest.address.strip():
            raise DispatchError("No delivery address.")
        return Dispatch(f"GRB-{uuid.uuid4().hex[:6].upper()}", now + STAGE * (len(STAGES) - 1))

    def poll(self, delivery_id: str, dispatched_at: datetime, now: datetime) -> list[CourierUpdate]:
        out = []
        for i, status in enumerate(STAGES):
            at = dispatched_at + STAGE * i
            if at <= now:
                out.append(CourierUpdate(status, at, FAKE_LOCATIONS[status]))
        return out


# ---------------- GrabExpress ----------------

# Grab status -> CareFlow stages reached (in order); failures handled separately.
_GRAB_REACHED = {
    "QUEUEING": 1,
    "ALLOCATING": 1,
    "PENDING_PICKUP": 1,
    "PICKING_UP": 1,
    "PENDING_DROP_OFF": 2,
    "IN_DELIVERY": 3,
    "COMPLETED": 4,
}
GRAB_FAILED = {"FAILED", "CANCELED", "CANCELLED", "RETURNED", "IN_RETURN"}


def grab_updates(
    status: str, now: datetime, failed_reason: str | None = None, place: str | None = None
) -> list[CourierUpdate]:
    """CareFlow tracking stages implied by a Grab delivery status."""
    status = status.upper()
    if status in GRAB_FAILED:
        reason = failed_reason or f"Grab reported the delivery as {status.lower()}."
        return [CourierUpdate("dispatched", now), CourierUpdate("failed", now, reason)]
    reached = _GRAB_REACHED.get(status, 1)
    return [CourierUpdate(s, now, place if s == "in_transit" else None) for s in STAGES[:reached]]


def merchant_order_id(order_id: str, now: datetime) -> str:
    """Unique per dispatch attempt (a rescheduled delivery is a new Grab delivery)."""
    return f"{order_id}.{int(now.timestamp())}"


def order_id_from_merchant(merchant_id: str) -> str:
    return merchant_id.rsplit(".", 1)[0]


def grab_phone(phone: str) -> str:
    """Grab wants the country code without '+'; Malaysian local numbers get 60."""
    digits = "".join(c for c in phone if c.isdigit())
    if digits.startswith("0") and not digits.startswith("00"):
        digits = "60" + digits[1:]
    return digits.removeprefix("00")


def _time(v: Any) -> datetime | None:
    if not isinstance(v, str) or not v:
        return None
    try:
        t = datetime.fromisoformat(v.replace("Z", "+00:00"))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=UTC)


class GrabExpressClient:
    name = "GrabExpress (sandbox)"
    simulated = False
    poll_in_lists = False  # one API call per order: only on the order screen and the sweep

    def __init__(
        self,
        client_id: str,
        client_secret: str,
        pharmacy: Place,
        pharmacy_phone: str,
        base_url: str = GRAB_SANDBOX_URL,
    ) -> None:
        self._id = client_id
        self._secret = client_secret
        self._pharmacy = pharmacy
        self._pharmacy_phone = pharmacy_phone
        self._base = base_url
        self._token: str | None = None
        self._token_expiry = 0.0
        self._lock = threading.Lock()

    def _access_token(self) -> str:
        with self._lock:
            if self._token and time.time() < self._token_expiry - 60:
                return self._token
            try:
                res = httpx.post(
                    GRAB_OAUTH_URL,
                    json={
                        "client_id": self._id,
                        "client_secret": self._secret,
                        "grant_type": "client_credentials",
                        "scope": GRAB_SCOPE,
                    },
                    timeout=15.0,
                )
            except httpx.HTTPError as exc:
                raise DispatchError(f"Grab sign-in failed: {exc}") from exc
            if res.status_code >= 300:
                raise DispatchError(f"Grab sign-in refused (HTTP {res.status_code}).")
            body = res.json()
            self._token = str(body["access_token"])
            self._token_expiry = time.time() + float(body.get("expires_in") or 3600)
            return self._token

    def _call(self, method: str, path: str, payload: dict[str, Any] | None = None) -> Any:
        for attempt in range(2):
            token = self._access_token()
            try:
                res = httpx.request(
                    method,
                    f"{self._base}{path}",
                    json=payload,
                    headers={"Authorization": f"Bearer {token}"},
                    timeout=20.0,
                )
            except httpx.HTTPError as exc:
                raise DispatchError(f"Grab request failed: {exc}") from exc
            if res.status_code == 401 and attempt == 0:
                self._token = None  # expired early: sign in again once
                continue
            if res.status_code >= 300:
                raise DispatchError(f"Grab refused the request (HTTP {res.status_code}).")
            return res.json() if res.content else {}
        raise DispatchError("Grab sign-in expired.")

    def dispatch(self, order_id: str, dest: Destination, now: datetime) -> Dispatch:
        if dest.lat is None or dest.lng is None:
            raise DispatchError("The delivery location is missing. Ask the patient to reschedule.")
        if not dest.phone:
            raise DispatchError("The patient's contact number is missing.")
        payload = {
            "merchantOrderID": merchant_order_id(order_id, now),
            "serviceType": "INSTANT",
            "vehicleType": "BIKE",
            "paymentMethod": "CASHLESS",
            "payer": "SENDER",
            "highValue": False,
            "packages": [
                {
                    "name": "Pharmacy parcel",
                    "description": "Sealed pharmacy parcel",
                    "quantity": 1,
                    "dimensions": {"height": 0, "width": 0, "depth": 0, "weight": 0},
                }
            ],
            "origin": {
                "address": self._pharmacy.address,
                "coordinates": {
                    "latitude": self._pharmacy.lat,
                    "longitude": self._pharmacy.lng,
                },
            },
            "destination": {
                "address": dest.address,
                "coordinates": {"latitude": dest.lat, "longitude": dest.lng},
            },
            "sender": {
                "firstName": "CareFlow pharmacy",
                "phone": grab_phone(self._pharmacy_phone),
                "smsEnabled": True,
            },
            "recipient": {
                "firstName": dest.first_name or "Patient",
                "phone": grab_phone(dest.phone),
                "smsEnabled": True,
            },
        }
        body = self._call("POST", "/v1/deliveries", payload)
        delivery_id = body.get("deliveryID")
        if not delivery_id:
            raise DispatchError("Grab did not return a delivery.")
        timeline = (body.get("quote") or {}).get("estimatedTimeline") or {}
        eta = _time(timeline.get("dropoff")) or now + DEFAULT_ETA
        log.info("Grab delivery %s created", delivery_id)
        return Dispatch(str(delivery_id), eta, body.get("trackingURL") or None)

    def poll(self, delivery_id: str, dispatched_at: datetime, now: datetime) -> list[CourierUpdate]:
        try:
            body = self._call("GET", f"/v1/deliveries/{delivery_id}")
        except DispatchError:
            log.warning("Grab status check for %s failed", delivery_id)
            return []
        reason = (body.get("advanceInfo") or {}).get("failedReason")
        return grab_updates(str(body.get("status") or ""), now, reason)


def build_courier_client(settings: Settings) -> CourierClient:
    ready = (
        settings.grab_client_id
        and settings.grab_client_secret
        and settings.pharmacy_address
        and settings.pharmacy_lat is not None
        and settings.pharmacy_lng is not None
    )
    if ready:
        return GrabExpressClient(
            settings.grab_client_id,
            settings.grab_client_secret,
            Place(settings.pharmacy_address, settings.pharmacy_lat, settings.pharmacy_lng),  # type: ignore[arg-type]
            settings.pharmacy_phone,
        )
    return FakeGrabClient()


_cached: tuple[Settings, CourierClient] | None = None


def get_courier_client() -> CourierClient:
    """One client per settings object, so the Grab token is reused across requests."""
    global _cached
    settings = get_settings()
    if _cached is None or _cached[0] is not settings:
        _cached = (settings, build_courier_client(settings))
    return _cached[1]
