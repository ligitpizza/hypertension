"""Email adapter (D-22). Real provider: Brevo transactional API. Fake: logs to console.

Selected by INTEGRATIONS_MODE (docs/05 "External integrations"); every provider
sits behind the same interface so the rest of the code never imports Brevo.
"""

import logging
from dataclasses import dataclass
from typing import Protocol

import httpx

from app.core.config import Settings, get_settings

log = logging.getLogger("careflow.email")

BREVO_SEND_URL = "https://api.brevo.com/v3/smtp/email"


@dataclass(frozen=True)
class EmailMessage:
    to_email: str
    to_name: str
    subject: str
    text: str
    html: str


class EmailError(Exception):
    pass


class EmailClient(Protocol):
    def send(self, message: EmailMessage) -> None: ...


class ConsoleEmailClient:
    """Fake used locally and in tests: records and logs instead of sending."""

    def __init__(self) -> None:
        self.sent: list[EmailMessage] = []

    def send(self, message: EmailMessage) -> None:
        self.sent.append(message)
        log.info(
            "[fake email] to=%s subject=%s\n%s", message.to_email, message.subject, message.text
        )


class BrevoEmailClient:
    def __init__(self, api_key: str, sender_email: str, sender_name: str) -> None:
        if not api_key or not sender_email:
            raise EmailError("Brevo is not configured (EMAIL_API_KEY / EMAIL_FROM).")
        self._api_key = api_key
        self._sender = {"email": sender_email, "name": sender_name}

    def send(self, message: EmailMessage) -> None:
        payload = {
            "sender": self._sender,
            "to": [{"email": message.to_email, "name": message.to_name}],
            "subject": message.subject,
            "textContent": message.text,
            "htmlContent": message.html,
        }
        try:
            res = httpx.post(
                BREVO_SEND_URL,
                json=payload,
                headers={"api-key": self._api_key, "accept": "application/json"},
                timeout=10.0,
            )
        except httpx.HTTPError as exc:
            raise EmailError(f"Brevo request failed: {exc}") from exc
        if res.status_code >= 300:
            raise EmailError(f"Brevo rejected the email (HTTP {res.status_code}).")


def build_email_client(settings: Settings) -> EmailClient:
    if settings.integrations_mode == "real" and settings.email_api_key:
        return BrevoEmailClient(
            settings.email_api_key, settings.email_from, settings.email_from_name
        )
    return ConsoleEmailClient()


def get_email_client() -> EmailClient:
    """Dependency so tests can inject a fake."""
    return build_email_client(get_settings())
