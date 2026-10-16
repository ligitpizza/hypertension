"""Module 10 message delivery notifications (FR-10.1, FR-10.3, FR-14.4; UC10.1, UC10.3; D-42).

Messages are end-to-end encrypted and written by the clients under Security Rules, so
this endpoint never sees message text. After the sender's write is stored (also after an
offline queue flushes, UC10.1 E1), the sending client calls it to:
  - push "New message from <name>" to the recipient's devices;
  - if the sender's on-device scan flagged the message (isFlagged), raise a
    `flagged_message` clinical alert for the assigned doctor (UC10.3).
"""

from datetime import UTC, datetime
from typing import Any, Protocol

from fastapi import APIRouter, Depends, status

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import ClinicalAlertType, Collection, RiskLevel, UserRole
from app.core.errors import ApiError
from app.core.firebase import get_firestore
from app.integrations.push import PushMessage
from app.services.escalation import DoctorAlert, EscalationPlan, Escalator, get_escalator
from app.services.notifications import Notifier, get_notifier

router = APIRouter(prefix="/messages", tags=["messages"])


class MessageRepository(Protocol):
    def message(self, message_id: str) -> dict[str, Any] | None:
        """Metadata only (senderId, recipientId, isFlagged, attachmentType); never the text."""
        ...

    def user(self, uid: str) -> dict[str, Any] | None: ...


class FirestoreMessageRepository:
    def __init__(self, db: Any) -> None:
        self._db = db

    def message(self, message_id: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.MESSAGES.value).document(message_id).get()
        return dict(snap.to_dict()) if snap.exists else None

    def user(self, uid: str) -> dict[str, Any] | None:
        snap = self._db.collection(Collection.USERS.value).document(uid).get()
        return dict(snap.to_dict()) if snap.exists else None


def get_message_repository() -> MessageRepository:
    return FirestoreMessageRepository(get_firestore())


@router.post("/{message_id}/notify", status_code=status.HTTP_204_NO_CONTENT)
def notify(
    message_id: str,
    user: CurrentUser = Depends(require_roles(UserRole.PATIENT, UserRole.DOCTOR)),
    repo: MessageRepository = Depends(get_message_repository),
    notifier: Notifier = Depends(get_notifier),
    escalator: Escalator = Depends(get_escalator),
    audit: AuditLogger = Depends(get_audit_logger),
) -> None:
    msg = repo.message(message_id)
    if msg is None or msg.get("senderId") != user.uid:
        raise ApiError("MESSAGE_NOT_FOUND", "Message not found.", status.HTTP_404_NOT_FOUND)
    recipient_id = str(msg.get("recipientId"))
    sender = repo.user(user.uid) or {}
    name = str(sender.get("name") or "Your care team")

    notifier.notify(
        recipient_id,
        PushMessage(
            f"New message from {name}",
            # E2E: the server cannot include the text; it only knows a file was attached (D-52).
            {"image": "Sent you a photo.", "pdf": "Sent you a document."}.get(
                str(msg.get("attachmentType")), "Open Harvey to read it."
            ),
            {"type": "message", "from": user.uid},
            urgent=bool(msg.get("isFlagged")),
        ),
    )
    flagged = bool(msg.get("isFlagged")) and user.role is UserRole.PATIENT
    if flagged:
        plan = EscalationPlan(
            doctor_alerts=[
                DoctorAlert(
                    ClinicalAlertType.FLAGGED_MESSAGE,
                    RiskLevel.HIGH,
                    f"Flagged message from {name}: high-risk words detected. "
                    "Open the conversation to review.",
                )
            ]
        )
        # The alert goes to the patient's assigned doctor (the message recipient).
        escalator.apply(plan, user.uid, sender.get("assignedDoctorId"), datetime.now(UTC))
    audit.log(
        user_id=user.uid,
        action="SEND_MESSAGE",
        details=f"Secure message sent{' (flagged by keyword scan)' if flagged else ''}.",
        target_type=Collection.MESSAGES.value,
        target_id=message_id,
    )
