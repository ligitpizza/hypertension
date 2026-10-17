"""D-76: team and admin-opened chats, Harvey AI in the patient-doctor chat (FR-10.1,
FR-10.3, FR-14.1, FR-14.4; UC10.1, UC10.3), and the weekly health summary."""

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.gemini import FakeLlmClient
from app.integrations.push import LogPushClient
from app.services.agent import bp_in_text, chat_concern
from app.services.notifications import Notifier
from app.services.weekly_summary import KIND, WeeklySummaryJob, ensure_summary, summary_text
from tests.conftest import (
    InMemoryAgentDataRepository,
    InMemoryConversationRepository,
    InMemoryDeteriorationRepository,
    InMemoryMessageRepository,
    InMemoryRiskRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    InMemoryVitalsRepository,
    bearer,
)

P, D, PH, A, P2 = "u-patient", "u-doctor", "u-pharm", "u-admin", "u-other"
PATIENT, DOCTOR, PHARM, ADMIN = (
    bearer("patient-token"),
    bearer("doctor-token"),
    bearer("pharmacist-token"),
    bearer("admin-token"),
)
URL = "/api/v1/conversations"


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users.update(
        {
            P: {"role": "patient", "name": "Siti", "assignedDoctorId": D},
            P2: {"role": "patient", "name": "Ali"},
            D: {"role": "doctor", "name": "Dr Tan"},
            PH: {"role": "pharmacist", "name": "Aisyah"},
            A: {"role": "admin", "name": "Admin Lee"},
            "u-fam": {"role": "family_member", "name": "Son"},
            "u-gone": {"role": "doctor", "name": "Dr Gone", "isActive": False},
        }
    )
    for uid in (P, P2, D, PH, A):
        tokens.add(uid, f"token-{uid}", "android")


def titles(push: LogPushClient, uid: str) -> list[str]:
    return [m.title for toks, m in push.sent if f"token-{uid}" in toks]


def start(client: TestClient, who: dict[str, str], user_id: str) -> dict[str, Any]:
    res = client.post(URL, json={"userId": user_id}, headers=who)
    assert res.status_code == 201, res.text
    return dict(res.json())


# ---- starting chats ----


def test_d76_staff_chat_with_staff_and_unread_counts(
    client: TestClient, push: LogPushClient
) -> None:
    conv = start(client, DOCTOR, PH)
    assert conv["other"]["name"] == "Aisyah" and conv["other"]["role"] == "pharmacist"
    assert start(client, PHARM, D)["id"] == conv["id"]  # one chat per pair

    res = client.post(
        f"{URL}/{conv['id']}/messages", json={"text": "Is losartan in stock?"}, headers=DOCTOR
    )
    assert res.status_code == 201 and res.json()["senderName"] == "Dr Tan"
    assert "Message from Dr Tan" in titles(push, PH)

    [mine] = client.get(URL, headers=PHARM).json()["conversations"]
    assert mine["unread"] == 1 and mine["lastText"] == "Is losartan in stock?"
    assert client.get(URL, headers=DOCTOR).json()["conversations"][0]["unread"] == 0

    assert client.post(f"{URL}/{conv['id']}/read", headers=PHARM).status_code == 204
    assert client.get(URL, headers=PHARM).json()["conversations"][0]["unread"] == 0


def test_d76_who_may_start_a_chat(client: TestClient) -> None:
    # Pharmacists and doctors start chats with staff only; patients start none here.
    assert client.post(URL, json={"userId": P2}, headers=PHARM).status_code == 403
    assert client.post(URL, json={"userId": PH}, headers=PATIENT).status_code == 403
    # Family members and deactivated accounts can't be messaged.
    assert client.post(URL, json={"userId": "u-fam"}, headers=ADMIN).status_code == 404
    assert client.post(URL, json={"userId": "u-gone"}, headers=ADMIN).status_code == 404
    assert client.post(URL, json={"userId": D}, headers=DOCTOR).status_code == 422
    assert client.post(URL, json={"userId": D}, headers=ADMIN).status_code == 201


def test_d76_admin_can_message_any_patient_and_the_patient_replies(
    client: TestClient, push: LogPushClient
) -> None:
    conv = start(client, ADMIN, P)
    client.post(
        f"{URL}/{conv['id']}/messages", json={"text": "Please update your IC."}, headers=ADMIN
    )
    [seen] = client.get(URL, headers=PATIENT).json()["conversations"]
    assert seen["other"] == {"uid": A, "name": "Admin Lee", "role": "admin"}
    assert seen["unread"] == 1
    res = client.post(f"{URL}/{conv['id']}/messages", json={"text": "Done!"}, headers=PATIENT)
    assert res.status_code == 201
    assert "Message from Siti" in titles(push, A)


