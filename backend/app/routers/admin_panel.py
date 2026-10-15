"""Module 11 admin panel: audit logs (D-59). System health, analytics and the
hospital-wide report are added alongside.

GET /admin/audit-logs        filter by date range, action, user, text; summary counts
GET /admin/audit-logs.csv    the same rows as CSV (FR-11.3); the export itself is audited
"""

from datetime import UTC, date, datetime, time, timedelta
from typing import Any

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import UserRole
from app.core.errors import ApiError
from app.services.audit_view import (
    AuditReader,
    get_audit_reader,
    module_of,
    summarise,
    to_csv,
)
from app.services.users import UserRepository, get_user_repository

router = APIRouter(prefix="/admin", tags=["admin"])
admin_only = require_roles(UserRole.ADMIN)

MYT = timedelta(hours=8)
MAX_RANGE_DAYS = 366


def _range(start: date | None, end: date | None) -> tuple[datetime, datetime]:
    """Malaysian dates [start, end] -> UTC instants [from, to). Default: the last 7 days."""
    today = (datetime.now(UTC) + MYT).date()
    end = end or today
    start = start or end - timedelta(days=6)
    if start > end:
        raise ApiError(
            "INVALID_RANGE",
            "The start date is after the end date.",
            status.HTTP_422_UNPROCESSABLE_CONTENT,
        )
    if (end - start).days > MAX_RANGE_DAYS:
        raise ApiError(
            "INVALID_RANGE", "Choose at most one year.", status.HTTP_422_UNPROCESSABLE_CONTENT
        )
    lo = datetime.combine(start, time.min, tzinfo=UTC) - MYT
    hi = datetime.combine(end + timedelta(days=1), time.min, tzinfo=UTC) - MYT
    return lo, hi


def _rows(
    reader: AuditReader,
    users: UserRepository,
    lo: datetime,
    hi: datetime,
    action: str | None,
    user_id: str | None,
    q: str | None,
) -> list[dict[str, Any]]:
    people = dict(users.list_users())
    needle = (q or "").strip().lower()
    rows: list[dict[str, Any]] = []
    for log_id, e in reader.between(lo, hi):
        if action and e.get("action") != action:
            continue
        if user_id and e.get("userId") != user_id:
            continue
        who = people.get(str(e.get("userId")), {})
        ts = e.get("timestamp")
        row = {
            "id": log_id,
            "timestamp": ts.isoformat() if isinstance(ts, datetime) else None,
            "userId": e.get("userId"),
            "userName": who.get("name"),
            "role": who.get("role"),
            "action": e.get("action"),
            "module": module_of(e),
            "targetType": e.get("targetType"),
            "targetId": e.get("targetId"),
            "details": e.get("details"),
        }
        if needle and not any(
            needle in str(v).lower()
            for v in (row["userName"], row["userId"], row["action"], row["details"], log_id)
        ):
            continue
        rows.append(row)
    return rows


@router.get("/audit-logs")
def audit_logs(
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
    action: str | None = None,
    user_id: str | None = Query(default=None, alias="userId"),
    q: str | None = None,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=15, ge=1, le=200),
    _: CurrentUser = Depends(admin_only),
    reader: AuditReader = Depends(get_audit_reader),
    users: UserRepository = Depends(get_user_repository),
) -> dict[str, Any]:
    """UC11.3: system-wide events, filterable by user / date / action (Fig 4.3.14.3)."""
    lo, hi = _range(start, end)
    rows = _rows(reader, users, lo, hi, action, user_id, q)
    previous = len(reader.between(lo - (hi - lo), lo))
    return {
        "summary": summarise([r for r in rows], previous),
        "actions": sorted({str(e.get("action")) for _, e in reader.between(lo, hi)}),
        "total": len(rows),
        "entries": rows[offset : offset + limit],
    }


@router.get("/audit-logs.csv")
def audit_logs_csv(
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
    action: str | None = None,
    user_id: str | None = Query(default=None, alias="userId"),
    q: str | None = None,
    admin: CurrentUser = Depends(admin_only),
    reader: AuditReader = Depends(get_audit_reader),
    users: UserRepository = Depends(get_user_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> Response:
    lo, hi = _range(start, end)
    rows = _rows(reader, users, lo, hi, action, user_id, q)
    audit.log(
        user_id=admin.uid,
        action="EXPORT_AUDIT_LOG",
        details=f"Exported {len(rows)} audit entries as CSV.",
    )
    return Response(
        content=to_csv(rows),
        media_type="text/csv",
        headers={"Content-Disposition": 'attachment; filename="careflow-audit-log.csv"'},
    )
