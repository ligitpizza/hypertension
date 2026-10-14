"""Module 5 request models (FR-5.1, FR-5.3; UC5.1, UC5.3; D-43)."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class MedicationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str = Field(min_length=2, max_length=100)
    dosage: str = Field(min_length=1, max_length=50)
    # "08:00,20:00" (Malaysia time) or "as_needed" (D-43).
    schedule: str = Field(min_length=1, max_length=100)
    quantityOnHand: float | None = Field(default=None, ge=0, le=10000)  # D-05
    refillThresholdDays: float | None = Field(default=None, ge=1, le=60)  # D-05, default 7
    # UC5.1 E1 / UC5.6 E1: the patient saw the warnings and chose to save anyway.
    acknowledgeWarnings: bool = False


class DoseRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    # A scheduled dose time; omitted for an as-needed (or extra) dose taken now.
    scheduledTime: datetime | None = None
