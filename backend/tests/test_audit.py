from typing import Any

import pytest

from app.core.audit import FirestoreAuditLogger, build_audit_entry


class _Ref:
    id = "doc-1"


class _FakeCollection:
    def __init__(self, store: dict[str, list[dict[str, Any]]], name: str) -> None:
        self._store, self._name = store, name

    def add(self, data: dict[str, Any]) -> tuple[None, _Ref]:
        self._store.setdefault(self._name, []).append(data)
        return None, _Ref()


class _FakeDb:
    def __init__(self) -> None:
        self.store: dict[str, list[dict[str, Any]]] = {}

    def collection(self, name: str) -> _FakeCollection:
        return _FakeCollection(self.store, name)


def test_fr_1_5_audit_entry_has_data_dictionary_fields() -> None:
    entry = build_audit_entry(
        user_id="u1",
        action="DEACTIVATE_ACCOUNT",
        details="Admin deactivated user u2",
        target_type="users",
        target_id="u2",
        timestamp="ts",
    )
    assert entry == {
        "userId": "u1",
        "action": "DEACTIVATE_ACCOUNT",
        "details": "Admin deactivated user u2",
        "targetType": "users",
        "targetId": "u2",
        "timestamp": "ts",
    }


def test_fr_1_5_optional_targets_are_omitted() -> None:
    entry = build_audit_entry(
        user_id="u1", action="LOGIN", details="", target_type=None, target_id=None, timestamp="ts"
    )
    assert "targetType" not in entry
    assert "targetId" not in entry


def test_fr_1_5_audit_entry_requires_actor_and_action() -> None:
    with pytest.raises(ValueError, match="user_id and action"):
        build_audit_entry(
            user_id="", action="X", details="", target_type=None, target_id=None, timestamp="ts"
        )


def test_fr_1_5_firestore_logger_writes_to_audit_logs() -> None:
    db = _FakeDb()
    log_id = FirestoreAuditLogger(db).log(user_id="u1", action="TEST", details="d")
    assert log_id == "doc-1"
    assert len(db.store["audit_logs"]) == 1
    assert db.store["audit_logs"][0]["action"] == "TEST"
