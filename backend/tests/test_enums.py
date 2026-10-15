import json
from enum import StrEnum
from pathlib import Path

import pytest

from app.core import enums

FIXTURE = json.loads(
    (Path(__file__).resolve().parents[2] / "docs" / "fixtures" / "enums.json").read_text("utf-8")
)

CASES: dict[str, type[StrEnum]] = {
    "collections": enums.Collection,
    "user_role": enums.UserRole,
    "triage_severity": enums.TriageSeverity,
    "triage_outcome": enums.TriageOutcome,
    "dose_status": enums.DoseStatus,
    "appointment_status": enums.AppointmentStatus,
    "order_method": enums.OrderMethod,
    "payment_status": enums.PaymentStatus,
    "order_delivery_status": enums.OrderDeliveryStatus,
    "tracking_event_status": enums.TrackingEventStatus,
    "payment_transaction_status": enums.PaymentTransactionStatus,
    "agent_message_role": enums.AgentMessageRole,
    "family_link_status": enums.FamilyLinkStatus,
    "complication": enums.Complication,
    "risk_level": enums.RiskLevel,
    "bp_category": enums.BpCategory,
    "alert_level": enums.AlertLevel,
    "interaction_severity": enums.InteractionSeverity,
    "gender": enums.Gender,
    "smoking_status": enums.SmokingStatus,
    "alcohol_use": enums.AlcoholUse,
    "salt_intake": enums.SaltIntake,
    "medical_condition": enums.MedicalCondition,
    "family_history_condition": enums.FamilyHistoryCondition,
    "client_app": enums.ClientApp,
    "session_event": enums.SessionEvent,
    "login_failure_reason": enums.LoginFailureReason,
    "clinical_alert_type": enums.ClinicalAlertType,
    "clinical_alert_status": enums.ClinicalAlertStatus,
    "prescription_source": enums.PrescriptionSource,
    "appointment_type": enums.AppointmentType,
    "assignment_request_kind": enums.AssignmentRequestKind,
    "assignment_request_status": enums.AssignmentRequestStatus,
    "record_category": enums.RecordCategory,
}


@pytest.mark.parametrize("key", sorted(CASES))
def test_shared_enum_matches_fixture(key: str) -> None:
    assert [e.value for e in CASES[key]] == FIXTURE[key]


def test_fixture_has_no_enum_missing_from_python() -> None:
    assert {k for k in FIXTURE if not k.startswith("_")} == set(CASES)


def test_fr_1_6_staff_roles_cannot_self_register() -> None:
    assert enums.STAFF_ROLES.isdisjoint(enums.SELF_REGISTER_ROLES)
