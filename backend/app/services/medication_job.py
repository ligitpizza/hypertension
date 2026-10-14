"""Every-15-minute medication sweep (UC5.3 backup reminder, UC5.4 missed dose; D-43).

Runs inside the existing `escalation` Cloud Scheduler call (no new paid job):
  - a scheduled dose not confirmed within MISSED_WINDOW becomes a `missed` dose_log and the
    medication's adherence rate is recomputed (algorithm C);
  - a dose that fell due in the last SWEEP_INTERVAL and is not yet taken gets a backup push
    (the phone also shows an exact-time local reminder);
  - D-49: a patient whose scheduled medicines show an adherence concern gets a
    `low_adherence` doctor alert (at most one per 7 days).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import Depends

from app.core.enums import ClinicalAlertType, DoseStatus, RiskLevel
from app.integrations.push import PushMessage
from app.services.escalation import (
    AlertRepository,
    DoctorAlert,
    EscalationPlan,
    Escalator,
    get_alert_repository,
    get_escalator,
)
from app.services.medications import (
    CONCERN_WINDOW,
    MedicationDoc,
    MedicationRepository,
    adherence_concern,
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
    alerts: AlertRepository | None = None
    escalator: Escalator | None = None

    def run(self, now: datetime | None = None) -> dict[str, Any]:
        now = now or datetime.now(UTC)
        missed = reminded = 0
        meds = self.repo.all_scheduled()
        newly_missed: set[str] = set()
        for med in meds:
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
                newly_missed.add(str(med.data.get("patientId")))
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
        raised = self._adherence_alerts(meds, newly_missed, now)
        return {
            "missedDosesLogged": missed,
            "remindersSent": reminded,
            "adherenceAlerts": raised,
        }

    def _adherence_alerts(
        self, meds: list[MedicationDoc], patients: set[str], now: datetime
    ) -> int:
        """D-49: only patients with a newly missed dose are checked."""
        if self.alerts is None or self.escalator is None:
            return 0
        raised = 0
        for patient_id in sorted(patients):
            concerns = []
            for med in meds:
                if med.data.get("patientId") != patient_id:
                    continue
                why = adherence_concern(self.repo.recent_logs(med.id, now - CONCERN_WINDOW))
                if why:
                    concerns.append(
                        f"{med.data.get('name')} {med.data.get('dosage', '')}".strip() + f": {why}"
                    )
            if not concerns:
                continue
            plan = EscalationPlan(
                doctor_alerts=[
                    DoctorAlert(
                        ClinicalAlertType.LOW_ADHERENCE,
                        RiskLevel.MODERATE,
                        "Low medication adherence. " + "; ".join(concerns) + ".",
                        dedupe=CONCERN_WINDOW,
                    )
                ]
            )
            user = self.alerts.user(patient_id) or {}
            if self.escalator.apply(plan, patient_id, user.get("assignedDoctorId"), now):
                raised += 1
        return raised


def get_medication_job(
    repo: MedicationRepository = Depends(get_medication_repository),
    notifier: Notifier = Depends(get_notifier),
    alerts: AlertRepository = Depends(get_alert_repository),
    escalator: Escalator = Depends(get_escalator),
) -> MedicationJob:
    return MedicationJob(repo, notifier, alerts, escalator)
