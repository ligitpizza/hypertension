"""Module 5 medication management (FR-5.1-5.4; UC5.1-UC5.6; algorithm C; D-05, D-43)."""

from datetime import UTC, datetime, time, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from app.services.medication_job import MedicationJob
from app.services.medications import (
    ScheduleError,
    adherence_rate,
    below_threshold,
    days_of_supply,
    dose_id,
    dose_moment,
    due_missed,
    due_now,
    format_schedule,
    parse_schedule,
)
from app.services.notifications import Notifier
from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryMedicationRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P = "u-patient"
PATIENT = bearer("patient-token")


# ---------- schedule (D-43) ----------


def test_schedule_is_parsed_sorted_and_deduplicated() -> None:
    assert parse_schedule(" 20:00, 08:00 ,08:00") == [time(8), time(20)]
    assert format_schedule(parse_schedule("20:00,08:00")) == "08:00,20:00"
    assert parse_schedule("AS_NEEDED") is None and format_schedule(None) == "as_needed"


@pytest.mark.parametrize(
    "bad", ["", "8am", "24:00", "08:60", "08:00,,x", ",".join(["01:00"] * 1) + ",9"]
)
def test_bad_schedules_are_rejected(bad: str) -> None:
    with pytest.raises(ScheduleError):
        parse_schedule(bad)


def test_dose_times_are_malaysia_time() -> None:
    day = datetime(2026, 10, 14, 3, tzinfo=UTC)  # 11:00 MYT
    assert dose_moment(day, time(8)) == datetime(2026, 10, 14, 0, tzinfo=UTC)
    assert dose_id("m1", dose_moment(day, time(8))) == "m1_202610140800"


# ---------- algorithm C, refill (UC5.5, UC5.2) ----------


def test_adherence_rate() -> None:
    assert adherence_rate([]) is None  # UC5.5 E1
    assert adherence_rate(["taken", "taken", "missed", "taken"]) == 75.0
    assert adherence_rate(["missed"]) == 0.0


def test_days_of_supply_and_threshold() -> None:
    twice = [time(8), time(20)]
    assert days_of_supply(14, twice) == 7
    assert days_of_supply(None, twice) is None and days_of_supply(10, None) is None
    assert below_threshold(13, twice, 7) and not below_threshold(14, twice, 7)


# ---------- missed doses and backup reminders (UC5.4, UC5.3) ----------


def test_due_missed_respects_window_and_creation_time() -> None:
    now = datetime(2026, 10, 14, 4, 0, tzinfo=UTC)  # 12:00 MYT
    created = datetime(2026, 10, 13, 0, 0, tzinfo=UTC)  # 08:00 MYT yesterday
    times = [time(8), time(11), time(20)]
    missed = due_missed(times, created, now, set(), "m1")
    # all of yesterday, then today 08:00; today 11:00 is still within its 2 h window
    assert [m.astimezone(UTC).hour for m in missed] == [0, 3, 12, 0]
    already = {dose_id("m1", missed[0])}
    assert len(due_missed(times, created, now, already, "m1")) == 3
    late_add = datetime(2026, 10, 14, 1, tzinfo=UTC)  # added at 09:00 MYT today
    assert due_missed(times, late_add, now, set(), "m1") == []


def test_due_now_finds_the_current_slot() -> None:
    now = datetime(2026, 10, 14, 0, 10, tzinfo=UTC)  # 08:10 MYT
    assert due_now([time(8), time(20)], now, timedelta(minutes=15)) == [
        datetime(2026, 10, 14, 0, tzinfo=UTC)
    ]
    assert due_now([time(8)], now + timedelta(minutes=10), timedelta(minutes=15)) == []


# ---------- API (UC5.1, UC5.6) ----------


def add(client: TestClient, **body: Any) -> Any:
    payload = {"name": "Amlodipine", "dosage": "5mg", "schedule": "08:00", **body}
    return client.post("/api/v1/medications", json=payload, headers=PATIENT)


