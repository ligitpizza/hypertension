"""Firebase ID token verification and role checks (FR-1.3, NFR-2.2, NFR-5.1).

Every /api/v1 request that touches user data sends `Authorization: Bearer <idToken>`.
The `role` custom claim is the source of truth for authorisation (docs/04 rule 4).
"""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from fastapi import Depends, Header, status
from firebase_admin import auth as fb_auth

from app.core.enums import UserRole
from app.core.errors import ApiError
from app.core.firebase import get_firebase_app

TokenVerifier = Callable[[str], dict[str, Any]]


@dataclass(frozen=True)
class CurrentUser:
    uid: str
    role: UserRole | None
    email: str | None


def _firebase_verify(token: str) -> dict[str, Any]:
    claims: dict[str, Any] = fb_auth.verify_id_token(token, app=get_firebase_app())
    return claims


def get_token_verifier() -> TokenVerifier:
    """Dependency so tests can swap in a fake verifier."""
    return _firebase_verify


def _unauthenticated(message: str) -> ApiError:
    return ApiError("UNAUTHENTICATED", message, status.HTTP_401_UNAUTHORIZED)


def get_current_user(
    authorization: str | None = Header(default=None),
    verify: TokenVerifier = Depends(get_token_verifier),
) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise _unauthenticated("Missing bearer token.")
    token = authorization.split(" ", 1)[1].strip()
    try:
        claims = verify(token)
    except Exception as exc:  # firebase raises several token error types
        raise _unauthenticated("Invalid or expired token.") from exc

    raw_role = claims.get("role")
    try:
        role = UserRole(raw_role) if raw_role else None
    except ValueError:
        role = None
    return CurrentUser(uid=str(claims["uid"]), role=role, email=claims.get("email"))


def require_roles(*roles: UserRole) -> Callable[..., CurrentUser]:
    """Dependency factory: allow only the given roles (FR-1.3)."""
    allowed = frozenset(roles)

    def _check(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if user.role not in allowed:
            raise ApiError(
                "FORBIDDEN", "You do not have access to this resource.", status.HTTP_403_FORBIDDEN
            )
        return user

    return _check
