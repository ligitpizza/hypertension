"""Payment adapter (FR-13.3, NFR-2.3, D-66). Real: Stripe test mode. Fake: simulated card.

Stripe's PaymentSheet collects the card in the app, so the platform never sees card data
(PCI DSS through Stripe). The backend only creates the PaymentIntent and learns the result
from the signed webhook (or by asking Stripe when the app returns from the sheet).
Only test keys are accepted: a live key is refused at start-up.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import time
import uuid
from dataclasses import dataclass
from typing import Any, Literal, Protocol

import httpx

from app.core.config import Settings, get_settings

log = logging.getLogger("careflow.payments")

STRIPE_API = "https://api.stripe.com/v1"
CURRENCY = "myr"
WEBHOOK_TOLERANCE_SECONDS = 300

# The fake's test cards, matching Stripe's own test numbers.
FAKE_DECLINED_CARD = "4000000000000002"

IntentStatus = Literal["succeeded", "failed", "pending"]


@dataclass(frozen=True)
class PaymentIntent:
    id: str
    client_secret: str
    status: IntentStatus
    charge_id: str | None = None
    amount_sen: int = 0
    decline_message: str | None = None


class PaymentError(Exception):
    pass


class WebhookSignatureError(Exception):
    pass


class PaymentGateway(Protocol):
    mode: Literal["stripe", "fake"]
    publishable_key: str

    def create_intent(self, amount_sen: int, metadata: dict[str, str]) -> PaymentIntent: ...

    def retrieve(self, intent_id: str) -> PaymentIntent: ...

    def parse_webhook(self, payload: bytes, signature: str | None) -> dict[str, Any]:
        """The verified event; raises WebhookSignatureError when it can't be trusted."""
        ...


def _status(stripe_status: str, has_error: bool) -> IntentStatus:
    if stripe_status == "succeeded":
        return "succeeded"
    # A declined attempt puts the intent back to requires_payment_method with an error.
    if stripe_status == "canceled" or (stripe_status == "requires_payment_method" and has_error):
        return "failed"
    return "pending"


def intent_from_stripe(obj: dict[str, Any]) -> PaymentIntent:
    err = obj.get("last_payment_error") or None
    charge = obj.get("latest_charge")
    return PaymentIntent(
        id=str(obj["id"]),
        client_secret=str(obj.get("client_secret") or ""),
        status=_status(str(obj.get("status") or ""), bool(err)),
        charge_id=str(charge) if isinstance(charge, str) else None,
        amount_sen=int(obj.get("amount") or 0),
        decline_message=str(err.get("message")) if isinstance(err, dict) else None,
    )


def verify_stripe_signature(
    payload: bytes, header: str | None, secret: str, now: float | None = None
) -> None:
    """Stripe-Signature: t=<unix>,v1=<hex hmac-sha256 of "t.payload">."""
    if not header or not secret:
        raise WebhookSignatureError("Missing signature.")
    pairs = [p.strip().split("=", 1) for p in header.split(",") if "=" in p]
    stamp = next((v for k, v in pairs if k == "t"), None)
    sent = [v for k, v in pairs if k == "v1"]
    if not stamp or not sent:
        raise WebhookSignatureError("Malformed signature.")
    expected = hmac.new(secret.encode(), f"{stamp}.".encode() + payload, hashlib.sha256).hexdigest()
    if not any(hmac.compare_digest(expected, s) for s in sent):
        raise WebhookSignatureError("Signature mismatch.")
    if abs((now or time.time()) - int(stamp)) > WEBHOOK_TOLERANCE_SECONDS:
        raise WebhookSignatureError("Signature too old.")


class StripeGateway:
    mode: Literal["stripe", "fake"] = "stripe"

    def __init__(self, secret_key: str, publishable_key: str, webhook_secret: str) -> None:
        if not secret_key.startswith("sk_test_") or not publishable_key.startswith("pk_test_"):
            raise PaymentError("Only Stripe test-mode keys are allowed (D-66).")
        self._key = secret_key
        self.publishable_key = publishable_key
        self._webhook_secret = webhook_secret

    def _call(self, method: str, path: str, data: dict[str, Any] | None = None) -> Any:
        try:
            res = httpx.request(
                method, f"{STRIPE_API}{path}", data=data, auth=(self._key, ""), timeout=15.0
            )
        except httpx.HTTPError as exc:
            raise PaymentError(f"Stripe request failed: {exc}") from exc
        if res.status_code >= 300:
            raise PaymentError(f"Stripe rejected the request (HTTP {res.status_code}).")
        return res.json()

    def create_intent(self, amount_sen: int, metadata: dict[str, str]) -> PaymentIntent:
        data: dict[str, Any] = {
            "amount": amount_sen,
            "currency": CURRENCY,
            "automatic_payment_methods[enabled]": "true",
        }
        data.update({f"metadata[{k}]": v for k, v in metadata.items()})
        return intent_from_stripe(self._call("POST", "/payment_intents", data))

    def retrieve(self, intent_id: str) -> PaymentIntent:
        return intent_from_stripe(self._call("GET", f"/payment_intents/{intent_id}"))

    def parse_webhook(self, payload: bytes, signature: str | None) -> dict[str, Any]:
        verify_stripe_signature(payload, signature, self._webhook_secret)
        event: dict[str, Any] = json.loads(payload)
        return event


class FakeGateway:
    """Simulated payments: any card succeeds except Stripe's decline test card."""

    mode: Literal["stripe", "fake"] = "fake"
    publishable_key = ""

    def __init__(self) -> None:
        self.intents: dict[str, PaymentIntent] = {}

    def create_intent(self, amount_sen: int, metadata: dict[str, str]) -> PaymentIntent:
        intent_id = f"pi_fake_{uuid.uuid4().hex[:16]}"
        intent = PaymentIntent(intent_id, f"{intent_id}_secret", "pending", None, amount_sen)
        self.intents[intent_id] = intent
        return intent

    def pay(self, intent_id: str, card_number: str) -> PaymentIntent:
        old = self.intents.get(intent_id)
        if old is None:
            raise PaymentError("Unknown payment.")
        digits = "".join(c for c in card_number if c.isdigit())
        if digits == FAKE_DECLINED_CARD or len(digits) < 12:
            new = PaymentIntent(
                old.id, old.client_secret, "failed", None, old.amount_sen, "Your card was declined."
            )
        else:
            new = PaymentIntent(
                old.id,
                old.client_secret,
                "succeeded",
                f"ch_fake_{uuid.uuid4().hex[:16]}",
                old.amount_sen,
            )
        self.intents[intent_id] = new
        return new

    def retrieve(self, intent_id: str) -> PaymentIntent:
        intent = self.intents.get(intent_id)
        if intent is None:
            raise PaymentError("Unknown payment.")
        return intent

    def parse_webhook(self, payload: bytes, signature: str | None) -> dict[str, Any]:
        raise WebhookSignatureError("Webhooks are not used in fake mode.")


_FAKE = FakeGateway()  # one per process so a created intent can be paid in a later request


def build_payment_gateway(settings: Settings) -> PaymentGateway:
    if settings.integrations_mode == "real" and settings.stripe_secret_key:
        return StripeGateway(
            settings.stripe_secret_key,
            settings.stripe_publishable_key,
            settings.stripe_webhook_secret,
        )
    return _FAKE


def get_payment_gateway() -> PaymentGateway:
    return build_payment_gateway(get_settings())
