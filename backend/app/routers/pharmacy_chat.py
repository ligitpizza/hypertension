"""Pharmacy chat (D-69).

Patient     GET/POST /pharmacy-chat/messages
Pharmacist  GET      /pharmacy-chat/conversations
            GET/POST /pharmacy-chat/{patientId}/messages

A pharmacist may write to any patient (D-70). Message text is never written to the
audit log.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field

from app.core.audit import AuditLogger, get_audit_logger
from app.core.auth import CurrentUser, require_roles
from app.core.enums import Collection, UserRole
from app.core.errors import ApiError
from app.integrations.push import PushMessage
from app.services.notifications import Notifier, get_notifier
from app.services.orders import OrderRepository, get_order_repository
from app.services.pharmacy_chat import (
    MAX_LENGTH,
    RECENT_SCAN,
    PharmacyChatRepository,
    conversations,
    get_pharmacy_chat_repository,
    message_view,
)

router = APIRouter(prefix="/pharmacy-chat", tags=["pharmacy-chat"])
patient_only = require_roles(UserRole.PATIENT)
pharmacist_only = require_roles(UserRole.PHARMACIST)

PHARMACY_NAME = "Harvey Pharmacy"


class ChatMessageRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    text: str = Field(min_length=1, max_length=MAX_LENGTH)


def _send(
    chat: PharmacyChatRepository,
    audit: AuditLogger,
    patient_id: str,
    sender: CurrentUser,
    sender_name: str,
    text: str,
) -> dict[str, Any]:
    data = {
        "patientId": patient_id,
        "senderId": sender.uid,
        "senderRole": sender.role.value if sender.role else "",
        "senderName": sender_name,
        "text": text,
        "sentAt": datetime.now(UTC),
    }
    message_id = chat.add(data)
    audit.log(
        user_id=sender.uid,
        action="PHARMACY_MESSAGE",
        details="Pharmacy chat message sent.",
        target_type=Collection.PHARMACY_MESSAGES.value,
        target_id=message_id,
    )
    return message_view(message_id, data)


@router.get("/messages")
def my_thread(
    user: CurrentUser = Depends(patient_only),
    chat: PharmacyChatRepository = Depends(get_pharmacy_chat_repository),
) -> dict[str, Any]:
    return {"messages": [message_view(i, m) for i, m in chat.thread(user.uid)]}


@router.post("/messages", status_code=status.HTTP_201_CREATED)
def patient_send(
    body: ChatMessageRequest,
    user: CurrentUser = Depends(patient_only),
    chat: PharmacyChatRepository = Depends(get_pharmacy_chat_repository),
    orders: OrderRepository = Depends(get_order_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    me = orders.user(user.uid) or {}
    name = str(me.get("name") or "Patient")
    view = _send(chat, audit, user.uid, user, name, body.text)
    for uid in orders.staff(UserRole.PHARMACIST.value):
        notifier.notify(
            uid,
            PushMessage(f"Message from {name}", body.text[:120], {"type": "pharmacy_chat"}),
        )
    return view


@router.get("/conversations")
def pharmacist_conversations(
    _: CurrentUser = Depends(pharmacist_only),
    chat: PharmacyChatRepository = Depends(get_pharmacy_chat_repository),
    orders: OrderRepository = Depends(get_order_repository),
) -> dict[str, Any]:
    out = []
    for c in conversations(chat.recent(RECENT_SCAN)):
        patient = orders.user(str(c["patientId"])) or {}
        out.append({**c, "patientName": patient.get("name")})
    return {"conversations": out}


def _served(orders: OrderRepository, patient_id: str) -> dict[str, Any]:
    """D-70: a pharmacist may message any patient account."""
    patient = orders.user(patient_id)
    if patient is None or patient.get("role") != UserRole.PATIENT.value:
        raise ApiError("PATIENT_NOT_FOUND", "Patient not found.", status.HTTP_404_NOT_FOUND)
    return patient


@router.get("/{patient_id}/messages")
def pharmacist_thread(
    patient_id: str,
    _: CurrentUser = Depends(pharmacist_only),
    chat: PharmacyChatRepository = Depends(get_pharmacy_chat_repository),
    orders: OrderRepository = Depends(get_order_repository),
) -> dict[str, Any]:
    patient = _served(orders, patient_id)
    return {
        "patientName": patient.get("name"),
        "messages": [message_view(i, m) for i, m in chat.thread(patient_id)],
    }


@router.post("/{patient_id}/messages", status_code=status.HTTP_201_CREATED)
def pharmacist_send(
    patient_id: str,
    body: ChatMessageRequest,
    user: CurrentUser = Depends(pharmacist_only),
    chat: PharmacyChatRepository = Depends(get_pharmacy_chat_repository),
    orders: OrderRepository = Depends(get_order_repository),
    notifier: Notifier = Depends(get_notifier),
    audit: AuditLogger = Depends(get_audit_logger),
) -> dict[str, Any]:
    _served(orders, patient_id)
    me = orders.user(user.uid) or {}
    sender = f"{PHARMACY_NAME} ({me.get('name') or 'pharmacist'})"
    view = _send(chat, audit, patient_id, user, sender, body.text)
    notifier.notify(
        patient_id,
        PushMessage(PHARMACY_NAME, body.text[:120], {"type": "pharmacy_chat"}),
    )
    return view
