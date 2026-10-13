from collections.abc import Callable
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.audit import get_audit_logger
from app.core.auth import get_token_verifier
from app.core.config import Settings, get_settings
from app.core.enums import ClinicalAlertType, RiskLevel, UserRole
from app.core.rate_limit import RateLimiter
from app.integrations.email import ConsoleEmailClient, EmailMessage, get_email_client
from app.integrations.gemini import FakeLlmClient, Turn, get_llm_client
from app.integrations.push import LogPushClient
from app.main import create_app
from app.ml.risk_model import get_risk_model
from app.routers.agent import get_agent_limiter
from app.routers.auth import get_failed_login_limiter
from app.routers.messages import get_message_repository
from app.services.agent_context import get_agent_data_repository
from app.services.deterioration import get_deterioration_repository
from app.services.escalation import get_alert_repository
from app.services.identity import EmailAlreadyRegisteredError, get_identity_provider
from app.services.notifications import Notifier, get_notifier, get_token_repository
from app.services.provider import get_provider_repository
from app.services.risk import get_risk_data_repository
from app.services.triage import Symptom, get_triage_repository
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


class InMemoryRiskRepository:
    """Shares users/readings with the other in-memory repositories."""

    def __init__(self, users: "InMemoryUserRepository", vitals: "InMemoryVitalsRepository") -> None:
        self._users = users
        self._vitals = vitals
        self.health_profiles: dict[str, dict[str, Any]] = {}
        self.meds: dict[str, list[dict[str, Any]]] = {}
        self.saved: list[dict[str, Any]] = []

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def health_profile(self, uid: str) -> dict[str, Any] | None:
        return self.health_profiles.get(uid) or self._users.health_profiles.get(uid)

    def recent_readings(self, uid: str, limit: int) -> list[dict[str, Any]]:
        mine = [r for r in self._vitals.readings.values() if r["patientId"] == uid]
        return list(reversed(mine))[:limit]

    def medications(self, uid: str) -> list[dict[str, Any]]:
        return self.meds.get(uid, [])

    def save_risk_score(self, data: dict[str, Any]) -> str:
        self.saved.append(data)
        return f"risk{len(self.saved)}"


class FixedPredictor:
    def __init__(self, p: float) -> None:
        self.p = p
        self.rows: list[Any] = []

    def predict_proba(self, x: Any) -> Any:
        import numpy as np

        self.rows.append(x)
        return np.array([[1 - self.p, self.p]])


def fake_risk_model(p: float = 0.3) -> Any:
    from app.core.enums import Complication
    from app.ml.risk_model import RiskModel

    feats = ["age", "systolic", "diastolic", "bmi"]
    cuts = {"moderate": 0.1, "high": 0.25, "critical": 0.5}
    return RiskModel(
        models={c: FixedPredictor(p) for c in Complication},
        features={c: feats for c in Complication},
        thresholds={c: cuts for c in Complication},
        model_used={c: "XGBoost v1" for c in Complication},
    )


class InMemoryTokenRepository:
    def __init__(self) -> None:
        self.by_user: dict[str, dict[str, str]] = {}

    def add(self, uid: str, token: str, platform: str) -> None:
        self.by_user.setdefault(uid, {})[token] = platform

    def remove(self, uid: str, token: str) -> None:
        self.by_user.get(uid, {}).pop(token, None)

    def tokens(self, uid: str) -> list[str]:
        return list(self.by_user.get(uid, {}))


class InMemoryAlertRepository:
    """Reads prior risk scores from the shared in-memory risk repository."""

    def __init__(self, risk: "InMemoryRiskRepository", users: "InMemoryUserRepository") -> None:
        self._risk = risk
        self._users = users
        self.alerts: list[dict[str, Any]] = []

    def latest_levels(self, uid: str) -> dict[str, RiskLevel]:
        mine = [d for d in self._risk.saved if d["patientId"] == uid]
        if not mine:
            return {}
        return {k: RiskLevel(v["level"]) for k, v in mine[-1]["scores"].items()}

    def family_member_ids(self, uid: str) -> list[str]:
        return [
            k
            for k, u in self._users.users.items()
            if u.get("role") == UserRole.FAMILY_MEMBER.value and u.get("patientId") == uid
        ]

    def recent_alert_exists(
        self,
        uid: str,
        alert_type: ClinicalAlertType,
        since: Any,
        at_least: RiskLevel = RiskLevel.LOW,
    ) -> bool:
        order = list(RiskLevel)
        return any(
            a["patientId"] == uid
            and a["type"] == alert_type.value
            and a["createdAt"] >= since
            and order.index(RiskLevel(a["severity"])) >= order.index(at_least)
            for a in self.alerts
        )

    def create_alert(self, data: dict[str, Any]) -> str:
        from datetime import UTC, datetime

        self.alerts.append({**data, "createdAt": data.get("createdAt", datetime.now(UTC))})
        return f"alert{len(self.alerts)}"

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def stale_open_alerts(self, severity: RiskLevel, before: Any) -> list[dict[str, Any]]:
        return [
            {**a, "id": f"alert{i + 1}"}
            for i, a in enumerate(self.alerts)
            if a["status"] == "open"
            and a["severity"] == severity.value
            and a["createdAt"] <= before
        ]