def test_uc5_1_add_normalises_schedule_and_audits(
    client: TestClient, med_repo: InMemoryMedicationRepository, audit: InMemoryAuditLogger
) -> None:
    res = add(client, schedule="20:00, 08:00", quantityOnHand=30)
    assert res.status_code == 201
    med = med_repo.meds[res.json()["id"]]
    assert med["schedule"] == "08:00,20:00"
    assert med["refillThresholdDays"] == 7 and med["quantityOnHand"] == 30
    assert med["patientId"] == P and med["adherenceRate"] is None
    assert "ADD_MEDICATION" in audit.actions()


def test_invalid_schedule_is_422(client: TestClient) -> None:
    res = add(client, schedule="8am")
    assert res.status_code == 422 and res.json()["error"]["code"] == "INVALID_SCHEDULE"


def test_uc5_1_e1_duplicate_warns_before_saving(
    client: TestClient, med_repo: InMemoryMedicationRepository
) -> None:
    add(client)
    res = add(client, dosage="10mg")
    assert res.status_code == 409
    assert res.json()["error"]["details"]["duplicates"] == ["Amlodipine 5mg"]
    assert add(client, dosage="10mg", acknowledgeWarnings=True).status_code == 201
    assert len(med_repo.meds) == 2


def test_uc5_6_interaction_warns_and_needs_acknowledgement(client: TestClient) -> None:
    add(client, name="Lisinopril", dosage="10mg")
    res = add(client, name="Spironolactone", dosage="25mg")
    assert res.status_code == 409
    [found] = res.json()["error"]["details"]["interactions"]
    assert found["existingDrug"].startswith("Lisinopril") and found["severity"] == "major"
    assert (
        add(client, name="Spironolactone", dosage="25mg", acknowledgeWarnings=True).status_code
        == 201
    )


def test_edit_excludes_itself_from_duplicate_check(
    client: TestClient, med_repo: InMemoryMedicationRepository
) -> None:
    mid = add(client).json()["id"]
    res = client.put(
        f"/api/v1/medications/{mid}",
        json={"name": "Amlodipine", "dosage": "10mg", "schedule": "08:00"},
        headers=PATIENT,
    )
    assert res.status_code == 200 and med_repo.meds[mid]["dosage"] == "10mg"


def test_delete_and_ownership(client: TestClient, med_repo: InMemoryMedicationRepository) -> None:
    med_repo.meds["theirs"] = {"patientId": "u-other", "name": "X", "schedule": "08:00"}
    assert client.delete("/api/v1/medications/theirs", headers=PATIENT).status_code == 404
    mid = add(client).json()["id"]
    assert client.delete(f"/api/v1/medications/{mid}", headers=PATIENT).status_code == 204
    assert mid not in med_repo.meds


@pytest.mark.parametrize("token", ["doctor-token", "family-token"])
def test_only_patients_manage_their_list(client: TestClient, token: str) -> None:
    res = client.post(
        "/api/v1/medications",
        json={"name": "A", "dosage": "1", "schedule": "08:00"},
        headers=bearer(token),
    )
    assert res.status_code in (403, 422)


# ---------- doses (UC5.3 step 3, UC5.5, UC5.2) ----------


def slot_today(at: time) -> str:
    """The most recent occurrence of `at` (yesterday's just after midnight MYT)."""
    now = datetime.now(UTC)
    moment = dose_moment(now, at)
    if moment > now + timedelta(hours=1):
        moment -= timedelta(days=1)
    return moment.isoformat()


@pytest.fixture
def daily_now(med_repo: InMemoryMedicationRepository) -> time:
    """A dose time just before 'now' (MYT), so it can be confirmed."""
    from app.services.medications import MYT

    local = datetime.now(UTC).astimezone(MYT) - timedelta(minutes=5)
    return time(local.hour, local.minute)


def test_uc5_3_confirm_dose_logs_taken_and_updates_adherence(
    client: TestClient, med_repo: InMemoryMedicationRepository, daily_now: time
) -> None:
    mid = add(client, schedule=daily_now.strftime("%H:%M"), quantityOnHand=20).json()["id"]
    res = client.post(
        f"/api/v1/medications/{mid}/doses",
        json={"scheduledTime": slot_today(daily_now)},
        headers=PATIENT,
    )
    assert res.status_code == 201
    assert res.json()["adherenceRate"] == 100.0 and res.json()["quantityOnHand"] == 19
    [log] = med_repo.logs.values()
    assert log["status"] == "taken" and log["confirmedAt"]
    again = client.post(
        f"/api/v1/medications/{mid}/doses",
        json={"scheduledTime": slot_today(daily_now)},
        headers=PATIENT,
    )
    assert again.status_code == 409


