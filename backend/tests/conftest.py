# ruff: noqa: E402  (the production guard below must run before the app modules import)
import os

# Tests must never reach the live project. Without these, any repository a test forgets to
# fake falls back to Application Default Credentials (the developer's gcloud login), i.e.
# production. With them, a missing fake fails against localhost instead (it happened once:
# the emergency auto-booking path, 2026-10-15).
# The emulator integration tests run only when the emulators were really started
# (`tasks.py test` sets the variables); remember that before filling in the guard values.
EMULATORS_STARTED = bool(
    os.environ.get("FIRESTORE_EMULATOR_HOST") and os.environ.get("FIREBASE_AUTH_EMULATOR_HOST")
)
for _var, _host in (
    ("FIRESTORE_EMULATOR_HOST", "localhost:8080"),
    ("FIREBASE_AUTH_EMULATOR_HOST", "localhost:9099"),
    ("FIREBASE_STORAGE_EMULATOR_HOST", "localhost:9199"),
):
    os.environ.setdefault(_var, _host)
# The D-57 testing aid in a developer's backend/.env must not change test behaviour.
os.environ["DEV_APPOINTMENT_TIMES"] = "false"

from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.audit import get_audit_logger
from app.core.auth import get_token_verifier
from app.core.config import Settings, get_settings
from app.core.enums import ClinicalAlertType, RiskLevel, UserRole
from app.core.rate_limit import RateLimiter
from app.integrations.delivery import FakeGrabClient, get_courier_client
from app.integrations.email import ConsoleEmailClient, EmailMessage, get_email_client
from app.integrations.gemini import FakeLlmClient, Turn, get_llm_client
from app.integrations.payments import FakeGateway, get_payment_gateway
from app.integrations.push import LogPushClient
from app.integrations.sms import LogSmsClient, get_sms_client
from app.main import create_app
from app.ml.risk_model import get_risk_model
from app.routers.agent import get_agent_limiter
from app.routers.auth import get_failed_login_limiter, get_reset_limiter
from app.routers.messages import get_message_repository
from app.services.agent_context import get_agent_data_repository
from app.services.analytics import get_analytics_source
from app.services.appointments import get_appointment_repository
from app.services.assignments import get_assignment_repository
from app.services.audit_view import get_audit_reader
from app.services.catalog import get_catalog_repository
from app.services.conversations import get_conversation_repository
from app.services.deterioration import get_deterioration_repository
from app.services.escalation import get_alert_repository
from app.services.family import get_family_repository
from app.services.identity import EmailAlreadyRegisteredError, get_identity_provider
from app.services.inbox import get_inbox_repository
from app.services.medications import MedicationDoc, get_medication_repository
from app.services.notifications import Notifier, get_notifier, get_token_repository
from app.services.orders import get_order_repository
from app.services.pharmacy_chat import get_pharmacy_chat_repository
from app.services.provider import get_provider_repository
from app.services.records import get_file_store, get_record_repository
from app.services.risk import get_risk_data_repository
from app.services.settings import get_settings_repository
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
        self.revoked: list[str] = []
        self.deleted: list[str] = []
        self.disabled: set[str] = set()
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

    def password_reset_link(self, email: str, continue_url: str) -> tuple[str, str] | None:
        if email not in self.emails:
            return None
        return f"https://example.test/reset?email={email}&continue={continue_url}", "Ali"

    def revoke_sessions(self, uid: str) -> None:
        self.revoked.append(uid)

    def delete_user(self, uid: str) -> None:
        self.deleted.append(uid)

    def set_disabled(self, uid: str, disabled: bool) -> None:
        if disabled:
            self.disabled.add(uid)
        else:
            self.disabled.discard(uid)


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

    def ic_owner(self, ic_number: str) -> str | None:
        return next((uid for uid, u in self.users.items() if u.get("icNumber") == ic_number), None)

    def link_code_exists(self, code: str) -> bool:
        return code in self.taken_link_codes or any(
            u.get("linkCode") == code for u in self.users.values()
        )

    def complete_onboarding(
        self, uid: str, profile: dict[str, Any], user_updates: dict[str, Any]
    ) -> None:
        self.health_profiles[uid] = dict(profile)
        self.users[uid].update(user_updates)

    def list_users(self) -> list[tuple[str, dict[str, Any]]]:
        return [(uid, dict(u)) for uid, u in self.users.items()]

    def update_user(self, uid: str, data: dict[str, Any]) -> None:
        u = self.users[uid]
        for k, v in data.items():
            if v is None:
                u.pop(k, None)
            else:
                u[k] = v


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

    def readings_before(self, uid: str, before: datetime, limit: int) -> list[dict[str, Any]]:
        mine = [
            r
            for r in self._vitals.readings.values()
            if r["patientId"] == uid and r["timestamp"] < before
        ]
        return sorted(mine, key=lambda r: r["timestamp"], reverse=True)[:limit]

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
        self.notification_prefs: dict[str, dict[str, Any]] = {}

    def add(self, uid: str, token: str, platform: str) -> None:
        self.by_user.setdefault(uid, {})[token] = platform

    def remove(self, uid: str, token: str) -> None:
        self.by_user.get(uid, {}).pop(token, None)

    def tokens(self, uid: str) -> list[str]:
        return list(self.by_user.get(uid, {}))

    def prefs(self, uid: str) -> dict[str, Any]:
        return self.notification_prefs.get(uid, {})


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


