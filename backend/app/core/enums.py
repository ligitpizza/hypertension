"""Shared enum values from docs/04-data-model.md.

Must stay identical to docs/fixtures/enums.json and app/lib/core/constants/enums.dart
(checked by tests/test_enums.py).
"""

from enum import StrEnum


class Collection(StrEnum):
    USERS = "users"
    HEALTH_PROFILES = "health_profiles"
    VITAL_READINGS = "vital_readings"
    RISK_SCORES = "risk_scores"
    TRIAGE_OUTCOMES = "triage_outcomes"
    MEDICATIONS = "medications"
    DOSE_LOGS = "dose_logs"
    HEALTH_RECORDS = "health_records"
    APPOINTMENTS = "appointments"
    DOCTOR_ASSIGNMENT_REQUESTS = "doctor_assignment_requests"  # D-54
    CLINICAL_NOTES = "clinical_notes"
    PRESCRIPTIONS = "prescriptions"
    CARE_PLANS = "care_plans"
    MESSAGES = "messages"
    MEDICATION_ORDERS = "medication_orders"
    AUDIT_LOGS = "audit_logs"
    AGENT_MESSAGES = "agent_messages"
    EMERGENCY_ALERTS = "emergency_alerts"
    SYMPTOM_CATALOG = "symptom_catalog"
    PAYMENT_TRANSACTIONS = "payment_transactions"
    DELIVERY_TRACKING_EVENTS = "delivery_tracking_events"
    FAMILY_LINK_REQUESTS = "family_link_requests"  # D-06
    CLINICAL_ALERTS = "clinical_alerts"  # D-32


class UserRole(StrEnum):
    PATIENT = "patient"
    DOCTOR = "doctor"
    PHARMACIST = "pharmacist"
    ADMIN = "admin"
    FAMILY_MEMBER = "family_member"


class TriageSeverity(StrEnum):
    MILD = "mild"
    MODERATE = "moderate"
    SEVERE = "severe"


class TriageOutcome(StrEnum):
    MONITOR_AT_HOME = "monitor_at_home"
    CONTACT_DOCTOR = "contact_doctor"
    SEEK_EMERGENCY_CARE = "seek_emergency_care"


class DoseStatus(StrEnum):
    TAKEN = "taken"
    MISSED = "missed"


class AppointmentStatus(StrEnum):
    BOOKED = "booked"
    RESCHEDULED = "rescheduled"
    CANCELLED = "cancelled"
    COMPLETED = "completed"
    NO_SHOW = "no_show"  # D-56


class AppointmentType(StrEnum):
    """appointments.type (D-53)."""

    CHECKUP = "checkup"
    FOLLOW_UP = "follow_up"
    EMERGENCY = "emergency"


class AssignmentRequestKind(StrEnum):
    """doctor_assignment_requests.kind (D-54)."""

    NEW_PATIENT = "new_patient"
    REASSIGN = "reassign"


class AssignmentRequestStatus(StrEnum):
    PENDING = "pending"
    APPROVED = "approved"
    DECLINED = "declined"


class OrderMethod(StrEnum):
    SELF_COLLECTION = "self_collection"
    HOME_DELIVERY = "home_delivery"


class PaymentStatus(StrEnum):
    PENDING = "pending"
    PAID = "paid"
    FAILED = "failed"


class OrderDeliveryStatus(StrEnum):
    """medication_orders.deliveryStatus (current state only)."""

    DISPATCHED = "dispatched"
    IN_TRANSIT = "in_transit"
    DELIVERED = "delivered"
    FAILED = "failed"


class TrackingEventStatus(StrEnum):
    """delivery_tracking_events.status (full trail, includes picked_up)."""

    DISPATCHED = "dispatched"
    PICKED_UP = "picked_up"
    IN_TRANSIT = "in_transit"
    DELIVERED = "delivered"
    FAILED = "failed"


class PaymentTransactionStatus(StrEnum):
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    REFUNDED = "refunded"


class AgentMessageRole(StrEnum):
    PATIENT = "patient"
    AGENT = "agent"


