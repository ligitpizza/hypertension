"""Harvey API entrypoint: `uvicorn app.main:app` (docs/10 §3)."""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import Settings, get_settings
from app.core.errors import register_error_handlers
from app.ml.risk_model import load_risk_model
from app.routers import (
    admin,
    admin_panel,
    agent,
    appointments,
    assignments,
    auth,
    conversations,
    devices,
    family,
    health,
    jobs,
    medications,
    messages,
    notifications,
    orders,
    pharmacy_chat,
    prescriptions,
    provider,
    records,
    risk,
    triage,
    vitals,
)
from app.routers import settings as settings_routes

API_PREFIX = "/api/v1"


def _configure_logging() -> None:
    """Show careflow.* INFO messages (push sent, job results) on the console / Cloud Logging.

    Never log request bodies: they contain health data.
    """
    logger = logging.getLogger("careflow")
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter("%(levelname)s %(name)s: %(message)s"))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    _configure_logging()
    app = FastAPI(
        title="Harvey API",
        version=settings.app_version,
        # Interactive docs only in dev.
        docs_url="/api/docs" if settings.is_dev else None,
        redoc_url=None,
        openapi_url="/api/openapi.json" if settings.is_dev else None,
    )

    if settings.is_dev:
        # Production is same-origin via the Hosting rewrite, so CORS is dev-only.
        app.add_middleware(
            CORSMiddleware,
            allow_origin_regex=settings.cors_origin_regex,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    register_error_handlers(app)
    app.include_router(health.router, prefix=API_PREFIX)
    app.include_router(auth.router, prefix=API_PREFIX)
    app.include_router(admin.router, prefix=API_PREFIX)
    app.include_router(admin_panel.router, prefix=API_PREFIX)
    app.include_router(vitals.router, prefix=API_PREFIX)
    app.include_router(risk.router, prefix=API_PREFIX)
    app.include_router(devices.router, prefix=API_PREFIX)
    app.include_router(provider.router, prefix=API_PREFIX)
    app.include_router(agent.router, prefix=API_PREFIX)
    app.include_router(orders.router, prefix=API_PREFIX)
    app.include_router(pharmacy_chat.router, prefix=API_PREFIX)
    app.include_router(conversations.router, prefix=API_PREFIX)
    app.include_router(triage.router, prefix=API_PREFIX)
    app.include_router(messages.router, prefix=API_PREFIX)
    app.include_router(notifications.router, prefix=API_PREFIX)
    app.include_router(medications.router, prefix=API_PREFIX)
    app.include_router(appointments.router, prefix=API_PREFIX)
    app.include_router(appointments.admin_router, prefix=API_PREFIX)
    app.include_router(assignments.router, prefix=API_PREFIX)
    app.include_router(prescriptions.router, prefix=API_PREFIX)
    app.include_router(records.router, prefix=API_PREFIX)
    app.include_router(family.router, prefix=API_PREFIX)
    app.include_router(settings_routes.router, prefix=API_PREFIX)
    app.include_router(jobs.router)
    return app


app = create_app()
# NFR-1.2: load the risk models once at startup, not per request.
load_risk_model()
