"""SMS adapter (FR-14.2, docs/06 Emergency band; D-62).

Only a fake is wired for now (Ping chose simulated SMS): it records and logs each message.
A real provider (Twilio, Brevo SMS, ...) can be added behind the same interface later.
"""

import logging
from dataclasses import dataclass, field
from typing import Protocol

log = logging.getLogger("careflow.sms")


class SmsClient(Protocol):
    def send(self, to_phone: str, text: str) -> bool:
        """Returns True only if a real provider accepted the message."""
        ...


@dataclass
class LogSmsClient:
    sent: list[tuple[str, str]] = field(default_factory=list)

    def send(self, to_phone: str, text: str) -> bool:
        self.sent.append((to_phone, text))
        log.info("SMS (simulated) to %s: %s", to_phone, text)
        return False


_FAKE = LogSmsClient()


def get_sms_client() -> SmsClient:
    return _FAKE
