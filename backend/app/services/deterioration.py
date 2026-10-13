"""30-day deterioration scan (FR-9.6, UC9.3; docs/06 §F).

A daily Cloud Scheduler job fits a least-squares line to each complication's risk value
over the last 30 days. If the slope is at or above SLOPE_PER_DAY and the latest value is
higher than the earliest, the assigned doctor gets a `deterioration` clinical alert
(at most one per patient per DEDUPE_DAYS).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

from fastapi import Depends
from firebase_admin import firestore

from app.core.enums import ClinicalAlertType, Collection, Complication, RiskLevel, UserRole
from app.core.firebase import get_firestore
from app.services.escalation import (
    AlertRepository,
    DoctorAlert,
    EscalationPlan,
    Escalator,
    get_alert_repository,
    get_escalator,
)

WINDOW = timedelta(days=30)
# Probability points per day: 0.001/day is a rise of 3 percentage points over 30 days.
SLOPE_PER_DAY = 0.001
MIN_SCORES = 3
MIN_SPAN = timedelta(days=7)
DEDUPE_DAYS = 7


def slope_per_day(points: list[tuple[datetime, float]]) -> float:
    t0 = points[0][0]
    xs = [(t - t0).total_seconds() / 86400 for t, _ in points]
    ys = [v for _, v in points]
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return 0.0
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys, strict=True)) / sxx


def deteriorating(points: list[tuple[datetime, float]]) -> bool:
    """`points` is oldest first."""
    if len(points) < MIN_SCORES or points[-1][0] - points[0][0] < MIN_SPAN:
        return False
    return slope_per_day(points) >= SLOPE_PER_DAY and points[-1][1] > points[0][1]


def worsening_complications(
    scores_oldest_first: list[tuple[datetime, dict[str, Any]]],
) -> list[Complication]:
    out = []
    for c in Complication:
        points = [(t, float(s[c.value]["value"])) for t, s in scores_oldest_first if c.value in s]
        if deteriorating(points):
            out.append(c)
    return out


class DeteriorationRepository(Protocol):
    def active_patients(self) -> list[tuple[str, dict[str, Any]]]: ...

    def scores_since(self, uid: str, since: datetime) -> list[tuple[datetime, dict[str, Any]]]:
        """(generatedAt, scores map) oldest first."""
        ...


class FirestoreDeteriorationRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def active_patients(self) -> list[tuple[str, dict[str, Any]]]:
        query = (
            self._db.collection(Collection.USERS.value)
            .where(filter=firestore.FieldFilter("role", "==", UserRole.PATIENT.value))
            .where(filter=firestore.FieldFilter("isActive", "==", True))
        )
        return [(d.id, dict(d.to_dict())) for d in query.stream()]

    def scores_since(self, uid: str, since: datetime) -> list[tuple[datetime, dict[str, Any]]]:
        query = (
            self._db.collection(Collection.RISK_SCORES.value)
            .where(filter=firestore.FieldFilter("patientId", "==", uid))
            .where(filter=firestore.FieldFilter("generatedAt", ">=", since))
            .order_by("generatedAt", direction=firestore.Query.DESCENDING)
        )
        rows = [(d.get("generatedAt"), d.get("scores") or {}) for d in query.stream()]
        return list(reversed(rows))


def get_deterioration_repository() -> DeteriorationRepository:
    return FirestoreDeteriorationRepository(get_firestore())


@dataclass
class DeteriorationJob:
    repo: DeteriorationRepository
    alerts: AlertRepository
    escalator: Escalator

    def run(self, now: datetime | None = None) -> dict[str, Any]:
        now = now or datetime.now(UTC)
        scanned = flagged = 0
        for uid, user in self.repo.active_patients():
            scanned += 1
            worse = worsening_complications(self.repo.scores_since(uid, now - WINDOW))
            if not worse:
                continue
            since = now - timedelta(days=DEDUPE_DAYS)
            if self.alerts.recent_alert_exists(uid, ClinicalAlertType.DETERIORATION, since):
                continue
            name = user.get("name") or "A patient"
            plan = EscalationPlan(
                doctor_alerts=[
                    DoctorAlert(
                        ClinicalAlertType.DETERIORATION,
                        RiskLevel.HIGH,
                        f"{name}'s risk has risen steadily over 30 days "
                        f"({', '.join(c.value for c in worse)}).",
                    )
                ]
            )
            if self.escalator.apply(plan, uid, user.get("assignedDoctorId"), now):
                flagged += 1
        return {"patientsScanned": scanned, "alertsRaised": flagged}


def get_deterioration_job(
    repo: DeteriorationRepository = Depends(get_deterioration_repository),
    alerts: AlertRepository = Depends(get_alert_repository),
    escalator: Escalator = Depends(get_escalator),
) -> DeteriorationJob:
    return DeteriorationJob(repo, alerts, escalator)
