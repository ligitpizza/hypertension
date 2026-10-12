"""Module 3 request/response models (FR-3.1, FR-3.2)."""

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.enums import AlertLevel, BpCategory


class LogReadingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    # Loose type bounds only; the plausible range (UC3.1 E1) is checked in the router
    # so the client gets READING_OUT_OF_RANGE instead of a generic validation error.
    systolic: int = Field(ge=0, le=1000)
    diastolic: int = Field(ge=0, le=1000)
    heartRate: int | None = Field(default=None, ge=0, le=1000)  # PPG estimate (UC3.3)
    note: str | None = Field(default=None, max_length=500)  # UC3.2

    @field_validator("note")
    @classmethod
    def _blank_to_none(cls, v: str | None) -> str | None:
        return v or None


class LogReadingResponse(BaseModel):
    id: str
    systolic: int
    diastolic: int
    heartRate: int | None
    category: BpCategory
    # Threshold alert band (FR-9.1). Alert delivery is wired in Increment 2 (Module 9).
    alertLevel: AlertLevel | None
