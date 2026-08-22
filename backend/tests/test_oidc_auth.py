"""OIDC 统一身份认证接口的回归测试。"""

from types import SimpleNamespace

from app.core import oidc

OIDC_ENV = {
    "OIDC_ISSUER": "https://idp.example.test/realms/shipyard",
    "OIDC_CLIENT_ID": "shipyard-client",
    "OIDC_CLIENT_SECRET": "client-secret",
    "OIDC_REDIRECT_URIS": "https://shipyard.example.test/oidc/callback,shipyard://oidc/callback",
}


def _configure_oidc(monkeypatch):
    for key, value in OIDC_ENV.items():
        monkeypatch.setattr(oidc, key, value)
    oidc.reset_discovery_cache()


def _discovery_response():
    return {
        "issuer": OIDC_ENV["OIDC_ISSUER"],
        "authorization_endpoint": f"{OIDC_ENV['OIDC_ISSUER']}/protocol/openid-connect/auth",
        "token_endpoint": f"{OIDC_ENV['OIDC_ISSUER']}/protocol/openid-connect/token",
        "jwks_uri": f"{OIDC_ENV['OIDC_ISSUER']}/protocol/openid-connect/certs",
    }


def test_oidc_config_disabled_without_required_environment(client, monkeypatch):
    monkeypatch.setattr(oidc, "OIDC_ISSUER", "")
    monkeypatch.setattr(oidc, "OIDC_CLIENT_ID", "")
    oidc.reset_discovery_cache()

    response = client.get("/admin/oidc/config")

    assert response.status_code == 200
    assert response.json() == {"enabled": False}


def test_oidc_config_exposes_only_safe_public_configuration(client, monkeypatch):
    _configure_oidc(monkeypatch)
    monkeypatch.setattr(
        oidc.requests,
        "get",
        lambda *args, **kwargs: SimpleNamespace(
            raise_for_status=lambda: None, json=_discovery_response
        ),
    )

    response = client.get("/admin/oidc/config")

    assert response.status_code == 200
    assert response.json() == {
        "enabled": True,
        "issuer": OIDC_ENV["OIDC_ISSUER"],
        "client_id": OIDC_ENV["OIDC_CLIENT_ID"],
        "authorization_endpoint": _discovery_response()["authorization_endpoint"],
        "scopes": ["openid", "profile", "email"],
    }
    assert "client-secret" not in response.text


def test_oidc_exchange_creates_subject_specific_api_key(client, monkeypatch):
    _configure_oidc(monkeypatch)
    monkeypatch.setattr(
        oidc,
        "exchange_code_for_identity",
        lambda **kwargs: {"sub": "alice", "preferred_username": "Alice"},
    )
    payload = {
        "code": "authorization-code",
        "code_verifier": "v" * 43,
        "nonce": "n" * 16,
        "redirect_uri": "https://shipyard.example.test/oidc/callback",
    }

    first = client.post("/admin/oidc/exchange", json=payload)
    second = client.post("/admin/oidc/exchange", json=payload)

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["api_key"] == second.json()["api_key"]
    assert first.json()["authentication_method"] == "oidc"
    assert first.json()["subject"] == "alice"
    assert first.json()["note"] == "OIDC: Alice (alice)"


def test_oidc_identity_uses_issuer_and_subject_unique_index():
    from sqlalchemy import create_engine, inspect

    from app.db.database import Base

    engine = create_engine("sqlite://")
    Base.metadata.create_all(bind=engine)
    indexes = inspect(engine).get_indexes("oidc_identities")

    assert any(
        index["unique"] and index["column_names"] == ["issuer", "subject"]
        for index in indexes
    )


def test_oidc_exchange_keeps_identities_separate_between_issuers(client, monkeypatch):
    _configure_oidc(monkeypatch)
    monkeypatch.setattr(
        oidc,
        "exchange_code_for_identity",
        lambda **kwargs: {"sub": "same-subject", "preferred_username": "Alice"},
    )
    payload = {
        "code": "authorization-code",
        "code_verifier": "v" * 43,
        "nonce": "n" * 16,
        "redirect_uri": "shipyard://oidc/callback",
    }

    first = client.post("/admin/oidc/exchange", json=payload)
    monkeypatch.setattr(oidc, "OIDC_ISSUER", "https://second-idp.example.test")
    second = client.post("/admin/oidc/exchange", json=payload)

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["api_key"] != second.json()["api_key"]


def test_oidc_exchange_uses_stable_subject_when_display_name_changes(
    client, monkeypatch
):
    _configure_oidc(monkeypatch)
    identities = iter(
        [
            {"sub": "alice", "preferred_username": "Alice"},
            {"sub": "alice", "preferred_username": "Alice Updated"},
        ]
    )
    monkeypatch.setattr(
        oidc, "exchange_code_for_identity", lambda **kwargs: next(identities)
    )
    payload = {
        "code": "authorization-code",
        "code_verifier": "v" * 43,
        "nonce": "n" * 16,
        "redirect_uri": "shipyard://oidc/callback",
    }

    first = client.post("/admin/oidc/exchange", json=payload)
    second = client.post("/admin/oidc/exchange", json=payload)

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["api_key"] == second.json()["api_key"]
    assert second.json()["note"] == "OIDC: Alice Updated (alice)"


def test_oidc_exchange_rejects_unregistered_callback(client, monkeypatch):
    _configure_oidc(monkeypatch)
    response = client.post(
        "/admin/oidc/exchange",
        json={
            "code": "authorization-code",
            "code_verifier": "v" * 43,
            "nonce": "n" * 16,
            "redirect_uri": "https://attacker.example/callback",
        },
    )

    assert response.status_code == 400
    assert "回调地址" in response.json()["detail"]


def test_oidc_exchange_rejects_missing_or_too_short_pkce_values(client, monkeypatch):
    _configure_oidc(monkeypatch)
    base_payload = {
        "code": "authorization-code",
        "code_verifier": "v" * 43,
        "nonce": "n" * 16,
        "redirect_uri": "shipyard://oidc/callback",
    }

    for field, value in (("code", ""), ("code_verifier", "short"), ("nonce", "")):
        payload = {**base_payload, field: value}
        response = client.post("/admin/oidc/exchange", json=payload)
        assert response.status_code == 422
