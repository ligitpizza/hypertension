"""Seed the Firebase Emulator Suite: symptom_catalog, medication_catalog (D-69) and one
demo account per role.

EMULATOR ONLY. Refuses to run unless FIRESTORE_EMULATOR_HOST and
FIREBASE_AUTH_EMULATOR_HOST are set, so it can never touch the cloud project.
Idempotent: re-running overwrites the same documents and accounts.

Run via `python tasks.py seed` (uses backend/.venv for firebase-admin).
"""

import json
import os
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import firebase_admin
from firebase_admin import auth, credentials, firestore
from google.auth.credentials import AnonymousCredentials

HERE = Path(__file__).resolve().parent
PROJECT_ID = "hypertension-dd85f"


class _EmulatorCredential(credentials.Base):  # type: ignore[misc]
    """The emulators accept any caller; no Application Default Credentials needed."""

    def get_credential(self) -> AnonymousCredentials:
        return AnonymousCredentials()


def _require_emulators() -> None:
    missing = [
        v
        for v in ("FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST")
        if not os.environ.get(v)
    ]
    if missing:
        sys.exit(f"Refusing to seed: {', '.join(missing)} not set (emulator only).")


def _load(name: str) -> dict[str, Any]:
    data: dict[str, Any] = json.loads((HERE / name).read_text(encoding="utf-8"))
    return data


def seed_symptoms(db: Any) -> int:
    symptoms = _load("symptom_catalog.json")["symptoms"]
    batch = db.batch()
    for s in symptoms:
        doc = {"name": s["name"], "category": s["category"], "isRedFlag": s["isRedFlag"]}
        batch.set(db.collection("symptom_catalog").document(s["id"]), doc)
    batch.commit()
    return len(symptoms)


def seed_medication_catalog(db: Any) -> tuple[int, int]:
    """D-69: catalogue items and their demo stock. Create-only, so a price or stock level
    the pharmacy has changed is never overwritten. Returns (new items, new stock items)."""
    from google.api_core.exceptions import AlreadyExists

    now = datetime.now(UTC)
    items = stock = 0
    for m in _load("medication_catalog.json")["medicines"]:
        doc = {
            "name": m["name"],
            "strength": m["strength"],
            "form": m["form"],
            "unitLabel": m["form"],
            "drugClass": m["drugClass"],
            "unitPrice": m["unitPrice"],
            "active": True,
            "updatedAt": now,
        }
        try:
            db.collection("medication_catalog").document(m["id"]).create(doc)
            items += 1
        except AlreadyExists:
            pass
        try:
            db.collection("medication_stock").document(f"stock-{m['id']}").create(
                {
                    "name": f"{m['name']} {m['strength']}",
                    "catalogId": m["id"],
                    "units": m["demoStock"],
                    # Demo batch: expires two years after seeding.
                    "expiryDate": now.replace(year=now.year + 2),
                    "lowStockAt": 50,
                    "updatedAt": now,
                }
            )
            stock += 1
        except AlreadyExists:
            pass
    return items, stock


def _user_doc(acc: dict[str, Any]) -> dict[str, Any]:
    now = firestore.SERVER_TIMESTAMP
    doc: dict[str, Any] = {
        "email": acc["email"],
        "name": acc["name"],
        "role": acc["role"],
        "isActive": True,
        "createdAt": now,
        "updatedAt": now,
    }
    role = acc["role"]
    if role == "patient":
        doc["dateOfBirth"] = datetime.fromisoformat(acc["dateOfBirth"]).replace(tzinfo=UTC)
        doc["gender"] = acc["gender"]
        doc["onboardingComplete"] = acc["onboardingComplete"]
        doc["assignedDoctorId"] = acc.get("assignedDoctorId")
        doc["linkCode"] = acc["linkCode"]  # D-06
    elif role == "doctor":
        doc["specialty"] = acc["specialty"]
    elif role == "family_member":
        doc["patientId"] = acc.get("patientId")
    return doc


def seed_accounts(db: Any) -> int:
    data = _load("demo_accounts.json")
    for acc in data["accounts"]:
        try:
            auth.get_user(acc["uid"])
            auth.update_user(acc["uid"], email=acc["email"], password=data["password"])
        except auth.UserNotFoundError:
            auth.create_user(
                uid=acc["uid"],
                email=acc["email"],
                password=data["password"],
                display_name=acc["name"],
                email_verified=True,
            )
        auth.set_custom_user_claims(acc["uid"], {"role": acc["role"]})
        db.collection("users").document(acc["uid"]).set(_user_doc(acc))
    return len(data["accounts"])


def main() -> None:
    _require_emulators()
    firebase_admin.initialize_app(
        credential=_EmulatorCredential(), options={"projectId": PROJECT_ID}
    )
    db = firestore.client()
    n_sym = seed_symptoms(db)
    n_acc = seed_accounts(db)
    n_med, n_stock = seed_medication_catalog(db)
    print(
        f"Seeded {n_sym} symptoms, {n_acc} demo accounts, {n_med} catalogue medicines and "
        f"{n_stock} stock items into the emulators."
    )


if __name__ == "__main__":
    main()