class InMemorySettingsRepository:
    """Module 12: shares users/profiles, readings and provider records with the other fakes."""

    def __init__(
        self,
        users: "InMemoryUserRepository",
        vitals: "InMemoryVitalsRepository",
        provider: "InMemoryProviderRepository",
    ) -> None:
        self._users = users
        self._vitals = vitals
        self._provider = provider
        self.records: dict[str, list[dict[str, Any]]] = {}  # other exported collections

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def health_profile(self, uid: str) -> dict[str, Any] | None:
        return self._users.health_profiles.get(uid)

    def update_user(self, uid: str, data: dict[str, Any]) -> None:
        self._users.users[uid].update(data)

    def update_health_profile(self, uid: str, data: dict[str, str]) -> None:
        self._users.health_profiles.setdefault(uid, {"patientId": uid}).update(data)

    def export_records(self, uid: str) -> dict[str, list[dict[str, Any]]]:
        mine = [r for r in self._vitals.readings.values() if r["patientId"] == uid]
        return {
            **{k: [r for r in v if r.get("patientId") == uid] for k, v in self.records.items()},
            "vital_readings": mine,
            "prescriptions": [p for p in self._provider.prescriptions if p["patientId"] == uid],
            "clinical_notes": [n for n in self._provider.notes if n.get("patientId") == uid],
        }

    def care_plan(self, uid: str) -> dict[str, Any] | None:
        return self._provider.care_plans.get(uid)

    def recurring_prescriptions(self, uid: str) -> list[dict[str, Any]]:
        return [
            p
            for p in self._provider.prescriptions
            if p["patientId"] == uid and p.get("isRecurring")
        ]

    def due_deletions(self, requested_before: datetime) -> list[str]:
        return [
            uid
            for uid, u in self._users.users.items()
            if u.get("deletionRequestedAt") is not None
            and u["deletionRequestedAt"] <= requested_before
        ]

    def purge(self, uid: str) -> int:
        gone = [k for k, r in self._vitals.readings.items() if r["patientId"] == uid]
        for k in gone:
            del self._vitals.readings[k]
        for p in self.recurring_prescriptions(uid):
            p["isRecurring"] = False
        self._users.health_profiles.pop(uid, None)
        self._users.users.pop(uid, None)
        return len(gone) + 2


class InMemoryFamilyRepository:
    """FR-14.2 (D-06, D-62): users come from the user repo; requests and alerts here."""

    def __init__(self, users: "InMemoryUserRepository") -> None:
        self._users = users
        self.requests: dict[str, dict[str, Any]] = {}
        self.alerts: dict[str, dict[str, Any]] = {}
        self.profiles: dict[str, dict[str, Any]] = {}

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def update_user(self, uid: str, data: dict[str, Any]) -> None:
        self._users.users[uid].update(data)

    def patient_by_code(self, code: str) -> str | None:
        return next(
            (
                uid
                for uid, u in self._users.users.items()
                if u.get("linkCode") == code
                and u.get("role") == "patient"
                and u.get("isActive") is not False
            ),
            None,
        )

    def family_of(self, patient_id: str) -> list[str]:
        return [
            uid
            for uid, u in self._users.users.items()
            if u.get("role") == "family_member"
            and u.get("patientId") == patient_id
            and u.get("isActive") is not False
        ]

    def health_profile(self, patient_id: str) -> dict[str, Any] | None:
        return self.profiles.get(patient_id)

    def create_request(self, data: dict[str, Any]) -> str:
        rid = f"r{len(self.requests) + 1}"
        self.requests[rid] = dict(data)
        return rid

    def get_request(self, request_id: str) -> dict[str, Any] | None:
        r = self.requests.get(request_id)
        return dict(r) if r else None

    def update_request(self, request_id: str, data: dict[str, Any]) -> None:
        self.requests[request_id].update(data)

    def pending_for_member(self, member_id: str) -> list[tuple[str, dict[str, Any]]]:
        return [
            (k, r)
            for k, r in self.requests.items()
            if r["familyMemberId"] == member_id and r["status"] == "pending"
        ]

    def create_alert(self, data: dict[str, Any]) -> str:
        aid = f"e{len(self.alerts) + 1}"
        self.alerts[aid] = dict(data)
        return aid

    def get_alert(self, alert_id: str) -> dict[str, Any] | None:
        a = self.alerts.get(alert_id)
        return dict(a) if a else None

    def update_alert(self, alert_id: str, data: dict[str, Any]) -> None:
        self.alerts[alert_id].update(data)

    def alerts_since(self, patient_id: str, since: datetime) -> list[tuple[str, dict[str, Any]]]:
        return [
            (k, dict(a))
            for k, a in self.alerts.items()
            if a["patientId"] == patient_id and a["sentAt"] >= since
        ]


