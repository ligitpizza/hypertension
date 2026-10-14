"""Doctor assignment request models (FR-7.2, UC7.3; D-54)."""

from pydantic import BaseModel, ConfigDict, Field


class ReassignRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    proposedDoctorId: str | None = Field(default=None, max_length=128)
    reason: str | None = Field(default=None, max_length=500)


class ApproveRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    doctorId: str = Field(min_length=1, max_length=128)


class DeclineRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    reason: str | None = Field(default=None, max_length=500)