class InMemoryDeteriorationRepository:
    def __init__(self) -> None:
        self.patients: list[tuple[str, dict[str, Any]]] = []
        self.scores: dict[str, list[tuple[Any, dict[str, Any]]]] = {}

    def active_patients(self) -> list[tuple[str, dict[str, Any]]]:
        return self.patients

    def scores_since(self, uid: str, since: Any) -> list[tuple[Any, dict[str, Any]]]:
        return [(t, s) for t, s in self.scores.get(uid, []) if t >= since]


class InMemoryProviderRepository:
    def __init__(self, users: "InMemoryUserRepository") -> None:
        self._users = users
        self.medications: dict[str, list[str]] = {}
        self.notes: list[dict[str, Any]] = []
        self.care_plans: dict[str, dict[str, Any]] = {}
        self.plan_versions: dict[str, list[dict[str, Any]]] = {}
        self.prescriptions: list[dict[str, Any]] = []

    def patient(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def current_medicines(self, uid: str) -> list[str]:
        rx = [p["medicationDetails"] for p in self.prescriptions if p["patientId"] == uid]
        return self.medications.get(uid, []) + rx

    def add_note(self, data: dict[str, Any]) -> str:
        self.notes.append(data)
        return f"note{len(self.notes)}"

    def set_care_plan(self, patient_id: str, data: dict[str, Any]) -> None:
        self.care_plans[patient_id] = data
        self.plan_versions.setdefault(patient_id, []).append(
            {"content": data["content"], "doctorId": data["doctorId"]}
        )

    def add_prescription(self, data: dict[str, Any]) -> str:
        self.prescriptions.append(data)
        return f"rx{len(self.prescriptions)}"


class InMemoryAgentDataRepository:
    """Agent context over the shared in-memory users / readings / risk repositories."""

    def __init__(
        self,
        users: "InMemoryUserRepository",
        vitals: "InMemoryVitalsRepository",
        risk: "InMemoryRiskRepository",
    ) -> None:
        self._users = users
        self._vitals = vitals
        self._risk = risk
        self.meds: dict[str, list[dict[str, Any]]] = {}
        self.appointments: dict[str, list[dict[str, Any]]] = {}
        self.plans: dict[str, dict[str, Any]] = {}
        self.prescriptions: dict[str, list[dict[str, Any]]] = {}
        self.messages: list[dict[str, Any]] = []

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def health_profile(self, uid: str) -> dict[str, Any] | None:
        return self._users.health_profiles.get(uid)

    def readings_since(self, uid: str, since: Any) -> list[dict[str, Any]]:
        mine = [r for r in self._vitals.readings.values() if r["patientId"] == uid]
        mine = [r for r in mine if r.get("timestamp") is None or r["timestamp"] >= since]
        return list(reversed(mine))

    def latest_risk(self, uid: str) -> dict[str, Any] | None:
        mine = [d for d in self._risk.saved if d["patientId"] == uid]
        return mine[-1] if mine else None

    def medications(self, uid: str) -> list[dict[str, Any]]:
        return self.meds.get(uid, [])

    def upcoming_appointments(self, uid: str, now: Any) -> list[dict[str, Any]]:
        return self.appointments.get(uid, [])

    def care_plan(self, uid: str) -> dict[str, Any] | None:
        return self.plans.get(uid)

    def recent_prescriptions(self, uid: str, limit: int) -> list[dict[str, Any]]:
        return self.prescriptions.get(uid, [])[:limit]

    def recent_turns(self, uid: str, limit: int) -> list[Turn]:
        mine = [m for m in self.messages if m["patientId"] == uid][-limit:]
        return [Turn(m["role"], m["text"]) for m in mine]

    def add_message(self, uid: str, role: str, text: str) -> str:
        self.messages.append({"patientId": uid, "role": role, "text": text})
        return f"msg{len(self.messages)}"


class InMemoryTriageRepository:
    """Seeded symptom catalog + the shared in-memory readings and risk scores."""

    def __init__(self, vitals: "InMemoryVitalsRepository", risk: "InMemoryRiskRepository") -> None:
        import json
        from pathlib import Path

        seed = Path(__file__).resolve().parents[2] / "firebase" / "seed" / "symptom_catalog.json"
        self.catalog = {
            s["id"]: Symptom(s["id"], s["name"], s["isRedFlag"])
            for s in json.loads(seed.read_text(encoding="utf-8"))["symptoms"]
        }
        self._vitals = vitals
        self._risk = risk
        self.saved: list[dict[str, Any]] = []

    def symptoms(self, ids: list[str]) -> dict[str, Symptom]:
        return {i: self.catalog[i] for i in ids if i in self.catalog}

    def reading(self, reading_id: str) -> dict[str, Any] | None:
        return self._vitals.readings.get(reading_id)

    def latest_risk_levels(self, uid: str) -> list[RiskLevel]:
        mine = [d for d in self._risk.saved if d["patientId"] == uid]
        if not mine:
            return []
        return [RiskLevel(v["level"]) for v in mine[-1]["scores"].values()]

    def save_outcome(self, data: dict[str, Any]) -> str:
        self.saved.append(data)
        return f"triage{len(self.saved)}"


class InMemoryMessageRepository:
    """Message metadata only (the text is ciphertext the server never reads)."""

    def __init__(self, users: "InMemoryUserRepository") -> None:
        self._users = users
        self.messages: dict[str, dict[str, Any]] = {}

    def message(self, message_id: str) -> dict[str, Any] | None:
        return self.messages.get(message_id)

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)


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
def risk_repo(
    repo: InMemoryUserRepository, vitals_repo: InMemoryVitalsRepository
) -> InMemoryRiskRepository:
    return InMemoryRiskRepository(repo, vitals_repo)


