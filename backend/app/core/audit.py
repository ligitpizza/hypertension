"""Audit logger (FR-1.5). Every state change writes one `audit_logs` document.

Fields follow docs/04 Table 4.2.3.15: userId, action, targetType, targetId,
details, timestamp. Clients never write this collection (server-only rules).
"""

from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore

SYSTEM_SCHEDULER_USER = "system:scheduler"


class AuditLogger(Protocol):
    def log(
        self,
        *,
        user_id: str,
        action: str,
        details: str,
        target_type: str | None = None,
        target_id: str | None = None,
    ) -> str: ...


def build_audit_entry(
    *,
    user_id: str,
    action: str,
    details: str,
    target_type: str | None,
    target_id: str | None,
    timestamp: Any,
) -> dict[str, Any]:
    if not user_id or not action:
        raise ValueError("audit entry needs user_id and action")
    entry: dict[str, Any] = {
        "userId": user_id,
        "action": action,
        "details": details,
        "timestamp": timestamp,
    }
    # Optional fields are omitted rather than stored as null.
    if target_type:
        entry["targetType"] = target_type
    if target_id:
        entry["targetId"] = target_id
    return entry


class FirestoreAuditLogger:
    def __init__(self, db: Any) -> None:
        self._db = db

    def log(
        self,
        *,
        user_id: str,
        action: str,
        details: str,
        target_type: str | None = None,
        target_id: str | None = None,
    ) -> str:
        entry = build_audit_entry(
            user_id=user_id,
            action=action,
            details=details,
            target_type=target_type,
            target_id=target_id,
            timestamp=firestore.SERVER_TIMESTAMP,
        )
        _, ref = self._db.collection(Collection.AUDIT_LOGS.value).add(entry)
        return str(ref.id)


def get_audit_logger() -> AuditLogger:
    """Dependency so tests can swap in an in-memory logger."""
    return FirestoreAuditLogger(get_firestore())
