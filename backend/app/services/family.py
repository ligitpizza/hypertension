"""FR-14.2 family monitoring (UC15.1-UC15.3; D-06, D-62).

Linking: a family member enters the patient's link code, the patient approves, and the
member's `users.patientId` is set. Emergencies: one `emergency_alerts` document per
linked member with the phone's GPS position, an urgent push, and a (simulated) SMS to the
patient's emergency contact.
"""

import html
import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

from fastapi import Depends
from google.cloud import firestore as gfs

from app.core.audit import AuditLogger, get_audit_logger
from app.core.enums import Collection, FamilyLinkStatus, UserRole
from app.core.firebase import get_firestore
from app.integrations.email import EmailClient, EmailMessage, get_email_client
from app.integrations.push import PushMessage
from app.integrations.sms import SmsClient, get_sms_client
from app.services.notifications import Notifier, get_notifier
from app.services.settings import parse_profile_field

log = logging.getLogger("careflow.family")

# A new reading-based alert is not repeated while one is still fresh (SOS always sends).
REPEAT_WINDOW = timedelta(minutes=30)
# The patient app keeps refreshing the location of alerts this recent (D-62).
OPEN_WINDOW = timedelta(hours=1)
TRIGGERS = ("emergency_reading", "critical_risk", "sos", "triage")


def normalise_code(code: str) -> str:
    return "".join(ch for ch in code.upper() if ch.isalnum())


def maps_link(location: dict[str, float] | None) -> str:
    if not location:
        return "location not available"
    return f"https://maps.google.com/?q={location['lat']:.6f},{location['lng']:.6f}"


class FamilyRepository(Protocol):
    def user(self, uid: str) -> dict[str, Any] | None: ...

    def update_user(self, uid: str, data: dict[str, Any]) -> None: ...

    def patient_by_code(self, code: str) -> str | None: ...

    def family_of(self, patient_id: str) -> list[str]: ...

    def health_profile(self, patient_id: str) -> dict[str, Any] | None: ...

    def create_request(self, data: dict[str, Any]) -> str: ...

    def get_request(self, request_id: str) -> dict[str, Any] | None: ...

    def update_request(self, request_id: str, data: dict[str, Any]) -> None: ...

    def pending_for_member(self, member_id: str) -> list[tuple[str, dict[str, Any]]]: ...

    def create_alert(self, data: dict[str, Any]) -> str: ...

    def get_alert(self, alert_id: str) -> dict[str, Any] | None: ...

    def update_alert(self, alert_id: str, data: dict[str, Any]) -> None: ...

    def alerts_since(self, patient_id: str, since: datetime) -> list[tuple[str, dict[str, Any]]]:
        """The patient's emergency alerts sent at or after [since]."""
        ...


def _geo(location: dict[str, float] | None) -> Any:
    return None if location is None else gfs.GeoPoint(location["lat"], location["lng"])


class FirestoreFamilyRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def _col(self, c: Collection) -> Any:
        return self._db.collection(c.value)

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._col(Collection.USERS).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def update_user(self, uid: str, data: dict[str, Any]) -> None:
        self._col(Collection.USERS).document(uid).update(
            {**data, "updatedAt": gfs.SERVER_TIMESTAMP}
        )

    def patient_by_code(self, code: str) -> str | None:
        q = (
            self._col(Collection.USERS)
            .where(filter=gfs.FieldFilter("linkCode", "==", code))
            .limit(1)
        )
        for d in q.stream():
            if d.get("role") == UserRole.PATIENT.value and d.get("isActive") is not False:
                return str(d.id)
        return None

    def family_of(self, patient_id: str) -> list[str]:
        q = (
            self._col(Collection.USERS)
            .where(filter=gfs.FieldFilter("role", "==", UserRole.FAMILY_MEMBER.value))
            .where(filter=gfs.FieldFilter("patientId", "==", patient_id))
        )
        return [d.id for d in q.stream() if d.get("isActive") is not False]

    def health_profile(self, patient_id: str) -> dict[str, Any] | None:
        snap = self._col(Collection.HEALTH_PROFILES).document(patient_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def create_request(self, data: dict[str, Any]) -> str:
        _, ref = self._col(Collection.FAMILY_LINK_REQUESTS).add(
            {**data, "createdAt": gfs.SERVER_TIMESTAMP}
        )
        return str(ref.id)

    def get_request(self, request_id: str) -> dict[str, Any] | None:
        snap = self._col(Collection.FAMILY_LINK_REQUESTS).document(request_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def update_request(self, request_id: str, data: dict[str, Any]) -> None:
        self._col(Collection.FAMILY_LINK_REQUESTS).document(request_id).update(data)

    def pending_for_member(self, member_id: str) -> list[tuple[str, dict[str, Any]]]:
        q = self._col(Collection.FAMILY_LINK_REQUESTS).where(
            filter=gfs.FieldFilter("familyMemberId", "==", member_id)
        )
        return [
            (d.id, dict(d.to_dict()))
            for d in q.stream()
            if d.get("status") == FamilyLinkStatus.PENDING.value
        ]

    def create_alert(self, data: dict[str, Any]) -> str:
        doc = {**data, "gpsLocation": _geo(data.get("gpsLocation"))}
        _, ref = self._col(Collection.EMERGENCY_ALERTS).add(doc)
        return str(ref.id)

    def get_alert(self, alert_id: str) -> dict[str, Any] | None:
        snap = self._col(Collection.EMERGENCY_ALERTS).document(alert_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def update_alert(self, alert_id: str, data: dict[str, Any]) -> None:
        if "gpsLocation" in data:
            data = {**data, "gpsLocation": _geo(data["gpsLocation"])}
        self._col(Collection.EMERGENCY_ALERTS).document(alert_id).update(data)

    def alerts_since(self, patient_id: str, since: datetime) -> list[tuple[str, dict[str, Any]]]:
        q = (
            self._col(Collection.EMERGENCY_ALERTS)
            .where(filter=gfs.FieldFilter("patientId", "==", patient_id))
            .where(filter=gfs.FieldFilter("sentAt", ">=", since))
        )
        return [(d.id, dict(d.to_dict())) for d in q.stream()]


def get_family_repository() -> FamilyRepository:
    return FirestoreFamilyRepository(get_firestore())


@dataclass
class EmergencyAlerts:
    """UC15.2: create the family alerts for one emergency event."""

    repo: FamilyRepository
    notifier: Notifier
    sms: SmsClient
    audit: AuditLogger
    email: EmailClient | None = None  # D-64: emergency email to each family member

    def raise_alerts(
        self,
        patient_id: str,
        trigger: str,
        location: dict[str, float] | None,
        now: datetime,
        risk_score_id: str | None = None,
        push: PushMessage | None = None,
    ) -> list[str]:
        patient = self.repo.user(patient_id) or {}
        name = str(patient.get("name") or "Your family member")
        recent = [
            (i, a)
            for i, a in self.repo.alerts_since(patient_id, now - REPEAT_WINDOW)
            if a.get("acknowledgedAt") is None
        ]
        if trigger != "sos" and recent:
            # The family was alerted moments ago: only refresh where the patient is.
            if location:
                for alert_id, _a in recent:
                    self.repo.update_alert(
                        alert_id, {"gpsLocation": location, "locationUpdatedAt": now}
                    )
            return []
        personal = parse_profile_field(
            (self.repo.health_profile(patient_id) or {}).get("personalInfo")
        )
        phone = str(personal.get("phone") or "") or None
        contact = personal.get("emergencyContact") or {}
        members = self.repo.family_of(patient_id)
        what = {
            "emergency_reading": "logged a very high blood pressure reading",
            "critical_risk": "has a critical health risk",
            "sos": "pressed the SOS button",
            "triage": "reported symptoms that need emergency care",
        }[trigger]
        created: list[str] = []
        for member in members:
            data: dict[str, Any] = {
                "patientId": patient_id,
                "familyMemberId": member,
                "trigger": trigger,
                "gpsLocation": location,
                "sentAt": now,
            }
            if risk_score_id:
                data["riskScoreId"] = risk_score_id
            if phone:
                data["patientPhone"] = phone
            alert_id = self.repo.create_alert(data)
            created.append(alert_id)
            self._email_member(member, name, what, location)
            message = push or PushMessage(f"Emergency: {name}", "", {})
            self.notifier.notify(
                member,
                PushMessage(
                    f"Emergency: {name}",
                    f"{name} {what}. Open CareFlow to see where they are; call 999 if they "
                    "are unwell.",
                    {
                        **message.data,
                        "type": "emergency_alert",
                        "alertId": alert_id,
                        "patientId": patient_id,
                    },
                    urgent=True,
                ),
            )
        if isinstance(contact, dict) and contact.get("phone"):
            self.sms.send(
                str(contact["phone"]),
                f"CareFlow emergency: {name} {what}. Location: {maps_link(location)}. "
                "Call them now; call 999 if they are unwell.",
            )
        self.audit.log(
            user_id="system:emergency",
            action="EMERGENCY_ALERT",
            details=f"{trigger}: {len(created)} family member(s) alerted"
            + ("" if created else " (none linked; doctor escalation only)")
            + ("; location attached." if location else "; no location."),
            target_type=Collection.EMERGENCY_ALERTS.value,
            target_id=created[0] if created else None,
        )
        return created

    def _email_member(
        self, member_id: str, name: str, what: str, location: dict[str, float] | None
    ) -> None:
        member = self.repo.user(member_id) or {}
        address = member.get("email")
        if self.email is None or not address:
            return
        link = maps_link(location)
        text = (
            f"{name} {what}.\n\nLast known location: {link}\n\n"
            "Contact them now. If they are unwell or do not answer, call 999.\n"
            "Open the CareFlow app (Family) to see the alert and the map.\n"
        )
        safe = html.escape(name)
        body = (
            f"<p><b>{safe} {html.escape(what)}.</b></p>"
            + (
                f'<p><a href="{html.escape(link, quote=True)}">Open their location in Google Maps'
                "</a></p>"
                if location
                else "<p>Their phone did not share a location.</p>"
            )
            + "<p>Contact them now. If they are unwell or do not answer, call <b>999</b>.</p>"
            "<p>Open the CareFlow app (Family) to see the alert and the map.</p>"
        )
        try:
            self.email.send(
                EmailMessage(
                    to_email=str(address),
                    to_name=str(member.get("name") or "Family member"),
                    subject=f"CareFlow emergency: {name}",
                    text=text,
                    html=body,
                )
            )
        except Exception:  # email must never stop the alert
            log.exception("Emergency email to %s failed", member_id)

    def update_location(self, patient_id: str, location: dict[str, float], now: datetime) -> int:
        """D-62: while an alert is open, the patient app refreshes the position."""
        updated = 0
        for alert_id, a in self.repo.alerts_since(patient_id, now - OPEN_WINDOW):
            if a.get("acknowledgedAt") is None:
                self.repo.update_alert(
                    alert_id, {"gpsLocation": location, "locationUpdatedAt": now}
                )
                updated += 1
        return updated

    def open_since(self, patient_id: str, now: datetime) -> int:
        return sum(
            1
            for _, a in self.repo.alerts_since(patient_id, now - OPEN_WINDOW)
            if a.get("acknowledgedAt") is None
        )


def get_emergency_alerts(
    repo: FamilyRepository = Depends(get_family_repository),
    notifier: Notifier = Depends(get_notifier),
    sms: SmsClient = Depends(get_sms_client),
    audit: AuditLogger = Depends(get_audit_logger),
    email: EmailClient = Depends(get_email_client),
) -> EmergencyAlerts:
    return EmergencyAlerts(repo, notifier, sms, audit, email)


def now_utc() -> datetime:
    return datetime.now(UTC)
