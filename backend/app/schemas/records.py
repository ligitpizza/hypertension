"""Module 6 health records (D-58)."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

RecordCategory = Literal[
    "lab_result", "prescription", "imaging", "discharge_summary", "referral_letter", "other"
]


class CreateRecordRequest(BaseModel):
    """UC6.1: the file is already in Storage under this id; save it with its category."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    recordId: str = Field(pattern=r"^[A-Za-z0-9_-]{8,64}$")
    category: RecordCategory
    fileName: str = Field(min_length=1, max_length=200)


class UpdateRecordRequest(BaseModel):
    """D-58: change the category later."""

    model_config = ConfigDict(extra="forbid")

    category: RecordCategory
