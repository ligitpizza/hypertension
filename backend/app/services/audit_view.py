"""Audit log viewer (FR-1.5, FR-11.3, UC11.3; D-59).

Entries are read by time range (single-field index) and filtered here, which is fine for
a single clinic. The admin also gets a CSV export.
"""

import csv
import io
from datetime import datetime
from typing import Any, Protocol

from google.cloud import firestore as gfs

from app.core.enums import Collection
from app.core.firebase import get_firestore

FAILED_LOGIN = ("LOGIN_FAILED", "LOGIN_BLOCKED")
PRIVILEGE = (
    "CREATE_STAFF_ACCOUNT",
    "EDIT_USER",
    "DEACTIVATE_ACCOUNT",
    "REACTIVATE_ACCOUNT",
    "ASSIGN_DOCTOR",
)
EXPORTS = ("EXPORT_DATA", "EXPORT_AUDIT_LOG", "GENERATE_REPORT")

# "Module affected" (Fig 4.3.14.3), from targetType first, then the action name.
_BY_TARGET = {
    "users": "Accounts",
    "vital_readings": "Vitals & risk",
    "risk_scores": "Vitals & risk",
    "medications": "Medications",
    "dose_logs": "Medications",
    "prescriptions": "Medications",
    "appointments": "Appointments",
    "doctor_assignment_requests": "Assignments",
    "messages": "Messaging",
    "health_records": "Health records",
    "clinical_notes": "Clinical care",
    "care_plans": "Clinical care",
    "clinical_alerts": "Clinical care",
    "triage_outcomes": "Symptom checker",
    "health_profiles": "Accounts",
}


def module_of(entry: dict[str, Any]) -> str:
    target = str(entry.get("targetType") or "")
    if target in _BY_TARGET:
        return _BY_TARGET[target]
    action = str(entry.get("action") or "")
    if action.startswith(("LOGIN", "LOGOUT", "REGISTER")):
        return "Authentication"
    if action.startswith("JOB_"):
        return "System"
    if "EXPORT" in action or "REPORT" in action:
        return "Reports & exports"
    return "Other"


class AuditReader(Protocol):
    def between(self, start: datetime, end: datetime) -> list[tuple[str, dict[str, Any]]]:
        """Entries with start <= timestamp < end, newest first."""
        ...


class FirestoreAuditReader:
    def __init__(self, db: Any) -> None:
        self._db = db

    def between(self, start: datetime, end: datetime) -> list[tuple[str, dict[str, Any]]]:
        q = (
            self._db.collection(Collection.AUDIT_LOGS.value)
            .where(filter=gfs.FieldFilter("timestamp", ">=", start))
            .where(filter=gfs.FieldFilter("timestamp", "<", end))
            .order_by("timestamp", direction=gfs.Query.DESCENDING)
        )
        return [(d.id, dict(d.to_dict())) for d in q.stream()]


def get_audit_reader() -> AuditReader:
    return FirestoreAuditReader(get_firestore())


def summarise(entries: list[dict[str, Any]], previous_total: int) -> dict[str, Any]:
    failed = [e for e in entries if e.get("action") in FAILED_LOGIN]
    change = (
        None
        if previous_total == 0
        else round((len(entries) - previous_total) / previous_total * 100)
    )
    return {
        "totalEvents": len(entries),
        "changeFromPrevious": change,
        "failedLogins": len(failed),
        "failedLoginDetails": len({str(e.get("details")) for e in failed}),
        "privilegeChanges": sum(1 for e in entries if e.get("action") in PRIVILEGE),
        "dataExports": sum(1 for e in entries if e.get("action") in EXPORTS),
    }


def to_csv(rows: list[dict[str, Any]]) -> str:
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(
        [
            "timestamp",
            "userId",
            "userName",
            "role",
            "action",
            "module",
            "targetType",
            "targetId",
            "details",
        ]
    )
    for r in rows:
        w.writerow(
            [
                r.get("timestamp") or "",
                r.get("userId") or "",
                r.get("userName") or "",
                r.get("role") or "",
                r.get("action") or "",
                r.get("module") or "",
                r.get("targetType") or "",
                r.get("targetId") or "",
                r.get("details") or "",
            ]
        )
    return out.getvalue()
