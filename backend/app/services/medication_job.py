"""Every-15-minute medication sweep (UC5.3 backup reminder, UC5.4 missed dose; D-43).

Runs inside the existing `escalation` Cloud Scheduler call (no new paid job):
  - a scheduled dose not confirmed within MISSED_WINDOW becomes a `missed` dose_log and the
    medication's adherence rate is recomputed (algorithm C);
  - a dose that fell due in the last SWEEP_INTERVAL and is not yet taken gets a backup push
    (the phone also shows an exact-time local reminder).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import Depends

from app.core.enums import DoseStatus
from app.integrations.push import PushMessage
from app.services.medications import (
    MedicationRepository,
    dose_id,
    due_missed,
    due_now,
    get_medication_repository,
    parse_schedule,
    refresh_adherence,
)
from app.services.notifications import Notifier, get_notifier

SWEEP_INTERVAL = timedelta(minutes=15)


@dataclass
class MedicationJob:
    repo: MedicationRepository
    notifier: Notifier

    def run(self, now: datetime | None = None) -> dict[str, Any]:
        now = now or datetime.now(UTC)
        missed = reminded = 0
        for med in self.repo.all_scheduled():
            try:
                times = parse_schedule(str(med.data.get("schedule", "")))
            except ValueError:
                continue
            if not times:
                continue
            created = med.data.get("createdAt")
            if not isinstance(created, datetime):
                continue
            logged = self.repo.logged_ids(med.id, now - timedelta(days=2))
            wrote = False
            for slot in due_missed(times, created, now, logged, med.id):
                if self.repo.log_dose(
                    dose_id(med.id, slot),
                    {
                        "medicationId": med.id,
                        "scheduledTime": slot,
                        "status": DoseStatus.MISSED.value,
                    },
                ):
                    missed += 1
                    wrote = True
            if wrote:
                refresh_adherence(self.repo, med.id, now)
            for slot in due_now(times, now, SWEEP_INTERVAL):
                if slot >= created and dose_id(med.id, slot) not in logged:
                    self.notifier.notify(
                        str(med.data.get("patientId")),
                        PushMessage(
                            f"Time to take {med.data.get('name')}",
                            f"{med.data.get('dosage', '')} — tap to confirm you have taken it.",
                            {"type": "dose", "medicationId": med.id},
                        ),
                    )
                    reminded += 1
        return {"missedDosesLogged": missed, "remindersSent": reminded}


def get_medication_job(
    repo: MedicationRepository = Depends(get_medication_repository),
    notifier: Notifier = Depends(get_notifier),
) -> MedicationJob:
    return MedicationJob(repo, notifier)