def test_d76_contacts_staff_see_staff_admin_sees_everyone(client: TestClient) -> None:
    doc = {c["uid"] for c in client.get(f"{URL}/contacts", headers=DOCTOR).json()["contacts"]}
    assert doc == {PH, A}
    admin = client.get(f"{URL}/contacts", headers=ADMIN).json()["contacts"]
    assert {c["uid"] for c in admin} == {P, P2, D, PH}
    found = client.get(f"{URL}/contacts?q=sit", headers=ADMIN).json()["contacts"]
    assert [c["uid"] for c in found] == [P]
    assert client.get(f"{URL}/contacts", headers=PATIENT).status_code == 403


# ---- admin assigns who chats with whom ----


def test_d76_admin_opens_a_chat_between_a_pharmacist_and_a_patient(
    client: TestClient, push: LogPushClient, conversations: InMemoryConversationRepository
) -> None:
    res = client.post(f"{URL}/pair", json={"userA": PH, "userB": P}, headers=ADMIN)
    assert res.status_code == 201, res.text
    conv = res.json()
    assert conv["observer"] is True and conv["openedByAdmin"] is True

    thread = client.get(f"{URL}/{conv['id']}/messages", headers=PATIENT).json()
    [note] = thread["messages"]
    assert note["senderRole"] == "system"
    assert "Admin Lee (admin) opened this chat between" in note["text"]
    assert thread["conversation"]["other"]["role"] == "pharmacist"
    assert "New chat opened by admin" in titles(push, P)
    assert "New chat opened by admin" in titles(push, PH)

    # Both can talk; the admin who opened it can read it but not write in it.
    assert (
        client.post(f"{URL}/{conv['id']}/messages", json={"text": "Hi"}, headers=PHARM).status_code
        == 201
    )
    admin_view = client.get(f"{URL}/{conv['id']}/messages", headers=ADMIN)
    assert admin_view.status_code == 200 and len(admin_view.json()["messages"]) == 2
    assert (
        client.post(f"{URL}/{conv['id']}/messages", json={"text": "x"}, headers=ADMIN).status_code
        == 404
    )
    assert any(c["observer"] for c in client.get(URL, headers=ADMIN).json()["conversations"])
    # Someone else can't see it at all.
    assert client.get(f"{URL}/{conv['id']}/messages", headers=DOCTOR).status_code == 404
    # Opening it again doesn't post a second notice.
    client.post(f"{URL}/pair", json={"userA": P, "userB": PH}, headers=ADMIN)
    assert len(conversations.msgs) == 2


def test_d76_pairing_rules(client: TestClient) -> None:
    pair = f"{URL}/pair"
    assert client.post(pair, json={"userA": P, "userB": P2}, headers=ADMIN).status_code == 422
    assert client.post(pair, json={"userA": D, "userB": P}, headers=ADMIN).status_code == 409
    assert client.post(pair, json={"userA": PH, "userB": PH}, headers=ADMIN).status_code == 422
    assert client.post(pair, json={"userA": PH, "userB": P}, headers=DOCTOR).status_code == 403


# ---- Harvey AI in the patient-doctor chat ----


def test_d76_bp_is_read_from_the_message_text() -> None:
    assert bp_in_text("my bp was 200/150 this morning") == (200, 150)
    assert bp_in_text("BP 185 over 100") == (185, 100)
    assert bp_in_text("see you on 12/10") is None
    assert chat_concern("my bp was 200/150")  # crisis range
    assert chat_concern("bp 150/95 today") is None  # high, but not a crisis
    assert chat_concern("I have chest pain") == "words that can be signs of an emergency"


def _stored(message_repo: InMemoryMessageRepository, flagged: bool, sender: str = P) -> None:
    message_repo.messages["m1"] = {
        "senderId": sender,
        "recipientId": D,
        "encryptedText": "b64",
        "isFlagged": flagged,
    }


def test_d76_flagged_bp_message_gets_a_harvey_ai_note_and_alerts_the_doctor(
    client: TestClient,
    message_repo: InMemoryMessageRepository,
    agent_repo: InMemoryAgentDataRepository,
    llm: FakeLlmClient,
    push: LogPushClient,
) -> None:
    _stored(message_repo, flagged=True)
    llm.reply = "Harvey AI here. 200/150 is very high."
    res = client.post(
        "/api/v1/messages/m1/ai-review", json={"text": "my bp was 200/150"}, headers=PATIENT
    )
    assert res.status_code == 200, res.text
    assert res.json() == {"posted": True, "note": "Harvey AI here. 200/150 is very high."}
    [note] = [m for m in agent_repo.messages if m.get("kind") == "chat_alert"]
    assert note["doctorId"] == D and note["role"] == "agent"
    assert "200/150" in llm.calls[-1][2] and "Dr Tan" in llm.calls[-1][2]
    [(_toks, msg)] = [(t, m) for t, m in push.sent if "token-u-doctor" in t]
    assert msg.urgent and msg.title == "Harvey AI flagged a message from Siti"


