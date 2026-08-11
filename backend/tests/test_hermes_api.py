"""Hermes 接入 API — /admin/hermes/status、/admin/hermes/chat、/admin/hermes/chat/stream。

覆盖：
- 正常路径：状态查询（已配置 / 未配置）、对话成功（非流式）、流式对话 SSE 文本
- 边界情况：未认证 401、未配置对话 503、非法消息 422（空列表 / 非法 role / 缺 content）、
  上游错误 502 透传、温度越界 422
"""

import pytest

from app.services import hermes_client


@pytest.fixture(autouse=True)
def hermes_env(monkeypatch):
    """默认配置一个可用的 hermes 实例。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "https://hermes.example.com/v1")
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "sk-hermes-test")
    monkeypatch.setattr(hermes_client, "HERMES_MODEL", "hermes-chat")


def _auth_headers(admin_headers):
    return dict(admin_headers)


# --- /admin/hermes/status ---


def test_status_requires_auth(client):
    response = client.get("/admin/hermes/status")
    assert response.status_code == 401


def test_status_when_not_configured(client, admin_headers, monkeypatch):
    """base_url 与 api_key 均未配置：整体未启用。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "")
    response = client.get("/admin/hermes/status", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["enabled"] is False
    assert data["base_url"] == ""
    assert data["api_key_configured"] is False
    assert data["test"]["ok"] is False
    assert "HERMES_BASE_URL" in data["test"]["message"]


def test_status_key_configured_but_url_missing(client, admin_headers, monkeypatch):
    """只配了 Key 未配地址：仍视为未启用，但如实报告 Key 已配置。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    response = client.get("/admin/hermes/status", headers=admin_headers)
    data = response.json()
    assert data["enabled"] is False
    assert data["api_key_configured"] is True


def test_status_when_configured(client, admin_headers, monkeypatch):
    monkeypatch.setattr(
        hermes_client, "test_connection", lambda: {"ok": True, "message": "连接成功"}
    )
    response = client.get("/admin/hermes/status", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["enabled"] is True
    assert data["base_url"] == "https://hermes.example.com/v1"
    assert data["model"] == "hermes-chat"
    assert data["api_key_configured"] is True
    assert data["test"] == {"ok": True, "message": "连接成功"}


def test_status_never_exposes_api_key(client, admin_headers):
    """任何响应不得包含 API Key 明文。"""
    response = client.get("/admin/hermes/status", headers=admin_headers)
    data = response.json()
    assert "api_key" not in data
    assert "sk-hermes-test" not in response.text


# --- /admin/hermes/chat ---


def test_chat_success(client, admin_headers, monkeypatch):
    def fake_chat(messages, model=None, temperature=0.7):
        assert messages == [{"role": "user", "content": "你好"}]
        assert model == "custom-model"
        assert temperature == 0.2
        return {
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [{"message": {"role": "assistant", "content": "你好"}}],
        }

    monkeypatch.setattr(hermes_client, "chat_completion", fake_chat)
    response = client.post(
        "/admin/hermes/chat",
        headers=admin_headers,
        json={
            "messages": [{"role": "user", "content": "你好"}],
            "model": "custom-model",
            "temperature": 0.2,
        },
    )
    assert response.status_code == 200
    assert response.json()["choices"][0]["message"]["content"] == "你好"


def test_chat_not_configured_returns_503(client, admin_headers, monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    response = client.post(
        "/admin/hermes/chat", headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 503
    assert "HERMES_BASE_URL" in response.json()["detail"]


def test_chat_upstream_error_returns_502(client, admin_headers, monkeypatch):
    def fake_chat(messages, model=None, temperature=0.7):
        raise hermes_client.HermesError("hermes API Key 无效或被拒绝（401）", status_code=502)

    monkeypatch.setattr(hermes_client, "chat_completion", fake_chat)
    response = client.post(
        "/admin/hermes/chat", headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 502
    assert "401" in response.json()["detail"]


def test_chat_empty_messages_422(client, admin_headers):
    response = client.post(
        "/admin/hermes/chat", headers=admin_headers, json={"messages": []}
    )
    assert response.status_code == 422


def test_chat_invalid_role_422(client, admin_headers):
    response = client.post(
        "/admin/hermes/chat", headers=admin_headers,
        json={"messages": [{"role": "robot", "content": "hi"}]},
    )
    assert response.status_code == 422
    assert "role" in response.text


def test_chat_missing_content_422(client, admin_headers):
    response = client.post(
        "/admin/hermes/chat", headers=admin_headers,
        json={"messages": [{"role": "user"}]},
    )
    assert response.status_code == 422


def test_chat_temperature_out_of_range_422(client, admin_headers):
    response = client.post(
        "/admin/hermes/chat", headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}], "temperature": 3.0},
    )
    assert response.status_code == 422


# --- /admin/hermes/chat/stream ---


def test_chat_stream_success(client, admin_headers, monkeypatch):
    def fake_stream(messages, model=None, temperature=0.7):
        assert messages == [{"role": "user", "content": "hi"}]
        yield {"type": "delta", "content": "你"}
        yield {"type": "delta", "content": "好"}
        yield {"type": "done"}

    monkeypatch.setattr(hermes_client, "stream_chat_completion", fake_stream)
    response = client.post(
        "/admin/hermes/chat/stream", headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")
    lines = response.text.splitlines()
    assert 'data: {"type": "delta", "content": "你"}' in lines
    assert 'data: {"type": "delta", "content": "好"}' in lines
    assert 'data: {"type": "done"}' in lines
    assert "data: [DONE]" in lines


def test_chat_stream_not_configured_returns_503(client, admin_headers, monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    response = client.post(
        "/admin/hermes/chat/stream", headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 503


def test_chat_stream_error_event_passthrough(client, admin_headers, monkeypatch):
    def fake_stream(messages, model=None, temperature=0.7):
        yield {"type": "error", "message": "hermes 请求失败: boom"}

    monkeypatch.setattr(hermes_client, "stream_chat_completion", fake_stream)
    response = client.post(
        "/admin/hermes/chat/stream", headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 200
    assert '"type": "error"' in response.text
    assert "boom" in response.text
