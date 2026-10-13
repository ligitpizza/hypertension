"""AI Health Agent (FR-14.1; UC2.6, UC2.7; Fig 4.1.1.16; docs/06 §G; D-34).

- chat(): context-grounded answer from Gemini, with guardrails in the system prompt.
- A dangerous message (deterministic keyword check, UC-14.1.3) never goes to Gemini:
  the patient gets a fixed safe reply with 999 wording and the assigned doctor gets a
  `flagged_message` clinical alert.
- proactive(): short status update after a reading; action buttons chosen by rule.
- Gemini failure or timeout: fallback text suggesting the care team (UC2.6 E1).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import UTC, datetime

from app.core.enums import BpCategory, ClinicalAlertType, RiskLevel
from app.integrations.gemini import LlmClient, LlmError
from app.services.agent_context import HISTORY_TURNS, AgentDataRepository, build_context
from app.services.bp import classify
from app.services.escalation import DoctorAlert, EscalationPlan, Escalator
from app.services.recommendations import DISCLAIMER

SYSTEM_PROMPT = """You are the CareFlow Health Assistant, helping an adult patient in Malaysia
manage high blood pressure. You are not a doctor.

Rules:
- Use plain, warm, simple English. Keep answers short (usually under 120 words).
- Use ONLY the patient data below for facts about this patient. If something is not in the
  data, say you don't have that information. Never invent readings, dates or medicines.
- When the patient asks about their readings or risk, quote the actual values and dates.
- Risk percentages are estimates from a machine-learning model, not a diagnosis.
- Never diagnose, never prescribe, never tell the patient to start, stop or change a medicine
  or dose. For medicine questions, tell them to ask their doctor or pharmacist.
- For anything serious or worrying, advise contacting their doctor. For emergency symptoms
  (chest pain, breathing difficulty, stroke signs, fainting, very high readings with symptoms)
  tell them to call 999 immediately.
- Heart rate from the phone camera is an estimate.
- Do not use markdown headings or tables.

