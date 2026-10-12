from typing import cast

from fastapi.testclient import TestClient
from httpx import Response

from tests.conftest import MakeClient, dev_settings


def _preflight(client: TestClient, origin: str) -> Response:
    res = client.options(
        "/api/v1/health",
        headers={"Origin": origin, "Access-Control-Request-Method": "GET"},
    )
    return cast(Response, res)


def test_inc0_dev_cors_allows_any_localhost_port(make_client: MakeClient) -> None:
    res = _preflight(make_client(dev_settings()), "http://localhost:53122")
    assert res.headers.get("access-control-allow-origin") == "http://localhost:53122"


def test_inc0_dev_cors_rejects_other_origins(make_client: MakeClient) -> None:
    res = _preflight(make_client(dev_settings()), "https://evil.example.com")
    assert "access-control-allow-origin" not in res.headers


def test_inc0_prod_has_no_cors(make_client: MakeClient) -> None:
    res = _preflight(make_client(dev_settings(app_env="prod")), "http://localhost:53122")
    assert "access-control-allow-origin" not in res.headers
