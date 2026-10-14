"""Module 8 request models (FR-8.3; UC8.4, UC8.5)."""

from pydantic import BaseModel, ConfigDict, Field


class NoteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    content: str = Field(min_length=1, max_length=10_000)


class CarePlanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    content: str = Field(min_length=1, max_length=10_000)


class PrescriptionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    medicationName: str = Field(min_length=2, max_length=100)
    dosage: str = Field(min_length=1, max_length=50)
    frequency: str = Field(min_length=1, max_length=100)
    duration: str | None = Field(default=None, max_length=50)
    isRecurring: bool = False  # UC13.1; monthly orders arrive with Module 13
    # UC8.4 E1: the doctor saw the interaction warning and chose to continue.
    acknowledgeInteractions: bool = False


class ReportedPrescriptionRequest(BaseModel):
    """D-50: a prescription the patient got elsewhere (e.g. another clinic's paper slip)."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    medicationName: str = Field(min_length=2, max_length=100)
    dosage: str = Field(min_length=1, max_length=50)
    frequency: str = Field(min_length=1, max_length=100)
    duration: str | None = Field(default=None, max_length=50)
    clinic: str | None = Field(default=None, max_length=100)