class InMemoryAuditReader:
    """Stored audit entries for the Module 11 viewer: (id, entry with timestamp)."""

    def __init__(self) -> None:
        self.entries: list[tuple[str, dict[str, Any]]] = []

    def add(self, when: datetime, action: str, user_id: str = "u-admin", **extra: Any) -> None:
        entry = {"userId": user_id, "action": action, "details": extra.pop("details", action)}
        entry.update(extra)
        entry["timestamp"] = when
        self.entries.append((f"log-{len(self.entries) + 1}", entry))

    def between(self, start: datetime, end: datetime) -> list[tuple[str, dict[str, Any]]]:
        rows = [(i, e) for i, e in self.entries if start <= e["timestamp"] < end]
        return sorted(rows, key=lambda r: r[1]["timestamp"], reverse=True)


class InMemoryAnalyticsSource:
    """Module 11 analytics: collection name -> documents; users come from the user repo."""

    def __init__(self, users: "InMemoryUserRepository") -> None:
        self._users = users
        self.docs: dict[str, list[dict[str, Any]]] = {}

    def add(self, collection: str, **doc: Any) -> None:
        self.docs.setdefault(collection, []).append(doc)

    def users(self) -> list[tuple[str, dict[str, Any]]]:
        return [(uid, dict(u)) for uid, u in self._users.users.items()]

    def in_range(self, collection: Any, field: str, start: datetime, end: datetime) -> list[Any]:
        return [
            d
            for d in self.docs.get(collection.value, [])
            if isinstance(d.get(field), datetime) and start <= d[field] < end
        ]

    def where_equal(self, collection: Any, field: str, value: Any) -> list[Any]:
        return [d for d in self.docs.get(collection.value, []) if d.get(field) == value]


class InMemoryRecordRepository:
    """Module 6 (D-58)."""

    def __init__(self, users: "InMemoryUserRepository") -> None:
        self._users = users
        self.records: dict[str, dict[str, Any]] = {}

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def get(self, record_id: str) -> dict[str, Any] | None:
        r = self.records.get(record_id)
        return dict(r) if r else None

    def create(self, record_id: str, data: dict[str, Any]) -> None:
        self.records[record_id] = dict(data)

    def update(self, record_id: str, data: dict[str, Any]) -> None:
        r = self.records[record_id]
        for k, v in data.items():
            if v is None:
                r.pop(k, None)
            else:
                r[k] = v

    def delete(self, record_id: str) -> None:
        self.records.pop(record_id, None)


class InMemoryFileStore:
    """Firebase Storage stand-in: path -> (bytes, content type)."""

    def __init__(self) -> None:
        self.files: dict[str, tuple[bytes, str]] = {}

    def stat(self, path: str) -> Any:
        from app.services.records import StoredFile

        f = self.files.get(path)
        return StoredFile(len(f[0]), f[1]) if f else None

    def read(self, path: str) -> bytes:
        return self.files[path][0]

    def write(self, path: str, data: bytes, content_type: str) -> None:
        self.files[path] = (data, content_type)

    def delete(self, path: str) -> None:
        self.files.pop(path, None)

    def delete_prefix(self, prefix: str) -> int:
        gone = [p for p in self.files if p.startswith(prefix)]
        for p in gone:
            del self.files[p]
        return len(gone)


