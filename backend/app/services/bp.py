"""BP classification, threshold alert level and plausible-range validation.

Python mirror of app/lib/core/utils/bp_classifier.dart; both are tested against
docs/fixtures/bp_cases.json (docs/06 §E, FR-9.1, Objective 1).
"""

from app.core.enums import AlertLevel, BpCategory

SYSTOLIC_MIN, SYSTOLIC_MAX = 70, 250
DIASTOLIC_MIN, DIASTOLIC_MAX = 40, 150
HEART_RATE_MIN, HEART_RATE_MAX = 30, 220


def classify(systolic: int, diastolic: int) -> BpCategory:
    """First match, top-down (docs/06 §E)."""
    if systolic >= 180 or diastolic >= 120:
        return BpCategory.CRISIS
    if systolic >= 140 or diastolic >= 90:
        return BpCategory.STAGE2
    if systolic >= 130 or diastolic >= 80:
        return BpCategory.STAGE1
    if systolic >= 120:
        return BpCategory.ELEVATED
    return BpCategory.NORMAL


_ALERTS = {
    BpCategory.STAGE1: AlertLevel.MILD,
    BpCategory.STAGE2: AlertLevel.MODERATE,
    BpCategory.CRISIS: AlertLevel.EMERGENCY,
}


def alert_level(category: BpCategory) -> AlertLevel | None:
    """Threshold alert band (Ch1 §1.4.1): Mild 130-139/80-89, Moderate 140-179/90-119,
    Emergency >=180/>=120. Normal and elevated readings raise no alert."""
    return _ALERTS.get(category)


def plausibility_error(systolic: int, diastolic: int, heart_rate: int | None) -> str | None:
    """UC3.1 E1: return a user-facing reason when the reading is not physiologically plausible."""
    if not SYSTOLIC_MIN <= systolic <= SYSTOLIC_MAX:
        return f"Systolic must be between {SYSTOLIC_MIN} and {SYSTOLIC_MAX} mmHg."
    if not DIASTOLIC_MIN <= diastolic <= DIASTOLIC_MAX:
        return f"Diastolic must be between {DIASTOLIC_MIN} and {DIASTOLIC_MAX} mmHg."
    if systolic <= diastolic:
        return "Systolic (top number) must be higher than diastolic (bottom number)."
    if heart_rate is not None and not HEART_RATE_MIN <= heart_rate <= HEART_RATE_MAX:
        return f"Heart rate must be between {HEART_RATE_MIN} and {HEART_RATE_MAX} bpm."
    return None
