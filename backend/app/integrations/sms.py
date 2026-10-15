"""SMS adapter (FR-14.2, docs/06 Emergency band; D-62, D-64).

Real provider: Brevo transactional SMS (same API key as email). Fake: records and logs.
Selected like email: INTEGRATIONS_MODE=real plus a key and a registered sender name.
"""

import logging
import re
from dataclasses import dataclass, field
from typing import Protocol

import httpx

from app.core.config import Settings, get_settings

log = logging.getLogger("careflow.sms")

BREVO_SMS_URL = "https://api.brevo.com/v3/transactionalSMS/send"


class SmsClient(Protocol):
    def send(self, to_phone: str, text: str) -> bool:
        """Returns True only if a real provider accepted the message."""
        ...


def international(phone: str, country_code: str = "60") -> str | None:
    """Malaysian-style numbers to E.164 digits: "012-345 6789" -> "60123456789".
    None when it can't be a phone number (Brevo needs 6-15 digits)."""
    digits = re.sub(r"\D", "", phone)
    if phone.strip().startswith("+"):
        pass
    elif digits.startswith("00"):
        digits = digits[2:]
    elif digits.startswith("0"):
        digits = country_code + digits[1:]
    return digits if 6 <= len(digits) <= 15 else None


@dataclass
class LogSmsClient:
    sent: list[tuple[str, str]] = field(default_factory=list)

    def send(self, to_phone: str, text: str) -> bool:
        self.sent.append((to_phone, text))
        log.info("SMS (simulated) to %s: %s", to_phone, text)
        return False


class BrevoSmsClient:
    def __init__(self, api_key: str, sender: str) -> None:
        self._api_key = api_key
        self._sender = sender

    def send(self, to_phone: str, text: str) -> bool:
        recipient = international(to_phone)
        if recipient is None:
            log.warning("SMS not sent: %r is not a phone number", to_phone)
            return False
        try:
            res = httpx.post(
                BREVO_SMS_URL,
                json={
                    "sender": self._sender,
                    "recipient": recipient,
                    "content": text,
                    "type": "transactional",
                    "tag": "careflow-emergency",
                },
                headers={"api-key": self._api_key, "accept": "application/json"},
                timeout=10.0,
            )
        except httpx.HTTPError as exc:
            # An SMS failure must never stop the alert (push and email still go out).
            log.error("Brevo SMS request failed: %s", exc)
            return False
        if res.status_code >= 300:
            log.error("Brevo rejected the SMS (HTTP %s): %s", res.status_code, res.text[:300])
            return False
        return True


_FAKE = LogSmsClient()


def sms_is_real(settings: Settings) -> bool:
    return bool(
        settings.integrations_mode == "real" and settings.email_api_key and settings.sms_sender
    )


def build_sms_client(settings: Settings) -> SmsClient:
    if sms_is_real(settings):
        return BrevoSmsClient(settings.email_api_key, settings.sms_sender)
    return _FAKE


def get_sms_client() -> SmsClient:
    return build_sms_client(get_settings())
