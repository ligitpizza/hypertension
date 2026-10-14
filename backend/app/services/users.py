"""Firestore access for `users` and `health_profiles` (docs/04 Tables 4.2.3.1-2)."""

import secrets
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection
from app.core.firebase import get_firestore

# D-06 link code: 6 characters, no look-alikes (0/O, 1/I/L).
LINK_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
LINK_CODE_LENGTH = 6


def new_link_code() -> str:
    return "".join(secrets.choice(LINK_CODE_ALPHABET) for _ in range(LINK_CODE_LENGTH))


class UserRepository(Protocol):
    def get_user(self, uid: str) -> dict[str, Any] | None: ...

    def create_user(self, uid: str, data: dict[str, Any]) -> None: ...

    def link_code_exists(self, code: str) -> bool: ...

    def ic_owner(self, ic_number: str) -> str | None:
        """The uid already using this IC number (D-51), if any."""
        ...

    def complete_onboarding(
        self, uid: str, profile: dict[str, Any], user_updates: dict[str, Any]
    ) -> None: ...


class FirestoreUserRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _users(self) -> Any:
        return self._db.collection(Collection.USERS.value)

    def get_user(self, uid: str) -> dict[str, Any] | None:
        snap = self._users().document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def create_user(self, uid: str, data: dict[str, Any]) -> None:
        now = firestore.SERVER_TIMESTAMP
        # create() fails if the document already exists, so registration is never overwritten.
        self._users().document(uid).create({**data, "createdAt": now, "updatedAt": now})

    def link_code_exists(self, code: str) -> bool:
        query = self._users().where(filter=firestore.FieldFilter("linkCode", "==", code)).limit(1)
        return any(True for _ in query.stream())

    def ic_owner(self, ic_number: str) -> str | None:
        query = self._users().where(filter=firestore.FieldFilter("icNumber", "==", ic_number))
        return next((d.id for d in query.limit(1).stream()), None)

    def complete_onboarding(
        self, uid: str, profile: dict[str, Any], user_updates: dict[str, Any]
    ) -> None:
        # One health profile per patient: the document ID is the patient's UID.
        batch = self._db.batch()
        profile_ref = self._db.collection(Collection.HEALTH_PROFILES.value).document(uid)
        batch.set(profile_ref, profile)
        batch.update(
            self._users().document(uid),
            {**user_updates, "updatedAt": firestore.SERVER_TIMESTAMP},
        )
        batch.commit()


def get_user_repository() -> UserRepository:
    return FirestoreUserRepository(get_firestore())