def test_a_time_that_is_not_scheduled_is_rejected(client: TestClient, daily_now: time) -> None:
    mid = add(client, schedule=daily_now.strftime("%H:%M")).json()["id"]
    wrong = time((daily_now.hour + 3) % 24, daily_now.minute)
    res = client.post(
        f"/api/v1/medications/{mid}/doses",
        json={"scheduledTime": slot_today(wrong)},
        headers=PATIENT,
    )
    assert res.status_code == 422


def test_as_needed_dose_counts_stock_but_has_no_adherence(
    client: TestClient, med_repo: InMemoryMedicationRepository
) -> None:
    mid = add(client, name="Paracetamol", schedule="as_needed", quantityOnHand=10).json()["id"]
    res = client.post(f"/api/v1/medications/{mid}/doses", json={}, headers=PATIENT)
    assert res.status_code == 201
    assert res.json()["adherenceRate"] is None and med_repo.meds[mid]["quantityOnHand"] == 9


def test_uc5_2_refill_push_once_when_crossing_threshold(
    client: TestClient,
    push: LogPushClient,
    tokens: InMemoryTokenRepository,
    med_repo: InMemoryMedicationRepository,
    daily_now: time,
) -> None:
    tokens.add(P, "phone", "android")
    # One dose a day, 8 left, threshold 7 days: the next dose leaves 7 (not below), then 6.
    mid = add(client, schedule=daily_now.strftime("%H:%M"), quantityOnHand=8).json()["id"]
    client.post(
        f"/api/v1/medications/{mid}/doses",
        json={"scheduledTime": slot_today(daily_now)},
        headers=PATIENT,
    )
    assert [m.title for _, m in push.sent if m.title.startswith("Refill")] == []
    med_repo.logs.clear()
    client.post(
        f"/api/v1/medications/{mid}/doses",
        json={"scheduledTime": slot_today(daily_now)},
        headers=PATIENT,
    )
    assert [m.title for _, m in push.sent] == ["Refill needed: Amlodipine"]


# ---------- 15-minute sweep (UC5.4, backup reminder) ----------


def test_uc5_4_job_logs_missed_doses_and_recomputes_adherence(
    med_repo: InMemoryMedicationRepository, repo: InMemoryUserRepository
) -> None:
    now = datetime(2026, 10, 14, 4, 0, tzinfo=UTC)  # 12:00 MYT
    med_repo.meds["m1"] = {
        "patientId": P,
        "name": "Amlodipine",
        "dosage": "5mg",
        "schedule": "08:00",
        "createdAt": datetime(2026, 10, 12, tzinfo=UTC),
    }
    tokens = InMemoryTokenRepository()
    job = MedicationJob(med_repo, Notifier(tokens, LogPushClient()))
    first = job.run(now)
    assert first["missedDosesLogged"] == 2  # yesterday 08:00 and today 08:00
    assert med_repo.meds["m1"]["adherenceRate"] == 0.0
    assert job.run(now)["missedDosesLogged"] == 0  # idempotent


def test_job_sends_backup_reminder_for_a_dose_due_now(
    med_repo: InMemoryMedicationRepository,
) -> None:
    now = datetime(2026, 10, 14, 0, 5, tzinfo=UTC)  # 08:05 MYT
    med_repo.meds["m1"] = {
        "patientId": P,
        "name": "Amlodipine",
        "dosage": "5mg",
        "schedule": "08:00",
        "createdAt": datetime(2026, 10, 13, tzinfo=UTC),
    }
    tokens = InMemoryTokenRepository()
    tokens.add(P, "phone", "android")
    push = LogPushClient()
    out = MedicationJob(med_repo, Notifier(tokens, push)).run(now)
    assert out["remindersSent"] == 1
    assert push.sent[0][1].title == "Time to take Amlodipine"


def test_escalation_endpoint_includes_the_medication_sweep(client: TestClient) -> None:
    body = client.post("/internal/jobs/escalation").json()
    assert {"alertsChecked", "missedDosesLogged", "remindersSent"} <= set(body)