class InMemoryAppointmentRepository:
    """Module 7 (D-53); booking is atomic like the Firestore transaction."""

    def __init__(self, users: "InMemoryUserRepository") -> None:
        self._users = users
        self.appointments: dict[str, dict[str, Any]] = {}

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def get(self, appointment_id: str) -> Any:
        from app.services.appointments import AppointmentDoc

        a = self.appointments.get(appointment_id)
        return AppointmentDoc(appointment_id, a) if a else None

    def taken(self, doctor_id: str, start: datetime, end: datetime) -> set[datetime]:
        from app.services.appointments import ACTIVE, held_time

        out = set()
        for a in self.appointments.values():
            if a["doctorId"] != doctor_id or a["status"] not in ACTIVE:
                continue
            for t in (a["dateTime"], held_time(a)):
                if t is not None and start <= t < end:
                    out.add(t)
        return out

    def _check_free(self, doctor_id: str, moment: datetime, exclude_id: str | None) -> None:
        from app.services.appointments import ACTIVE, SlotTakenError, clashes, held_time

        for k, a in self.appointments.items():
            if (
                k != exclude_id
                and a["doctorId"] == doctor_id
                and a["status"] in ACTIVE
                and any(t is not None and clashes(t, moment) for t in (a["dateTime"], held_time(a)))
            ):
                raise SlotTakenError

    def request_reschedule(
        self, appointment_id: str, doctor_id: str, pending: dict[str, Any]
    ) -> None:
        self._check_free(doctor_id, pending["dateTime"], appointment_id)
        self.appointments[appointment_id]["pendingChange"] = pending

    def book(self, data: dict[str, Any], exclude_id: str | None = None) -> str:
        self._check_free(data["doctorId"], data["dateTime"], exclude_id)
        appt_id = exclude_id or f"a{len(self.appointments) + 1}"
        self.appointments[appt_id] = dict(data)
        return appt_id

    def update(self, appointment_id: str, data: dict[str, Any]) -> None:
        self.appointments[appointment_id].update(data)

    def upcoming_for_patient(self, patient_id: str, now: datetime) -> list[Any]:
        from app.services.appointments import ACTIVE, AppointmentDoc

        return sorted(
            (
                AppointmentDoc(k, a)
                for k, a in self.appointments.items()
                if a["patientId"] == patient_id and a["dateTime"] >= now and a["status"] in ACTIVE
            ),
            key=lambda d: d.data["dateTime"],
        )

    def active_for_patient(self, patient_id: str) -> list[Any]:
        from app.services.appointments import ACTIVE, AppointmentDoc

        return [
            AppointmentDoc(k, a)
            for k, a in self.appointments.items()
            if a["patientId"] == patient_id and a["status"] in ACTIVE
        ]

    def active_between(self, start: datetime, end: datetime) -> list[Any]:
        from app.services.appointments import ACTIVE, AppointmentDoc

        return [
            AppointmentDoc(k, a)
            for k, a in self.appointments.items()
            if start <= a["dateTime"] < end and a["status"] in ACTIVE
        ]


class InMemoryAssignmentRepository:
    """D-54 doctor assignment requests."""

    def __init__(self, users: "InMemoryUserRepository") -> None:
        self._users = users
        self.requests: dict[str, dict[str, Any]] = {}

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def request(self, request_id: str) -> dict[str, Any] | None:
        return self.requests.get(request_id)

    def has_pending(self, patient_id: str) -> bool:
        return any(
            r["patientId"] == patient_id and r["status"] == "pending"
            for r in self.requests.values()
        )

    def create(self, data: dict[str, Any]) -> str:
        request_id = f"r{len(self.requests) + 1}"
        self.requests[request_id] = dict(data)
        return request_id

    def resolve(self, request_id: str, data: dict[str, Any]) -> None:
        self.requests[request_id].update(data)

    def set_doctor(self, patient_id: str, doctor_id: str) -> None:
        self._users.users[patient_id]["assignedDoctorId"] = doctor_id


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

    def prescription(self, rx_id: str) -> dict[str, Any] | None:
        return next((p for p in self.prescriptions if p.get("id") == rx_id), None)

    def update_prescription(self, rx_id: str, data: dict[str, Any]) -> None:
        rx = self.prescription(rx_id)
        assert rx is not None
        rx.update(data)

    def delete_prescription(self, rx_id: str) -> None:
        self.prescriptions = [p for p in self.prescriptions if p.get("id") != rx_id]

    def set_care_plan(self, patient_id: str, data: dict[str, Any]) -> None:
        self.care_plans[patient_id] = data
        self.plan_versions.setdefault(patient_id, []).append(
            {"content": data["content"], "doctorId": data["doctorId"]}
        )

    def add_prescription(self, data: dict[str, Any]) -> str:
        rx_id = f"rx{len(self.prescriptions) + 1}"
        self.prescriptions.append({**data, "id": rx_id})
        return rx_id


