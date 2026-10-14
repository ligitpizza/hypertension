"""Module 7 appointment scheduling (FR-7.1-7.5; UC7.1-UC7.5; D-53).

Pure slot rules are unit-tested; the repository wraps Firestore. Times are Malaysia time
(UTC+8). Appointments are always with the patient's assigned (personal) doctor.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Any, Protocol

from firebase_admin import firestore as gfs

from app.core.enums import AppointmentStatus, Collection
from app.core.firebase import get_firestore
from app.services.medications import MYT

# ---- D-53 clinic hours (one place to change them) ----
SLOT = timedelta(minutes=30)
DAY_START = time(9, 0)
DAY_END = time(21, 0)
LUNCH = (time(13, 0), time(14, 0))
WORKING_DAYS = {0, 1, 2, 3, 4}  # Mon-Fri
MIN_LEAD = timedelta(hours=1)
MAX_AHEAD = timedelta(days=60)
LATE_CHANGE = timedelta(hours=24)  # UC7.2 E1 warning
REMINDERS = (timedelta(hours=24), timedelta(hours=1))  # UC7.4
SUMMARY_DAYS = 14  # UC7.5 recent vitals window
ACTIVE = (AppointmentStatus.BOOKED.value, AppointmentStatus.RESCHEDULED.value)


def day_slots(day: date) -> list[datetime]:
    """Every slot start on a Malaysian date, as UTC instants (empty on non-working days)."""
    if day.weekday() not in WORKING_DAYS:
        return []
    out = []
    t = datetime.combine(day, DAY_START, tzinfo=MYT)
    end = datetime.combine(day, DAY_END, tzinfo=MYT)
    while t + SLOT <= end:
        if not (LUNCH[0] <= t.time() < LUNCH[1]):
            out.append(t.astimezone(UTC))
        t += SLOT
    return out


def is_bookable(moment: datetime, now: datetime) -> bool:
    """A real slot start, at least MIN_LEAD ahead and at most MAX_AHEAD."""
    local = moment.astimezone(MYT)
    return (
        moment.astimezone(UTC) in day_slots(local.date())
        and now + MIN_LEAD <= moment <= now + MAX_AHEAD
    )


def free_slots(day: date, taken: set[datetime], now: datetime) -> list[datetime]:
    return [s for s in day_slots(day) if s not in taken and is_bookable(s, now)]


def next_free(taken: set[datetime], now: datetime, limit: int = 3) -> list[datetime]:
    """UC7.1 E1 / emergency auto-book: the nearest free slots from now."""
    out: list[datetime] = []
    day = now.astimezone(MYT).date()
    last = (now + MAX_AHEAD).astimezone(MYT).date()
    while day <= last and len(out) < limit:
        out += free_slots(day, taken, now)[: limit - len(out)]
        day += timedelta(days=1)
    return out


def period(moment: datetime) -> str:
    """Morning / Afternoon / Evening tab (Fig 4.3.6.1)."""
    h = moment.astimezone(MYT).hour
    return "morning" if h < 12 else "afternoon" if h < 17 else "evening"


# ---------------- repository ----------------


@dataclass(frozen=True)
class AppointmentDoc:
    id: str
    data: dict[str, Any]


class SlotTakenError(Exception):
    pass


class AppointmentRepository(Protocol):
    def user(self, uid: str) -> dict[str, Any] | None: ...

    def get(self, appointment_id: str) -> AppointmentDoc | None: ...

    def taken(self, doctor_id: str, start: datetime, end: datetime) -> set[datetime]:
        """Active appointment times of a doctor in [start, end)."""
        ...

    def book(self, data: dict[str, Any], exclude_id: str | None = None) -> str:
        """Create (or, with exclude_id, move) atomically; SlotTakenError if the doctor is
        already booked then. Returns the appointment id."""
        ...

    def update(self, appointment_id: str, data: dict[str, Any]) -> None: ...

    def upcoming_for_patient(self, patient_id: str, now: datetime) -> list[AppointmentDoc]: ...

    def active_between(self, start: datetime, end: datetime) -> list[AppointmentDoc]:
        """All active appointments starting in [start, end) (reminders, completion)."""
        ...


class FirestoreAppointmentRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _col(self) -> Any:
        return self._db.collection(Collection.APPOINTMENTS.value)

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def get(self, appointment_id: str) -> AppointmentDoc | None:
        snap = self._col().document(appointment_id).get()
        return AppointmentDoc(snap.id, dict(snap.to_dict())) if snap.exists else None

    def _doctor_query(self, doctor_id: str, start: datetime, end: datetime) -> Any:
        # Uses the (doctorId, dateTime) index; status is filtered in code.
        return (
            self._col()
            .where(filter=gfs.FieldFilter("doctorId", "==", doctor_id))
            .where(filter=gfs.FieldFilter("dateTime", ">=", start))
            .where(filter=gfs.FieldFilter("dateTime", "<", end))
        )

    def taken(self, doctor_id: str, start: datetime, end: datetime) -> set[datetime]:
        return {
            d.get("dateTime")
            for d in self._doctor_query(doctor_id, start, end).stream()
            if d.get("status") in ACTIVE
        }

    def book(self, data: dict[str, Any], exclude_id: str | None = None) -> str:
        moment: datetime = data["dateTime"]
        query = self._doctor_query(data["doctorId"], moment, moment + SLOT)
        ref = self._col().document(exclude_id) if exclude_id else self._col().document()

        @gfs.transactional  # type: ignore[untyped-decorator]
        def run(tx: Any) -> None:
            for d in query.stream(transaction=tx):
                if d.id != exclude_id and d.get("status") in ACTIVE:
                    raise SlotTakenError
            if exclude_id:
                tx.update(ref, {**data, "updatedAt": gfs.SERVER_TIMESTAMP})
            else:
                tx.set(ref, {**data, "createdAt": gfs.SERVER_TIMESTAMP})

        run(self._db.transaction())
        return str(ref.id)

    def update(self, appointment_id: str, data: dict[str, Any]) -> None:
        self._col().document(appointment_id).update({**data, "updatedAt": gfs.SERVER_TIMESTAMP})

    def upcoming_for_patient(self, patient_id: str, now: datetime) -> list[AppointmentDoc]:
        q = (
            self._col()
            .where(filter=gfs.FieldFilter("patientId", "==", patient_id))
            .where(filter=gfs.FieldFilter("dateTime", ">=", now))
            .order_by("dateTime")
        )
        return [
            AppointmentDoc(d.id, dict(d.to_dict())) for d in q.stream() if d.get("status") in ACTIVE
        ]

    def active_between(self, start: datetime, end: datetime) -> list[AppointmentDoc]:
        q = (
            self._col()
            .where(filter=gfs.FieldFilter("dateTime", ">=", start))
            .where(filter=gfs.FieldFilter("dateTime", "<", end))
        )
        return [
            AppointmentDoc(d.id, dict(d.to_dict())) for d in q.stream() if d.get("status") in ACTIVE
        ]


def get_appointment_repository() -> AppointmentRepository:
    return FirestoreAppointmentRepository(get_firestore())
