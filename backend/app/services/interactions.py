"""Drug interaction check (UC5.6, UC8.4 E1; docs/06 §C).

Matches medicine names against a small static class table (interactions.json) and
reports interacting pairs plus duplicate therapy (two medicines of the same class).
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

_TABLE = Path(__file__).with_name("interactions.json")
SEVERITY_ORDER = ("minor", "major", "critical")


@dataclass(frozen=True)
class Interaction:
    new_drug: str
    existing_drug: str
    severity: str
    message: str

    def to_dict(self) -> dict[str, str]:
        return {
            "newDrug": self.new_drug,
            "existingDrug": self.existing_drug,
            "severity": self.severity,
            "message": self.message,
        }


@lru_cache
def _table() -> dict[str, Any]:
    data: dict[str, Any] = json.loads(_TABLE.read_text(encoding="utf-8"))
    return data


def drug_classes(name: str) -> set[str]:
    text = name.lower()
    return {cls for cls, drugs in _table()["classes"].items() if any(d in text for d in drugs)}


def check(new_drug: str, current: list[str]) -> list[Interaction]:
    """Interactions between `new_drug` and each of the patient's current medicines."""
    new_classes = drug_classes(new_drug)
    found: list[Interaction] = []
    if not new_classes:
        return found
    for existing in current:
        existing_classes = drug_classes(existing)
        for pair in _table()["pairs"]:
            a, b = pair["a"], pair["b"]
            if (a in new_classes and b in existing_classes) or (
                b in new_classes and a in existing_classes
            ):
                found.append(Interaction(new_drug, existing, pair["severity"], pair["message"]))
        same = new_classes & existing_classes
        if same:
            found.append(
                Interaction(
                    new_drug,
                    existing,
                    "major",
                    f"Duplicate therapy: both are {sorted(same)[0].replace('_', ' ')}s.",
                )
            )
    return sorted(found, key=lambda i: -SEVERITY_ORDER.index(i.severity))
