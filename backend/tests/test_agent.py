"""AI Health Agent (FR-14.1; UC2.6, UC2.6 A1/E1, UC2.7; Fig 4.1.1.16; D-34)."""

import json
from datetime import UTC, datetime
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.rate_limit import RateLimiter
from app.integrations.gemini import FakeLlmClient
from app.services.agent import (
    EMERGENCY_REPLY,
    FALLBACK_REPLY,
    SYSTEM_PROMPT,
    detect_emergency,
)
from app.services.agent_context import SECTIONS, build_context
from tests.conftest import (
    InMemoryAgentDataRepository,
    InMemoryAlertRepository,
    InMemoryRiskRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    bearer,
)

NOW = datetime(2026, 10, 13, 9, tzinfo=UTC)
P = "u-patient"
PATIENT = bearer("patient-token")


@pytest.fixture(autouse=True)
def patient(repo: InMemoryUserRepository) -> None:
    repo.users[P] = {
        "name": "Siti",
        "role": "patient",
        "isActive": True,
        "gender": "female",
        "dateOfBirth": datetime(1966, 10, 20, tzinfo=UTC),
        "assignedDoctorId": "u-doctor",
    }
    repo.health_profiles[P] = {
        "medicalHistory": json.dumps(
            {"conditions": ["diabetes"], "hypertensionDiagnosedYear": 2015, "familyHistory": []}
        ),
        "lifestyleFactors": json.dumps({"smokingStatus": "never", "saltIntake": "high"}),
    }


def add_reading(vitals: InMemoryVitalsRepository, sys: int, dia: int, **extra: Any) -> None:
    vitals.add_reading(
        {"patientId": P, "systolic": sys, "diastolic": dia, "timestamp": NOW, **extra}
    )


def add_risk(risk: InMemoryRiskRepository, level: str, value: float = 0.31) -> None:
    risk.saved.append(
        {
            "patientId": P,
            "generatedAt": NOW,
            "scores": {
                "stroke": {"value": value, "level": level},
                "ckd": {"value": 0.004, "level": "low"},
            },
        }
    )


# ---------- UC-14.1.3 deterministic danger check ----------


@pytest.mark.parametrize(
    "text",
    [
        "I have chest pain",
        "my chest feels tight",
        "I can't breathe properly",
        "shortness of breath since morning",
        "my face is drooping and my arm feels weak",
        "I think I'm having a stroke",
        "I fainted in the bathroom",
        "worst headache of my life",
        "sudden blurred vision",
        "saya sakit dada",
    ],
)
def test_uc14_1_3_emergency_phrases_are_detected(text: str) -> None:
    assert detect_emergency(text) == "emergency"


@pytest.mark.parametrize("text", ["I want to kill myself", "thinking about suicide"])
def test_self_harm_is_detected(text: str) -> None:
    assert detect_emergency(text) == "self_harm"


@pytest.mark.parametrize(
    "text",
    [
        "What is my stroke risk?",
        "Explain my stroke score",
        "I feel fit today",
        "I can't see my readings in the app",
        "What was my blood pressure yesterday?",
        "Should I exercise?",
    ],
)
def test_normal_questions_are_not_flagged(text: str) -> None:
    assert detect_emergency(text) is None


# ---------- UC2.6 step 2: context ----------


def test_uc2_6_context_contains_patient_data_and_empty_sections(
    agent_repo: InMemoryAgentDataRepository,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
) -> None:
    add_reading(vitals_repo, 152, 96, heartRate=78)
    add_risk(risk_repo, "high")
    ctx = build_context(agent_repo, P, NOW)
    assert "Name: Siti, age 59, female" in ctx
    assert "152/96 mmHg (stage2), heart rate 78 bpm (camera estimate)" in ctx
    assert "overall high" in ctx
    assert "stroke: 31% (high)" in ctx
    assert "conditions: diabetes" in ctx
    assert "salt intake: high" in ctx
    # Modules not built yet say so instead of failing (fill in automatically later).
    assert "MEDICATIONS: none recorded." in ctx
    assert "UPCOMING APPOINTMENTS: none booked." in ctx
    assert len(SECTIONS) == 8


