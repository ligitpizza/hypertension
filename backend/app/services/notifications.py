"""Device tokens (users/{uid}/fcmTokens, D-07/D-33) and sending pushes to users."""

from __future__ import annotations

import logging
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore
from app.integrations.push import PushClient, PushMessage, get_push_client
from app.services.inbox import InboxRepository, get_inbox_repository, save

log = logging.getLogger("careflow.notify")

TOKENS = "fcmTokens"

# D-45: push data types that count as medication reminders; every other non-urgent push is a
# health update. Urgent pushes ignore the preferences.
MEDICATION_TYPES = {"dose", "refill"}


def pref_key(message: PushMessage) -> str | None:
    """The notificationPrefs switch that governs this push, or None if it is always sent."""
    if message.urgent:
        return None
    return (
        "medicationReminders" if message.data.get("type") in MEDICATION_TYPES else "healthUpdates"
    )


class TokenRepository(Protocol):
    def add(self, uid: str, token: str, platform: str) -> None: ...

    def remove(self, uid: str, token: str) -> None: ...

    def tokens(self, uid: str) -> list[str]: ...

    def prefs(self, uid: str) -> dict[str, Any]:
        """users.notificationPrefs (D-45); {} when unset."""
        ...


class FirestoreTokenRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _col(self, uid: str) -> Any:
        return self._db.collection(Collection.USERS.value).document(uid).collection(TOKENS)

    def add(self, uid: str, token: str, platform: str) -> None:
        self._col(uid).document(token).set(
            {"platform": platform, "createdAt": firestore.SERVER_TIMESTAMP}
        )

    def remove(self, uid: str, token: str) -> None:
        self._col(uid).document(token).delete()

    def tokens(self, uid: str) -> list[str]:
        return [d.id for d in self._col(uid).stream()]

    def prefs(self, uid: str) -> dict[str, Any]:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        raw = (snap.to_dict() or {}).get("notificationPrefs") if snap.exists else None
        return dict(raw) if isinstance(raw, dict) else {}


def get_token_repository() -> TokenRepository:
    return FirestoreTokenRepository(get_firestore())


class Notifier:
    """Sends a push to every registered device of a user; drops rejected tokens.

    D-77: also saves it to the user's bell inbox (with or without a device).
    """

    def __init__(
        self, tokens: TokenRepository, push: PushClient, inbox: InboxRepository | None = None
    ) -> None:
        self._tokens = tokens
        self._push = push
        self._inbox = inbox

    def notify(self, uid: str, message: PushMessage) -> int:
        if self._inbox is not None:
            save(self._inbox, uid, message.title, message.body, message.data, message.urgent)
        tokens = self._tokens.tokens(uid)
        if not tokens:
            return 0
        key = pref_key(message)
        if key is not None:
            try:
                muted = self._tokens.prefs(uid).get(key) is False
            except Exception:  # unreadable prefs -> deliver (safer than silence)
                muted = False
            if muted:
                log.info("Push '%s' to %s skipped (%s off)", message.title, uid, key)
                return 0
        try:
            invalid = self._push.send(tokens, message)
        except Exception:  # a push failure must never break the clinical flow
            log.exception("Push to %s failed", uid)
            return 0
        for token in invalid:
            self._tokens.remove(uid, token)
        return len(tokens) - len(invalid)


def get_notifier() -> Notifier:
    return Notifier(get_token_repository(), get_push_client(), get_inbox_repository())
