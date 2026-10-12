"""Seed the Firebase Emulator Suite: symptom_catalog + one demo account per role.

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
from firebase_admin import auth, firestore

HERE = Path(__file__).resolve().parent
PROJECT_ID = "hypertension-dd85f"


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
    firebase_admin.initialize_app(options={"projectId": PROJECT_ID})
    db = firestore.client()
    n_sym = seed_symptoms(db)
    n_acc = seed_accounts(db)
    print(f"Seeded {n_sym} symptoms and {n_acc} demo accounts into the emulators.")


if __name__ == "__main__":
    main()
