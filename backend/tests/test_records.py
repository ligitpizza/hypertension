"""Module 6 health records (FR-6.1, FR-6.2; UC6.1-UC6.3; D-58)."""

from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryFileStore,
    InMemoryRecordRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P, D = "u-patient", "u-doctor"
PATIENT, DOCTOR = bearer("patient-token"), bearer("doctor-token")
PDF = b"%PDF-1.7 test"


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users[P] = {"role": "patient", "name": "Siti", "assignedDoctorId": D}
    repo.users[D] = {"role": "doctor", "name": "Dr John"}
    tokens.add(D, "token-of-doctor", "web")


def upload(
    client: TestClient,
    files: InMemoryFileStore,
    rid: str = "rec00001",
    content_type: str = "application/pdf",
    data: bytes = PDF,
    category: str = "lab_result",
) -> Any:
    files.files[f"health_records/{P}/{rid}"] = (data, content_type)
    return client.post(
        "/api/v1/records",
        json={"recordId": rid, "category": category, "fileName": "blood_test.pdf"},
        headers=PATIENT,
    )


def test_fr6_1_uc6_1_upload_and_categorise(
    client: TestClient,
    file_store: InMemoryFileStore,
    record_repo: InMemoryRecordRepository,
    audit: InMemoryAuditLogger,
) -> None:
    res = upload(client, file_store)
    assert res.status_code == 201
    body = res.json()
    assert body["category"] == "lab_result" and body["sizeBytes"] == len(PDF)
    assert body["sharedWithDoctor"] is False
    r = record_repo.records["rec00001"]
    assert r["patientId"] == P and r["fileUrl"] == f"health_records/{P}/rec00001"
    assert r["contentType"] == "application/pdf" and r["fileName"] == "blood_test.pdf"
    assert audit.entries[-1]["action"] == "UPLOAD_RECORD"


def test_uc6_1_category_is_required_and_known(
    client: TestClient, file_store: InMemoryFileStore
) -> None:
    assert upload(client, file_store, category="diary").status_code == 422
    file_store.files[f"health_records/{P}/rec00002"] = (PDF, "application/pdf")
    res = client.post(
        "/api/v1/records",
        json={"recordId": "rec00002", "fileName": "x.pdf"},
        headers=PATIENT,
    )
    assert res.status_code == 422


def test_uc6_1_e1_unsupported_type_is_rejected_and_removed(
    client: TestClient, file_store: InMemoryFileStore
) -> None:
    res = upload(client, file_store, content_type="application/msword")
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "UNSUPPORTED_FILE" and "PDF, JPG or PNG" in err["message"]
    assert file_store.files == {}


def test_uc6_1_e1_too_large_is_rejected(client: TestClient, file_store: InMemoryFileStore) -> None:
    big = b"0" * (10 * 1024 * 1024 + 1)
    res = upload(client, file_store, content_type="image/png", data=big)
    assert res.json()["error"]["code"] == "UNSUPPORTED_FILE"


def test_uc6_1_e2_missing_upload_asks_to_retry(client: TestClient) -> None:
    res = client.post(
        "/api/v1/records",
        json={"recordId": "rec00009", "category": "other", "fileName": "a.pdf"},
        headers=PATIENT,
    )
    assert res.status_code == 409 and res.json()["error"]["code"] == "UPLOAD_MISSING"


def test_only_patients_upload(client: TestClient, file_store: InMemoryFileStore) -> None:
    file_store.files[f"health_records/{D}/rec00001"] = (PDF, "application/pdf")
    res = client.post(
        "/api/v1/records",
        json={"recordId": "rec00001", "category": "other", "fileName": "a.pdf"},
        headers=DOCTOR,
    )
    assert res.status_code == 403


