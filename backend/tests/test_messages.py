"""Module 10 message notifications (FR-10.1, FR-10.3, FR-14.4; UC10.1, UC10.3; D-42)."""

from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from tests.conftest import (
    InMemoryAlertRepository,
    InMemoryAuditLogger,
    InMemoryMessageRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P, D = "u-patient", "u-doctor"


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users[P] = {"name": "Siti", "role": "patient", "assignedDoctorId": D}
    repo.users[D] = {"name": "Dr John", "role": "doctor"}
    tokens.add(P, "token-of-patient", "android")
    tokens.add(D, "token-of-doctor", "web")


def stored(repo: InMemoryMessageRepository, mid: str, **fields: Any) -> None:
    repo.messages[mid] = {
        "senderId": P,
        "recipientId": D,
        "encryptedText": "b64-ciphertext",
        "isFlagged": False,
        **fields,
    }


def test_uc10_1_recipient_is_pushed_without_message_text(
    client: TestClient,
    message_repo: InMemoryMessageRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
    alerts_repo: InMemoryAlertRepository,
) -> None:
    stored(message_repo, "m1")
    res = client.post("/api/v1/messages/m1/notify", headers=bearer("patient-token"))
    assert res.status_code == 204
    [(tokens, msg)] = push.sent
    assert tokens == ["token-of-doctor"]
    assert msg.title == "New message from Siti"
    assert "ciphertext" not in msg.body and not msg.urgent
    assert alerts_repo.alerts == []
    assert "SEND_MESSAGE" in audit.actions()


def test_uc10_3_flagged_patient_message_alerts_the_doctor(
    client: TestClient,
    message_repo: InMemoryMessageRepository,
    push: LogPushClient,
    alerts_repo: InMemoryAlertRepository,
) -> None:
    stored(message_repo, "m1", isFlagged=True)
    client.post("/api/v1/messages/m1/notify", headers=bearer("patient-token"))
    [alert] = alerts_repo.alerts
    assert alert["type"] == "flagged_message" and alert["severity"] == "high"
    assert alert["doctorId"] == D
    assert "Siti" in alert["message"] and "b64" not in alert["message"]
    assert push.sent[0][1].urgent


def test_doctor_replies_notify_the_patient_but_never_raise_alerts(
    client: TestClient,
    message_repo: InMemoryMessageRepository,
    push: LogPushClient,
    alerts_repo: InMemoryAlertRepository,
) -> None:
    stored(message_repo, "m2", senderId=D, recipientId=P, isFlagged=True)
    assert (
        client.post("/api/v1/messages/m2/notify", headers=bearer("doctor-token")).status_code == 204
    )
    assert push.sent[0][0] == ["token-of-patient"]
    assert push.sent[0][1].title == "New message from Dr John"
    assert alerts_repo.alerts == []


@pytest.mark.parametrize("token", ["doctor-token", "family-token"])
def test_only_the_sender_can_notify(
    client: TestClient, message_repo: InMemoryMessageRepository, token: str
) -> None:
    stored(message_repo, "m1")
    res = client.post("/api/v1/messages/m1/notify", headers=bearer(token))
    assert res.status_code in (403, 404)


def test_unknown_message_is_404(client: TestClient) -> None:
    res = client.post("/api/v1/messages/nope/notify", headers=bearer("patient-token"))
    assert res.status_code == 404


@pytest.mark.parametrize(
    ("kind", "body"), [("image", "Sent you a photo."), ("pdf", "Sent you a document.")]
)
def test_d52_attachment_push_says_what_was_sent_but_not_what_it_is(
    client: TestClient,
    message_repo: InMemoryMessageRepository,
    push: LogPushClient,
    kind: str,
    body: str,
) -> None:
    stored(
        message_repo,
        "m1",
        encryptedText="",
        attachmentPath=f"message_attachments/{P}/{D}/m1",
        attachmentType=kind,
        attachmentName="b64-encrypted-name",
    )
    client.post("/api/v1/messages/m1/notify", headers=bearer("patient-token"))
    [(_, msg)] = push.sent
    assert msg.body == body and "b64" not in msg.body
