"""D-65: forgot-password email through Brevo with Firebase's reset link."""

from fastapi.testclient import TestClient

from app.core.rate_limit import RateLimiter
from app.integrations.email import ConsoleEmailClient
from app.routers.auth import get_reset_limiter
from tests.conftest import (
    FakeIdentityProvider,
    InMemoryAuditLogger,
    MakeClient,
    dev_settings,
)

URL = "/api/v1/auth/password-reset"


def test_d65_existing_account_gets_a_branded_email(
    client: TestClient,
    identity: FakeIdentityProvider,
    emails: ConsoleEmailClient,
    audit: InMemoryAuditLogger,
) -> None:
    res = client.post(URL, json={"email": "Taken@Example.com"})
    assert res.status_code == 202 and res.json() == {"status": "sent_if_exists"}
    mail = emails.sent[-1]
    assert mail.to_email == "taken@example.com"
    assert mail.subject == "Reset your CareFlow password"
    assert "Hello Ali," in mail.text
    # Firebase's secure page first, then back to CareFlow's "password changed" page.
    assert "continue=https://hypertension-dd85f.web.app/reset-done.html" in mail.text
    assert "1 hour" in mail.text
    # Plain text, not <a href>: Brevo's click-tracking redirect would break the link.
    assert "https://example.test/reset" in mail.html and "<a " not in mail.html
    assert audit.entries[-1]["action"] == "PASSWORD_RESET_REQUESTED"
    assert "taken@" not in audit.entries[-1]["details"]  # domain only


def test_unknown_email_gives_the_same_answer_and_sends_nothing(
    client: TestClient, emails: ConsoleEmailClient
) -> None:
    res = client.post(URL, json={"email": "nobody@example.com"})
    assert res.status_code == 202 and res.json() == {"status": "sent_if_exists"}
    assert emails.sent == []


def test_invalid_email_is_rejected(client: TestClient) -> None:
    assert client.post(URL, json={"email": "not-an-email"}).status_code == 422


def test_rate_limited_per_client(make_client: MakeClient) -> None:
    limiter = RateLimiter(5)
    client = make_client(dev_settings())
    client.app.dependency_overrides[get_reset_limiter] = lambda: limiter  # type: ignore[attr-defined]
    codes = [client.post(URL, json={"email": "x@example.com"}).status_code for _ in range(7)]
    assert codes[:5] == [202] * 5 and 429 in codes[5:]
