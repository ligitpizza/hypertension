"""Cloud Scheduler targets: POST /internal/jobs/{job} (D-08).

Not under /api, so Firebase Hosting never exposes them; Cloud Scheduler calls the
Cloud Run URL directly with an OIDC token for the scheduler service account.
Real jobs (missed doses, reminders, deterioration scan, ...) are added per module.
"""

from collections.abc import Callable
from typing import Any

from fastapi import APIRouter, Depends, Header, status

from app.core.audit import SYSTEM_SCHEDULER_USER, AuditLogger, get_audit_logger
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.services.deterioration import DeteriorationJob, get_deterioration_job

router = APIRouter(prefix="/internal/jobs", tags=["jobs"])

OidcVerifier = Callable[[str, str], dict[str, Any]]


def _google_verify(token: str, audience: str) -> dict[str, Any]:
    from google.auth.transport import requests as g_requests
    from google.oauth2 import id_token

    claims: dict[str, Any] = id_token.verify_oauth2_token(  # type: ignore[no-untyped-call]
        token, g_requests.Request(), audience
    )
    return claims


def get_oidc_verifier() -> OidcVerifier:
    return _google_verify


def verify_scheduler(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    verify: OidcVerifier = Depends(get_oidc_verifier),
) -> None:
    if settings.internal_jobs_auth == "none":
        return
    if not authorization or not authorization.lower().startswith("bearer "):
        raise ApiError("UNAUTHENTICATED", "Missing OIDC token.", status.HTTP_401_UNAUTHORIZED)
    try:
        claims = verify(authorization.split(" ", 1)[1].strip(), settings.jobs_oidc_audience)
    except Exception as exc:
        raise ApiError(
            "UNAUTHENTICATED", "Invalid OIDC token.", status.HTTP_401_UNAUTHORIZED
        ) from exc
    if claims.get("email") != settings.jobs_service_account or not claims.get("email_verified"):
        raise ApiError("FORBIDDEN", "Caller is not the scheduler.", status.HTTP_403_FORBIDDEN)


def _heartbeat(audit: AuditLogger) -> dict[str, Any]:
    """Increment 0 test job: proves Scheduler -> Cloud Run -> Firestore works."""
    log_id = audit.log(
        user_id=SYSTEM_SCHEDULER_USER,
        action="JOB_HEARTBEAT",
        details="Scheduled heartbeat job ran.",
        target_type="audit_logs",
    )
    return {"auditLogId": log_id}


JOBS: dict[str, Callable[[AuditLogger], dict[str, Any]]] = {
    "heartbeat": _heartbeat,
}


@router.post("/deterioration", dependencies=[Depends(verify_scheduler)])
def run_deterioration(job: DeteriorationJob = Depends(get_deterioration_job)) -> dict[str, Any]:
    """FR-9.6: daily 30-day deterioration scan."""
    return {"job": "deterioration", "status": "ok", **job.run()}


@router.post("/{job}", dependencies=[Depends(verify_scheduler)])
def run_job(job: str, audit: AuditLogger = Depends(get_audit_logger)) -> dict[str, Any]:
    handler = JOBS.get(job)
    if handler is None:
        raise ApiError("JOB_NOT_FOUND", f"Unknown job '{job}'.", status.HTTP_404_NOT_FOUND)
    return {"job": job, "status": "ok", **handler(audit)}
