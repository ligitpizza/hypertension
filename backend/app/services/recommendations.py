"""FR-9.4: personalised recommendations from the BP category and risk level.

Rule-based, plain language (NFR-3.1) and never diagnostic or dosage advice. Emergency
wording points to 999 (CLAUDE.md health-safety rules).
"""

from __future__ import annotations

from app.core.enums import BpCategory, Complication, RiskLevel
from app.ml.risk_model import RiskPrediction

_BP = {
    BpCategory.NORMAL: "Your reading is in the normal range. Keep up your current routine.",
    BpCategory.ELEVATED: "Your reading is slightly above normal. Cut down on salty food and "
    "stay active most days.",
    BpCategory.STAGE1: "Your reading is high (stage 1). Rest for 5 minutes and measure again, "
    "and keep logging readings at the same time each day.",
    BpCategory.STAGE2: "Your reading is high (stage 2). Avoid heavy exertion today, take your "
    "medicines as prescribed and contact your doctor.",
    BpCategory.CRISIS: "Your reading is very high. Sit quietly and measure again in 5 minutes. "
    "If you have chest pain, shortness of breath, weakness, confusion or blurred vision, "
    "call 999 now.",
}

_RISK = {
    RiskLevel.HIGH: "Your risk assessment is high. Please book an appointment with your doctor "
    "soon to review your treatment.",
    RiskLevel.CRITICAL: "Your risk assessment is critical. Contact your doctor today. If you "
    "feel unwell, call 999.",
}

_FOCUS = {
    Complication.STROKE: "Know the stroke warning signs: face drooping, arm weakness, speech "
    "difficulty - call 999 straight away if they appear.",
    Complication.CAD: "Chest discomfort during activity should be checked by your doctor.",
    Complication.HEART_FAILURE: "Tell your doctor about new breathlessness or swollen ankles.",
    Complication.CKD: "Ask your doctor whether a kidney function blood test is due.",
    Complication.T2D: "Ask your doctor whether a blood sugar test is due.",
}

DISCLAIMER = "These tips are general guidance, not a substitute for advice from your doctor."


def recommendations(
    category: BpCategory,
    prediction: RiskPrediction | None,
    diagnosed: set[Complication] | None = None,
) -> list[str]:
    tips = [_BP[category]]
    if prediction is not None:
        overall = prediction.overall_level
        if overall in _RISK:
            tips.append(_RISK[overall])
        diagnosed = diagnosed or set()
        for c, score in prediction.scores.items():
            if c not in diagnosed and score.level in (RiskLevel.HIGH, RiskLevel.CRITICAL):
                tips.append(_FOCUS[c])
    tips.append(DISCLAIMER)
    return tips