@pytest.fixture
def risk_model() -> Any:
    return fake_risk_model()


@pytest.fixture
def tokens() -> InMemoryTokenRepository:
    return InMemoryTokenRepository()


@pytest.fixture
def push() -> LogPushClient:
    return LogPushClient()


@pytest.fixture
def alerts_repo(
    risk_repo: InMemoryRiskRepository, repo: InMemoryUserRepository
) -> InMemoryAlertRepository:
    return InMemoryAlertRepository(risk_repo, repo)


@pytest.fixture
def deterioration_repo() -> InMemoryDeteriorationRepository:
    return InMemoryDeteriorationRepository()


@pytest.fixture
def provider_repo(repo: InMemoryUserRepository) -> InMemoryProviderRepository:
    return InMemoryProviderRepository(repo)


@pytest.fixture
def agent_repo(
    repo: InMemoryUserRepository,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
) -> InMemoryAgentDataRepository:
    return InMemoryAgentDataRepository(repo, vitals_repo, risk_repo)


@pytest.fixture
def llm() -> FakeLlmClient:
    return FakeLlmClient(reply="Your last reading was fine.")


@pytest.fixture
def agent_limiter() -> RateLimiter:
    return RateLimiter(max_events=100)


@pytest.fixture
def triage_repo(
    vitals_repo: InMemoryVitalsRepository, risk_repo: InMemoryRiskRepository
) -> InMemoryTriageRepository:
    return InMemoryTriageRepository(vitals_repo, risk_repo)


@pytest.fixture
def message_repo(repo: InMemoryUserRepository) -> InMemoryMessageRepository:
    return InMemoryMessageRepository(repo)


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
    risk_repo: InMemoryRiskRepository,
    risk_model: Any,
    tokens: InMemoryTokenRepository,
    push: LogPushClient,
    alerts_repo: InMemoryAlertRepository,
    deterioration_repo: InMemoryDeteriorationRepository,
    provider_repo: InMemoryProviderRepository,
    agent_repo: InMemoryAgentDataRepository,
    llm: FakeLlmClient,
    agent_limiter: RateLimiter,
    triage_repo: InMemoryTriageRepository,
    message_repo: InMemoryMessageRepository,
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
        app.dependency_overrides[get_risk_data_repository] = lambda: risk_repo
        app.dependency_overrides[get_risk_model] = lambda: risk_model
        app.dependency_overrides[get_token_repository] = lambda: tokens
        app.dependency_overrides[get_notifier] = lambda: Notifier(tokens, push)
        app.dependency_overrides[get_alert_repository] = lambda: alerts_repo
        app.dependency_overrides[get_deterioration_repository] = lambda: deterioration_repo
        app.dependency_overrides[get_provider_repository] = lambda: provider_repo
        app.dependency_overrides[get_agent_data_repository] = lambda: agent_repo
        app.dependency_overrides[get_llm_client] = lambda: llm
        app.dependency_overrides[get_agent_limiter] = lambda: agent_limiter
        app.dependency_overrides[get_triage_repository] = lambda: triage_repo
        app.dependency_overrides[get_message_repository] = lambda: message_repo
        return TestClient(app)

    return _make


@pytest.fixture
def client(make_client: MakeClient) -> TestClient:
    return make_client()
