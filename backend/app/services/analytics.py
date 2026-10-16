"""Hospital and system analytics, and the hospital-wide PDF report (FR-11.3, FR-11.4,
UC11.5; Figs 4.3.14.5-4.3.14.6; D-59).

Everything is computed on request from single-field range queries (no extra
collections or indexes); the clinic is small enough for that.
"""

from collections import Counter
from collections.abc import Iterable
from datetime import UTC, date, datetime, timedelta
from itertools import pairwise
from typing import Any, Protocol

from google.cloud import firestore as gfs

from app.core.enums import Collection, RiskLevel, UserRole
from app.core.firebase import get_firestore
from app.services.appointments import CHANGE_REASONS

MYT = timedelta(hours=8)
LEVELS = [lvl.value for lvl in RiskLevel]  # ascending: low, moderate, high, critical
CLINICIANS = (UserRole.DOCTOR.value, UserRole.PHARMACIST.value)


class AnalyticsSource(Protocol):
    def users(self) -> list[tuple[str, dict[str, Any]]]: ...

    def in_range(
        self, collection: Collection, field: str, start: datetime, end: datetime
    ) -> list[dict[str, Any]]:
        """Documents with start <= field < end."""
        ...

    def where_equal(
        self, collection: Collection, field: str, value: Any
    ) -> list[dict[str, Any]]: ...


class FirestoreAnalyticsSource:
    def __init__(self, db: Any) -> None:
        self._db = db

    def users(self) -> list[tuple[str, dict[str, Any]]]:
        return [(d.id, dict(d.to_dict())) for d in self._db.collection("users").stream()]

    def in_range(
        self, collection: Collection, field: str, start: datetime, end: datetime
    ) -> list[dict[str, Any]]:
        q = (
            self._db.collection(collection.value)
            .where(filter=gfs.FieldFilter(field, ">=", start))
            .where(filter=gfs.FieldFilter(field, "<", end))
        )
        return [dict(d.to_dict()) for d in q.stream()]

    def where_equal(self, collection: Collection, field: str, value: Any) -> list[dict[str, Any]]:
        q = self._db.collection(collection.value).where(filter=gfs.FieldFilter(field, "==", value))
        return [dict(d.to_dict()) for d in q.stream()]


def get_analytics_source() -> AnalyticsSource:
    return FirestoreAnalyticsSource(get_firestore())


# ---------------- helpers ----------------


def overall_level(score: dict[str, Any]) -> str | None:
    """D-03: the highest complication level."""
    levels = [
        str(v.get("level"))
        for v in (score.get("scores") or {}).values()
        if isinstance(v, dict) and v.get("level") in LEVELS
    ]
    return max(levels, key=LEVELS.index) if levels else None


def _myt_day(t: datetime) -> date:
    return (t.astimezone(UTC) + MYT).date()


def _month_key(t: datetime) -> str:
    d = _myt_day(t)
    return f"{d.year}-{d.month:02d}"


def _month_starts(now: datetime, months: int) -> list[datetime]:
    """UTC instants of Malaysian month starts, oldest first, ending with the current one."""
    d = _myt_day(now).replace(day=1)
    out = []
    for _ in range(months):
        out.append(datetime(d.year, d.month, 1, tzinfo=UTC) - MYT)
        d = (d - timedelta(days=1)).replace(day=1)
    return list(reversed(out))


def _next_month(start: datetime) -> datetime:
    d = _myt_day(start + timedelta(hours=1))
    d = (d.replace(day=28) + timedelta(days=4)).replace(day=1)
    return datetime(d.year, d.month, 1, tzinfo=UTC) - MYT


