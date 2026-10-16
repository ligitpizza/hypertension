"""Courier adapter (FR-13.4, UC13.4, D-11, D-66).

Grab Express sandbox access needs business onboarding, so CareFlow ships the interface
with a fake simulator: the parcel moves dispatched -> picked_up -> in_transit -> delivered
about one minute per stage. A real Grab client would implement the same Protocol and post
its status changes to /api/v1/webhooks/grab.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Protocol

STAGE = timedelta(minutes=1)
# Courier statuses in order (delivery_tracking_events.status, docs/04).
FAKE_STAGES = ("dispatched", "picked_up", "in_transit", "delivered")
FAKE_LOCATIONS = {
    "dispatched": "CareFlow pharmacy",
    "picked_up": "CareFlow pharmacy",
    "in_transit": "On the way",
    "delivered": None,
}


@dataclass(frozen=True)
class Dispatch:
    delivery_id: str
    eta: datetime


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

    def dispatch(self, order_id: str, address: str, now: datetime) -> Dispatch: ...

    def updates_since_dispatch(self, dispatched_at: datetime, now: datetime) -> list[CourierUpdate]:
        """Statuses the courier has reported by [now] (simulator only; a real courier
        pushes them through the webhook, so it returns [])."""
        ...


class FakeGrabClient:
    name = "Grab (simulated)"
    simulated = True

    def dispatch(self, order_id: str, address: str, now: datetime) -> Dispatch:
        if not address.strip():
            raise DispatchError("No delivery address.")
        return Dispatch(f"GRB-{uuid.uuid4().hex[:6].upper()}", now + STAGE * (len(FAKE_STAGES) - 1))

    def updates_since_dispatch(self, dispatched_at: datetime, now: datetime) -> list[CourierUpdate]:
        out = []
        for i, status in enumerate(FAKE_STAGES):
            at = dispatched_at + STAGE * i
            if at <= now:
                out.append(CourierUpdate(status, at, FAKE_LOCATIONS[status]))
        return out


def get_courier_client() -> CourierClient:
    return FakeGrabClient()
