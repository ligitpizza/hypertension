"""Module 7 request models (FR-7.1; UC7.1, UC7.2; D-53)."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict


class BookRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    dateTime: datetime
    # Emergency visits are only booked by the system (docs/06 Emergency band).
    type: Literal["checkup", "follow_up"] = "checkup"


class ChangeRequest(BaseModel):
    """UC7.2: either a new time (reschedule) or cancel."""

    model_config = ConfigDict(extra="forbid")

    dateTime: datetime | None = None
    cancel: bool = False