def _latest_per_patient(scores: Iterable[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    for s in scores:
        pid, at = s.get("patientId"), s.get("generatedAt")
        if not pid or not isinstance(at, datetime):
            continue
        if pid not in latest or at > latest[pid]["generatedAt"]:
            latest[pid] = s
    return latest


def _distribution(latest: Iterable[dict[str, Any]]) -> dict[str, int]:
    counts = Counter(overall_level(s) for s in latest)
    return {lvl: counts.get(lvl, 0) for lvl in LEVELS}


def _active_patients(users: list[tuple[str, dict[str, Any]]]) -> set[str]:
    return {
        uid
        for uid, u in users
        if u.get("role") == UserRole.PATIENT.value and u.get("isActive") is not False
    }


def _adherence(logs: Iterable[dict[str, Any]]) -> float | None:
    statuses = [d.get("status") for d in logs if d.get("status") in ("taken", "missed")]
    return round(statuses.count("taken") / len(statuses) * 100, 1) if statuses else None


# ---------------- hospital analytics (Fig 4.3.14.5) ----------------


def delivery_stats(orders: list[dict[str, Any]]) -> dict[str, Any]:
    """D-72: medication orders by stage and method, paid revenue and courier fees."""
    stages = Counter(str(o.get("fulfilmentStatus")) for o in orders)
    home = [o for o in orders if o.get("method") == "home_delivery"]
    paid = [o for o in orders if o.get("paymentStatus") == "paid"]
    fees = [float(o.get("deliveryFee") or 0) for o in home if o.get("deliveryFee")]
    revenue = sum(float(o.get("amount") or 0) + float(o.get("deliveryFee") or 0) for o in paid)
    return {
        "orders": len(orders),
        "homeDelivery": len(home),
        "selfCollection": sum(1 for o in orders if o.get("method") == "self_collection"),
        "paid": len(paid),
        "delivered": stages.get("delivered", 0),
        "collected": stages.get("collected", 0),
        "inProgress": sum(
            stages.get(s, 0)
            for s in ("preparing", "ready_for_collection", "ready_for_delivery", "out_of_stock")
        ),
        "failed": stages.get("failed", 0),
        "outOfStock": stages.get("out_of_stock", 0),
        "awaitingPatient": sum(
            stages.get(s, 0) for s in ("awaiting_confirmation", "awaiting_payment")
        ),
        "revenue": round(revenue, 2),
        "averageCourierFee": round(sum(fees) / len(fees), 2) if fees else None,
    }


def hospital(src: AnalyticsSource, now: datetime, months: int = 6) -> dict[str, Any]:
    users = src.users()
    active = _active_patients(users)
    starts = _month_starts(now, months)
    edges = [*starts, _next_month(starts[-1])]
    year_ago = now - timedelta(days=365)
    soon = now + timedelta(seconds=1)

    # Current distribution: each active patient's latest score (in the last year).
    scores = src.in_range(Collection.RISK_SCORES, "generatedAt", year_ago, soon)
    latest = [s for pid, s in _latest_per_patient(scores).items() if pid in active]
    distribution = _distribution(latest)

    # Monthly trend (ML follow-up, D-59): each patient's last score in that month.
    trend = []
    for start, end in pairwise(edges):
        month_scores = [s for s in scores if start <= s.get("generatedAt", start) < end]
        trend.append(
            {
                "month": _month_key(start + MYT),
                **_distribution(_latest_per_patient(month_scores).values()),
            }
        )

    appts = src.in_range(Collection.APPOINTMENTS, "dateTime", edges[0], edges[-1])
    consultations = []
    for start, end in pairwise(edges):
        in_month = [a for a in appts if start <= a["dateTime"] < end]
        by_status = Counter(a.get("status") for a in in_month)
        consultations.append(
            {
                "month": _month_key(start + MYT),
                "completed": by_status.get("completed", 0),
                "noShow": by_status.get("no_show", 0),
                "cancelled": by_status.get("cancelled", 0),
                "upcoming": by_status.get("booked", 0) + by_status.get("rescheduled", 0),
            }
        )

    since = now - timedelta(days=30)
    logs = src.in_range(Collection.DOSE_LOGS, "scheduledTime", since, now)
    daily: dict[date, list[dict[str, Any]]] = {}
    for d in logs:
        daily.setdefault(_myt_day(d["scheduledTime"]), []).append(d)
    adherence_days = [
        {"date": day.isoformat(), "rate": _adherence(daily[day])} for day in sorted(daily)
    ]

    return {
        "generatedAt": now.isoformat(),
        "activePatients": len(active),
        "risk": {"scored": len(latest), "counts": distribution},
        "riskTrend": trend,
        "consultations": consultations,
        "adherence": {"current": _adherence(logs), "daily": adherence_days},
        # D-72: orders created in the charted months.
        "delivery": delivery_stats(
            src.in_range(Collection.MEDICATION_ORDERS, "createdAt", starts[0], soon)
        ),
    }


# ---------------- system analytics (Fig 4.3.14.6) ----------------


def system(
    src: AnalyticsSource,
    audit_entries: list[dict[str, Any]],
    now: datetime,
    days: int = 7,
    uptime: float | None = None,
) -> dict[str, Any]:
    users = dict(src.users())
    start = now - timedelta(days=days)
    in_window = [
        e
        for e in audit_entries
        if isinstance(e.get("timestamp"), datetime)
        and start <= e["timestamp"] < now + timedelta(seconds=1)
        and e.get("action") != "JOB_HEARTBEAT"
    ]

    def role_of(uid: Any) -> str | None:
        return users.get(str(uid), {}).get("role")

    clinicians = {uid for uid, u in users.items() if u.get("role") in CLINICIANS}
    active_clinicians = {e["userId"] for e in in_window if e.get("userId") in clinicians}

    # Daily activity by role (Patient app / clinicians / admin / family).
    activity: dict[str, Counter[str]] = {}
    for e in in_window:
        role = role_of(e.get("userId"))
        if role is None:
            continue
        activity.setdefault(_myt_day(e["timestamp"]).isoformat(), Counter())[role] += 1
    first = _myt_day(start) + timedelta(days=1)
    days_list = [(first + timedelta(days=i)).isoformat() for i in range(days)]
    daily = [{"date": d, **dict(activity.get(d, Counter()))} for d in days_list]

    # Usage by doctor specialty: doctors' own events plus their patients' events.
    def specialty_of(uid: Any) -> str | None:
        u = users.get(str(uid), {})
        if u.get("role") == UserRole.DOCTOR.value:
            return str(u.get("specialty") or "General")
        if u.get("role") == UserRole.PATIENT.value and u.get("assignedDoctorId"):
            doctor = users.get(str(u["assignedDoctorId"]), {})
            return str(doctor.get("specialty") or "General")
        return None

    by_specialty = Counter(
        s for s in (specialty_of(e.get("userId")) for e in in_window) if s is not None
    )

    messages = src.in_range(Collection.MESSAGES, "sentAt", start, now + timedelta(seconds=1))
    critical_open = [
        a
        for a in src.where_equal(Collection.CLINICAL_ALERTS, "status", "open")
        if a.get("severity") == RiskLevel.CRITICAL.value
    ]
    return {
        "days": days,
        "activeClinicians": len(active_clinicians),
        "totalClinicians": len(clinicians),
        "uptime": uptime,
        "messagesSent": len(messages),
        "messagesPerDay": round(len(messages) / days, 1),
        "unresolvedCritical": len(critical_open),
        "totalUsers": len(users),
        "dailyActivity": daily,
        "bySpecialty": [{"specialty": k, "events": v} for k, v in by_specialty.most_common()],
    }


# ---------------- hospital-wide report (UC11.5) ----------------


def report_data(
    src: AnalyticsSource,
    audit_entries: list[dict[str, Any]],
    start: datetime,
    end: datetime,
) -> dict[str, Any] | None:
    """The four sections Ping chose (D-59), or None when the range has no data (E1)."""
    users = src.users()
    by_uid = dict(users)
    active = _active_patients(users)
    new_patients = [
        u
        for _, u in users
        if u.get("role") == UserRole.PATIENT.value
        and isinstance(u.get("createdAt"), datetime)
        and start <= u["createdAt"] < end
    ]
    readings = src.in_range(Collection.VITAL_READINGS, "timestamp", start, end)
    scores = src.in_range(Collection.RISK_SCORES, "generatedAt", start, end)
    latest = _latest_per_patient(scores).values()
    appts = src.in_range(Collection.APPOINTMENTS, "dateTime", start, end)
    logs = src.in_range(Collection.DOSE_LOGS, "scheduledTime", start, end)
    alerts = src.in_range(Collection.CLINICAL_ALERTS, "createdAt", start, end)
    triage = src.in_range(Collection.TRIAGE_OUTCOMES, "generatedAt", start, end)
    messages = src.in_range(Collection.MESSAGES, "sentAt", start, end)
    shared = src.in_range(Collection.HEALTH_RECORDS, "sharedAt", start, end)
    orders = src.in_range(Collection.MEDICATION_ORDERS, "createdAt", start, end)
    events = [
        e
        for e in audit_entries
        if isinstance(e.get("timestamp"), datetime) and start <= e["timestamp"] < end
    ]
    logins = [e for e in events if e.get("action") == "LOGIN"]
    if not any(
        [new_patients, readings, scores, appts, logs, alerts, triage, messages, logins, orders]
    ):
        return None

    statuses = Counter(a.get("status") for a in appts)
    reasons = Counter(
        CHANGE_REASONS.get(str(a.get("changeReason")), str(a.get("changeReason")))
        for a in appts
        if a.get("status") == "cancelled" and a.get("changeReason")
    )
    clinicians = {
        e.get("userId")
        for e in events
        if by_uid.get(str(e.get("userId")), {}).get("role") in CLINICIANS
    }
    return {
        "from": start.isoformat(),
        "to": end.isoformat(),
        "patients": {
            "active": len(active),
            "newRegistrations": len(new_patients),
            "readingsLogged": len(readings),
            "patientsScored": len(list(latest)),
            "risk": _distribution(_latest_per_patient(scores).values()),
        },
        "appointments": {
            "total": len(appts),
            "completed": statuses.get("completed", 0),
            "noShow": statuses.get("no_show", 0),
            "cancelled": statuses.get("cancelled", 0),
            "upcoming": statuses.get("booked", 0) + statuses.get("rescheduled", 0),
            "topCancellationReasons": reasons.most_common(3),
        },
        "care": {
            "adherence": _adherence(logs),
            "missedDoses": sum(1 for d in logs if d.get("status") == "missed"),
            "alertsRaised": len(alerts),
            "alertsBySeverity": dict(Counter(a.get("severity") for a in alerts)),
            "alertsResolved": sum(1 for a in alerts if a.get("status") != "open"),
            "triage": dict(Counter(t.get("outcome") for t in triage)),
        },
        "delivery": delivery_stats(orders),  # D-72
        "usage": {
            "activeClinicians": len(clinicians),
            "messagesSent": len(messages),
            "recordsShared": len(shared),
            "logins": len(logins),
        },
    }


def _latin1(text: object) -> str:
    return str(text).encode("latin-1", "replace").decode("latin-1")


def report_pdf(data: dict[str, Any], period: str, generated: str) -> bytes:
    from fpdf import FPDF

    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.add_page()
    width = pdf.epw

    def line(text: object, size: int = 10, style: str = "") -> None:
        pdf.set_font("Helvetica", style, size)
        pdf.multi_cell(width, 6 if size <= 10 else 8, _latin1(text), new_x="LMARGIN", new_y="NEXT")

    def pct(v: float | None) -> str:
        return "-" if v is None else f"{v:.1f}%"

    line("CareFlow hospital-wide report", 16, "B")
    line(f"Period: {period} (Malaysia time)")
    line(f"Generated {generated}")
    p, a, c, u = data["patients"], data["appointments"], data["care"], data["usage"]

    pdf.ln(3)
    line("1. Patients and risk", 13, "B")
    line(f"Active patients: {p['active']}")
    line(f"New registrations: {p['newRegistrations']}")
    line(f"Blood pressure readings logged: {p['readingsLogged']}")
    line(f"Patients with a risk assessment: {p['patientsScored']}")
    risk = p["risk"]
    line(
        "Risk distribution (latest in period): "
        + ", ".join(f"{lvl.title()} {risk.get(lvl, 0)}" for lvl in LEVELS)
    )

    pdf.ln(2)
    line("2. Appointments", 13, "B")
    line(
        f"Total {a['total']}: completed {a['completed']}, no-show {a['noShow']}, "
        f"cancelled {a['cancelled']}, still upcoming {a['upcoming']}"
    )
    reasons = a["topCancellationReasons"]
    line(
        "Top cancellation reasons: "
        + (", ".join(f"{r} ({n})" for r, n in reasons) if reasons else "none recorded")
    )

    pdf.ln(2)
    line("3. Adherence and alerts", 13, "B")
    line(f"Medication adherence: {pct(c['adherence'])}; missed doses: {c['missedDoses']}")
    sev = c["alertsBySeverity"]
    line(
        f"Clinical alerts raised: {c['alertsRaised']} ("
        + ", ".join(f"{k} {v}" for k, v in sorted(sev.items()))
        + f"); resolved: {c['alertsResolved']}"
    )
    tri = c["triage"]
    line(
        "Symptom checker outcomes: "
        + (", ".join(f"{str(k).replace('_', ' ')} {v}" for k, v in tri.items()) or "none")
    )

    d = data.get("delivery")
    if d:
        pdf.ln(2)
        line("4. Medication orders and delivery", 13, "B")
        line(
            f"Orders: {d['orders']} (home delivery {d['homeDelivery']}, self-collection "
            f"{d['selfCollection']}); paid {d['paid']}"
        )
        line(
            f"Delivered {d['delivered']}, collected {d['collected']}, in progress "
            f"{d['inProgress']}, failed {d['failed']}, out of stock {d['outOfStock']}"
        )
        fee = d["averageCourierFee"]
        line(
            f"Paid revenue: RM{d['revenue']:.2f}; average courier fee: "
            + ("-" if fee is None else f"RM{fee:.2f}")
        )

    pdf.ln(2)
    line(f"{5 if d else 4}. Platform usage", 13, "B")
    line(f"Active clinicians: {u['activeClinicians']}")
    line(f"Messages sent: {u['messagesSent']} (contents are end-to-end encrypted)")
    line(f"Health records shared with doctors: {u['recordsShared']}")
    line(f"Sign-ins: {u['logins']}")

    pdf.ln(4)
    line(
        "Aggregated figures only; no individual patient is identified. Risk levels come from "
        "the CareFlow prediction models and are not a diagnosis.",
        9,
        "I",
    )
    return bytes(pdf.output())
