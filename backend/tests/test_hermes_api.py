"""Hermes 接入 API — /admin/hermes/chat、/admin/hermes/chat/stream。

issue #33：外部 hermes 配置选项已删除（/admin/hermes/status 与
/admin/hermes/config 端点同步下线），hermes 仅由部署环境的环境变量
（HERMES_BASE_URL 等）配置，指向容器内集成的 hermes。

覆盖：
- 正常路径：对话成功（非流式）、流式对话 SSE 文本
- 边界情况：未认证 401、未配置对话 503、非法消息 422（空列表 / 非法 role / 缺 content）、
  上游错误 502 透传、温度越界 422
- 已下线端点：/status 与 /config 返回 404
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


# --- 已下线端点（issue #33：删除外部 hermes 配置选项） ---


def test_status_endpoint_removed(client, admin_headers):
    """外部 hermes 配置入口已删除：/admin/hermes/status 不再提供。"""
    response = client.get("/admin/hermes/status", headers=admin_headers)
    assert response.status_code == 404


def test_config_endpoint_removed(client, admin_headers):
    """外部 hermes 配置入口已删除：/admin/hermes/config 不再提供。"""
    response = client.put(
        "/admin/hermes/config",
        headers=admin_headers,
        json={"base_url": "https://hermes.example.com/v1", "api_key": "sk-x"},
    )
    assert response.status_code == 404


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


# --- /admin/hermes/chat（保留：容器内集成的 hermes 透传对话） ---
