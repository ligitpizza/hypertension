"""System health (Fig 4.3.14.7; FR-11.3; D-59).

Each service gets a live check with its latency. Uptime comes from the 15-minute
scheduled sweep, which writes a JOB_HEARTBEAT audit entry every run: heartbeats received
/ heartbeats expected over the last 30 days (or since the first one).
"""

import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from app.core.config import Settings, get_settings
from app.core.enums import Collection
from app.core.firebase import get_firestore
from app.integrations.sms import sms_is_real
from app.ml.risk_model import RiskModel, get_risk_model
from app.services.audit_view import AuditReader, get_audit_reader

UPTIME_WINDOW = timedelta(days=30)
SWEEP_EVERY = timedelta(minutes=15)
SLOW_MS = {"firestore": 1000.0, "ml": 3000.0}  # ML: NFR-1.2 inference < 3 s

# A typical adult profile; only used to time one prediction.
SAMPLE_INPUTS = {
    "age": 55.0,
    "female": 1.0,
    "bmi": 27.0,
    "systolic": 135.0,
    "diastolic": 85.0,
    "heart_rate": 72.0,
    "smoking": 0.0,
    "bp_medication": 1.0,
    "medication_count": 1.0,
    "family_history": 0.0,
    "hypertension": 1.0,
    "high_cholesterol": 0.0,
    "t2d": 0.0,
    "stroke": 0.0,
    "cad": 0.0,
    "heartFailure": 0.0,
    "ckd": 0.0,
}


@dataclass(frozen=True)
class Probe:
    """Measures one dependency; raises when it is unreachable."""

    firestore: Callable[[], None]
    model: RiskModel | None


def _firestore_ping() -> None:
    get_firestore().collection(Collection.USERS.value).limit(1).get()


def get_probe() -> Probe:
    return Probe(firestore=_firestore_ping, model=get_risk_model())


def _timed(fn: Callable[[], Any]) -> tuple[bool, float]:
    start = time.perf_counter()
    try:
        fn()
        ok = True
    except Exception:
        ok = False
    return ok, round((time.perf_counter() - start) * 1000, 1)


def uptime(reader: AuditReader, now: datetime) -> float | None:
    """Percent of expected 15-minute heartbeats received; None before the first one."""
    beats = [
        e["timestamp"]
        for _, e in reader.between(now - UPTIME_WINDOW, now + timedelta(seconds=1))
        if e.get("action") == "JOB_HEARTBEAT" and e.get("targetType") == "sweep"
    ]
    if not beats:
        return None
    since = max(min(beats), now - UPTIME_WINDOW)
    expected = max(1, int((now - since) / SWEEP_EVERY) + 1)
    return round(min(100.0, len(beats) / expected * 100), 2)


def check(probe: Probe, reader: AuditReader, settings: Settings, now: datetime) -> dict[str, Any]:
    services: list[dict[str, Any]] = []

    def add(
        key: str,
        name: str,
        status: str,
        latency: float | None = None,
        note: str = "",
        up: float | None = None,
    ) -> None:
        services.append(
            {
                "key": key,
                "name": name,
                "status": status,
                "latencyMs": latency,
                "uptime": up,
                "note": note,
            }
        )

    api_uptime = uptime(reader, now)
    add("api", "CareFlow API", "operational", 0.0, "Answering this request.", api_uptime)

    ok, ms = _timed(probe.firestore)
    add(
        "firestore",
        "Patient database",
        "down" if not ok else "degraded" if ms > SLOW_MS["firestore"] else "operational",
        ms,
        "" if ok else "Firestore did not answer.",
        api_uptime,  # the sweep writes to Firestore, so it shares the API's history
    )

    model = probe.model
    if model is None:
        add("ml", "ML risk model", "down", None, "Model files are not loaded.")
    else:
        ok, ms = _timed(lambda: model.predict(SAMPLE_INPUTS))
        add(
            "ml",
            "ML risk model",
            "down" if not ok else "degraded" if ms > SLOW_MS["ml"] else "operational",
            ms,
            "Five complication models (test prediction)." if ok else "Prediction failed.",
        )

    add(
        "push",
        "Notification service",
        "operational" if settings.fcm_enabled else "simulated",
        note="Firebase Cloud Messaging" if settings.fcm_enabled else "Pushes are only logged.",
    )
    add(
        "email",
        "Email",
        "operational" if settings.email_api_key else "not_configured",
        note="Brevo" if settings.email_api_key else "No email key; links are shown on screen.",
    )
    add(
        "ai",
        "AI Health Agent",
        "operational" if settings.gemini_api_key else "simulated",
        note="Gemini" if settings.gemini_api_key else "Offline replies (no Gemini key).",
    )
    live_sms = sms_is_real(settings)
    add(
        "sms",
        "SMS (family emergencies)",
        "operational" if live_sms else "simulated",
        note=f"Brevo SMS as {settings.sms_sender}" if live_sms else "Messages are logged.",
    )
    live_stripe = settings.integrations_mode == "real" and bool(settings.stripe_secret_key)
    add(
        "stripe",
        "Stripe payments",
        "operational" if live_stripe else "simulated",
        note="Stripe test mode" if live_stripe else "Simulated card form (no Stripe keys).",
    )
    # D-67: GrabExpress sandbox once a partner project's credentials are set; else D-11.
    from app.integrations.delivery import build_courier_client

    grab = not build_courier_client(settings).simulated
    add(
        "grab",
        "Grab delivery API",
        "operational" if grab else "simulated",
        note="GrabExpress sandbox" if grab else "Simulated courier (about 1 min per stage).",
    )

    statuses = {s["status"] for s in services}
    overall = (
        "down" if "down" in statuses else "degraded" if "degraded" in statuses else "operational"
    )
    timed = [s["latencyMs"] for s in services if s["latencyMs"] is not None and s["key"] != "api"]
    return {
        "checkedAt": now.isoformat(),
        "overall": overall,
        "uptime": api_uptime,
        "averageLatencyMs": round(sum(timed) / len(timed), 1) if timed else None,
        "services": services,
    }


def system_health(
    probe: Probe, reader: AuditReader | None = None, settings: Settings | None = None
) -> dict[str, Any]:
    return check(probe, reader or get_audit_reader(), settings or get_settings(), datetime.now(UTC))
