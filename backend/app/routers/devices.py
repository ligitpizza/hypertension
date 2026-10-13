"""Device registration for push notifications (D-33)."""

from typing import Literal

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field

from app.core.auth import CurrentUser, get_current_user
from app.services.notifications import TokenRepository, get_token_repository

router = APIRouter(prefix="/devices", tags=["devices"])


class FcmTokenRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=10, max_length=4096)
    platform: Literal["android", "web"]


@router.post("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
def register_token(
    body: FcmTokenRequest,
    user: CurrentUser = Depends(get_current_user),
    tokens: TokenRepository = Depends(get_token_repository),
) -> None:
    tokens.add(user.uid, body.token, body.platform)


@router.delete("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
def remove_token(
    body: FcmTokenRequest,
    user: CurrentUser = Depends(get_current_user),
    tokens: TokenRepository = Depends(get_token_repository),
) -> None:
    """Called on sign-out so the device stops receiving this user's alerts."""
    tokens.remove(user.uid, body.token)
