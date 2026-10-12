"""Health endpoints for the walking skeleton and system health (FR-11.3)."""

from typing import Any

from fastapi import APIRouter, Depends

from app.core.auth import CurrentUser, get_current_user
from app.core.config import Settings, get_settings

router = APIRouter(tags=["health"])


@router.get("/health")
def health(settings: Settings = Depends(get_settings)) -> dict[str, Any]:
    """Unauthenticated liveness check. Reached through the Hosting /api/** rewrite."""
    return {"status": "ok", "service": "careflow-api", "version": settings.app_version}


@router.get("/health/auth")
def health_auth(user: CurrentUser = Depends(get_current_user)) -> dict[str, Any]:
    """Authenticated check: proves ID token verification and the role claim work."""
    return {"status": "ok", "uid": user.uid, "role": user.role.value if user.role else None}
