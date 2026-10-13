"""CareFlow API entrypoint: `uvicorn app.main:app` (docs/10 §3)."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import Settings, get_settings
from app.core.errors import register_error_handlers
from app.ml.risk_model import load_risk_model
from app.routers import admin, auth, devices, health, jobs, provider, risk, vitals

API_PREFIX = "/api/v1"


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    app = FastAPI(
        title="CareFlow API",
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
    app.include_router(vitals.router, prefix=API_PREFIX)
    app.include_router(risk.router, prefix=API_PREFIX)
    app.include_router(devices.router, prefix=API_PREFIX)
    app.include_router(provider.router, prefix=API_PREFIX)
    app.include_router(jobs.router)
    return app


app = create_app()
# NFR-1.2: load the risk models once at startup, not per request.
load_risk_model()
