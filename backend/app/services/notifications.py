"""Device tokens (users/{uid}/fcmTokens, D-07/D-33) and sending pushes to users."""

from __future__ import annotations

import logging
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore
from app.integrations.push import PushClient, PushMessage, get_push_client

log = logging.getLogger("careflow.notify")

TOKENS = "fcmTokens"


class TokenRepository(Protocol):
    def add(self, uid: str, token: str, platform: str) -> None: ...

    def remove(self, uid: str, token: str) -> None: ...

    def tokens(self, uid: str) -> list[str]: ...


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


def get_token_repository() -> TokenRepository:
    return FirestoreTokenRepository(get_firestore())


class Notifier:
    """Sends a push to every registered device of a user; drops rejected tokens."""

    def __init__(self, tokens: TokenRepository, push: PushClient) -> None:
        self._tokens = tokens
        self._push = push

    def notify(self, uid: str, message: PushMessage) -> int:
        tokens = self._tokens.tokens(uid)
        if not tokens:
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
    return Notifier(get_token_repository(), get_push_client())
