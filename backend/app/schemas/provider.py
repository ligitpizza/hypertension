"""Module 8 request models (FR-8.3; UC8.4, UC8.5; D-69)."""

from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator


class NoteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    content: str = Field(min_length=1, max_length=10_000)


class CarePlanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    content: str = Field(min_length=1, max_length=10_000)


class PrescriptionItemRequest(BaseModel):
    """One medicine of a consolidated prescription, picked from the catalogue (D-69)."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    catalogId: str = Field(min_length=1, max_length=100)
    dose: str = Field(min_length=1, max_length=50)  # e.g. "1 tablet"
    frequency: Literal["once_daily", "twice_daily", "three_times_daily", "at_night", "as_needed"]
    quantity: int = Field(ge=1, le=1000)


class PrescriptionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    # D-69: a consolidated prescription lists catalogue items; the single free-text
    # medicine below is the older form (still accepted).
    items: list[PrescriptionItemRequest] | None = Field(default=None, min_length=1, max_length=10)
    medicationName: str | None = Field(default=None, min_length=2, max_length=100)
    dosage: str | None = Field(default=None, min_length=1, max_length=50)
    frequency: str | None = Field(default=None, min_length=1, max_length=100)
    duration: str | None = Field(default=None, max_length=50)
    isRecurring: bool = False  # UC13.1: starts the monthly order cycle (D-66)
    # UC8.4 E1: the doctor saw the interaction warning and chose to continue.
    acknowledgeInteractions: bool = False

    @model_validator(mode="after")
    def _one_form(self) -> Self:
        if not self.items and not (self.medicationName and self.dosage and self.frequency):
            raise ValueError("Add at least one medicine.")
        return self


class ReportedPrescriptionRequest(BaseModel):
    """D-50: a prescription the patient got elsewhere (e.g. another clinic's paper slip)."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    medicationName: str = Field(min_length=2, max_length=100)
    dosage: str = Field(min_length=1, max_length=50)
    frequency: str = Field(min_length=1, max_length=100)
    duration: str | None = Field(default=None, max_length=50)
    clinic: str | None = Field(default=None, max_length=100)