class InMemoryOrderRepository:
    """Module 13 (D-66). Prescriptions are shared with the provider fake."""

    def __init__(self, users: "InMemoryUserRepository", provider: InMemoryProviderRepository):
        self._users = users
        self._provider = provider
        self.orders: dict[str, dict[str, Any]] = {}
        self.transactions: dict[str, dict[str, Any]] = {}
        self.tracking: list[dict[str, Any]] = []
        self.stock_items: dict[str, dict[str, Any]] = {}
        self.phones: dict[str, str] = {}

    def user(self, uid: str) -> dict[str, Any] | None:
        return self._users.users.get(uid)

    def profile_phone(self, uid: str) -> str | None:
        from app.services.orders import phone_from_profile

        return self.phones.get(uid) or phone_from_profile(self.health_profile(uid))

    def health_profile(self, uid: str) -> dict[str, Any] | None:
        return self._users.health_profiles.get(uid)

    def prescriptions_for(self, uid: str) -> list[dict[str, Any]]:
        return [dict(p) for p in self._provider.prescriptions if p.get("patientId") == uid]

    def order_patients(self) -> set[str]:
        return {str(o.get("patientId")) for o in self.orders.values()}

    def patients(self) -> list[tuple[str, dict[str, Any]]]:
        return [(u, dict(d)) for u, d in self._users.users.items() if d.get("role") == "patient"]

    def all_orders(self) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(o)) for i, o in self.orders.items()]

    def delete_stock(self, stock_id: str) -> None:
        self.stock_items.pop(stock_id, None)

    def return_stock(self, stock_id: str, units: int) -> None:
        self.stock_items[stock_id]["units"] = int(self.stock_items[stock_id]["units"]) + units

    def stock_for_catalog(self, catalog_id: str) -> tuple[str, dict[str, Any]] | None:
        return next(
            ((i, dict(s)) for i, s in self.stock_items.items() if s.get("catalogId") == catalog_id),
            None,
        )

    def staff(self, role: str) -> list[str]:
        return [
            uid
            for uid, u in self._users.users.items()
            if u.get("role") == role and u.get("isActive", True) is not False
        ]

    def prescription(self, rx_id: str) -> dict[str, Any] | None:
        rx = self._provider.prescription(rx_id)
        return dict(rx) if rx else None

    def update_prescription(self, rx_id: str, data: dict[str, Any]) -> None:
        self._provider.update_prescription(rx_id, data)

    def recurring_prescriptions(self) -> list[dict[str, Any]]:
        return [dict(p) for p in self._provider.prescriptions if p.get("isRecurring")]

    def order(self, order_id: str) -> dict[str, Any] | None:
        o = self.orders.get(order_id)
        return dict(o) if o else None

    def create_order(self, order_id: str, data: dict[str, Any]) -> bool:
        if order_id in self.orders:
            return False
        self.orders[order_id] = dict(data)
        return True

    def update_order(self, order_id: str, data: dict[str, Any]) -> None:
        self.orders[order_id].update(data)

    def _where(self, test: Callable[[dict[str, Any]], bool]) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(o)) for i, o in self.orders.items() if test(o)]

    def orders_for_patient(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        return self._where(lambda o: o.get("patientId") == uid)

    def orders_for_prescription(self, rx_id: str) -> list[tuple[str, dict[str, Any]]]:
        return self._where(lambda o: o.get("prescriptionId") == rx_id)

    def orders_with_status(self, statuses: tuple[str, ...]) -> list[tuple[str, dict[str, Any]]]:
        return self._where(lambda o: o.get("fulfilmentStatus") in statuses)

    def home_deliveries(self) -> list[tuple[str, dict[str, Any]]]:
        return self._where(lambda o: o.get("method") == "home_delivery")

    def order_by_courier_ref(self, ref: str) -> tuple[str, dict[str, Any]] | None:
        found = self._where(lambda o: o.get("courierRef") == ref)
        return found[0] if found else None

    def add_transaction(self, tx_id: str, data: dict[str, Any]) -> None:
        self.transactions[tx_id] = dict(data)

    def events(self, order_id: str) -> list[dict[str, Any]]:
        return [dict(e) for e in self.tracking if e["orderId"] == order_id]

    def add_event(self, data: dict[str, Any]) -> None:
        self.tracking.append(dict(data))

    def stock(self) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(s)) for i, s in self.stock_items.items()]

    def stock_item(self, stock_id: str) -> dict[str, Any] | None:
        s = self.stock_items.get(stock_id)
        return dict(s) if s else None

    def add_stock(self, data: dict[str, Any]) -> str:
        stock_id = f"stock{len(self.stock_items) + 1}"
        self.stock_items[stock_id] = dict(data)
        return stock_id

    def update_stock(self, stock_id: str, data: dict[str, Any]) -> None:
        self.stock_items[stock_id].update(data)

    def take_stock(self, stock_id: str, units: int) -> bool:
        s = self.stock_items.get(stock_id)
        if s is None or int(s.get("units") or 0) < units:
            return False
        s["units"] = int(s["units"]) - units
        return True


