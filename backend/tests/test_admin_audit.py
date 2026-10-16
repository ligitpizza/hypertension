"""Module 11 audit log viewer (FR-1.5, FR-11.3, UC11.3; D-59)."""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryAuditReader,
    InMemoryUserRepository,
    bearer,
)

ADMIN = bearer("admin-token")


def myt_noon(days_ago: int) -> datetime:
    now = datetime.now(UTC) + timedelta(hours=8)
    day = now.date() - timedelta(days=days_ago)
    return datetime(day.year, day.month, day.day, 4, tzinfo=UTC)  # 12:00 MYT


@pytest.fixture(autouse=True)
def seeded(audit_reader: InMemoryAuditReader, repo: InMemoryUserRepository) -> None:
    repo.users["u-admin"] = {"role": "admin", "name": "Ada Admin"}
    repo.users["u-doctor"] = {"role": "doctor", "name": "Dr John"}
    add = audit_reader.add
    add(myt_noon(0), "UPDATE_CARE_PLAN", "u-doctor", targetType="care_plans", targetId="p1")
    add(myt_noon(1), "LOGIN_FAILED", "anonymous", details="app=staff; reason=wrong_password")
    add(myt_noon(1), "LOGIN_FAILED", "anonymous", details="app=staff; reason=wrong_password")
    add(myt_noon(2), "DEACTIVATE_ACCOUNT", targetType="users", targetId="u-x")
    add(myt_noon(3), "EXPORT_DATA", "u-patient")
    add(myt_noon(5), "LOGIN", "u-doctor")
    add(myt_noon(10), "LOGIN", "u-doctor")  # previous 7-day window
    add(myt_noon(40), "LOGIN", "u-doctor")  # outside both


def test_uc11_3_last_7_days_with_summary_and_names(client: TestClient) -> None:
    res = client.get("/api/v1/admin/audit-logs", headers=ADMIN)
    assert res.status_code == 200
    body = res.json()
    assert body["total"] == 6
    first = body["entries"][0]
    assert first["action"] == "UPDATE_CARE_PLAN" and first["userName"] == "Dr John"
    assert first["role"] == "doctor" and first["module"] == "Clinical care"
    s = body["summary"]
    assert s["totalEvents"] == 6 and s["changeFromPrevious"] == 500  # 1 -> 6
    assert s["failedLogins"] == 2 and s["privilegeChanges"] == 1 and s["dataExports"] == 1
    assert "LOGIN_FAILED" in body["actions"]


def test_filter_by_action_user_text_and_dates(client: TestClient) -> None:
    def get(**p: str) -> Any:
        return client.get("/api/v1/admin/audit-logs", params=p, headers=ADMIN).json()

    assert get(action="LOGIN_FAILED")["total"] == 2
    assert get(userId="u-doctor")["total"] == 2
    assert get(q="wrong_password")["total"] == 2
    assert get(q="dr john")["total"] == 2
    day = (datetime.now(UTC) + timedelta(hours=8)).date() - timedelta(days=10)
    body = get(**{"from": day.isoformat(), "to": day.isoformat()})
    assert body["total"] == 1 and body["entries"][0]["module"] == "Authentication"


def test_paging(client: TestClient) -> None:
    res = client.get(
        "/api/v1/admin/audit-logs", params={"offset": 4, "limit": 15}, headers=ADMIN
    ).json()
    assert res["total"] == 6 and len(res["entries"]) == 2


def test_bad_range(client: TestClient) -> None:
    res = client.get(
        "/api/v1/admin/audit-logs",
        params={"from": "2026-10-10", "to": "2026-10-01"},
        headers=ADMIN,
    )
    assert res.json()["error"]["code"] == "INVALID_RANGE"


def test_fr11_3_csv_export_is_itself_audited(
    client: TestClient, audit: InMemoryAuditLogger
) -> None:
    res = client.get(
        "/api/v1/admin/audit-logs.csv", params={"action": "LOGIN_FAILED"}, headers=ADMIN
    )
    assert res.status_code == 200 and res.headers["content-type"].startswith("text/csv")
    lines = res.text.strip().splitlines()
    assert lines[0].startswith("timestamp,userId,userName,role,action,module")
    assert len(lines) == 3
    assert audit.entries[-1]["action"] == "EXPORT_AUDIT_LOG"


@pytest.mark.parametrize("token", ["doctor-token", "patient-token"])
def test_admin_only(client: TestClient, token: str) -> None:
    assert client.get("/api/v1/admin/audit-logs", headers=bearer(token)).status_code == 403
    assert client.get("/api/v1/admin/audit-logs.csv", headers=bearer(token)).status_code == 403
