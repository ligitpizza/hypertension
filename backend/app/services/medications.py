"""Module 5 medication management (FR-5.1-5.4; UC5.1-UC5.6; docs/06 algorithm C; D-05, D-43).

Pure helpers (schedule parsing, adherence, refill, missed doses) are unit-tested; the
repository wraps Firestore. Dose times are Malaysia local time (UTC+8, no daylight saving).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta, timezone
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection, DoseStatus
from app.core.firebase import get_firestore

MYT = timezone(timedelta(hours=8), "MYT")
AS_NEEDED = "as_needed"
MISSED_WINDOW = timedelta(hours=2)  # UC5.4: unconfirmed this long after the dose time
ADHERENCE_WINDOW = timedelta(days=30)  # algorithm C rolling window
DEFAULT_REFILL_DAYS = 7  # D-05
_TIME = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


class ScheduleError(ValueError):
    pass


def parse_schedule(raw: str) -> list[time] | None:
    """'08:00,20:00' -> [08:00, 20:00] (sorted, unique); 'as_needed' -> None."""
    text = raw.strip().lower()
    if text == AS_NEEDED:
        return None
    parts = [p.strip() for p in text.split(",") if p.strip()]
    if not parts:
        raise ScheduleError("Add at least one dose time, or choose 'as needed'.")
    times = set()
    for p in parts:
        m = _TIME.match(p)
        if not m:
            raise ScheduleError(f"'{p}' is not a time like 08:00.")
        times.add(time(int(m.group(1)), int(m.group(2))))
    if len(times) > 8:
        raise ScheduleError("At most 8 dose times per day.")
    return sorted(times)


def format_schedule(times: list[time] | None) -> str:
    return AS_NEEDED if times is None else ",".join(t.strftime("%H:%M") for t in times)


def dose_moment(day: datetime, at: time) -> datetime:
    """The UTC instant of a local (MYT) dose time on `day`'s Malaysian date."""
    local_day = day.astimezone(MYT).date()
    return datetime.combine(local_day, at, tzinfo=MYT).astimezone(UTC)


def dose_id(medication_id: str, scheduled: datetime) -> str:
    """One dose_log per medication and dose time (no duplicates on retry)."""
    return f"{medication_id}_{scheduled.astimezone(MYT).strftime('%Y%m%d%H%M')}"


def adherence_rate(statuses: list[str]) -> float | None:
    """Algorithm C: taken / all logged doses x 100; None with no history (UC5.5 E1)."""
    if not statuses:
        return None
    taken = sum(1 for s in statuses if s == DoseStatus.TAKEN.value)
    return round(taken / len(statuses) * 100, 1)


def days_of_supply(quantity: float | None, times: list[time] | None) -> float | None:
    """Remaining supply in days; None when stock isn't tracked or the medicine is as-needed."""
    if quantity is None or times is None or not times:
        return None
    return quantity / len(times)


def below_threshold(quantity: float | None, times: list[time] | None, threshold: float) -> bool:
    days = days_of_supply(quantity, times)
    return days is not None and days < threshold


def due_missed(
    times: list[time],
    created: datetime,
    now: datetime,
    logged: set[str],
    medication_id: str,
) -> list[datetime]:
    """Scheduled doses (today and yesterday, MYT) whose window has passed with no log,
    only after the medicine was added (D-43)."""
    out = []
    for back in (1, 0):
        day = now - timedelta(days=back)
        for at in times:
            moment = dose_moment(day, at)
            if moment < created or moment + MISSED_WINDOW > now:
                continue
            if dose_id(medication_id, moment) not in logged:
                out.append(moment)
    return out


def due_now(times: list[time], now: datetime, window: timedelta) -> list[datetime]:
    """Dose times that fell in the last `window` (backup reminder slot)."""
    return [m for at in times if (m := dose_moment(now, at)) <= now and now - m < window]


# ---------------- repository ----------------


@dataclass(frozen=True)
class MedicationDoc:
    id: str
    data: dict[str, Any]


class MedicationRepository(Protocol):
    def list_for(self, patient_id: str) -> list[MedicationDoc]: ...

    def get(self, medication_id: str) -> MedicationDoc | None: ...

    def create(self, data: dict[str, Any]) -> str: ...

    def update(self, medication_id: str, data: dict[str, Any]) -> None: ...

    def delete(self, medication_id: str) -> None: ...

    def all_scheduled(self) -> list[MedicationDoc]:
        """Every medication with dose times (for the 15-minute job)."""
        ...

    def log_dose(self, log_id: str, data: dict[str, Any]) -> bool:
        """Create the dose_log if absent; True when it was created."""
        ...

    def recent_statuses(self, medication_id: str, since: datetime) -> list[str]: ...

    def logged_ids(self, medication_id: str, since: datetime) -> set[str]: ...


class FirestoreMedicationRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _meds(self) -> Any:
        return self._db.collection(Collection.MEDICATIONS.value)

    def _logs(self) -> Any:
        return self._db.collection(Collection.DOSE_LOGS.value)

    def list_for(self, patient_id: str) -> list[MedicationDoc]:
        q = self._meds().where(filter=firestore.FieldFilter("patientId", "==", patient_id))
        return [MedicationDoc(d.id, dict(d.to_dict())) for d in q.stream()]

    def get(self, medication_id: str) -> MedicationDoc | None:
        snap = self._meds().document(medication_id).get()
        return MedicationDoc(snap.id, dict(snap.to_dict())) if snap.exists else None

    def create(self, data: dict[str, Any]) -> str:
        _, ref = self._meds().add(
            {
                **data,
                "createdAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }
        )
        return str(ref.id)

    def update(self, medication_id: str, data: dict[str, Any]) -> None:
        self._meds().document(medication_id).update(
            {**data, "updatedAt": firestore.SERVER_TIMESTAMP}
        )

    def delete(self, medication_id: str) -> None:
        self._meds().document(medication_id).delete()

    def all_scheduled(self) -> list[MedicationDoc]:
        q = self._meds().where(filter=firestore.FieldFilter("schedule", "!=", AS_NEEDED))
        return [MedicationDoc(d.id, dict(d.to_dict())) for d in q.stream()]

    def log_dose(self, log_id: str, data: dict[str, Any]) -> bool:
        try:
            self._logs().document(log_id).create(data)
        except Exception as exc:  # AlreadyExists: confirmed or logged before
            if "already exists" in str(exc).lower() or type(exc).__name__ == "AlreadyExists":
                return False
            raise
        return True

    def recent_statuses(self, medication_id: str, since: datetime) -> list[str]:
        q = (
            self._logs()
            .where(filter=firestore.FieldFilter("medicationId", "==", medication_id))
            .where(filter=firestore.FieldFilter("scheduledTime", ">=", since))
        )
        return [str(d.get("status")) for d in q.stream()]

    def logged_ids(self, medication_id: str, since: datetime) -> set[str]:
        q = (
            self._logs()
            .where(filter=firestore.FieldFilter("medicationId", "==", medication_id))
            .where(filter=firestore.FieldFilter("scheduledTime", ">=", since))
        )
        return {d.id for d in q.stream()}


def get_medication_repository() -> MedicationRepository:
    return FirestoreMedicationRepository(get_firestore())


def refresh_adherence(
    repo: MedicationRepository, medication_id: str, now: datetime
) -> float | None:
    """Algorithm C step 3: recompute and store after every dose_log write."""
    rate = adherence_rate(repo.recent_statuses(medication_id, now - ADHERENCE_WINDOW))
    repo.update(medication_id, {"adherenceRate": rate})
    return rate
