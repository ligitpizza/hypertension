"""D-69: consolidated catalogue prescriptions, an order per prescription, locked doctor
medicines, catalogue stock, pharmacist patient view, patient address and pharmacy chat."""

import json
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.integrations.push import LogPushClient
from app.services.orders import phone_from_profile
from tests.conftest import (
    InMemoryAuditLogger,
    InMemoryCatalogRepository,
    InMemoryMedicationRepository,
    InMemoryOrderRepository,
    InMemoryPharmacyChatRepository,
    InMemoryProviderRepository,
    InMemoryTokenRepository,
    InMemoryUserRepository,
    bearer,
)

P, D, PH, A = "u-patient", "u-doctor", "u-pharm", "u-admin"
PATIENT, DOCTOR, PHARM, ADMIN = (
    bearer("patient-token"),
    bearer("doctor-token"),
    bearer("pharmacist-token"),
    bearer("admin-token"),
)
RX_URL = f"/api/v1/provider/patients/{P}/prescriptions"
TWO_ITEMS = {
    "items": [
        {
            "catalogId": "amlodipine-5",
            "dose": "1 tablet",
            "frequency": "once_daily",
            "quantity": 30,
        },
        {
            "catalogId": "losartan-50",
            "dose": "1 tablet",
            "frequency": "twice_daily",
            "quantity": 60,
        },
    ]
}


@pytest.fixture(autouse=True)
def people(repo: InMemoryUserRepository, tokens: InMemoryTokenRepository) -> None:
    repo.users.update(
        {
            P: {"role": "patient", "name": "Siti Aminah", "assignedDoctorId": D},
            D: {"role": "doctor", "name": "Dr Tan"},
            PH: {"role": "pharmacist", "name": "Ahmad"},
            A: {"role": "admin", "name": "Admin"},
            "u-other": {"role": "patient", "name": "Ali"},
        }
    )
    repo.health_profiles[P] = {
        "patientId": P,
        "personalInfo": json.dumps({"phone": "012-345 6789", "heightCm": 160, "weightKg": 60}),
        "medicalHistory": json.dumps(
            {"conditions": ["diabetes"], "familyHistory": [], "allergies": "Penicillin"}
        ),
    }
    for uid in (P, PH, A):
        tokens.add(uid, f"token-{uid}", "android")


def titles(push: LogPushClient, uid: str) -> list[str]:
    return [m.title for toks, m in push.sent if f"token-{uid}" in toks]


def issue(client: TestClient, body: dict[str, Any] | None = None) -> dict[str, Any]:
    res = client.post(RX_URL, json=body or TWO_ITEMS, headers=DOCTOR)
    assert res.status_code == 201, res.text
    return dict(res.json())


def seed_stock(order_repo: InMemoryOrderRepository, amlo: int = 100, losartan: int = 100) -> None:
    order_repo.stock_items.update(
        {
            "s-amlo": {"name": "Amlodipine 5mg", "catalogId": "amlodipine-5", "units": amlo},
            "s-los": {"name": "Losartan 50mg", "catalogId": "losartan-50", "units": losartan},
        }
    )


def pay(client: TestClient, oid: str) -> None:
    client.post(
        f"/api/v1/orders/{oid}/confirm", json={"method": "self_collection"}, headers=PATIENT
    )
    client.post(f"/api/v1/orders/{oid}/pay", headers=PATIENT)
    res = client.post(
        f"/api/v1/orders/{oid}/pay/fake", json={"cardNumber": "4242424242424242"}, headers=PATIENT
    )
    assert res.json()["result"] == "paid"


# ---------------- prescription -> medicines -> order ----------------


def test_consolidated_prescription_prices_from_the_catalogue(
    client: TestClient,
    provider_repo: InMemoryProviderRepository,
    order_repo: InMemoryOrderRepository,
    push: LogPushClient,
) -> None:
    body = issue(client)
    assert body["total"] == 63.0  # 30 x 0.30 + 60 x 0.90
    assert body["medicationDetails"] == (
        "Amlodipine 5mg 1 tablet, once daily x30; Losartan 50mg 1 tablet, twice daily x60"
    )
    rx = provider_repo.prescription(body["id"])
    assert rx is not None and [i["unitPrice"] for i in rx["items"]] == [0.30, 0.90]
    # D-69: an order goes to the pharmacy straight away, even when not recurring.
    o = order_repo.orders[body["orderId"]]
    assert o["amount"] == 63.0 and len(o["items"]) == 2
    assert "Confirm this month's order" in titles(push, P)
    view = client.get(f"/api/v1/orders/{body['orderId']}", headers=PATIENT).json()
    assert [i["lineTotal"] for i in view["items"]] == [9.0, 54.0]


