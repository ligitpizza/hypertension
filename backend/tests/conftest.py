from collections.abc import Callable
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.audit import get_audit_logger
from app.core.auth import get_token_verifier
from app.core.config import Settings, get_settings
from app.core.enums import UserRole
from app.core.rate_limit import RateLimiter
from app.integrations.email import ConsoleEmailClient, EmailMessage, get_email_client
from app.main import create_app
from app.routers.auth import get_failed_login_limiter
from app.services.identity import EmailAlreadyRegisteredError, get_identity_provider
from app.services.users import get_user_repository
from app.services.vitals import get_vitals_repository


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

    def actions(self) -> list[str]:
        return [e["action"] for e in self.entries]


class FakeIdentityProvider:
    """In-memory stand-in for Firebase Auth admin operations."""

    def __init__(self) -> None:
        self.emails: dict[str, str] = {"taken@example.com": "u-existing"}
        self.claims: dict[str, str] = {}
        self._next = 0

    def create_user(self, *, email: str, display_name: str) -> str:
        if email in self.emails:
            raise EmailAlreadyRegisteredError(email)
        self._next += 1
        uid = f"u-staff-{self._next}"
        self.emails[email] = uid
        return uid

    def set_role(self, uid: str, role: UserRole) -> None:
        self.claims[uid] = role.value

    def password_setup_link(self, email: str) -> str:
        return f"https://example.test/reset?email={email}&oob=abc"


class InMemoryUserRepository:
    def __init__(self) -> None:
        self.users: dict[str, dict[str, Any]] = {}
        self.health_profiles: dict[str, dict[str, Any]] = {}
        self.taken_link_codes: set[str] = set()

    def get_user(self, uid: str) -> dict[str, Any] | None:
        return self.users.get(uid)

    def create_user(self, uid: str, data: dict[str, Any]) -> None:
        if uid in self.users:
            raise ValueError("already exists")
        self.users[uid] = dict(data)

    def link_code_exists(self, code: str) -> bool:
        return code in self.taken_link_codes or any(
            u.get("linkCode") == code for u in self.users.values()
        )

    def complete_onboarding(
        self, uid: str, profile: dict[str, Any], user_updates: dict[str, Any]
    ) -> None:
        self.health_profiles[uid] = dict(profile)
        self.users[uid].update(user_updates)


class InMemoryVitalsRepository:
    def __init__(self) -> None:
        self.readings: dict[str, dict[str, Any]] = {}

    def add_reading(self, data: dict[str, Any]) -> str:
        rid = f"r{len(self.readings) + 1}"
        self.readings[rid] = dict(data)
        return rid


class DeliveringEmailClient(ConsoleEmailClient):
    """Records like the fake but reports delivery, like Brevo."""

    def send(self, message: EmailMessage) -> bool:
        super().send(message)
        return True


class FailingEmailClient:
    def send(self, message: EmailMessage) -> bool:
        raise RuntimeError("provider down")


# token -> claims; anything else raises like firebase_admin would.
FAKE_TOKENS: dict[str, dict[str, Any]] = {
    "patient-token": {"uid": "u-patient", "role": "patient", "email": "p@example.com"},
    "family-token": {"uid": "u-family", "role": "family_member", "email": "f@example.com"},
    "doctor-token": {"uid": "u-doctor", "role": "doctor", "email": "d@example.com"},
    "pharmacist-token": {"uid": "u-pharm", "role": "pharmacist", "email": "ph@example.com"},
    "admin-token": {"uid": "u-admin", "role": "admin", "email": "a@example.com"},
    "norole-token": {"uid": "u-new", "email": "n@example.com"},
}


def fake_verify(token: str) -> dict[str, Any]:
    if token not in FAKE_TOKENS:
        raise ValueError("invalid token")
    return FAKE_TOKENS[token]


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def dev_settings(**overrides: Any) -> Settings:
    values: dict[str, Any] = {"app_env": "dev", "internal_jobs_auth": "none", **overrides}
    return Settings(_env_file=None, **values)


MakeClient = Callable[..., TestClient]


@pytest.fixture
def audit() -> InMemoryAuditLogger:
    return InMemoryAuditLogger()


@pytest.fixture
def identity() -> FakeIdentityProvider:
    return FakeIdentityProvider()


@pytest.fixture
def repo() -> InMemoryUserRepository:
    return InMemoryUserRepository()


@pytest.fixture
def emails() -> ConsoleEmailClient:
    return DeliveringEmailClient()


@pytest.fixture
def vitals_repo() -> InMemoryVitalsRepository:
    return InMemoryVitalsRepository()


@pytest.fixture
def limiter() -> RateLimiter:
    return RateLimiter(max_events=3)


@pytest.fixture
def make_client(
    audit: InMemoryAuditLogger,
    identity: FakeIdentityProvider,
    repo: InMemoryUserRepository,
    emails: ConsoleEmailClient,
    limiter: RateLimiter,
    vitals_repo: InMemoryVitalsRepository,
) -> MakeClient:
    def _make(settings: Settings | None = None) -> TestClient:
        s = settings or dev_settings()
        app = create_app(s)
        app.dependency_overrides[get_settings] = lambda: s
        app.dependency_overrides[get_token_verifier] = lambda: fake_verify
        app.dependency_overrides[get_audit_logger] = lambda: audit
        app.dependency_overrides[get_identity_provider] = lambda: identity
        app.dependency_overrides[get_user_repository] = lambda: repo
        app.dependency_overrides[get_email_client] = lambda: emails
        app.dependency_overrides[get_failed_login_limiter] = lambda: limiter
        app.dependency_overrides[get_vitals_repository] = lambda: vitals_repo
        return TestClient(app)

    return _make


@pytest.fixture
def client(make_client: MakeClient) -> TestClient:
    return make_client()
