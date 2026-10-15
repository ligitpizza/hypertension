"""FR-14.2 family monitoring (D-06, D-62)."""

from pydantic import BaseModel, ConfigDict, Field


class Location(BaseModel):
    """The phone's GPS position (stored only inside emergency alerts, D-62)."""

    model_config = ConfigDict(extra="forbid")

    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)

    def as_dict(self) -> dict[str, float]:
        return {"lat": self.lat, "lng": self.lng}


class LinkRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    code: str = Field(min_length=4, max_length=20)


class SosRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    location: Location | None = None
    notifyFamily: bool = True


class LocationUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    location: Location
