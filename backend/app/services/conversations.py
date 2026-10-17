"""Team and admin-opened chats (D-76): one conversation between two people.

- Doctors, pharmacists and admins may start a chat with each other.
- An admin may start a chat with anyone (patients too), and may open a chat between any
  two people ("assign who chats with whom").
- Patients reply in chats opened with them; they start chats only with their doctor
  (the end-to-end encrypted chat) and the shared Harvey Pharmacy chat.

Like the pharmacy chat (D-69) these go through FastAPI and are not end-to-end encrypted;
the patient-doctor chat (NFR-2.1) is unchanged. Unread counts are kept per participant on
the conversation document, so they follow the user across devices.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, Protocol

from firebase_admin import firestore

from app.core.enums import Collection, UserRole
from app.core.firebase import get_firestore

MAX_LENGTH = 2000
PREVIEW_LENGTH = 120
THREAD_LIMIT = 200

STAFF_ROLES = {UserRole.DOCTOR.value, UserRole.PHARMACIST.value, UserRole.ADMIN.value}
# Family members have no messaging screens; everyone else can be in a conversation.
CHAT_ROLES = STAFF_ROLES | {UserRole.PATIENT.value}


def conversation_id(a: str, b: str) -> str:
    """One conversation per pair, whoever started it."""
    first, second = sorted((a, b))
    return f"{first}__{second}"


def is_active(user: dict[str, Any] | None) -> bool:
    return user is not None and user.get("isActive", True) is not False


def has_secure_chat(a: dict[str, Any], a_id: str, b: dict[str, Any], b_id: str) -> bool:
    """A patient and their assigned doctor already have the encrypted chat (FR-10.1)."""
    return (a.get("role") == UserRole.PATIENT.value and a.get("assignedDoctorId") == b_id) or (
        b.get("role") == UserRole.PATIENT.value and b.get("assignedDoctorId") == a_id
    )


def can_start(caller_role: str, target_role: str) -> bool:
    if caller_role == UserRole.ADMIN.value:
        return target_role in CHAT_ROLES
    if caller_role in STAFF_ROLES:
        return target_role in STAFF_ROLES
    return False


def _iso(value: Any) -> str | None:
    return value.isoformat() if isinstance(value, datetime) else None


def message_view(message_id: str, m: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": message_id,
        "conversationId": m.get("conversationId"),
        "senderId": m.get("senderId"),
        "senderRole": m.get("senderRole"),
        "senderName": m.get("senderName"),
        "text": m.get("text"),
        "sentAt": _iso(m.get("sentAt")),
    }


class ConversationRepository(Protocol):
    def get(self, cid: str) -> dict[str, Any] | None: ...

    def create(self, cid: str, data: dict[str, Any]) -> None: ...

    def for_user(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        """Conversations the user is in."""
        ...

    def opened_by(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        """Conversations an admin opened between two other people."""
        ...

    def add_message(self, data: dict[str, Any], recipients: list[str]) -> str:
        """Stores the message, updates the preview and adds one unread for each recipient."""
        ...

    def messages(self, cid: str, limit: int) -> list[tuple[str, dict[str, Any]]]:
        """Oldest first, the latest [limit]."""
        ...

    def mark_read(self, cid: str, uid: str) -> None: ...


class FirestoreConversationRepository:
    def __init__(self, db: Any) -> None:
        self._db = db
        self._convs = db.collection(Collection.CONVERSATIONS.value)
        self._msgs = db.collection(Collection.CONVERSATION_MESSAGES.value)

    def get(self, cid: str) -> dict[str, Any] | None:
        snap = self._convs.document(cid).get()
        return dict(snap.to_dict()) if snap.exists else None

    def create(self, cid: str, data: dict[str, Any]) -> None:
        self._convs.document(cid).set(data)

    def for_user(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        q = self._convs.where(filter=firestore.FieldFilter("participantIds", "array_contains", uid))
        return [(d.id, dict(d.to_dict())) for d in q.stream()]

    def opened_by(self, uid: str) -> list[tuple[str, dict[str, Any]]]:
        q = self._convs.where(filter=firestore.FieldFilter("openedBy", "==", uid))
        return [(d.id, dict(d.to_dict())) for d in q.stream()]

    def add_message(self, data: dict[str, Any], recipients: list[str]) -> str:
        ref = self._msgs.document()
        batch = self._db.batch()
        batch.set(ref, data)
        update: dict[str, Any] = {
            "lastText": str(data.get("text") or "")[:PREVIEW_LENGTH],
            "lastSenderId": data.get("senderId"),
            "lastMessageAt": data.get("sentAt"),
        }
        for uid in recipients:
            update[f"unread.{uid}"] = firestore.Increment(1)
        batch.update(self._convs.document(str(data["conversationId"])), update)
        batch.commit()
        return str(ref.id)

    def messages(self, cid: str, limit: int) -> list[tuple[str, dict[str, Any]]]:
        q = (
            self._msgs.where(filter=firestore.FieldFilter("conversationId", "==", cid))
            .order_by("sentAt", direction=firestore.Query.DESCENDING)
            .limit(limit)
        )
        return list(reversed([(d.id, dict(d.to_dict())) for d in q.stream()]))

    def mark_read(self, cid: str, uid: str) -> None:
        self._convs.document(cid).update({f"unread.{uid}": 0})


def get_conversation_repository() -> ConversationRepository:
    return FirestoreConversationRepository(get_firestore())


def new_conversation(
    a: str, b: str, opener: str, opener_role: str, *, by_admin: bool, now: datetime | None = None
) -> dict[str, Any]:
    now = now or datetime.now(UTC)
    return {
        "participantIds": sorted((a, b)),
        "openedBy": opener,
        "openedByRole": opener_role,
        "openedByAdmin": by_admin,
        "createdAt": now,
        "lastMessageAt": now,
        "lastText": "",
        "lastSenderId": None,
        "unread": {a: 0, b: 0},
    }