PATIENT DATA:
"""

FALLBACK_REPLY = (
    "Sorry, I can't answer right now. Please try again in a few minutes. If you need advice "
    "now, contact your doctor or care team directly. If it is an emergency, call 999."
)

_EMERGENCY = [
    r"chest (feels |is )?(pain|tight|pressure|hurt|heavy)",
    r"pain in (my )?chest",
    r"(can'?t|cannot|can not|hard to|struggling to|difficulty) breath",
    r"short(ness)? of breath",
    r"face (is )?(droop|drooping)",
    r"slurred speech|can'?t (speak|talk) properly",
    r"(numb|weak)(ness)? (on |in )?(one|my left|my right|left|right) side",
    r"(arm|leg) (is |feels )?(suddenly )?(weak|numb)",
    # Not a bare "stroke": "what is my stroke risk?" is a normal question.
    r"(having|had|think i'?m having) a stroke|stroke symptoms",
    r"\bfainted\b|passed out|unconscious|\bcollapsed?\b",
    r"worst headache|severe headache|sudden (severe )?headache",
    r"(lost|losing|loss of|sudden) (my )?(vision|sight)|blurred vision|can'?t see properly",
    r"\bseizure",
    r"sakit dada|sesak nafas|\bpengsan\b",
]
_SELF_HARM = [
    r"suicid",
    r"kill (myself|me)",
    r"end (my|it all|my life)",
    r"want to die",
    r"self[- ]?harm|hurt myself",
    r"bunuh diri",
]

EMERGENCY_REPLY = (
    "What you describe could be serious. Please call 999 now or go to the nearest emergency "
    "department. Do not drive yourself. If someone is with you, tell them now. I have let "
    "your doctor know. " + DISCLAIMER
)
SELF_HARM_REPLY = (
    "I'm really sorry you're feeling this way. You don't have to go through this alone. "
    "If you are in danger or might act on these thoughts, call 999 now. You can also talk to "
    "someone at Talian HEAL 15555. Please reach out to someone you trust. I have let your "
    "doctor know so they can support you."
)


def detect_emergency(text: str) -> str | None:
    """'self_harm', 'emergency' or None. Deterministic so it is testable (UC-14.1.3)."""
    t = text.lower()
    if any(re.search(p, t) for p in _SELF_HARM):
        return "self_harm"
    if any(re.search(p, t) for p in _EMERGENCY):
        return "emergency"
    return None


@dataclass
class ChatResult:
    reply: str
    emergency: bool = False
    fallback: bool = False


@dataclass
class ProactiveResult:
    text: str
    risk_level: RiskLevel | None
    actions: list[str] = field(default_factory=list)
    fallback: bool = False


# UC2.7 table (docs/06 §G): buttons by risk level.
ACTIONS = {
    RiskLevel.HIGH: ["book_appointment", "view_medications"],
    RiskLevel.CRITICAL: [
        "book_emergency_appointment",
        "call_emergency_contact",
        "alert_family",
    ],
}


class NoReadingError(Exception):
    pass


class HealthAgent:
    def __init__(self, repo: AgentDataRepository, llm: LlmClient, escalator: Escalator) -> None:
        self._repo = repo
        self._llm = llm
        self._escalator = escalator

    def chat(self, uid: str, message: str, now: datetime | None = None) -> ChatResult:
        now = now or datetime.now(UTC)
        history = self._repo.recent_turns(uid, HISTORY_TURNS)
        self._repo.add_message(uid, "patient", message)

        kind = detect_emergency(message)
        if kind is not None:
            user = self._repo.user(uid) or {}
            name = user.get("name") or "A patient"
            label = "possible self-harm" if kind == "self_harm" else "emergency symptoms"
            plan = EscalationPlan(
                doctor_alerts=[
                    DoctorAlert(
                        ClinicalAlertType.FLAGGED_MESSAGE,
                        RiskLevel.CRITICAL,
                        f'AI agent: {name} reported {label}: "{message[:200]}"',
                    )
                ]
            )
            self._escalator.apply(plan, uid, user.get("assignedDoctorId"), now)
            reply = SELF_HARM_REPLY if kind == "self_harm" else EMERGENCY_REPLY
            self._repo.add_message(uid, "agent", reply)
            return ChatResult(reply, emergency=True)

        system = SYSTEM_PROMPT + build_context(self._repo, uid, now)
        try:
            reply = self._llm.generate(system, history, message)
        except LlmError:
            return ChatResult(FALLBACK_REPLY, fallback=True)
        self._repo.add_message(uid, "agent", reply)
        return ChatResult(reply)

    def proactive(self, uid: str, now: datetime | None = None) -> ProactiveResult:
        """UC2.7: status update after the latest reading."""
        now = now or datetime.now(UTC)
        readings = self._repo.readings_since(uid, datetime(1970, 1, 1, tzinfo=UTC))
        if not readings:
            raise NoReadingError("Log a reading first.")
        latest = readings[0]
        category = classify(int(latest["systolic"]), int(latest["diastolic"]))
        risk = self._repo.latest_risk(uid)
        order = list(RiskLevel)
        level = (
            max((RiskLevel(s["level"]) for s in risk["scores"].values()), key=order.index)
            if risk and risk.get("scores")
            else None
        )
        # A crisis-range reading gets the emergency buttons whatever the model says.
        effective = RiskLevel.CRITICAL if category is BpCategory.CRISIS else level
        actions = ACTIONS.get(effective, []) if effective else []

        instruction = (
            "Write a short status update (at most 80 words) for the patient about the reading "
            f"they just logged ({latest['systolic']}/{latest['diastolic']} mmHg, "
            f"{category.value}) and their overall risk level "
            f"({level.value if level else 'not available yet'}). Explain it simply and give one "
            "or two practical next steps. "
            + (
                "Their reading or risk is critical: tell them calmly to call 999 if they have "
                "chest pain, breathlessness, weakness or confusion, and to contact their doctor "
                "today. "
                if effective is RiskLevel.CRITICAL
                else "Their risk is high: suggest booking an appointment with their doctor. "
                if effective is RiskLevel.HIGH
                else ""
            )
            + "Do not greet with a long introduction."
        )
        system = SYSTEM_PROMPT + build_context(self._repo, uid, now)
        fallback = False
        try:
            text = self._llm.generate(system, [], instruction)
        except LlmError:
            fallback = True
            text = _rule_based_update(latest, category, effective)
        self._repo.add_message(uid, "agent", text)
        return ProactiveResult(text, level, actions, fallback)


def _rule_based_update(
    latest: dict[str, object], category: BpCategory, level: RiskLevel | None
) -> str:
    bp = f"{latest['systolic']}/{latest['diastolic']} mmHg"
    if level is RiskLevel.CRITICAL:
        return (
            f"Your reading of {bp} needs attention. If you have chest pain, breathlessness, "
            "weakness or confusion, call 999 now. Otherwise, rest and contact your doctor today."
        )
    if level is RiskLevel.HIGH:
        return (
            f"Your reading is {bp}. Your risk assessment is high, so please book an "
            "appointment with your doctor soon and keep taking your medicines as prescribed."
        )
    if category in (BpCategory.STAGE1, BpCategory.STAGE2):
        return (
            f"Your reading is {bp}, which is above target. Rest, cut down on salt and keep logging."
        )
    return f"Your reading is {bp}. Keep up your routine and keep logging your readings."