def test_d76_ai_note_falls_back_to_a_fixed_text(
    client: TestClient,
    message_repo: InMemoryMessageRepository,
    agent_repo: InMemoryAgentDataRepository,
    llm: FakeLlmClient,
) -> None:
    _stored(message_repo, flagged=True)
    llm.fail = True
    res = client.post(
        "/api/v1/messages/m1/ai-review", json={"text": "bp 210/130 now"}, headers=PATIENT
    )
    note = res.json()["note"]
    assert "999" in note and "Dr Tan" in note and "210/130" in note


def test_d76_ai_review_needs_the_patients_own_flagged_message(
    client: TestClient, message_repo: InMemoryMessageRepository
) -> None:
    review = "/api/v1/messages/m1/ai-review"
    _stored(message_repo, flagged=False)
    assert client.post(review, json={"text": "200/150"}, headers=PATIENT).json() == {
        "posted": False
    }
    _stored(message_repo, flagged=True)
    # The server's own check also has to agree.
    assert client.post(review, json={"text": "all fine"}, headers=PATIENT).json() == {
        "posted": False
    }
    _stored(message_repo, flagged=True, sender=P2)
    assert client.post(review, json={"text": "200/150"}, headers=PATIENT).status_code == 404
    assert client.post(review, json={"text": "200/150"}, headers=DOCTOR).status_code == 403


# ---- weekly summary ----

NOW = datetime(2026, 10, 19, 6, tzinfo=UTC)  # a Monday


def _readings(vitals_repo: InMemoryVitalsRepository) -> None:
    for i, (s, d) in enumerate([(150, 95), (140, 90), (160, 100)]):
        vitals_repo.readings[f"r{i}"] = {
            "patientId": P,
            "systolic": s,
            "diastolic": d,
            "timestamp": NOW - timedelta(days=i + 1),
        }


def test_d76_summary_reports_readings_adherence_and_risk_change(
    agent_repo: InMemoryAgentDataRepository,
    vitals_repo: InMemoryVitalsRepository,
    risk_repo: InMemoryRiskRepository,
) -> None:
    _readings(vitals_repo)
    agent_repo.meds[P] = [{"name": "Amlodipine", "adherenceRate": 80.0}, {"name": "X"}]
    risk_repo.saved += [
        {
            "patientId": P,
            "generatedAt": NOW - timedelta(days=10),
            "scores": {"stroke": {"level": "moderate"}},
        },
        {
            "patientId": P,
            "generatedAt": NOW - timedelta(days=1),
            "scores": {"stroke": {"level": "high"}},
        },
    ]
    text = summary_text(agent_repo, P, NOW)
    assert "3 readings, average 150/95 mmHg" in text
    assert "Highest 160/100" in text
    assert "80% of doses taken" in text
    assert "high, up from moderate last week" in text
    assert "book a check-up" in text


def test_d76_summary_with_no_data_still_helps(agent_repo: InMemoryAgentDataRepository) -> None:
    text = summary_text(agent_repo, P, NOW)
    assert "no readings this week" in text and "not assessed yet" in text


def test_d76_one_summary_a_week(agent_repo: InMemoryAgentDataRepository) -> None:
    assert ensure_summary(agent_repo, P, NOW) is True
    assert ensure_summary(agent_repo, P, NOW) is False
    assert [m["kind"] for m in agent_repo.messages] == [KIND]


def test_d76_job_posts_on_mondays_only(
    agent_repo: InMemoryAgentDataRepository,
    deterioration_repo: InMemoryDeteriorationRepository,
    tokens: InMemoryTokenRepository,
    push: LogPushClient,
) -> None:
    deterioration_repo.patients = [(P, {"name": "Siti"})]
    job = WeeklySummaryJob(agent_repo, deterioration_repo, Notifier(tokens, push))
    assert job.run(NOW + timedelta(days=1)) == {"weeklySummaries": 0}
    assert job.run(NOW) == {"weeklySummaries": 1}
    assert "Your weekly health summary" in titles(push, P)


def test_d76_inbox_asks_for_the_first_summary(
    client: TestClient, agent_repo: InMemoryAgentDataRepository
) -> None:
    res = client.post("/api/v1/agent/weekly-summary", headers=PATIENT)
    assert res.json() == {"created": True}
    assert client.post("/api/v1/agent/weekly-summary", headers=PATIENT).json() == {"created": False}
    assert client.post("/api/v1/agent/weekly-summary", headers=DOCTOR).status_code == 403
