"""Push notification adapter (Firebase Cloud Messaging, D-33).

FCM is sent from FastAPI with the Admin SDK. With FCM_ENABLED=false (local
development and tests) pushes are logged instead of sent.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Protocol

from firebase_admin import messaging

from app.core.config import get_settings
from app.core.firebase import get_firebase_app

log = logging.getLogger("careflow.push")


@dataclass(frozen=True)
class PushMessage:
    title: str
    body: str
    data: dict[str, str] = field(default_factory=dict)
    # "high" for alerts that must wake the device (emergency, critical risk).
    urgent: bool = False


class PushClient(Protocol):
    def send(self, tokens: list[str], message: PushMessage) -> list[str]:
        """Send to the tokens; return the tokens FCM rejected as invalid."""
        ...


class LogPushClient:
    """Fake used locally and in tests."""

    def __init__(self) -> None:
        self.sent: list[tuple[list[str], PushMessage]] = []

    def send(self, tokens: list[str], message: PushMessage) -> list[str]:
        self.sent.append((list(tokens), message))
        log.info("[push] to %d device(s): %s - %s", len(tokens), message.title, message.body)
        return []


class FcmPushClient:
    _INVALID = ("registration-token-not-registered", "invalid-argument")

    def send(self, tokens: list[str], message: PushMessage) -> list[str]:
        if not tokens:
            return []
        multicast = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=message.title, body=message.body),
            data=message.data,
            android=messaging.AndroidConfig(
                priority="high" if message.urgent else "normal",
                notification=messaging.AndroidNotification(
                    channel_id="careflow_alerts" if message.urgent else "careflow_general"
                ),
            ),
        )
        response = messaging.send_each_for_multicast(multicast, app=get_firebase_app())
        invalid = []
        for token, result in zip(tokens, response.responses, strict=True):
            if not result.success and result.exception is not None:
                code = getattr(result.exception, "code", "")
                if any(k in str(code).lower() for k in self._INVALID):
                    invalid.append(token)
                else:
                    log.warning("FCM send failed: %s", result.exception)
        return invalid


def get_push_client() -> PushClient:
    return FcmPushClient() if get_settings().fcm_enabled else LogPushClient()
