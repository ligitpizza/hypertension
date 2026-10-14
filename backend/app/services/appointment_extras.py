"""Module 7: pre-visit summary (UC7.5), emergency auto-booking (docs/06 §E) and the
reminder / completion sweep (UC7.4) run inside the existing 15-minute job (D-53)."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import Depends

from app.core.enums import AppointmentStatus, AppointmentType
from app.integrations.email import EmailClient, EmailMessage, get_email_client
from app.integrations.push import PushMessage
from app.services.appointments import (
    MAX_AHEAD,
    REMINDERS,
    AppointmentDoc,
    AppointmentRepository,
    SlotTakenError,
    get_appointment_repository,
    next_free,
)
from app.services.medications import MYT
from app.services.notifications import Notifier, get_notifier

log = logging.getLogger("careflow.appointments")

SWEEP = timedelta(minutes=15)
STALE_READINGS = timedelta(days=7)


def when_text(moment: datetime) -> str:
    """'Thu 16 Oct, 10:00 AM' in Malaysia time."""
    local = moment.astimezone(MYT)
    hour = local.hour % 12 or 12
    return (
        f"{local:%a} {local.day} {local:%b}, {hour}:{local:%M} {'AM' if local.hour < 12 else 'PM'}"
    )


# ---------------- UC7.5 pre-visit summary ----------------


def build_pre_visit_summary(
    appointment: dict[str, Any],
    readings_newest_first: list[dict[str, Any]],
    risk: dict[str, Any] | None,
    medications: list[dict[str, Any]],
    care_plan: dict[str, Any] | None,
    now: datetime,
) -> dict[str, Any]:
    """Recent vitals, risk and medicines for the visit, with data gaps flagged (E1)."""
    gaps: list[str] = []
    vitals: dict[str, Any] | None = None
    if readings_newest_first:
        sys = [int(r["systolic"]) for r in readings_newest_first]
        dia = [int(r["diastolic"]) for r in readings_newest_first]
        hrs = [int(r["heartRate"]) for r in readings_newest_first if r.get("heartRate")]
        latest = readings_newest_first[0]
        vitals = {
            "count": len(sys),
            "averageSystolic": round(sum(sys) / len(sys)),
            "averageDiastolic": round(sum(dia) / len(dia)),
            "highest": f"{max(sys)}/{dia[sys.index(max(sys))]}",
            "latest": f"{latest['systolic']}/{latest['diastolic']}",
            "latestAt": latest.get("timestamp"),
            "averageHeartRate": round(sum(hrs) / len(hrs)) if hrs else None,
        }
        last = latest.get("timestamp")
        if isinstance(last, datetime) and now - last > STALE_READINGS:
            gaps.append("No blood pressure reading in the last 7 days.")
        if not hrs:
            gaps.append("No heart rate recorded recently.")
    else:
        gaps.append("No blood pressure readings in the last 14 days.")
    if risk is None:
        gaps.append("No risk assessment yet (needs three readings).")
    if not medications:
        gaps.append("No medicines recorded by the patient.")
    meds: list[dict[str, Any]] = []
    low: list[str] = []
    for m in medications:
        name = f"{m.get('name', '')} {m.get('dosage', '')}".strip()
        rate = m.get("adherenceRate")
        meds.append({"name": name, "schedule": m.get("schedule"), "adherenceRate": rate})
        if isinstance(rate, int | float) and rate < 80:
            low.append(name)
    open_items = [f"Low adherence: {', '.join(low)}"] if low else []
    return {
        "appointmentId": appointment.get("id"),
        "dateTime": appointment.get("dateTime"),
        "type": appointment.get("type"),
        "vitals": vitals,
        "risk": (
            {
                "overallLevel": risk.get("overallLevel"),
                "scores": risk.get("scores"),
                "generatedAt": risk.get("generatedAt"),
            }
            if risk
            else None
        ),
        "medications": meds,
        "carePlan": care_plan.get("content") if care_plan else None,
        "openItems": open_items,
        "dataGaps": gaps,
        "generatedAt": now,
    }


# ---------------- emergency auto-booking ----------------


def auto_book_emergency(
    repo: AppointmentRepository,
    notifier: Notifier,
    patient_id: str,
    doctor_id: str | None,
    now: datetime,
) -> str | None:
    """docs/06 Emergency band: book the next free slot with the patient's own doctor
    (D-53: no reassignment). Skipped if an emergency visit is already booked."""
    if not doctor_id:
        return None
    if any(
        a.data.get("type") == AppointmentType.EMERGENCY.value
        for a in repo.upcoming_for_patient(patient_id, now)
    ):
        return None
    taken = repo.taken(doctor_id, now, now + MAX_AHEAD)
    for slot in next_free(taken, now, limit=3):
        try:
            appt_id = repo.book(
                {
                    "patientId": patient_id,
                    "doctorId": doctor_id,
                    "dateTime": slot,
                    "status": AppointmentStatus.BOOKED.value,
                    "type": AppointmentType.EMERGENCY.value,
                }
            )
        except SlotTakenError:
            continue
        text = f"Emergency appointment booked for {when_text(slot)}."
        notifier.notify(
            patient_id,
            PushMessage(
                "Emergency appointment booked",
                f"{text} If you feel unwell now, call 999.",
                {"type": "appointment", "appointmentId": appt_id},
                urgent=True,
            ),
        )
        notifier.notify(
            doctor_id,
            PushMessage(
                "Emergency appointment",
                f"{text} Booked automatically after a very high reading.",
                {"type": "appointment", "appointmentId": appt_id, "patientId": patient_id},
                urgent=True,
            ),
        )
        return appt_id
    log.warning("No free slot for an emergency appointment for %s", patient_id)
    return None


# ---------------- UC7.4 reminders + completion ----------------


@dataclass
class AppointmentJob:
    repo: AppointmentRepository
    notifier: Notifier
    email: EmailClient

    def run(self, now: datetime | None = None) -> dict[str, Any]:
        now = now or datetime.now(UTC)
        sent = 0
        for offset in REMINDERS:
            # Each run covers the next 15-minute window, so every appointment is
            # reminded once per offset without storing anything.
            for a in self.repo.active_between(now + offset, now + offset + SWEEP):
                self._remind(a, offset)
                sent += 1
        done = 0
        for a in self.repo.active_between(now - timedelta(days=7), now - timedelta(hours=1)):
            self.repo.update(a.id, {"status": AppointmentStatus.COMPLETED.value})
            done += 1
        return {"appointmentReminders": sent, "appointmentsCompleted": done}

    def _remind(self, a: AppointmentDoc, offset: timedelta) -> None:
        patient_id = str(a.data.get("patientId"))
        doctor = self.repo.user(str(a.data.get("doctorId") or "")) or {}
        doctor_name = str(doctor.get("name") or "your doctor")
        when = when_text(a.data["dateTime"])
        lead = "tomorrow" if offset >= timedelta(hours=12) else "in 1 hour"
        self.notifier.notify(
            patient_id,
            PushMessage(
                f"Appointment {lead}",
                f"With {doctor_name}, {when}.",
                {"type": "appointment", "appointmentId": a.id},
            ),
        )
        patient = self.repo.user(patient_id) or {}
        address = patient.get("email")
        if address:
            text = (
                f"Hello {patient.get('name', '')},\n\nThis is a reminder of your appointment "
                f"with {doctor_name} on {when} (Malaysia time).\n\nYou can reschedule or "
                "cancel it in the CareFlow app.\n"
            )
            try:
                self.email.send(
                    EmailMessage(
                        to_email=str(address),
                        to_name=str(patient.get("name") or ""),
                        subject=f"CareFlow: appointment {lead}",
                        text=text,
                        html=text.replace("\n", "<br>"),
                    )
                )
            except Exception:
                log.exception("Reminder email for appointment %s failed", a.id)


def get_appointment_job(
    repo: AppointmentRepository = Depends(get_appointment_repository),
    notifier: Notifier = Depends(get_notifier),
    email: EmailClient = Depends(get_email_client),
) -> AppointmentJob:
    return AppointmentJob(repo, notifier, email)