def test_context_picks_up_medications_and_care_plan_when_present(
    agent_repo: InMemoryAgentDataRepository,
) -> None:
    agent_repo.meds[P] = [
        {"name": "Lisinopril", "dosage": "10mg", "schedule": "morning", "adherenceRate": 85}
    ]
    agent_repo.plans[P] = {"content": "Target BP below 130/80", "updatedAt": NOW}
    ctx = build_context(agent_repo, P, NOW)
    assert "- Lisinopril 10mg, morning, adherence 85%" in ctx
    assert "Target BP below 130/80" in ctx


# ---------- POST /agent/chat ----------


def test_uc2_6_chat_sends_context_and_history_and_saves_both_messages(
    client: TestClient,
    llm: FakeLlmClient,
    agent_repo: InMemoryAgentDataRepository,
    vitals_repo: InMemoryVitalsRepository,
) -> None:
    add_reading(vitals_repo, 141, 91)
    agent_repo.add_message(P, "patient", "hello")
    agent_repo.add_message(P, "agent", "Hi Siti")
    res = client.post("/api/v1/agent/chat", json={"message": "What was my BP?"}, headers=PATIENT)
    assert res.status_code == 200
    assert res.json() == {
        "reply": "Your last reading was fine.",
        "emergency": False,
        "fallback": False,
    }
    system, history, message = llm.calls[0]
    assert system.startswith(SYSTEM_PROMPT)
    assert "141/91 mmHg" in system
    assert [t.text for t in history] == ["hello", "Hi Siti"]
    assert message == "What was my BP?"
    assert [(m["role"], m["text"]) for m in agent_repo.messages[-2:]] == [
        ("patient", "What was my BP?"),
        ("agent", "Your last reading was fine."),
    ]


def test_guardrails_are_in_the_system_prompt() -> None:
    for rule in ("not a doctor", "Never diagnose", "call 999", "estimate"):
        assert rule in SYSTEM_PROMPT


def test_uc2_6_e1_gemini_failure_shows_fallback(
    client: TestClient, llm: FakeLlmClient, agent_repo: InMemoryAgentDataRepository
) -> None:
    llm.fail = True
    body = client.post("/api/v1/agent/chat", json={"message": "hi"}, headers=PATIENT).json()
    assert body == {"reply": FALLBACK_REPLY, "emergency": False, "fallback": True}
    assert [m["role"] for m in agent_repo.messages] == ["patient"]


def test_uc14_1_3_emergency_message_skips_gemini_and_alerts_doctor(
    client: TestClient,
    llm: FakeLlmClient,
    agent_repo: InMemoryAgentDataRepository,
    alerts_repo: InMemoryAlertRepository,
    tokens: InMemoryTokenRepository,
) -> None:
    res = client.post(
        "/api/v1/agent/chat", json={"message": "I have crushing chest pain"}, headers=PATIENT
    )
    assert res.json() == {"reply": EMERGENCY_REPLY, "emergency": True, "fallback": False}
    assert "999" in EMERGENCY_REPLY
    assert llm.calls == []
    [alert] = alerts_repo.alerts
    assert alert["type"] == "flagged_message"
    assert alert["severity"] == "critical"
    assert alert["doctorId"] == "u-doctor"
    assert "chest pain" in alert["message"]
    assert agent_repo.messages[-1]["text"] == EMERGENCY_REPLY


def test_self_harm_reply_gives_999_and_helpline(client: TestClient) -> None:
    body = client.post(
        "/api/v1/agent/chat", json={"message": "I want to end my life"}, headers=PATIENT
    ).json()
    assert body["emergency"] is True
    assert "999" in body["reply"] and "15555" in body["reply"]


def test_agent_is_rate_limited(client: TestClient, agent_limiter: RateLimiter) -> None:
    agent_limiter._max = 2
    for _ in range(2):
        assert (
            client.post("/api/v1/agent/chat", json={"message": "hi"}, headers=PATIENT).status_code
            == 200
        )
    res = client.post("/api/v1/agent/chat", json={"message": "hi"}, headers=PATIENT)
    assert res.status_code == 429


@pytest.mark.parametrize("message", ["", "x" * 1001])
def test_message_length_is_validated(client: TestClient, message: str) -> None:
    res = client.post("/api/v1/agent/chat", json={"message": message}, headers=PATIENT)
    assert res.status_code == 422


@pytest.mark.parametrize("token", ["doctor-token", "family-token", "admin-token"])
def test_only_patients_use_the_agent(client: TestClient, token: str) -> None:
    res = client.post("/api/v1/agent/chat", json={"message": "hi"}, headers=bearer(token))
    assert res.status_code == 403


# ---------- UC2.7 proactive update ----------


