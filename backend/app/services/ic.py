"""Malaysian IC (MyKad) numbers (D-51): YYMMDD-PB-####.

The first six digits are the date of birth, PB the place of birth and the last digit is odd
for males and even for females. Mirrors app/lib/core/utils/ic_number.dart.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date

_DIGITS = re.compile(r"^\d{12}$")


class IcError(ValueError):
    pass


@dataclass(frozen=True)
class IcNumber:
    value: str  # "YYMMDD-PB-####"
    date_of_birth: date
    gender: str  # "male" | "female"


def parse_ic(raw: str, today: date | None = None) -> IcNumber:
    digits = re.sub(r"[\s-]", "", raw)
    if not _DIGITS.match(digits):
        raise IcError("Enter a 12-digit IC number, e.g. 900101-14-5678.")
    today = today or date.today()
    yy, mm, dd = int(digits[:2]), int(digits[2:4]), int(digits[4:6])
    # Born this century unless that would be in the future.
    century = 2000 if 2000 + yy <= today.year else 1900
    try:
        born = date(century + yy, mm, dd)
    except ValueError as exc:
        raise IcError("The first six digits must be a real date of birth (YYMMDD).") from exc
    if born > today:
        raise IcError("The date of birth in the IC number is in the future.")
    gender = "male" if int(digits[-1]) % 2 else "female"
    return IcNumber(f"{digits[:6]}-{digits[6:8]}-{digits[8:]}", born, gender)


def mask_ic(value: str) -> str:
    """900101-14-5678 -> 900101-**-**78 (for staff screens and logs)."""
    return f"{value[:6]}-**-**{value[-2:]}" if len(value) == 14 else "***"
