"""Gemini Flash adapter for the AI Health Agent (FR-14.1, docs/06 §G).

Gemini is called only from FastAPI, never from Flutter, so the API key stays on the
server. Without GEMINI_API_KEY (tests, offline development) a fake client answers.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Any, Literal, Protocol

import httpx

from app.core.config import get_settings

log = logging.getLogger("careflow.gemini")

API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
# One retry for overload / rate limit / timeout, which Gemini returns at busy times.
RETRIES = 1
RETRY_DELAY_SECONDS = 1.5


def _transient(exc: Exception) -> bool:
    if isinstance(exc, httpx.TimeoutException):
        return True
    return isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code in (429, 500, 503)


def _describe(exc: Exception) -> str:
    if isinstance(exc, httpx.HTTPStatusError):
        return f"HTTP {exc.response.status_code}"
    return type(exc).__name__


@dataclass(frozen=True)
class Turn:
    role: Literal["patient", "agent"]
    text: str


class LlmError(Exception):
    """Gemini failed, timed out or returned nothing usable (UC2.6 E1)."""


class LlmClient(Protocol):
    def generate(self, system: str, history: list[Turn], message: str) -> str: ...


class GeminiClient:
    def __init__(self, api_key: str, model: str, timeout: float) -> None:
        self._key = api_key
        self._model = model
        self._timeout = timeout

    def generate(self, system: str, history: list[Turn], message: str) -> str:
        contents = [
            {"role": "user" if t.role == "patient" else "model", "parts": [{"text": t.text}]}
            for t in history
        ]
        contents.append({"role": "user", "parts": [{"text": message}]})
        config: dict[str, Any] = {"temperature": 0.4, "maxOutputTokens": 1024}
        # Short health answers need little "thinking"; it mainly adds latency.
        if "2.5-flash" in self._model:
            config["thinkingConfig"] = {"thinkingBudget": 0}
        elif self._model.startswith("gemini-3"):
            config["thinkingConfig"] = {"thinkingLevel": "low"}
        body = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": contents,
            "generationConfig": config,
        }
        text = ""
        for attempt in range(1 + RETRIES):
            try:
                res = httpx.post(
                    API_URL.format(model=self._model),
                    headers={"x-goog-api-key": self._key},
                    json=body,
                    timeout=self._timeout,
                )
                res.raise_for_status()
                parts = res.json()["candidates"][0]["content"]["parts"]
                text = "".join(p.get("text", "") for p in parts).strip()
                break
            except (httpx.HTTPError, KeyError, IndexError, ValueError) as exc:
                # Never log the request: it contains health data.
                log.warning("Gemini call failed (attempt %d): %s", attempt + 1, _describe(exc))
                if attempt < RETRIES and _transient(exc):
                    time.sleep(RETRY_DELAY_SECONDS)
                    continue
                raise LlmError(_describe(exc)) from exc
        if not text:
            raise LlmError("empty reply")
        return text


class FakeLlmClient:
    """Deterministic stand-in: proves the context reached the model without calling it."""

    def __init__(self, reply: str | None = None, fail: bool = False) -> None:
        self.reply = reply
        self.fail = fail
        self.calls: list[tuple[str, list[Turn], str]] = []

    def generate(self, system: str, history: list[Turn], message: str) -> str:
        self.calls.append((system, list(history), message))
        if self.fail:
            raise LlmError("fake failure")
        return self.reply or (
            "(Offline demo reply: no Gemini key configured.) I can see your recent health "
            "information. Please ask your doctor about anything that worries you."
        )


def get_llm_client() -> LlmClient:
    s = get_settings()
    if s.gemini_api_key:
        return GeminiClient(s.gemini_api_key, s.gemini_model, s.gemini_timeout_seconds)
    return FakeLlmClient()