class FamilyLinkStatus(StrEnum):
    """family_link_requests.status (D-06)."""

    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class Complication(StrEnum):
    """Keys of the risk_scores.scores map (FR-9.2)."""

    STROKE = "stroke"
    CAD = "cad"
    HEART_FAILURE = "heartFailure"
    CKD = "ckd"
    T2D = "t2d"


class RiskLevel(StrEnum):
    """FR-9.3, ascending severity (overall level = max, D-03)."""

    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"
    CRITICAL = "critical"


class BpCategory(StrEnum):
    """BP classifier categories (docs/06 §E), ascending severity."""

    NORMAL = "normal"
    ELEVATED = "elevated"
    STAGE1 = "stage1"
    STAGE2 = "stage2"
    CRISIS = "crisis"


class AlertLevel(StrEnum):
    """Threshold alert levels (FR-9.1). Separate from TriageOutcome (D-18)."""

    MILD = "mild"
    MODERATE = "moderate"
    EMERGENCY = "emergency"


class InteractionSeverity(StrEnum):
    """Drug interaction severity (docs/06 §C)."""

    MINOR = "minor"
    MAJOR = "major"
    CRITICAL = "critical"


class Gender(StrEnum):
    MALE = "male"
    FEMALE = "female"
    OTHER = "other"


class SmokingStatus(StrEnum):
    NEVER = "never"
    FORMER = "former"
    CURRENT = "current"


class AlcoholUse(StrEnum):
    NONE = "none"
    OCCASIONAL = "occasional"
    REGULAR = "regular"


class SaltIntake(StrEnum):
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"


class MedicalCondition(StrEnum):
    """Existing conditions captured at onboarding (D-25)."""

    DIABETES = "diabetes"
    CHRONIC_KIDNEY_DISEASE = "chronic_kidney_disease"
    HEART_DISEASE = "heart_disease"
    HEART_FAILURE = "heart_failure"
    STROKE = "stroke"
    HIGH_CHOLESTEROL = "high_cholesterol"


class FamilyHistoryCondition(StrEnum):
    HYPERTENSION = "hypertension"
    HEART_DISEASE = "heart_disease"
    STROKE = "stroke"
    DIABETES = "diabetes"
    KIDNEY_DISEASE = "kidney_disease"


class ClientApp(StrEnum):
    """Which client surface made the request (D-14)."""

    PATIENT = "patient"
    FAMILY = "family"
    STAFF = "staff"


class SessionEvent(StrEnum):
    LOGIN = "LOGIN"
    LOGOUT = "LOGOUT"


class LoginFailureReason(StrEnum):
    """Reasons recorded for failed sign-ins (D-27)."""

    INVALID_CREDENTIALS = "invalid_credentials"
    ACCOUNT_DEACTIVATED = "account_deactivated"
    ROLE_MISMATCH = "role_mismatch"
    WRONG_APP = "wrong_app"
    TOO_MANY_ATTEMPTS = "too_many_attempts"
    OTHER = "other"


class ClinicalAlertType(StrEnum):
    """clinical_alerts.type (D-32)."""

    THRESHOLD = "threshold"
    RISK_ESCALATION = "risk_escalation"
    DETERIORATION = "deterioration"
    MEDICATION_REVIEW = "medication_review"
    TRIAGE = "triage"
    FLAGGED_MESSAGE = "flagged_message"
    LOW_ADHERENCE = "low_adherence"  # D-49


class PrescriptionSource(StrEnum):
    """prescriptions.source (D-50); absent means doctor."""

    DOCTOR = "doctor"
    PATIENT = "patient"


class ClinicalAlertStatus(StrEnum):
    OPEN = "open"
    ACKNOWLEDGED = "acknowledged"
    DISMISSED = "dismissed"


STAFF_ROLES = frozenset({UserRole.DOCTOR, UserRole.PHARMACIST, UserRole.ADMIN})
SELF_REGISTER_ROLES = frozenset({UserRole.PATIENT, UserRole.FAMILY_MEMBER})  # FR-1.1, FR-1.6

# Which role each client app serves (D-14, D-26).
APP_ROLES: dict[ClientApp, frozenset[UserRole]] = {
    ClientApp.PATIENT: frozenset({UserRole.PATIENT}),
    ClientApp.FAMILY: frozenset({UserRole.FAMILY_MEMBER}),
    ClientApp.STAFF: STAFF_ROLES,
}
