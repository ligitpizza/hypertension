"""Notification inbox, the bell (D-77).

Every push Harvey sends is also saved to `notifications`, so people can catch up later
(staff on the web portal get no phone pushes at all). Each user chooses which categories
reach their bell (`users.bellPrefs`); urgent notifications are always kept. Entries older
than 30 days are removed by the daily job.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore

log = logging.getLogger("careflow.inbox")

KEEP_DAYS = 30
LIST_LIMIT = 50

# Push data "type" -> bell category (the switches on the Settings page).
CATEGORIES: dict[str, str] = {
    "message": "messages",
    "conversation": "messages",
    "pharmacy_chat": "messages",
    "bp_alert": "alerts",
    "clinical_alert": "alerts",
    "emergency_alert": "alerts",
    "emergency_ack": "alerts",
    "escalation": "alerts",
    "risk": "alerts",
    "triage": "alerts",
    "sos": "alerts",
    "order": "orders",
    "appointment": "appointments",
    "assignment": "appointments",
    "dose": "medication",
    "refill": "medication",
}
CATEGORY_NAMES = ["messages", "alerts", "appointments", "orders", "medication", "other"]


def category(kind: str | None) -> str:
    return CATEGORIES.get(kind or "", "other")


def keeps(prefs: dict[str, Any], kind: str | None, urgent: bool) -> bool:
    return urgent or prefs.get(category(kind)) is not False


def view(notification_id: str, n: dict[str, Any]) -> dict[str, Any]:
    created = n.get("createdAt")
    return {
        "id": notification_id,
        "title": n.get("title"),
        "body": n.get("body"),
        "type": n.get("type"),
        "category": n.get("category"),
        "data": dict(n.get("data") or {}),
        "urgent": bool(n.get("urgent")),
        "read": bool(n.get("read")),
        "createdAt": created.isoformat() if isinstance(created, datetime) else None,
    }


class InboxRepository(Protocol):
    def add(self, data: dict[str, Any]) -> str: ...

    def for_user(self, uid: str, limit: int) -> list[tuple[str, dict[str, Any]]]:
        """Newest first."""
        ...

    def unread_count(self, uid: str) -> int: ...

    def get(self, notification_id: str) -> dict[str, Any] | None: ...

    def mark_read(self, notification_id: str) -> None: ...

    def mark_all_read(self, uid: str) -> int: ...

    def bell_prefs(self, uid: str) -> dict[str, Any]: ...

    def set_bell_prefs(self, uid: str, prefs: dict[str, bool]) -> None: ...

    def purge(self, before: datetime) -> int: ...


class FirestoreInboxRepository:
    def __init__(self, db: Any) -> None:
        self._db = db
        self._col = db.collection(Collection.NOTIFICATIONS.value)

    def _mine(self, uid: str) -> Any:
        return self._col.where(filter=firestore.FieldFilter("userId", "==", uid))

    def add(self, data: dict[str, Any]) -> str:
        _, ref = self._col.add(data)
        return str(ref.id)

    def for_user(self, uid: str, limit: int) -> list[tuple[str, dict[str, Any]]]:
        q = self._mine(uid).order_by("createdAt", direction=firestore.Query.DESCENDING).limit(limit)
        return [(d.id, dict(d.to_dict())) for d in q.stream()]

    def unread_count(self, uid: str) -> int:
        q = self._mine(uid).where(filter=firestore.FieldFilter("read", "==", False))
        return int(q.count().get()[0][0].value)

    def get(self, notification_id: str) -> dict[str, Any] | None:
        snap = self._col.document(notification_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def mark_read(self, notification_id: str) -> None:
        self._col.document(notification_id).update({"read": True})

    def mark_all_read(self, uid: str) -> int:
        q = self._mine(uid).where(filter=firestore.FieldFilter("read", "==", False))
        batch = self._db.batch()
        n = 0
        for d in q.limit(400).stream():
            batch.update(d.reference, {"read": True})
            n += 1
        if n:
            batch.commit()
        return n

    def bell_prefs(self, uid: str) -> dict[str, Any]:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        raw = (snap.to_dict() or {}).get("bellPrefs") if snap.exists else None
        return dict(raw) if isinstance(raw, dict) else {}

    def set_bell_prefs(self, uid: str, prefs: dict[str, bool]) -> None:
        self._db.collection(Collection.USERS.value).document(uid).update({"bellPrefs": prefs})

    def purge(self, before: datetime) -> int:
        q = self._col.where(filter=firestore.FieldFilter("createdAt", "<", before)).limit(400)
        batch = self._db.batch()
        n = 0
        for d in q.stream():
            batch.delete(d.reference)
            n += 1
        if n:
            batch.commit()
        return n


def get_inbox_repository() -> InboxRepository:
    return FirestoreInboxRepository(get_firestore())


def save(
    inbox: InboxRepository,
    uid: str,
    title: str,
    body: str,
    data: dict[str, str],
    urgent: bool,
    now: datetime | None = None,
) -> str | None:
    """Saves one notification unless the user switched its category off; never raises."""
    kind = data.get("type")
    try:
        if not keeps(inbox.bell_prefs(uid), kind, urgent):
            return None
        return inbox.add(
            {
                "userId": uid,
                "title": title,
                "body": body,
                "type": kind,
                "category": category(kind),
                "data": dict(data),
                "urgent": urgent,
                "read": False,
                "createdAt": now or datetime.now(UTC),
            }
        )
    except Exception:  # the bell is a convenience; never break the clinical flow
        log.exception("Saving notification for %s failed", uid)
        return None


def purge_old(inbox: InboxRepository, now: datetime | None = None) -> dict[str, Any]:
    now = now or datetime.now(UTC)
    return {"notificationsPurged": inbox.purge(now - timedelta(days=KEEP_DAYS))}
