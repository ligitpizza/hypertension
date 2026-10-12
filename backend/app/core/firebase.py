"""Firebase Admin SDK initialisation.

Locally, the SDK talks to the Emulator Suite when FIRESTORE_EMULATOR_HOST,
FIREBASE_AUTH_EMULATOR_HOST and FIREBASE_STORAGE_EMULATOR_HOST are set (docs/10 §3).
On Cloud Run it uses the service's default credentials.
"""

from functools import lru_cache
from typing import Any

import firebase_admin
from firebase_admin import firestore

from app.core.config import get_settings


@lru_cache
def get_firebase_app() -> firebase_admin.App:
    try:
        return firebase_admin.get_app()
    except ValueError:
        settings = get_settings()
        return firebase_admin.initialize_app(options={"projectId": settings.firebase_project_id})


def get_firestore() -> Any:
    """Firestore client (google.cloud.firestore.Client)."""
    return firestore.client(app=get_firebase_app())
