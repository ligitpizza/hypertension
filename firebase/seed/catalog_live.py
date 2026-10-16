"""Load reference data into the LIVE Firestore: symptom_catalog (FR-14.3, D-10) and the
medication_catalog with demo stock (D-69).

Reference data only: writes the 14 symptoms from symptom_catalog.json (same stable ids,
so re-running just overwrites them). Never touches patient or user data.
Refuses to run against the emulators (seed.py does that).

Uses Application Default Credentials (`gcloud auth application-default login`).
Run via:  python tasks.py seed-catalog-live --yes   (also a step of deploy-all)
"""

import os
import sys

import firebase_admin
from firebase_admin import firestore

from seed import seed_medication_catalog, seed_symptoms

PROJECT_ID = "hypertension-dd85f"


def main() -> None:
    for var in ("FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"):
        if os.environ.get(var):
            sys.exit(f"Refusing: {var} is set. This script is for the live project only.")
    firebase_admin.initialize_app(options={"projectId": PROJECT_ID})
    db = firestore.client()
    count = seed_symptoms(db)
    print(f"Live symptom_catalog: {count} symptoms written.")
    # D-69: create-only, so prices and stock the pharmacy has changed are kept.
    items, stock = seed_medication_catalog(db)
    print(f"Live medication_catalog: {items} new medicines, {stock} new demo stock items.")


if __name__ == "__main__":
    main()
