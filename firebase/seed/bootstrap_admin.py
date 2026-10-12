"""Create the FIRST admin account in the live Firebase project (one-time bootstrap).

Staff accounts are created by an admin (FR-1.6), so the very first admin cannot be made
through the app. This script:
  - refuses to run against the emulators (use seed.py there),
  - refuses if any admin already exists (further admins are created in the staff portal),
  - creates the Firebase Auth user without a password, sets the `admin` role claim,
    creates the users/{uid} document (never overwrites) and writes an audit_logs entry,
  - prints a password-setup link for the new admin.

Uses Application Default Credentials: run `gcloud auth application-default login` once.
Run via:  python tasks.py bootstrap-admin you@example.com "Your Name" --yes
"""

import os
import sys

import firebase_admin
from firebase_admin import auth, firestore

PROJECT_ID = "hypertension-dd85f"


def main(email: str, name: str) -> None:
    for var in ("FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"):
        if os.environ.get(var):
            sys.exit(f"Refusing: {var} is set. This script is for the live project only.")

    firebase_admin.initialize_app(options={"projectId": PROJECT_ID})
    db = firestore.client()

    existing_admins = (
        db.collection("users")
        .where(filter=firestore.FieldFilter("role", "==", "admin"))
        .limit(1)
        .get()
    )
    if existing_admins:
        sys.exit("An admin already exists. Create further staff in the staff portal (Users).")

    try:
        user = auth.get_user_by_email(email)
        uid = user.uid
        print(f"Using existing Firebase Auth user {uid}.")
    except auth.UserNotFoundError:
        uid = auth.create_user(email=email, display_name=name).uid
        print(f"Created Firebase Auth user {uid}.")

    auth.set_custom_user_claims(uid, {"role": "admin"})
    ref = db.collection("users").document(uid)
    if ref.get().exists:
        sys.exit(f"users/{uid} already exists; not overwriting it. Claim set to admin.")
    now = firestore.SERVER_TIMESTAMP
    ref.create(
        {
            "email": email,
            "name": name,
            "role": "admin",
            "isActive": True,
            "createdAt": now,
            "updatedAt": now,
        }
    )
    db.collection("audit_logs").add(
        {
            "userId": "system:bootstrap",
            "action": "BOOTSTRAP_ADMIN",
            "targetType": "users",
            "targetId": uid,
            "details": "First admin account created with tasks.py bootstrap-admin.",
            "timestamp": now,
        }
    )
    link = auth.generate_password_reset_link(email)
    print("\nAdmin account ready. Open this link to set the password, then sign in to the")
    print("staff portal with the Admin role selected:\n")
    print(link)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit('Usage: bootstrap_admin.py <email> "<full name>"')
    main(sys.argv[1].strip().lower(), sys.argv[2].strip())
