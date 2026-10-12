from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from app.core.auth import CurrentUser, get_token_verifier, require_roles
from app.core.enums import UserRole
from app.core.errors import register_error_handlers
from tests.conftest import fake_verify


def test_fr_1_3_missing_token_is_401(client: TestClient) -> None:
    res = client.get("/api/v1/health/auth")
    assert res.status_code == 401
    assert res.json()["error"]["code"] == "UNAUTHENTICATED"


def test_fr_1_3_invalid_token_is_401(client: TestClient) -> None:
    res = client.get("/api/v1/health/auth", headers={"Authorization": "Bearer forged"})
    assert res.status_code == 401
    assert res.json()["error"]["code"] == "UNAUTHENTICATED"


def test_fr_1_3_valid_token_exposes_role_claim(client: TestClient) -> None:
    res = client.get("/api/v1/health/auth", headers={"Authorization": "Bearer doctor-token"})
    assert res.status_code == 200
    assert res.json() == {"status": "ok", "uid": "u-doctor", "role": "doctor"}


def test_fr_1_3_token_without_role_claim_has_null_role(client: TestClient) -> None:
    res = client.get("/api/v1/health/auth", headers={"Authorization": "Bearer norole-token"})
    assert res.status_code == 200
    assert res.json()["role"] is None


def _role_app() -> TestClient:
    app = FastAPI()
    register_error_handlers(app)

    @app.get("/admin-only")
    def admin_only(user: CurrentUser = Depends(require_roles(UserRole.ADMIN))) -> dict[str, str]:
        return {"uid": user.uid}

    app.dependency_overrides[get_token_verifier] = lambda: fake_verify
    return TestClient(app)


def test_fr_1_3_require_roles_allows_matching_role() -> None:
    res = _role_app().get("/admin-only", headers={"Authorization": "Bearer admin-token"})
    assert res.status_code == 200


def test_fr_1_3_require_roles_rejects_other_role() -> None:
    res = _role_app().get("/admin-only", headers={"Authorization": "Bearer patient-token"})
    assert res.status_code == 403
    assert res.json()["error"]["code"] == "FORBIDDEN"


def test_fr_1_3_require_roles_rejects_missing_role() -> None:
    res = _role_app().get("/admin-only", headers={"Authorization": "Bearer norole-token"})
    assert res.status_code == 403