class InMemoryCatalogRepository:
    """D-69 medication catalogue."""

    def __init__(self) -> None:
        self.items: dict[str, dict[str, Any]] = {
            "amlodipine-5": {
                "name": "Amlodipine",
                "strength": "5mg",
                "form": "tablet",
                "drugClass": "Calcium channel blocker",
                "unitPrice": 0.30,
                "active": True,
            },
            "losartan-50": {
                "name": "Losartan",
                "strength": "50mg",
                "form": "tablet",
                "drugClass": "Angiotensin receptor blocker",
                "unitPrice": 0.90,
                "active": True,
            },
            "spironolactone-25": {
                "name": "Spironolactone",
                "strength": "25mg",
                "form": "tablet",
                "drugClass": "Potassium-sparing diuretic",
                "unitPrice": 0.50,
                "active": True,
            },
        }

    def all(self) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(c)) for i, c in self.items.items()]

    def get(self, item_id: str) -> dict[str, Any] | None:
        c = self.items.get(item_id)
        return dict(c) if c else None

    def create(self, data: dict[str, Any]) -> str:
        item_id = f"cat{len(self.items) + 1}"
        self.items[item_id] = dict(data)
        return item_id

    def update(self, item_id: str, data: dict[str, Any]) -> None:
        self.items[item_id].update(data)


class InMemoryPharmacyChatRepository:
    """D-69 pharmacy chat."""

    def __init__(self) -> None:
        self.messages: list[tuple[str, dict[str, Any]]] = []

    def add(self, data: dict[str, Any]) -> str:
        message_id = f"pm{len(self.messages) + 1}"
        self.messages.append((message_id, dict(data)))
        return message_id

    def thread(self, patient_id: str) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(m)) for i, m in self.messages if m["patientId"] == patient_id]

    def recent(self, limit: int) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(m)) for i, m in reversed(self.messages)][:limit]


class InMemoryInboxRepository:
    """D-77 notification bell."""

    def __init__(self, users: "InMemoryUserRepository") -> None:
        self._users = users
        self.items: dict[str, dict[str, Any]] = {}

    def add(self, data: dict[str, Any]) -> str:
        nid = f"n{len(self.items) + 1}"
        self.items[nid] = dict(data)
        return nid

    def for_user(self, uid: str, limit: int) -> list[tuple[str, dict[str, Any]]]:
        mine = [(i, dict(n)) for i, n in self.items.items() if n["userId"] == uid]
        return list(reversed(mine))[:limit]

    def unread_count(self, uid: str) -> int:
        return sum(1 for n in self.items.values() if n["userId"] == uid and not n["read"])

    def get(self, notification_id: str) -> dict[str, Any] | None:
        n = self.items.get(notification_id)
        return dict(n) if n else None

    def mark_read(self, notification_id: str) -> None:
        self.items[notification_id]["read"] = True

    def mark_all_read(self, uid: str) -> int:
        n = 0
        for item in self.items.values():
            if item["userId"] == uid and not item["read"]:
                item["read"] = True
                n += 1
        return n

    def bell_prefs(self, uid: str) -> dict[str, Any]:
        return dict((self._users.users.get(uid) or {}).get("bellPrefs") or {})

    def set_bell_prefs(self, uid: str, prefs: dict[str, bool]) -> None:
        self._users.users.setdefault(uid, {})["bellPrefs"] = dict(prefs)

    def purge(self, before: datetime) -> int:
        old = [i for i, n in self.items.items() if n["createdAt"] < before]
        for i in old:
            del self.items[i]
        return len(old)


