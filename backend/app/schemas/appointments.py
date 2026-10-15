"""Module 7 request models (FR-7.1; UC7.1, UC7.2; D-53)."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class BookRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    dateTime: datetime
    # Emergency visits are only booked by the system (docs/06 Emergency band).
    type: Literal["checkup", "follow_up"] = "checkup"


ChangeReason = Literal[
    "feeling_better", "schedule_conflict", "transport", "cost", "other_doctor", "other"
]


class ChangeRequest(BaseModel):
    """UC7.2 / D-55: ask to reschedule (dateTime) or cancel, with a reason; or withdraw the
    pending request."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    dateTime: datetime | None = None
    cancel: bool = False
    withdraw: bool = False
    reason: ChangeReason | None = None
    note: str | None = Field(default=None, max_length=300)


class DecisionRequest(BaseModel):
    """D-55: the doctor (or admin) approves or declines a pending change."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    approve: bool
    note: str | None = Field(default=None, max_length=300)


class OutcomeRequest(BaseModel):
    """D-56: the doctor (or admin) records how the visit went."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    outcome: Literal["completed", "no_show"]
    note: str | None = Field(default=None, max_length=300)


class StaffCancelRequest(BaseModel):
    """D-55: a doctor or the admin cancels, saying why."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    reason: str = Field(min_length=3, max_length=300)


AdminType = Literal["checkup", "follow_up", "emergency"]


class AdminBookRequest(BaseModel):
    """D-60: the admin books for a patient with any doctor at any minute."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    patientId: str = Field(min_length=1, max_length=128)
    doctorId: str = Field(min_length=1, max_length=128)
    dateTime: datetime
    type: AdminType = "checkup"


class AdminEditRequest(BaseModel):
    """D-60: the admin moves an appointment (time, doctor or type) instantly."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    dateTime: datetime | None = None
    doctorId: str | None = Field(default=None, min_length=1, max_length=128)
    type: AdminType | None = None
