"""D-77: the notification bell, staff profile settings and charts in the PDF report."""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient, PushMessage
from app.services.analytics import report_pdf
from app.services.inbox import category, purge_old
from app.services.notifications import Notifier
from tests.conftest import (
    InMemoryInboxRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P, D = "u-patient", "u-doctor"
PATIENT, DOCTOR, ADMIN = bearer("patient-token"), bearer("doctor-token"), bearer("admin-token")


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository) -> None:
    repo.users.update(
        {
            P: {"role": "patient", "name": "Siti", "assignedDoctorId": D},
            D: {"role": "doctor", "name": "Dr Tan", "specialty": "Cardiology"},
            "u-admin": {"role": "admin", "name": "Admin Lee"},
        }
    )


def test_d77_every_push_is_saved_even_without_a_device(
    inbox: InMemoryInboxRepository, tokens: InMemoryTokenRepository, push: LogPushClient
) -> None:
    notifier = Notifier(tokens, push, inbox)
    assert notifier.notify(D, PushMessage("Message from Siti", "Hello", {"type": "message"})) == 0
    [(_, saved)] = inbox.for_user(D, 10)
    assert saved["title"] == "Message from Siti" and saved["category"] == "messages"
    assert saved["read"] is False


def test_d77_bell_lists_and_marks_read(client: TestClient, inbox: InMemoryInboxRepository) -> None:
    for i in range(3):
        inbox.add(
            {
                "userId": D,
                "title": f"Alert {i}",
                "body": "",
                "type": "clinical_alert",
                "category": "alerts",
                "data": {"type": "clinical_alert"},
                "urgent": False,
                "read": False,
                "createdAt": datetime.now(UTC),
            }
        )
    body = client.get("/api/v1/notifications", headers=DOCTOR).json()
    assert body["unread"] == 3 and body["notifications"][0]["title"] == "Alert 2"
    assert client.post("/api/v1/notifications/n1/read", headers=DOCTOR).status_code == 204
    assert client.get("/api/v1/notifications", headers=DOCTOR).json()["unread"] == 2
    # Someone else's notification can't be touched.
    assert client.post("/api/v1/notifications/n2/read", headers=PATIENT).status_code == 404
    assert client.post("/api/v1/notifications/read-all", headers=DOCTOR).json() == {"updated": 2}
    assert client.get("/api/v1/notifications", headers=PATIENT).json()["notifications"] == []


def test_d77_categories_can_be_switched_off_but_urgent_stays(
    client: TestClient,
    inbox: InMemoryInboxRepository,
    tokens: InMemoryTokenRepository,
    push: LogPushClient,
) -> None:
    res = client.put(
        "/api/v1/notifications/prefs",
        json={
            "messages": True,
            "alerts": True,
            "appointments": True,
            "orders": False,
            "medication": True,
            "other": True,
        },
        headers=DOCTOR,
    )
    assert res.status_code == 200
    assert client.get("/api/v1/notifications/prefs", headers=DOCTOR).json()["orders"] is False
    notifier = Notifier(tokens, push, inbox)
    notifier.notify(D, PushMessage("Order ready", "", {"type": "order"}))
    notifier.notify(D, PushMessage("Order failed", "", {"type": "order"}, urgent=True))
    assert [n["title"] for _, n in inbox.for_user(D, 10)] == ["Order failed"]
    assert category("pharmacy_chat") == "messages" and category("nope") == "other"


def test_d77_old_notifications_are_purged(inbox: InMemoryInboxRepository) -> None:
    now = datetime(2026, 10, 17, tzinfo=UTC)
    for days in (40, 5):
        inbox.add({"userId": D, "read": True, "createdAt": now - timedelta(days=days)})
    assert purge_old(inbox, now) == {"notificationsPurged": 1}
    assert len(inbox.items) == 1


def test_d77_staff_edit_their_profile(client: TestClient, repo: InMemoryUserRepository) -> None:
    res = client.put(
        "/api/v1/settings/staff-profile",
        json={"name": "Dr Tan Wei", "phone": "012-345 6789", "specialty": "Nephrology"},
        headers=DOCTOR,
    )
    assert res.status_code == 200, res.text
    me = client.get("/api/v1/settings/staff-profile", headers=DOCTOR).json()
    assert me["name"] == "Dr Tan Wei" and me["phone"] == "012-345 6789"
    assert me["specialty"] == "Nephrology"
    # Admins have no specialty; patients use their own settings pages.
    client.put(
        "/api/v1/settings/staff-profile",
        json={"name": "Admin Lee", "specialty": "x"},
        headers=ADMIN,
    )
    assert "specialty" not in repo.users["u-admin"]
    assert (
        client.put(
            "/api/v1/settings/staff-profile", json={"name": "Siti"}, headers=PATIENT
        ).status_code
        == 403
    )
    bad = client.put(
        "/api/v1/settings/staff-profile", json={"name": "Dr Tan", "phone": "abc"}, headers=DOCTOR
    )
    assert bad.status_code == 422


def test_d77_pdf_report_draws_charts() -> None:
    data: dict[str, Any] = {
        "patients": {
            "active": 10,
            "newRegistrations": 2,
            "readingsLogged": 50,
            "patientsScored": 8,
            "risk": {"low": 4, "moderate": 2, "high": 1, "critical": 1},
        },
        "appointments": {
            "total": 6,
            "completed": 3,
            "noShow": 1,
            "cancelled": 1,
            "upcoming": 1,
            "topCancellationReasons": [],
        },
        "care": {
            "adherence": 80.0,
            "missedDoses": 3,
            "alertsRaised": 4,
            "alertsBySeverity": {"high": 3, "critical": 1},
            "alertsResolved": 2,
            "triage": {},
        },
        "usage": {"activeClinicians": 2, "messagesSent": 9, "recordsShared": 1, "logins": 20},
    }
    with_charts = report_pdf(data, "Oct 2026", "today")
    data["patients"]["risk"] = {}
    for key in ("completed", "noShow", "cancelled", "upcoming"):
        data["appointments"][key] = 0
    data["care"]["alertsBySeverity"] = {}
    data["usage"] = {"activeClinicians": 0, "messagesSent": 0, "recordsShared": 0, "logins": 0}
    without = report_pdf(data, "Oct 2026", "today")
    assert with_charts.startswith(b"%PDF")
    # The charts are drawn as filled rectangles (" re" operators) in the content.
    assert len(with_charts) > len(without)
