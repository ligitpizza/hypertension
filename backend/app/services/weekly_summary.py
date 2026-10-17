"""D-76: weekly health summary from the Harvey Assistant.

Every Monday the daily scheduler job (no extra Cloud Scheduler job) posts each active
patient's last 7 days into their Harvey Assistant chat (`agent_messages`, kind
"weekly_summary"): readings and average BP, medicine adherence and the change in risk.
A fixed template, not Gemini, so it costs nothing and never invents numbers. The patient
app also asks for one when the inbox opens, so a new patient doesn't wait for Monday.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import Depends

from app.core.enums import RiskLevel
from app.integrations.push import PushMessage
from app.services.agent_context import MYT, AgentDataRepository, get_agent_data_repository
from app.services.bp import classify
from app.services.deterioration import DeteriorationRepository, get_deterioration_repository
from app.services.notifications import Notifier, get_notifier

KIND = "weekly_summary"
WEEK = timedelta(days=7)
# Monday (MYT) is summary day for the scheduled run.
SUMMARY_WEEKDAY = 0
_LEVELS = [r.value for r in RiskLevel]


def _overall(risk: dict[str, Any] | None) -> str | None:
    scores = (risk or {}).get("scores") or {}
    levels = [str(s.get("level")) for s in scores.values() if s.get("level") in _LEVELS]
    return max(levels, key=_LEVELS.index) if levels else None


def summary_text(repo: AgentDataRepository, uid: str, now: datetime) -> str:
    start = now - WEEK
    span = f"{start.astimezone(MYT):%d %b} to {now.astimezone(MYT):%d %b}"
    lines = [f"Your weekly health summary ({span})"]

    readings = repo.readings_since(uid, start)
    if readings:
        sys_avg = round(sum(int(r["systolic"]) for r in readings) / len(readings))
        dia_avg = round(sum(int(r["diastolic"]) for r in readings) / len(readings))
        highest = max(readings, key=lambda r: (int(r["systolic"]), int(r["diastolic"])))
        lines.append(
            f"- Blood pressure: {len(readings)} reading{'s' if len(readings) != 1 else ''}, "
            f"average {sys_avg}/{dia_avg} mmHg ({classify(sys_avg, dia_avg).value}). "
            f"Highest {highest['systolic']}/{highest['diastolic']} mmHg."
        )
    else:
        lines.append("- Blood pressure: no readings this week. Try to log at least 3 a week.")

    rates = [
        float(m["adherenceRate"])
        for m in repo.medications(uid)
        if m.get("adherenceRate") is not None
    ]
    if rates:
        lines.append(f"- Medicines: {round(sum(rates) / len(rates))}% of doses taken.")
    else:
        lines.append("- Medicines: no doses logged yet.")

    now_level = _overall(repo.latest_risk(uid))
    before_level = _overall(repo.risk_before(uid, start))
    if now_level is None:
        lines.append("- Risk: not assessed yet (it needs three readings).")
    elif before_level is None or before_level == now_level:
        lines.append(f"- Risk: {now_level}{' (no change)' if before_level else ''}.")
    else:
        direction = "up" if _LEVELS.index(now_level) > _LEVELS.index(before_level) else "down"
        lines.append(f"- Risk: {now_level}, {direction} from {before_level} last week.")

    if now_level in (RiskLevel.HIGH.value, RiskLevel.CRITICAL.value):
        lines.append("Please book a check-up with your doctor soon.")
    else:
        lines.append("Keep logging your readings and taking your medicines as prescribed.")
    lines.append("This is a summary of your own records, not medical advice.")
    return "\n".join(lines)


def ensure_summary(repo: AgentDataRepository, uid: str, now: datetime) -> bool:
    """Posts a summary unless one was posted in the last 7 days; True when posted."""
    last = repo.latest_of_kind(uid, KIND)
    if last is not None and now - last < WEEK - timedelta(hours=1):
        return False
    repo.add_message(uid, "agent", summary_text(repo, uid, now), {"kind": KIND})
    return True


@dataclass
class WeeklySummaryJob:
    repo: AgentDataRepository
    patients: DeteriorationRepository
    notifier: Notifier

    def run(self, now: datetime | None = None, force: bool = False) -> dict[str, Any]:
        now = now or datetime.now(UTC)
        if not force and now.astimezone(MYT).weekday() != SUMMARY_WEEKDAY:
            return {"weeklySummaries": 0}
        posted = 0
        for uid, _ in self.patients.active_patients():
            if ensure_summary(self.repo, uid, now):
                posted += 1
                self.notifier.notify(
                    uid,
                    PushMessage(
                        "Your weekly health summary",
                        "See how your blood pressure went this week.",
                        {"type": "weekly_summary"},
                    ),
                )
        return {"weeklySummaries": posted}


def get_weekly_summary_job(
    repo: AgentDataRepository = Depends(get_agent_data_repository),
    patients: DeteriorationRepository = Depends(get_deterioration_repository),
    notifier: Notifier = Depends(get_notifier),
) -> WeeklySummaryJob:
    return WeeklySummaryJob(repo, patients, notifier)
