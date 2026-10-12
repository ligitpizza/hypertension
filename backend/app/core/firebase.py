"""Firebase Admin SDK initialisation.

Locally, the SDK talks to the Emulator Suite when FIRESTORE_EMULATOR_HOST,
FIREBASE_AUTH_EMULATOR_HOST and FIREBASE_STORAGE_EMULATOR_HOST are set (docs/10 §3).
On Cloud Run it uses the service's default credentials.
"""

import os
from functools import lru_cache
from typing import Any

import firebase_admin
from firebase_admin import credentials, firestore
from google.auth.credentials import AnonymousCredentials

from app.core.config import get_settings


class EmulatorCredential(credentials.Base):  # type: ignore[misc]
    """The emulators accept any caller; avoids needing Application Default Credentials."""

    def get_credential(self) -> AnonymousCredentials:
        return AnonymousCredentials()  # type: ignore[no-untyped-call]


def using_emulators() -> bool:
    return bool(os.environ.get("FIRESTORE_EMULATOR_HOST"))


@lru_cache
def get_firebase_app() -> firebase_admin.App:
    try:
        return firebase_admin.get_app()
    except ValueError:
        settings = get_settings()
        cred = EmulatorCredential() if using_emulators() else None
        return firebase_admin.initialize_app(
            credential=cred, options={"projectId": settings.firebase_project_id}
        )


def get_firestore() -> Any:
    """Firestore client (google.cloud.firestore.Client)."""
    return firestore.client(app=get_firebase_app())