def test_prescribed_medicines_join_the_meds_tab_locked(
    client: TestClient, med_repo: InMemoryMedicationRepository
) -> None:
    rx_id = issue(client)["id"]
    meds = {m["name"]: (k, m) for k, m in med_repo.meds.items()}
    amlo_id, amlo = meds["Amlodipine 5mg"]
    assert amlo["schedule"] == "08:00" and amlo["quantityOnHand"] == 30.0
    assert amlo["source"] == "doctor" and amlo["prescribedBy"] == "Dr Tan"
    assert meds["Losartan 50mg"][1]["schedule"] == "08:00,20:00"
    url = f"/api/v1/medications/{amlo_id}"
    change = {"name": "Amlodipine 5mg", "dosage": "1 tablet", "schedule": "09:00"}
    res = client.put(url, json=change, headers=PATIENT)
    assert res.status_code == 200 and med_repo.meds[amlo_id]["schedule"] == "09:00"
    assert med_repo.meds[amlo_id]["quantityOnHand"] == 30.0  # untouched
    res = client.put(url, json={**change, "dosage": "2 tablets"}, headers=PATIENT)
    assert res.json()["error"]["code"] == "MEDICATION_LOCKED"
    assert client.delete(url, headers=PATIENT).json()["error"]["code"] == "MEDICATION_LOCKED"
    # The doctor stopping the prescription removes its medicines.
    client.delete(f"{RX_URL}/{rx_id}", headers=DOCTOR)
    assert med_repo.meds == {}


def test_self_added_medicines_stay_editable(
    client: TestClient, med_repo: InMemoryMedicationRepository
) -> None:
    res = client.post(
        "/api/v1/medications",
        json={"name": "Vitamin D", "dosage": "1 capsule", "schedule": "08:00"},
        headers=PATIENT,
    )
    mid = res.json()["id"]
    assert client.delete(f"/api/v1/medications/{mid}", headers=PATIENT).status_code == 204


def test_unknown_catalogue_item_and_item_interactions(client: TestClient) -> None:
    bad = {"items": [{"catalogId": "nope", "dose": "1", "frequency": "once_daily", "quantity": 1}]}
    assert client.post(RX_URL, json=bad, headers=DOCTOR).status_code == 404
    risky = {
        "items": [
            {
                "catalogId": "losartan-50",
                "dose": "1 tablet",
                "frequency": "once_daily",
                "quantity": 30,
            },
            {
                "catalogId": "spironolactone-25",
                "dose": "1 tablet",
                "frequency": "once_daily",
                "quantity": 30,
            },
        ]
    }
    res = client.post(RX_URL, json=risky, headers=DOCTOR)
    assert res.status_code == 409 and res.json()["error"]["code"] == "DRUG_INTERACTION"
    res = client.post(RX_URL, json={**risky, "acknowledgeInteractions": True}, headers=DOCTOR)
    assert res.status_code == 201


def test_empty_prescription_is_refused(client: TestClient) -> None:
    assert client.post(RX_URL, json={"isRecurring": True}, headers=DOCTOR).status_code == 422