class InMemoryConversationRepository:
    """D-76 team and admin-opened chats."""

    def __init__(self) -> None:
        self.convs: dict[str, dict[str, Any]] = {}
        self.msgs: list[tuple[str, dict[str, Any]]] = []

    def get(self, cid: str) -> dict[str, Any] | None:
        c = self.convs.get(cid)
        return dict(c) if c else None

    def create(self, cid: str, data: dict[str, Any]) -> None:
        self.convs[cid] = {**data, "unread": dict(data.get("unread") or {})}

    def for_user(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(c)) for i, c in self.convs.items() if uid in c["participantIds"]]

    def opened_by(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(c)) for i, c in self.convs.items() if c.get("openedBy") == uid]

    def add_message(self, data: dict[str, Any], recipients: list[str]) -> str:
        message_id = f"cm{len(self.msgs) + 1}"
        self.msgs.append((message_id, dict(data)))
        c = self.convs[str(data["conversationId"])]
        c.update(
            lastText=str(data["text"])[:120],
            lastSenderId=data["senderId"],
            lastMessageAt=data["sentAt"],
        )
        for uid in recipients:
            c["unread"][uid] = c["unread"].get(uid, 0) + 1
        return message_id

    def messages(self, cid: str, limit: int) -> list[tuple[str, dict[str, Any]]]:
        return [(i, dict(m)) for i, m in self.msgs if m["conversationId"] == cid][-limit:]

    def mark_read(self, cid: str, uid: str) -> None:
        self.convs[cid]["unread"][uid] = 0


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
        self.sent_at: list[datetime] = []

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

    def add_message(
        self, uid: str, role: str, text: str, extra: dict[str, Any] | None = None
    ) -> str:
        self.messages.append({"patientId": uid, "role": role, "text": text, **(extra or {})})
        self.sent_at.append(datetime.now(UTC))
        return f"msg{len(self.messages)}"

    def risk_before(self, uid: str, before: Any) -> dict[str, Any] | None:
        mine = [
            d
            for d in self._risk.saved
            if d["patientId"] == uid and d.get("generatedAt") and d["generatedAt"] < before
        ]
        return mine[-1] if mine else None

    def latest_of_kind(self, uid: str, kind: str) -> Any:
        times = [
            t
            for m, t in zip(self.messages, self.sent_at, strict=True)
            if m["patientId"] == uid and m.get("kind") == kind
        ]
        return times[-1] if times else None


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


class InMemoryMedicationRepository:
    def __init__(self) -> None:
        from datetime import UTC, datetime

        self.meds: dict[str, dict[str, Any]] = {}
        self.logs: dict[str, dict[str, Any]] = {}
        self.now = datetime.now(UTC)

    def list_for(self, patient_id: str) -> list[MedicationDoc]:
        return [MedicationDoc(k, v) for k, v in self.meds.items() if v["patientId"] == patient_id]

    def get(self, medication_id: str) -> MedicationDoc | None:
        m = self.meds.get(medication_id)
        return MedicationDoc(medication_id, m) if m else None

    def create(self, data: dict[str, Any]) -> str:
        mid = f"med{len(self.meds) + 1}"
        self.meds[mid] = {**data, "createdAt": self.now}
        return mid

    def update(self, medication_id: str, data: dict[str, Any]) -> None:
        self.meds[medication_id].update(data)

    def delete(self, medication_id: str) -> None:
        del self.meds[medication_id]

    def all_scheduled(self) -> list[MedicationDoc]:
        return [MedicationDoc(k, v) for k, v in self.meds.items() if v["schedule"] != "as_needed"]

    def log_dose(self, log_id: str, data: dict[str, Any]) -> bool:
        if log_id in self.logs:
            return False
        self.logs[log_id] = data
        return True

    def recent_statuses(self, medication_id: str, since: Any) -> list[str]:
        return [
            v["status"]
            for v in self.logs.values()
            if v["medicationId"] == medication_id and v["scheduledTime"] >= since
        ]

    def recent_logs(self, medication_id: str, since: Any) -> list[tuple[Any, str]]:
        mine = [
            (v["scheduledTime"], v["status"])
            for v in self.logs.values()
            if v["medicationId"] == medication_id and v["scheduledTime"] >= since
        ]
        return sorted(mine, key=lambda x: x[0])

    def mark_taken_late(self, log_id: str, confirmed_at: Any) -> bool:
        log = self.logs.get(log_id)
        if log is None or log["status"] != "missed":
            return False
        log.update({"status": "taken", "confirmedAt": confirmed_at})
        return True

    def logged_ids(self, medication_id: str, since: Any) -> set[str]:
        return {
            k
            for k, v in self.logs.items()
            if v["medicationId"] == medication_id and v["scheduledTime"] >= since
        }


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
def med_repo() -> InMemoryMedicationRepository:
    return InMemoryMedicationRepository()


@pytest.fixture
def limiter() -> RateLimiter:
    return RateLimiter(max_events=3)


@pytest.fixture
def assignment_repo(repo: InMemoryUserRepository) -> InMemoryAssignmentRepository:
    return InMemoryAssignmentRepository(repo)


@pytest.fixture
def appointment_repo(repo: InMemoryUserRepository) -> InMemoryAppointmentRepository:
    return InMemoryAppointmentRepository(repo)


@pytest.fixture
def record_repo(repo: InMemoryUserRepository) -> InMemoryRecordRepository:
    return InMemoryRecordRepository(repo)


@pytest.fixture
def file_store() -> InMemoryFileStore:
    return InMemoryFileStore()


@pytest.fixture
def audit_reader() -> InMemoryAuditReader:
    return InMemoryAuditReader()


