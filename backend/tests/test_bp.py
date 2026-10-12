"""BP classifier and plausible range, driven by the shared fixture (Objective 1: thresholds
verified by unit tests; same cases as the Dart classifier)."""

import json
from pathlib import Path
from typing import Any

import pytest

from app.core.enums import AlertLevel, BpCategory
from app.services import bp

FIXTURE: dict[str, Any] = json.loads(
    (Path(__file__).resolve().parents[2] / "docs" / "fixtures" / "bp_cases.json").read_text("utf-8")
)


@pytest.mark.parametrize("case", FIXTURE["cases"], ids=lambda c: f"{c['sys']}/{c['dia']}")
def test_fr_9_1_bp_category_and_alert_level(case: dict[str, Any]) -> None:
    category = bp.classify(case["sys"], case["dia"])
    assert category == BpCategory(case["category"]), case["why"]
    expected_alert = AlertLevel(case["alert"]) if case["alert"] else None
    assert bp.alert_level(category) == expected_alert, case["why"]


@pytest.mark.parametrize("case", FIXTURE["cases"], ids=lambda c: f"{c['sys']}/{c['dia']}")
def test_uc3_1_plausible_cases_pass_validation(case: dict[str, Any]) -> None:
    assert bp.plausibility_error(case["sys"], case["dia"], None) is None


@pytest.mark.parametrize("case", FIXTURE["implausible"], ids=lambda c: c["why"])
def test_uc3_1_e1_implausible_readings_are_rejected(case: dict[str, Any]) -> None:
    assert bp.plausibility_error(case["sys"], case["dia"], None) is not None, case["why"]


def test_uc3_3_heart_rate_range() -> None:
    p = FIXTURE["plausible"]
    assert bp.plausibility_error(120, 80, p["heartRateMin"]) is None
    assert bp.plausibility_error(120, 80, p["heartRateMax"]) is None
    assert bp.plausibility_error(120, 80, p["heartRateMin"] - 1) is not None
    assert bp.plausibility_error(120, 80, p["heartRateMax"] + 1) is not None


def test_plausible_limits_match_fixture() -> None:
    p = FIXTURE["plausible"]
    assert (bp.SYSTOLIC_MIN, bp.SYSTOLIC_MAX) == (p["systolicMin"], p["systolicMax"])
    assert (bp.DIASTOLIC_MIN, bp.DIASTOLIC_MAX) == (p["diastolicMin"], p["diastolicMax"])
    assert (bp.HEART_RATE_MIN, bp.HEART_RATE_MAX) == (p["heartRateMin"], p["heartRateMax"])