def proactive(client: TestClient) -> dict[str, Any]:
    res = client.post("/api/v1/agent/proactive", headers=PATIENT)
    assert res.status_code == 200, res.text
    body: dict[str, Any] = res.json()
    return body


def test_uc2_7_needs_a_reading(client: TestClient) -> None:
    res = client.post("/api/v1/agent/proactive", headers=PATIENT)
    assert res.status_code == 409


def test_uc2_7_low_risk_has_no_action_buttons(
    client: TestClient,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
    agent_repo: InMemoryAgentDataRepository,
    llm: FakeLlmClient,
) -> None:
    add_reading(vitals_repo, 118, 76)
    add_risk(risk_repo, "low", 0.02)
    body = proactive(client)
    assert body == {
        "text": "Your last reading was fine.",
        "riskLevel": "low",
        "actions": [],
        "fallback": False,
    }
    assert "118/76" in llm.calls[0][2]
    assert agent_repo.messages[-1] == {"patientId": P, "role": "agent", "text": body["text"]}


def test_uc2_7_high_risk_offers_booking_and_medications(
    client: TestClient, vitals_repo: InMemoryVitalsRepository, risk_repo: InMemoryRiskRepository
) -> None:
    add_reading(vitals_repo, 150, 95)
    add_risk(risk_repo, "high")
    assert proactive(client)["actions"] == ["book_appointment", "view_medications"]


def test_uc2_7_crisis_reading_gets_emergency_actions_even_without_risk_score(
    client: TestClient, vitals_repo: InMemoryVitalsRepository, llm: FakeLlmClient
) -> None:
    add_reading(vitals_repo, 186, 122)
    body = proactive(client)
    assert body["riskLevel"] is None
    assert body["actions"] == [
        "book_emergency_appointment",
        "call_emergency_contact",
        "alert_family",
    ]
    assert "999" in llm.calls[0][2]


def test_uc2_7_gemini_failure_falls_back_to_rule_text(
    client: TestClient,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
    llm: FakeLlmClient,
) -> None:
    llm.fail = True
    add_reading(vitals_repo, 186, 122)
    add_risk(risk_repo, "critical", 0.6)
    body = proactive(client)
    assert body["fallback"] is True
    assert "call 999" in body["text"]


# ---------- Gemini adapter retry (live check: Gemini returned 503 at a busy time) ----------


class _Resp:
    def __init__(self, status: int, payload: dict[str, Any] | None = None) -> None:
        import httpx

        self.status_code = status
        self._payload = payload or {}
        self._req = httpx.Request("POST", "https://example.test")

    def raise_for_status(self) -> None:
        import httpx

        if self.status_code >= 400:
            raise httpx.HTTPStatusError(
                "err", request=self._req, response=httpx.Response(self.status_code)
            )

    def json(self) -> dict[str, Any]:
        return self._payload


OK = {"candidates": [{"content": {"parts": [{"text": "Hello"}]}}]}


def _client(monkeypatch: pytest.MonkeyPatch, responses: list[_Resp]) -> Any:
    import app.integrations.gemini as g

    calls: list[dict[str, Any]] = []

    def fake_post(url: str, **kwargs: Any) -> _Resp:
        calls.append(kwargs["json"])
        return responses.pop(0)

    monkeypatch.setattr("app.integrations.gemini.httpx.post", fake_post)
    monkeypatch.setattr(g, "RETRY_DELAY_SECONDS", 0)
    return g.GeminiClient("key", "gemini-3.1-flash-lite", 5), calls


def test_gemini_retries_once_on_503(monkeypatch: pytest.MonkeyPatch) -> None:
    client, calls = _client(monkeypatch, [_Resp(503), _Resp(200, OK)])
    assert client.generate("sys", [], "hi") == "Hello"
    assert len(calls) == 2
    assert calls[0]["generationConfig"]["thinkingConfig"] == {"thinkingLevel": "low"}


def test_gemini_gives_up_after_the_retry(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.integrations.gemini import LlmError

    client, calls = _client(monkeypatch, [_Resp(503), _Resp(503)])
    with pytest.raises(LlmError):
        client.generate("sys", [], "hi")
    assert len(calls) == 2


def test_gemini_does_not_retry_a_bad_request(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.integrations.gemini import LlmError

    client, calls = _client(monkeypatch, [_Resp(400)])
    with pytest.raises(LlmError):
        client.generate("sys", [], "hi")
    assert len(calls) == 1