def test_fr6_2_uc6_2_share_grants_the_doctor_and_pushes(
    client: TestClient,
    file_store: InMemoryFileStore,
    record_repo: InMemoryRecordRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    upload(client, file_store)
    # Not shared yet: the doctor cannot open it.
    assert client.get("/api/v1/records/rec00001/file", headers=DOCTOR).status_code == 404
    res = client.post("/api/v1/records/rec00001/share", headers=PATIENT)
    assert res.status_code == 200 and res.json()["sharedWithDoctor"] is True
    assert record_repo.records["rec00001"]["sharedAt"] is not None
    assert push.sent[-1][1].title == "New shared document"
    assert "Siti shared a document: Lab result" in push.sent[-1][1].body
    assert audit.entries[-1]["action"] == "SHARE_RECORD"
    # UC6.3: the assigned doctor can now open the file.
    res = client.get("/api/v1/records/rec00001/file", headers=DOCTOR)
    assert res.status_code == 200 and res.content == PDF
    assert res.headers["content-type"] == "application/pdf"
    # Sharing again does not push twice.
    count = len(push.sent)
    client.post("/api/v1/records/rec00001/share", headers=PATIENT)
    assert len(push.sent) == count


def test_share_needs_an_assigned_doctor(
    client: TestClient, file_store: InMemoryFileStore, repo: InMemoryUserRepository
) -> None:
    upload(client, file_store)
    repo.users[P].pop("assignedDoctorId")
    res = client.post("/api/v1/records/rec00001/share", headers=PATIENT)
    assert res.json()["error"]["code"] == "NO_DOCTOR"


def test_another_doctor_cannot_open_a_shared_record(
    client: TestClient, file_store: InMemoryFileStore, repo: InMemoryUserRepository
) -> None:
    upload(client, file_store)
    client.post("/api/v1/records/rec00001/share", headers=PATIENT)
    repo.users[P]["assignedDoctorId"] = "someone-else"  # reassigned
    assert client.get("/api/v1/records/rec00001/file", headers=DOCTOR).status_code == 404


def test_d58_stop_sharing_removes_access(
    client: TestClient,
    file_store: InMemoryFileStore,
    record_repo: InMemoryRecordRepository,
    audit: InMemoryAuditLogger,
) -> None:
    upload(client, file_store)
    client.post("/api/v1/records/rec00001/share", headers=PATIENT)
    res = client.delete("/api/v1/records/rec00001/share", headers=PATIENT)
    assert res.json()["sharedWithDoctor"] is False
    assert "sharedAt" not in record_repo.records["rec00001"]
    assert audit.entries[-1]["action"] == "UNSHARE_RECORD"
    assert client.get("/api/v1/records/rec00001/file", headers=DOCTOR).status_code == 404


def test_d58_change_category(
    client: TestClient, file_store: InMemoryFileStore, record_repo: InMemoryRecordRepository
) -> None:
    upload(client, file_store)
    res = client.patch(
        "/api/v1/records/rec00001", json={"category": "referral_letter"}, headers=PATIENT
    )
    assert res.json()["category"] == "referral_letter"
    assert record_repo.records["rec00001"]["category"] == "referral_letter"


def test_d58_delete_removes_record_and_file(
    client: TestClient,
    file_store: InMemoryFileStore,
    record_repo: InMemoryRecordRepository,
    audit: InMemoryAuditLogger,
) -> None:
    upload(client, file_store)
    assert client.delete("/api/v1/records/rec00001", headers=PATIENT).status_code == 204
    assert record_repo.records == {} and file_store.files == {}
    assert audit.entries[-1]["action"] == "DELETE_RECORD"


def test_patients_only_touch_their_own_records(
    client: TestClient,
    file_store: InMemoryFileStore,
    record_repo: InMemoryRecordRepository,
) -> None:
    upload(client, file_store)
    record_repo.records["rec00001"]["patientId"] = "someone-else"
    for res in (
        client.get("/api/v1/records/rec00001/file", headers=PATIENT),
        client.post("/api/v1/records/rec00001/share", headers=PATIENT),
        client.patch("/api/v1/records/rec00001", json={"category": "other"}, headers=PATIENT),
        client.delete("/api/v1/records/rec00001", headers=PATIENT),
    ):
        assert res.status_code == 404


def test_patient_opens_own_file(client: TestClient, file_store: InMemoryFileStore) -> None:
    upload(client, file_store)
    res = client.get("/api/v1/records/rec00001/file", headers=PATIENT)
    assert res.status_code == 200 and res.content == PDF
