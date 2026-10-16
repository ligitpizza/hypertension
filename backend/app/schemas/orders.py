"""Module 13 request models (FR-13.1-13.5; D-66)."""

from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class _Body(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class ConfirmOrderRequest(_Body):
    method: Literal["self_collection", "home_delivery"]
    deliveryAddress: str | None = Field(default=None, max_length=300)
    # D-67: the phone's current location and a contact number, for the courier.
    deliveryLat: float | None = Field(default=None, ge=-90, le=90)
    deliveryLng: float | None = Field(default=None, ge=-180, le=180)
    deliveryPhone: str | None = Field(default=None, max_length=20, pattern=r"^[0-9+\- ]*$")


class DeliveryQuoteRequest(_Body):
    """D-71: where the courier would deliver, for a fee preview."""

    deliveryAddress: str = Field(default="", max_length=300)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class FakePaymentRequest(_Body):
    """Simulated card form (fake mode only): Stripe's test numbers, never real cards."""

    cardNumber: str = Field(min_length=12, max_length=23)


class RecurringRequest(_Body):
    isRecurring: bool


class PriceRequest(_Body):
    # Stripe's minimum charge in MYR is RM2.
    monthlyPrice: float = Field(ge=2, le=5000)


class ReadyRequest(_Body):
    # Catalogue orders take each item from its linked stock automatically (D-69); older
    # single-text orders name the stock item and units.
    stockItemId: str | None = Field(default=None, min_length=1, max_length=100)
    units: int | None = Field(default=None, ge=1, le=1000)


class CancelOrderRequest(_Body):
    """D-74: why the order is cancelled (shown to the patient)."""

    reason: str = Field(min_length=3, max_length=300)


class OutOfStockRequest(_Body):
    note: str | None = Field(default=None, max_length=300)


class StockRequest(_Body):
    name: str = Field(min_length=2, max_length=100)
    catalogId: str | None = Field(default=None, max_length=100)  # D-69
    units: int = Field(ge=0, le=1_000_000)
    expiryDate: date
    lowStockAt: int = Field(default=50, ge=0, le=1_000_000)


class StockEditRequest(_Body):
    name: str | None = Field(default=None, min_length=2, max_length=100)
    units: int | None = Field(default=None, ge=0, le=1_000_000)
    expiryDate: date | None = None
    lowStockAt: int | None = Field(default=None, ge=0, le=1_000_000)


class ReceiveStockRequest(_Body):
    """ "New Stock" (Fig 4.3.13.1): units received and that batch's expiry."""

    units: int = Field(ge=1, le=1_000_000)
    expiryDate: date


class CatalogItemRequest(_Body):
    """D-69: a medicine pharmacists and admins add to the catalogue."""

    name: str = Field(min_length=2, max_length=80)
    strength: str = Field(min_length=1, max_length=30)
    form: Literal["tablet", "capsule", "syrup", "injection", "other"] = "tablet"
    drugClass: str = Field(default="", max_length=60)
    unitPrice: float = Field(ge=0.01, le=1000)


class CatalogEditRequest(_Body):
    unitPrice: float | None = Field(default=None, ge=0.01, le=1000)
    active: bool | None = None
    # D-70: admins and pharmacists correct the medicine itself.
    name: str | None = Field(default=None, min_length=2, max_length=80)
    strength: str | None = Field(default=None, min_length=1, max_length=30)
    drugClass: str | None = Field(default=None, max_length=60)
    form: Literal["tablet", "capsule", "syrup", "injection", "other"] | None = None


class GrabWebhook(BaseModel):
    """GrabExpress tracking webhook body (developer.grab.com/docs/grab-express); only the
    fields Harvey uses. Grab may add fields, so extras are ignored."""

    model_config = ConfigDict(extra="ignore")
    deliveryID: str = Field(min_length=1, max_length=200)
    merchantOrderID: str = Field(min_length=1, max_length=300)
    status: str = Field(min_length=1, max_length=40)
    failedReason: str | None = Field(default=None, max_length=500)


class FailDeliveryRequest(_Body):
    reason: str = Field(default="The courier could not reach the address.", max_length=300)