def test_catalogue_prescriptions_are_not_priced_by_hand(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    rx_id = issue(client)["id"]
    res = client.put(
        f"/api/v1/pharmacy/prescriptions/{rx_id}/price", json={"monthlyPrice": 10}, headers=PHARM
    )
    assert res.json()["error"]["code"] == "PRICED_FROM_CATALOGUE"


# ---------------- stock ----------------


def test_ready_takes_each_item_from_its_catalogue_stock_and_restocks_the_patient(
    client: TestClient,
    order_repo: InMemoryOrderRepository,
    med_repo: InMemoryMedicationRepository,
) -> None:
    oid = issue(client)["orderId"]
    pay(client, oid)
    seed_stock(order_repo)
    res = client.post(f"/api/v1/pharmacy/orders/{oid}/ready", json={}, headers=PHARM)
    assert res.json()["fulfilmentStatus"] == "ready_for_collection", res.text
    assert order_repo.stock_items["s-amlo"]["units"] == 70
    assert order_repo.stock_items["s-los"]["units"] == 40
    client.post(f"/api/v1/pharmacy/orders/{oid}/collected", headers=PHARM)
    on_hand = {m["name"]: m["quantityOnHand"] for m in med_repo.meds.values()}
    assert on_hand == {"Amlodipine 5mg": 60.0, "Losartan 50mg": 120.0}


def test_short_item_is_named_and_nothing_is_taken(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = issue(client)["orderId"]
    pay(client, oid)
    seed_stock(order_repo, losartan=10)
    res = client.post(f"/api/v1/pharmacy/orders/{oid}/ready", json={}, headers=PHARM)
    assert res.json()["error"]["code"] == "INSUFFICIENT_STOCK"
    assert "Losartan 50mg" in res.json()["error"]["message"]
    assert order_repo.stock_items["s-amlo"]["units"] == 100


def test_stock_taken_is_returned_if_a_later_item_fails(
    client: TestClient, order_repo: InMemoryOrderRepository, monkeypatch: pytest.MonkeyPatch
) -> None:
    oid = issue(client)["orderId"]
    pay(client, oid)
    seed_stock(order_repo)
    real = order_repo.take_stock
    monkeypatch.setattr(
        order_repo, "take_stock", lambda sid, n: False if sid == "s-los" else real(sid, n)
    )
    res = client.post(f"/api/v1/pharmacy/orders/{oid}/ready", json={}, headers=PHARM)
    assert res.json()["error"]["code"] == "INSUFFICIENT_STOCK"
    assert order_repo.stock_items["s-amlo"]["units"] == 100


# ---------------- catalogue ----------------


def test_catalogue_listing_and_pricing(
    client: TestClient, catalog: InMemoryCatalogRepository, audit: InMemoryAuditLogger
) -> None:
    items = client.get("/api/v1/catalog", headers=DOCTOR).json()["items"]
    assert [i["name"] for i in items] == ["Amlodipine", "Losartan", "Spironolactone"]
    assert client.get("/api/v1/catalog", headers=PATIENT).status_code == 403
    res = client.patch("/api/v1/catalog/amlodipine-5", json={"unitPrice": 0.35}, headers=PHARM)
    assert res.json()["unitPrice"] == 0.35
    assert (
        client.patch(
            "/api/v1/catalog/amlodipine-5", json={"unitPrice": 1}, headers=DOCTOR
        ).status_code
        == 403
    )
    res = client.post(
        "/api/v1/catalog",
        json={"name": "Olmesartan", "strength": "20mg", "unitPrice": 1.8},
        headers=ADMIN,
    )
    assert res.status_code == 201 and catalog.items[res.json()["id"]]["active"] is True
    assert any(e["action"] == "EDIT_CATALOG_ITEM" for e in audit.entries)


def test_price_change_does_not_alter_an_issued_prescription(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    oid = issue(client)["orderId"]
    client.patch("/api/v1/catalog/amlodipine-5", json={"unitPrice": 5}, headers=PHARM)
    assert order_repo.orders[oid]["amount"] == 63.0


# ---------------- pharmacist patient view ----------------


def test_pharmacist_sees_dispensing_details_of_any_patient(
    client: TestClient, audit: InMemoryAuditLogger
) -> None:
    # D-70: any patient (not only those with an order); staff accounts are not patients.
    assert client.get(f"/api/v1/pharmacy/patients/{P}", headers=PHARM).status_code == 200
    assert client.get(f"/api/v1/pharmacy/patients/{D}", headers=PHARM).status_code == 404
    issue(client)
    d = client.get(f"/api/v1/pharmacy/patients/{P}", headers=PHARM).json()
    assert d["name"] == "Siti Aminah" and d["phone"] == "012-345 6789"
    assert d["allergies"] == "Penicillin" and d["conditions"] == ["diabetes"]
    assert {m["name"] for m in d["medications"]} == {"Amlodipine 5mg", "Losartan 50mg"}
    assert len(d["prescriptions"][0]["items"]) == 2 and len(d["orders"]) == 1
    assert "readings" not in d and "risk" not in d
    assert any(e["action"] == "VIEW_PATIENT_DISPENSING" for e in audit.entries)
    assert client.get(f"/api/v1/pharmacy/patients/{P}", headers=DOCTOR).status_code == 403
    found = client.get("/api/v1/pharmacy/patients?q=siti", headers=PHARM).json()["patients"]
    assert [p["id"] for p in found] == [P]


def test_phone_is_read_from_the_json_string_profile() -> None:
    assert phone_from_profile({"personalInfo": json.dumps({"phone": "0123"})}) == "0123"
    assert phone_from_profile({"personalInfo": {"phone": "0123"}}) == "0123"
    assert phone_from_profile(None) is None


# ---------------- address ----------------


def test_address_is_saved_and_prefills_checkout(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    res = client.put(
        "/api/v1/settings/address",
        json={
            "address": "77 Lorong Lembah Permai 3, Tanjung Bungah",
            "lat": 5.4588,
            "lng": 100.2886,
        },
        headers=PATIENT,
    )
    assert res.status_code == 200
    assert repo.users[P]["addressLat"] == 5.4588
    oid = issue(client)["orderId"]
    view = client.get(f"/api/v1/orders/{oid}", headers=PATIENT).json()
    assert view["suggestedAddress"].startswith("77 Lorong")
    assert view["suggestedLng"] == 100.2886 and view["suggestedPhone"] == "012-345 6789"
    bad = client.put("/api/v1/settings/address", json={"address": "x"}, headers=PATIENT)
    assert bad.status_code == 422


# ---------------- pharmacy chat ----------------


def test_pharmacy_chat_both_ways(
    client: TestClient,
    pharmacy_chat: InMemoryPharmacyChatRepository,
    push: LogPushClient,
    audit: InMemoryAuditLogger,
) -> None:
    # D-70: a pharmacist can start a chat with any patient, but not with staff.
    res = client.post(f"/api/v1/pharmacy-chat/{D}/messages", json={"text": "Hi"}, headers=PHARM)
    assert res.status_code == 404
    res = client.post(
        f"/api/v1/pharmacy-chat/{P}/messages",
        json={"text": "Your refill is ready for collection."},
        headers=PHARM,
    )
    assert res.status_code == 201 and res.json()["senderName"] == "CareFlow Pharmacy (Ahmad)"
    assert "CareFlow Pharmacy" in titles(push, P)
    res = client.post("/api/v1/pharmacy-chat/messages", json={"text": "Thanks!"}, headers=PATIENT)
    assert res.status_code == 201 and "Message from Siti Aminah" in titles(push, PH)
    thread = client.get("/api/v1/pharmacy-chat/messages", headers=PATIENT).json()["messages"]
    assert [m["senderRole"] for m in thread] == ["pharmacist", "patient"]
    convs = client.get("/api/v1/pharmacy-chat/conversations", headers=PHARM).json()
    assert convs["conversations"][0]["patientName"] == "Siti Aminah"
    assert convs["conversations"][0]["text"] == "Thanks!"
    full = client.get(f"/api/v1/pharmacy-chat/{P}/messages", headers=PHARM).json()
    assert len(full["messages"]) == 2
    # Roles and privacy.
    assert client.get("/api/v1/pharmacy-chat/conversations", headers=DOCTOR).status_code == 403
    assert client.get(f"/api/v1/pharmacy-chat/{P}/messages", headers=PATIENT).status_code == 403
    logged = [e for e in audit.entries if e["action"] == "PHARMACY_MESSAGE"]
    assert len(logged) == 2 and all("refill" not in str(e) for e in logged)


# ---------------- D-70 ----------------


def test_d70_patients_tab_lists_every_patient(client: TestClient) -> None:
    issue(client)
    rows = client.get("/api/v1/pharmacy/patients", headers=PHARM).json()["patients"]
    assert [r["name"] for r in rows] == ["Ali", "Siti Aminah"]
    siti = rows[1]
    assert siti["orderCount"] == 1 and siti["activeOrders"] == 1
    found = client.get("/api/v1/pharmacy/patients?q=ali", headers=PHARM).json()["patients"]
    assert [r["id"] for r in found] == ["u-other"]


def test_d70_order_tracking_overview(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    first = issue(client)["orderId"]
    pay(client, first)
    res = client.get("/api/v1/orders-overview", headers=ADMIN).json()
    assert res["counts"]["in_pharmacy"] == 1 and [o["id"] for o in res["orders"]] == [first]
    waiting = client.get("/api/v1/orders-overview?group=awaiting_patient", headers=PHARM).json()[
        "orders"
    ]
    assert waiting == []
    by_name = client.get("/api/v1/orders-overview?q=siti", headers=PHARM).json()["orders"]
    assert len(by_name) == 1
    assert client.get("/api/v1/orders-overview", headers=PATIENT).status_code == 403
    assert client.get("/api/v1/orders-overview", headers=DOCTOR).status_code == 403


def test_d70_catalogue_medicine_can_be_corrected_and_deactivated(
    client: TestClient, catalog: InMemoryCatalogRepository
) -> None:
    res = client.patch(
        "/api/v1/catalog/amlodipine-5",
        json={"name": "Amlodipine besylate", "strength": "5 mg", "form": "tablet", "active": False},
        headers=ADMIN,
    )
    assert res.status_code == 200
    c = catalog.items["amlodipine-5"]
    assert c["name"] == "Amlodipine besylate" and c["active"] is False
    bad = {
        "items": [
            {"catalogId": "amlodipine-5", "dose": "1", "frequency": "once_daily", "quantity": 1}
        ]
    }
    assert client.post(RX_URL, json=bad, headers=DOCTOR).status_code == 404  # inactive


def test_d70_emergency_alert_falls_back_to_the_saved_location(
    client: TestClient, repo: InMemoryUserRepository, family_repo: Any
) -> None:
    repo.users[P].update({"addressLat": 5.4588, "addressLng": 100.2886, "patientId": None})
    repo.users["u-fam"] = {"role": "family_member", "name": "Mum", "patientId": P}
    res = client.post("/api/v1/emergency/sos", json={}, headers=PATIENT)
    assert res.status_code in (200, 201), res.text
    alert = next(iter(family_repo.alerts.values()))
    assert alert["locationSource"] == "saved"
    assert alert["gpsLocation"] == {"lat": 5.4588, "lng": 100.2886}


# ---------------- D-72: gaps from the feature cross-check ----------------


def test_d72_doctor_sees_the_patient_delivery_preference(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    url = f"/api/v1/provider/patients/{P}/delivery"
    assert client.get(url, headers=DOCTOR).json()["method"] is None
    oid = issue(client)["orderId"]
    client.post(
        f"/api/v1/orders/{oid}/confirm", json={"method": "self_collection"}, headers=PATIENT
    )
    body = client.get(url, headers=DOCTOR).json()
    assert body["method"] == "self_collection" and body["orders"] == 1
    assert body["latestStatus"] == "awaiting_payment"
    repo.users[P]["assignedDoctorId"] = "someone-else"
    assert client.get(url, headers=DOCTOR).status_code == 403


def test_d72_estimated_ready_time_is_two_hours_after_payment(
    client: TestClient, order_repo: InMemoryOrderRepository
) -> None:
    from datetime import datetime, timedelta

    oid = issue(client)["orderId"]
    pay(client, oid)
    view = client.get(f"/api/v1/orders/{oid}", headers=PATIENT).json()
    paid = datetime.fromisoformat(view["paidAt"])
    assert datetime.fromisoformat(view["estimatedReadyAt"]) - paid == timedelta(hours=2)


def test_d72_admin_courier_settings_are_read_only(client: TestClient) -> None:
    body = client.get("/api/v1/admin/courier", headers=ADMIN).json()
    assert body["provider"] == "Lalamove" and body["simulated"] is True
    assert body["webhookUrl"].endswith("/api/v1/webhooks/lalamove")
    assert "secret" not in str(body).lower()
    assert client.get("/api/v1/admin/courier", headers=PHARM).status_code == 403


def test_d72_delivery_stats() -> None:
    from app.services.analytics import delivery_stats

    stats = delivery_stats(
        [
            {
                "method": "home_delivery",
                "paymentStatus": "paid",
                "fulfilmentStatus": "delivered",
                "amount": 35.0,
                "deliveryFee": 13.2,
            },
            {
                "method": "self_collection",
                "paymentStatus": "paid",
                "fulfilmentStatus": "collected",
                "amount": 20.0,
                "deliveryFee": 0.0,
            },
            {
                "method": "home_delivery",
                "paymentStatus": "paid",
                "fulfilmentStatus": "failed",
                "amount": 10.0,
                "deliveryFee": 6.8,
            },
            {
                "method": None,
                "paymentStatus": "pending",
                "fulfilmentStatus": "awaiting_confirmation",
                "amount": 15.0,
                "deliveryFee": 0.0,
            },
        ]
    )
    assert stats["orders"] == 4 and stats["homeDelivery"] == 2 and stats["selfCollection"] == 1
    assert (stats["delivered"], stats["collected"], stats["failed"]) == (1, 1, 1)
    assert stats["awaitingPatient"] == 1 and stats["paid"] == 3
    assert stats["revenue"] == 85.0 and stats["averageCourierFee"] == 10.0


def test_d72_agent_offers_the_emergency_contact_number(
    client: TestClient, repo: InMemoryUserRepository
) -> None:
    from app.routers.agent import _emergency_phone

    profile = json.loads(repo.health_profiles[P]["personalInfo"])
    profile["emergencyContact"] = {"name": "Mum", "phone": "013-999 8888", "relationship": "parent"}
    repo.health_profiles[P]["personalInfo"] = json.dumps(profile)

    class Profiles:
        def health_profile(self, uid: str) -> dict[str, Any] | None:
            return repo.health_profiles.get(uid)

    assert _emergency_phone(Profiles(), P) == "013-999 8888"  # type: ignore[arg-type]
    assert _emergency_phone(Profiles(), "nobody") is None  # type: ignore[arg-type]
