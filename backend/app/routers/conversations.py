"""Team and admin-opened chats (D-76).

GET  /conversations                  the caller's chats (admins also see chats they opened)
GET  /conversations/contacts?q=      people the caller may start a chat with
POST /conversations                  start (or reopen) a chat with one person
POST /conversations/pair             admin: open a chat between two people
GET  /conversations/{id}/messages    the thread (participants; the opening admin read-only)
POST /conversations/{id}/messages    send (participants)
POST /conversations/{id}/read        clear the caller's unread count

Message text is never written to the audit log.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, ConfigDict, Field

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.integrations.push import PushMessage
from app.services.conversations import (
    CHAT_ROLES,
    MAX_LENGTH,
    THREAD_LIMIT,
    ConversationRepository,
    can_start,
    conversation_id,
    get_conversation_repository,
    has_secure_chat,
    is_active,
    message_view,
    new_conversation,
)
from app.services.notifications import Notifier, get_notifier
from app.services.users import UserRepository, get_user_repository

router = APIRouter(prefix="/conversations", tags=["conversations"])
anyone = require_roles(UserRole.PATIENT, UserRole.DOCTOR, UserRole.PHARMACIST, UserRole.ADMIN)
staff = require_roles(UserRole.DOCTOR, UserRole.PHARMACIST, UserRole.ADMIN)
admin_only = require_roles(UserRole.ADMIN)

CONTACT_LIMIT = 50


class StartRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    userId: str = Field(min_length=1, max_length=128)  # noqa: N815 (JSON field name)


class PairRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    userA: str = Field(min_length=1, max_length=128)  # noqa: N815
    userB: str = Field(min_length=1, max_length=128)  # noqa: N815


class SendRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    text: str = Field(min_length=1, max_length=MAX_LENGTH)


def _person(users: UserRepository, uid: str) -> dict[str, Any]:
    u = users.get_user(uid) or {}
    return {"uid": uid, "name": u.get("name") or "Unknown", "role": u.get("role")}


def _view(
    cid: str, c: dict[str, Any], me: str, users: UserRepository, names: dict[str, Any]
) -> dict[str, Any]:
    def person(uid: str) -> dict[str, Any]:
        if uid not in names:
            names[uid] = _person(users, uid)
        return dict(names[uid])

    ids = [str(i) for i in c.get("participantIds") or []]
    observer = me not in ids
    others = [i for i in ids if i != me]
    last = c.get("lastMessageAt")
    return {
        "id": cid,
        "participants": [person(i) for i in ids],
        "other": None if observer or not others else person(others[0]),
        "observer": observer,
        "openedByAdmin": bool(c.get("openedByAdmin")),
        "openedBy": person(str(c.get("openedBy"))) if c.get("openedBy") else None,
        "lastText": c.get("lastText") or "",
        "lastSenderId": c.get("lastSenderId"),
        "lastMessageAt": last.isoformat() if isinstance(last, datetime) else None,
        "unread": 0 if observer else int((c.get("unread") or {}).get(me) or 0),
    }


def _chat_user(users: UserRepository, uid: str) -> dict[str, Any]:
    u = users.get_user(uid)
    if not is_active(u) or (u or {}).get("role") not in CHAT_ROLES:
        raise ApiError("USER_NOT_FOUND", "That person can't be messaged.", 404)
    return dict(u or {})


def _conversation(
    convs: ConversationRepository, cid: str, user: CurrentUser, *, write: bool
) -> dict[str, Any]:
    c = convs.get(cid)
    ids = (c or {}).get("participantIds") or []
    allowed = user.uid in ids or (
        not write and user.role is UserRole.ADMIN and (c or {}).get("openedBy") == user.uid
    )
    if c is None or not allowed:
        raise ApiError("CONVERSATION_NOT_FOUND", "Conversation not found.", 404)
    return c


def _post(
    convs: ConversationRepository,
    notifier: Notifier,
    cid: str,
    c: dict[str, Any],
    sender_id: str,
    sender_role: str,
    sender_name: str,
    text: str,
    push_title: str,
) -> dict[str, Any]:
    recipients = [str(i) for i in c.get("participantIds") or [] if i != sender_id]
    data = {
        "conversationId": cid,
        "senderId": sender_id,
        "senderRole": sender_role,
        "senderName": sender_name,
        "text": text,
        "sentAt": datetime.now(UTC),
    }
    message_id = convs.add_message(data, recipients)
    for uid in recipients:
        notifier.notify(
            uid, PushMessage(push_title, text[:120], {"type": "conversation", "id": cid})
        )
    return message_view(message_id, data)


@router.get("")
def my_conversations(
    user: CurrentUser = Depends(anyone),
    convs: ConversationRepository = Depends(get_conversation_repository),
    users: UserRepository = Depends(get_user_repository),
) -> dict[str, Any]:
    found = dict(convs.for_user(user.uid))
    if user.role is UserRole.ADMIN:
        for cid, c in convs.opened_by(user.uid):
            found.setdefault(cid, c)
    names: dict[str, Any] = {}
    out = [_view(cid, c, user.uid, users, names) for cid, c in found.items()]
    out.sort(key=lambda v: v["lastMessageAt"] or "", reverse=True)
    return {"conversations": out}


@router.get("/contacts")
def contacts(
    q: str = Query(default="", max_length=80),
    user: CurrentUser = Depends(staff),
    users: UserRepository = Depends(get_user_repository),
) -> dict[str, Any]:
    """Who the caller may start a chat with (admins: anyone; others: staff)."""
    role = user.role.value if user.role else ""
    term = q.strip().lower()
    out = []
    for uid, u in users.list_users():
        if uid == user.uid or not is_active(u) or not can_start(role, str(u.get("role"))):
            continue
        name = str(u.get("name") or "")
        email = str(u.get("email") or "")
        if term and term not in name.lower() and term not in email.lower():
            continue
        out.append({"uid": uid, "name": name or "Unknown", "role": u.get("role"), "email": email})
    out.sort(key=lambda p: (str(p["role"]), str(p["name"]).lower()))
    return {"contacts": out[:CONTACT_LIMIT]}


@router.post("", status_code=status.HTTP_201_CREATED)
def start(
    body: StartRequest,
    user: CurrentUser = Depends(anyone),
    convs: ConversationRepository = Depends(get_conversation_repository),
    users: UserRepository = Depends(get_user_repository),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    if body.userId == user.uid:
        raise ApiError("INVALID_CONTACT", "You can't start a chat with yourself.", 422)
    role = user.role.value if user.role else ""
    target = _chat_user(users, body.userId)
    if not can_start(role, str(target.get("role"))):
        raise ApiError("CANNOT_START_CHAT", "You can't start a chat with this person.", 403)
    me = users.get_user(user.uid) or {}
    if has_secure_chat(me, user.uid, target, body.userId):
        raise ApiError(
            "USE_SECURE_CHAT", "Use the secure doctor-patient chat for this patient.", 409
        )
    cid = conversation_id(user.uid, body.userId)
    if convs.get(cid) is None:
        convs.create(cid, new_conversation(user.uid, body.userId, user.uid, role, by_admin=False))
        audit.log(
            user_id=user.uid,
            action="START_CONVERSATION",
            details="Chat started.",
            target_type=Collection.CONVERSATIONS.value,
            target_id=cid,
        )
    return _view(cid, convs.get(cid) or {}, user.uid, users, {})


@router.post("/pair", status_code=status.HTTP_201_CREATED)
def pair(
    body: PairRequest,
    user: CurrentUser = Depends(admin_only),
    convs: ConversationRepository = Depends(get_conversation_repository),
    users: UserRepository = Depends(get_user_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    """D-76: the admin assigns who chats with whom."""
    if body.userA == body.userB:
        raise ApiError("INVALID_CONTACT", "Choose two different people.", 422)
    a = _chat_user(users, body.userA)
    b = _chat_user(users, body.userB)
    if a.get("role") == UserRole.PATIENT.value and b.get("role") == UserRole.PATIENT.value:
        raise ApiError("INVALID_CONTACT", "Two patients can't be put in a chat together.", 422)
    if has_secure_chat(a, body.userA, b, body.userB):
        raise ApiError("USE_SECURE_CHAT", "They already have the secure doctor-patient chat.", 409)
    cid = conversation_id(body.userA, body.userB)
    existing = convs.get(cid)
    if existing is None:
        convs.create(
            cid, new_conversation(body.userA, body.userB, user.uid, "admin", by_admin=True)
        )
        admin = users.get_user(user.uid) or {}
        c = convs.get(cid) or {}
        _post(
            convs,
            notifier,
            cid,
            c,
            user.uid,
            "system",
            "Harvey",
            f"{admin.get('name') or 'An admin'} (admin) opened this chat between "
            f"{a.get('name') or 'Unknown'} and {b.get('name') or 'Unknown'}.",
            "New chat opened by admin",
        )
        audit.log(
            user_id=user.uid,
            action="OPEN_CONVERSATION",
            details="Admin opened a chat between two users.",
            target_type=Collection.CONVERSATIONS.value,
            target_id=cid,
        )
    return _view(cid, convs.get(cid) or {}, user.uid, users, {})


@router.get("/{cid}/messages")
def thread(
    cid: str,
    user: CurrentUser = Depends(anyone),
    convs: ConversationRepository = Depends(get_conversation_repository),
    users: UserRepository = Depends(get_user_repository),
) -> dict[str, Any]:
    c = _conversation(convs, cid, user, write=False)
    return {
        "conversation": _view(cid, c, user.uid, users, {}),
        "messages": [message_view(i, m) for i, m in convs.messages(cid, THREAD_LIMIT)],
    }


@router.post("/{cid}/messages", status_code=status.HTTP_201_CREATED)
def send(
    cid: str,
    body: SendRequest,
    user: CurrentUser = Depends(anyone),
    convs: ConversationRepository = Depends(get_conversation_repository),
    users: UserRepository = Depends(get_user_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    c = _conversation(convs, cid, user, write=True)
    me = users.get_user(user.uid) or {}
    name = str(me.get("name") or "Harvey user")
    view = _post(
        convs,
        notifier,
        cid,
        c,
        user.uid,
        user.role.value if user.role else "",
        name,
        body.text,
        f"Message from {name}",
    )
    audit.log(
        user_id=user.uid,
        action="CONVERSATION_MESSAGE",
        details="Chat message sent.",
        target_type=Collection.CONVERSATION_MESSAGES.value,
        target_id=view["id"],
    )
    return view


@router.post("/{cid}/read", status_code=status.HTTP_204_NO_CONTENT)
def read(
    cid: str,
    user: CurrentUser = Depends(anyone),
    convs: ConversationRepository = Depends(get_conversation_repository),
) -> None:
    c = _conversation(convs, cid, user, write=False)
    if user.uid in (c.get("participantIds") or []):
        convs.mark_read(cid, user.uid)
