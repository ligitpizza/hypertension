"""AI Health Agent endpoints (FR-14.1; UC2.6, UC2.7; docs/05 POST /agent/chat; D-34).

POST /agent/chat       patient question -> grounded reply (or safe emergency reply)
POST /agent/proactive  status update after the latest reading, with action buttons
"""

from functools import lru_cache
from typing import Any

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field

from app.core.auth import CurrentUser, require_roles
from app.core.config import get_settings
from app.core.enums import UserRole
from app.core.errors import ApiError
from app.core.rate_limit import RateLimiter
from app.integrations.gemini import LlmClient, get_llm_client
from app.services.agent import HealthAgent, NoReadingError
from app.services.agent_context import AgentDataRepository, get_agent_data_repository
from app.services.escalation import Escalator, get_escalator
from app.services.settings import (
    SettingsRepository,
    get_settings_repository,
    parse_profile_field,
)

router = APIRouter(prefix="/agent", tags=["agent"])


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    message: str = Field(min_length=1, max_length=1000)


@lru_cache
def _agent_limiter() -> RateLimiter:
    return RateLimiter(get_settings().agent_rate_per_minute)


def get_agent_limiter() -> RateLimiter:
    return _agent_limiter()


def get_health_agent(
    repo: AgentDataRepository = Depends(get_agent_data_repository),
    llm: LlmClient = Depends(get_llm_client),
    escalator: Escalator = Depends(get_escalator),
) -> HealthAgent:
    return HealthAgent(repo, llm, escalator)


def _limit(user: CurrentUser, limiter: RateLimiter) -> None:
    if not limiter.allow(user.uid):
        raise ApiError(
            "TOO_MANY_REQUESTS",
            "You're sending messages quickly. Please wait a moment and try again.",
            status.HTTP_429_TOO_MANY_REQUESTS,
        )


@router.post("/chat")
def chat(
    body: ChatRequest,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    agent: HealthAgent = Depends(get_health_agent),
    limiter: RateLimiter = Depends(get_agent_limiter),
) -> dict[str, Any]:
    _limit(user, limiter)
    result = agent.chat(user.uid, body.message)
    return {"reply": result.reply, "emergency": result.emergency, "fallback": result.fallback}


@router.post("/proactive")
def proactive(
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT)),
    agent: HealthAgent = Depends(get_health_agent),
    limiter: RateLimiter = Depends(get_agent_limiter),
    profiles: SettingsRepository = Depends(get_settings_repository),
) -> dict[str, Any]:
    _limit(user, limiter)
    try:
        result = agent.proactive(user.uid)
    except NoReadingError as exc:
        raise ApiError("NO_READING", str(exc), status.HTTP_409_CONFLICT) from exc
    return {
        "text": result.text,
        "riskLevel": result.risk_level.value if result.risk_level else None,
        "actions": result.actions,
        "fallback": result.fallback,
        # D-72: the Critical "Call emergency contact" button dials this number.
        "emergencyContactPhone": _emergency_phone(profiles, user.uid),
    }


def _emergency_phone(profiles: SettingsRepository, uid: str) -> str | None:
    try:
        personal = parse_profile_field((profiles.health_profile(uid) or {}).get("personalInfo"))
    except Exception:
        return None
    contact = personal.get("emergencyContact")
    phone = contact.get("phone") if isinstance(contact, dict) else None
    return str(phone) if phone else None
