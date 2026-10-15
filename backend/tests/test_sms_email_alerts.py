"""D-64: Brevo SMS adapter and the family emergency email."""

from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.integrations.sms import (
    BREVO_SMS_URL,
    BrevoSmsClient,
    LogSmsClient,
    build_sms_client,
    international,
)
from tests.conftest import (
    ConsoleEmailClient,
    InMemoryUserRepository,
    bearer,
    dev_settings,
)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("012-345 6789", "60123456789"),
        ("+60 12-345 6789", "60123456789"),
        ("0060123456789", "60123456789"),
        ("6012 3456789", "60123456789"),
        ("12", None),
    ],
)
def test_malaysian_numbers_become_international(raw: str, expected: str | None) -> None:
    assert international(raw) == expected


def test_brevo_sms_request(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, Any] = {}

    def fake_post(url: str, json: dict[str, Any], headers: dict[str, str], timeout: float) -> Any:
        seen.update(url=url, json=json, headers=headers)
        return httpx.Response(201, json={"messageId": 1})

    monkeypatch.setattr("app.integrations.sms.httpx.post", fake_post)
    assert BrevoSmsClient("key-1", "CareFlow").send("012-3456789", "Help") is True
    assert seen["url"] == BREVO_SMS_URL
    assert seen["headers"]["api-key"] == "key-1"
    assert seen["json"] == {
        "sender": "CareFlow",
        "recipient": "60123456789",
        "content": "Help",
        "type": "transactional",
        "tag": "careflow-emergency",
    }


def test_brevo_refusal_or_outage_never_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.integrations.sms.httpx.post",
        lambda *a, **k: httpx.Response(402, text="not enough credits"),
    )
    assert BrevoSmsClient("k", "CareFlow").send("0123456789", "x") is False

    def boom(*a: Any, **k: Any) -> Any:
        raise httpx.ConnectError("down")

    monkeypatch.setattr("app.integrations.sms.httpx.post", boom)
    assert BrevoSmsClient("k", "CareFlow").send("0123456789", "x") is False
    assert BrevoSmsClient("k", "CareFlow").send("abc", "x") is False


def test_real_sms_needs_mode_key_and_sender() -> None:
    real = dev_settings(integrations_mode="real", email_api_key="k", sms_sender="CareFlow")
    assert isinstance(build_sms_client(real), BrevoSmsClient)
    for missing in (
        dev_settings(integrations_mode="fake", email_api_key="k", sms_sender="CareFlow"),
        dev_settings(integrations_mode="real", email_api_key="", sms_sender="CareFlow"),
        dev_settings(integrations_mode="real", email_api_key="k", sms_sender=""),
    ):
        assert isinstance(build_sms_client(missing), LogSmsClient)


def test_d64_family_members_also_get_an_emergency_email(
    client: TestClient, repo: InMemoryUserRepository, emails: ConsoleEmailClient
) -> None:
    repo.users.update(
        {
            "u-patient": {"role": "patient", "name": "Siti"},
            "u-family": {
                "role": "family_member",
                "name": "Aisyah",
                "email": "aisyah@example.com",
                "patientId": "u-patient",
            },
        }
    )
    res = client.post(
        "/api/v1/emergency/sos",
        json={"location": {"lat": 3.139, "lng": 101.6869}},
        headers=bearer("patient-token"),
    )
    assert res.json()["familyAlerted"] == 1
    mail = emails.sent[-1]
    assert mail.to_email == "aisyah@example.com"
    assert mail.subject == "CareFlow emergency: Siti"
    assert "pressed the SOS button" in mail.text
    assert "maps.google.com/?q=3.139000,101.686900" in mail.text
    assert "999" in mail.text
