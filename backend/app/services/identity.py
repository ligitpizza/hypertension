"""Firebase Authentication admin operations used by Module 1.

Wrapped behind a Protocol so routers can be tested with an in-memory fake.
"""

from typing import Protocol

from firebase_admin import auth as fb_auth

from app.core.enums import UserRole
from app.core.firebase import get_firebase_app


class EmailAlreadyRegisteredError(Exception):
    pass


class IdentityProvider(Protocol):
    def create_user(self, *, email: str, display_name: str) -> str: ...

    def set_role(self, uid: str, role: UserRole) -> None: ...

    def password_setup_link(self, email: str) -> str: ...

    def revoke_sessions(self, uid: str) -> None:
        """Sign the user out everywhere (refresh tokens revoked; UC12.4)."""
        ...

    def delete_user(self, uid: str) -> None:
        """Remove the login (D-46 purge); a login that is already gone is fine."""
        ...

    def set_disabled(self, uid: str, disabled: bool) -> None:
        """UC11.1: block or allow signing in (the admin deactivates an account)."""
        ...


class FirebaseIdentityProvider:
    def create_user(self, *, email: str, display_name: str) -> str:
        # No password: the staff member sets one through the setup link (UC1.5 step 5).
        try:
            user = fb_auth.create_user(
                email=email, display_name=display_name, app=get_firebase_app()
            )
        except fb_auth.EmailAlreadyExistsError as exc:
            raise EmailAlreadyRegisteredError(email) from exc
        return str(user.uid)

    def set_role(self, uid: str, role: UserRole) -> None:
        # The `role` custom claim is what Security Rules and FastAPI trust (docs/04 rule 4).
        fb_auth.set_custom_user_claims(uid, {"role": role.value}, app=get_firebase_app())

    def password_setup_link(self, email: str) -> str:
        link: str = fb_auth.generate_password_reset_link(email, app=get_firebase_app())
        return link

    def revoke_sessions(self, uid: str) -> None:
        fb_auth.revoke_refresh_tokens(uid, app=get_firebase_app())

    def delete_user(self, uid: str) -> None:
        try:
            fb_auth.delete_user(uid, app=get_firebase_app())
        except fb_auth.UserNotFoundError:
            pass

    def set_disabled(self, uid: str, disabled: bool) -> None:
        try:
            fb_auth.update_user(uid, disabled=disabled, app=get_firebase_app())
        except fb_auth.UserNotFoundError:
            pass  # no login (e.g. already purged): isActive alone decides


def get_identity_provider() -> IdentityProvider:
    return FirebaseIdentityProvider()
