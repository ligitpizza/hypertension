from collections.abc import Callable
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.audit import get_audit_logger
from app.core.auth import get_token_verifier
from app.core.config import Settings, get_settings
from app.main import create_app


class InMemoryAuditLogger:
    def __init__(self) -> None:
        self.entries: list[dict[str, Any]] = []

    def log(
        self,
        *,
        user_id: str,
        action: str,
        details: str,
        target_type: str | None = None,
        target_id: str | None = None,
    ) -> str:
        self.entries.append(
            {
                "userId": user_id,
                "action": action,
                "details": details,
                "targetType": target_type,
                "targetId": target_id,
            }
        )
        return f"log-{len(self.entries)}"


# token -> claims; anything else raises like firebase_admin would.
FAKE_TOKENS: dict[str, dict[str, Any]] = {
    "patient-token": {"uid": "u-patient", "role": "patient", "email": "p@example.com"},
    "doctor-token": {"uid": "u-doctor", "role": "doctor", "email": "d@example.com"},
    "admin-token": {"uid": "u-admin", "role": "admin", "email": "a@example.com"},
    "norole-token": {"uid": "u-new", "email": "n@example.com"},
}


def fake_verify(token: str) -> dict[str, Any]:
    if token not in FAKE_TOKENS:
        raise ValueError("invalid token")
    return FAKE_TOKENS[token]


def dev_settings(**overrides: Any) -> Settings:
    values: dict[str, Any] = {"app_env": "dev", "internal_jobs_auth": "none", **overrides}
    return Settings(_env_file=None, **values)


MakeClient = Callable[..., TestClient]


@pytest.fixture
def audit() -> InMemoryAuditLogger:
    return InMemoryAuditLogger()


@pytest.fixture
def make_client(audit: InMemoryAuditLogger) -> MakeClient:
    def _make(settings: Settings | None = None) -> TestClient:
        s = settings or dev_settings()
        app = create_app(s)
        app.dependency_overrides[get_settings] = lambda: s
        app.dependency_overrides[get_token_verifier] = lambda: fake_verify
        app.dependency_overrides[get_audit_logger] = lambda: audit
        return TestClient(app)

    return _make


@pytest.fixture
def client(make_client: MakeClient) -> TestClient:
    return make_client()
