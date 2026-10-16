"""Module 12 settings requests (FR-12.1, FR-12.2; UC12.1-UC12.4; D-25, D-45)."""

from datetime import date

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.enums import Gender
from app.schemas.auth import (
    EmergencyContact,
    LifestyleFactors,
    MedicalHistory,
    _check_phone,
    _Strict,
    check_dob,
)


class PersonalInfoUpdate(_Strict):
    """UC12.1 'Personal information': name, date of birth, gender."""

    name: str = Field(min_length=2, max_length=100)
    dateOfBirth: date
    gender: Gender
    # D-51: existing patients add or correct their IC here; omitted = unchanged.
    icNumber: str | None = Field(default=None, max_length=20)

    # Same age rules as onboarding (UC1.4).
    _dob = field_validator("dateOfBirth")(check_dob)


class ContactUpdate(_Strict):
    """UC12.1 'Contact details' (D-25 personalInfo.phone / emergencyContact)."""

    phone: str
    emergencyContact: EmergencyContact | None = None

    _phone = field_validator("phone")(_check_phone)


class HealthProfileUpdate(_Strict):
    """UC12.2: the onboarding health profile, minus contact details."""

    heightCm: float = Field(ge=100, le=250)
    weightKg: float = Field(ge=25, le=300)
    medicalHistory: MedicalHistory
    lifestyleFactors: LifestyleFactors


class NotificationPrefs(_Strict):
    """D-45. Urgent safety alerts are always sent regardless."""

    medicationReminders: bool = True
    healthUpdates: bool = True


class AddressUpdate(BaseModel):
    """D-69: the patient's delivery address; the map point is optional (typed address)."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    address: str = Field(min_length=5, max_length=300)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
