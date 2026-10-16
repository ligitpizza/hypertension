"""Module 13 request models (FR-13.1-13.5; D-66)."""

from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class _Body(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class ConfirmOrderRequest(_Body):
    method: Literal["self_collection", "home_delivery"]
    deliveryAddress: str | None = Field(default=None, max_length=300)


class FakePaymentRequest(_Body):
    """Simulated card form (fake mode only): Stripe's test numbers, never real cards."""

    cardNumber: str = Field(min_length=12, max_length=23)


class RecurringRequest(_Body):
    isRecurring: bool


class PriceRequest(_Body):
    # Stripe's minimum charge in MYR is RM2.
    monthlyPrice: float = Field(ge=2, le=5000)


class ReadyRequest(_Body):
    stockItemId: str = Field(min_length=1, max_length=100)
    units: int = Field(ge=1, le=1000)


class OutOfStockRequest(_Body):
    note: str | None = Field(default=None, max_length=300)


class StockRequest(_Body):
    name: str = Field(min_length=2, max_length=100)
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


class GrabWebhook(_Body):
    orderId: str = Field(min_length=1, max_length=200)
    status: Literal["dispatched", "picked_up", "in_transit", "delivered", "failed"]
    location: str | None = Field(default=None, max_length=300)


class FailDeliveryRequest(_Body):
    reason: str = Field(default="The courier could not reach the address.", max_length=300)