@pytest.fixture
def family_repo(repo: InMemoryUserRepository) -> InMemoryFamilyRepository:
    return InMemoryFamilyRepository(repo)


@pytest.fixture
def sms() -> LogSmsClient:
    return LogSmsClient()


@pytest.fixture
def analytics(repo: InMemoryUserRepository) -> InMemoryAnalyticsSource:
    return InMemoryAnalyticsSource(repo)


@pytest.fixture
def settings_repo(
    repo: InMemoryUserRepository,
    vitals_repo: InMemoryVitalsRepository,
    provider_repo: InMemoryProviderRepository,
) -> InMemorySettingsRepository:
    return InMemorySettingsRepository(repo, vitals_repo, provider_repo)


@pytest.fixture
def order_repo(
    repo: InMemoryUserRepository, provider_repo: InMemoryProviderRepository
) -> InMemoryOrderRepository:
    return InMemoryOrderRepository(repo, provider_repo)


@pytest.fixture
def catalog() -> InMemoryCatalogRepository:
    return InMemoryCatalogRepository()


@pytest.fixture
def pharmacy_chat() -> InMemoryPharmacyChatRepository:
    return InMemoryPharmacyChatRepository()


@pytest.fixture
def inbox(repo: InMemoryUserRepository) -> InMemoryInboxRepository:
    return InMemoryInboxRepository(repo)


@pytest.fixture
def conversations() -> InMemoryConversationRepository:
    return InMemoryConversationRepository()


@pytest.fixture
def gateway() -> FakeGateway:
    return FakeGateway()


@pytest.fixture
def courier() -> FakeGrabClient:
    return FakeGrabClient()


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
    med_repo: InMemoryMedicationRepository,
    settings_repo: InMemorySettingsRepository,
    appointment_repo: InMemoryAppointmentRepository,
    assignment_repo: InMemoryAssignmentRepository,
    record_repo: InMemoryRecordRepository,
    file_store: InMemoryFileStore,
    audit_reader: InMemoryAuditReader,
    analytics: InMemoryAnalyticsSource,
    family_repo: InMemoryFamilyRepository,
    sms: LogSmsClient,
    order_repo: InMemoryOrderRepository,
    gateway: FakeGateway,
    courier: FakeGrabClient,
    catalog: InMemoryCatalogRepository,
    pharmacy_chat: InMemoryPharmacyChatRepository,
    conversations: InMemoryConversationRepository,
    inbox: InMemoryInboxRepository,
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
        app.dependency_overrides[get_notifier] = lambda: Notifier(tokens, push, inbox)
        app.dependency_overrides[get_alert_repository] = lambda: alerts_repo
        app.dependency_overrides[get_deterioration_repository] = lambda: deterioration_repo
        app.dependency_overrides[get_provider_repository] = lambda: provider_repo
        app.dependency_overrides[get_agent_data_repository] = lambda: agent_repo
        app.dependency_overrides[get_llm_client] = lambda: llm
        app.dependency_overrides[get_agent_limiter] = lambda: agent_limiter
        app.dependency_overrides[get_triage_repository] = lambda: triage_repo
        app.dependency_overrides[get_message_repository] = lambda: message_repo
        app.dependency_overrides[get_medication_repository] = lambda: med_repo
        app.dependency_overrides[get_settings_repository] = lambda: settings_repo
        app.dependency_overrides[get_appointment_repository] = lambda: appointment_repo
        app.dependency_overrides[get_assignment_repository] = lambda: assignment_repo
        app.dependency_overrides[get_record_repository] = lambda: record_repo
        app.dependency_overrides[get_file_store] = lambda: file_store
        app.dependency_overrides[get_audit_reader] = lambda: audit_reader
        app.dependency_overrides[get_analytics_source] = lambda: analytics
        app.dependency_overrides[get_family_repository] = lambda: family_repo
        reset_limiter = RateLimiter(5)  # D-65: fresh per client, not shared across tests
        app.dependency_overrides[get_reset_limiter] = lambda: reset_limiter
        app.dependency_overrides[get_sms_client] = lambda: sms
        app.dependency_overrides[get_order_repository] = lambda: order_repo
        app.dependency_overrides[get_payment_gateway] = lambda: gateway
        app.dependency_overrides[get_courier_client] = lambda: courier
        app.dependency_overrides[get_catalog_repository] = lambda: catalog
        app.dependency_overrides[get_pharmacy_chat_repository] = lambda: pharmacy_chat
        app.dependency_overrides[get_conversation_repository] = lambda: conversations
        app.dependency_overrides[get_inbox_repository] = lambda: inbox
        return TestClient(app)

    return _make


@pytest.fixture
def client(make_client: MakeClient) -> TestClient:
    return make_client()
