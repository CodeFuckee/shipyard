"""镜像拉取 Agent API — /admin/agent/status、/admin/agent/chat。

覆盖：
- 正常路径：状态查询（未配置 / 已配置）、对话成功（返回 reply + steps）
- 边界情况：未认证 401、未配置对话 503、非法消息 422（空列表 / 非法 role / 缺 content）、
  上游错误 502 透传
"""

import pytest
from langchain_core.messages import AIMessage

from app.agent import service
from app.agent.mirror_sources import DEFAULT_MIRROR_PREFIXES
from app.services import hermes_client


@pytest.fixture(autouse=True)
def hermes_env(monkeypatch):
    """默认配置一个可用的 hermes 实例。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "https://hermes.example.com/v1")
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "sk-hermes-test")
    monkeypatch.setattr(hermes_client, "HERMES_MODEL", "hermes-chat")


class FakeAgent:
    """假 agent：invoke 返回固定消息列表。"""

    def __init__(self, messages):
        self.messages = messages

    def invoke(self, inputs, config=None):
        return {"messages": self.messages}


@pytest.fixture
def fake_build_agent(monkeypatch):
    def install(messages):
        agent = FakeAgent(messages)
        monkeypatch.setattr(service, "build_agent", lambda model=None: agent)
        return agent

    return install


# --- /admin/agent/status ---


def test_status_requires_auth(client):
    response = client.get("/admin/agent/status")
    assert response.status_code == 401


def test_status_when_not_configured(client, admin_headers, monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    response = client.get("/admin/agent/status", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["enabled"] is False
    assert data["tools"] == ["docker_mirror_pull", "docker_pull_from_file"]
    assert data["mirror_prefixes"] == DEFAULT_MIRROR_PREFIXES


def test_status_when_configured(client, admin_headers):
    response = client.get("/admin/agent/status", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["enabled"] is True
    assert data["base_url"] == "https://hermes.example.com/v1"
    assert data["model"] == "hermes-chat"
    assert data["tools"] == ["docker_mirror_pull", "docker_pull_from_file"]
    assert "mirror_prefixes" in data


# --- /admin/agent/chat ---


def test_chat_requires_auth(client):
    response = client.post("/admin/agent/chat", json={"messages": [{"role": "user", "content": "hi"}]})
    assert response.status_code == 401


def test_chat_when_not_configured(client, admin_headers, monkeypatch):
    """LLM 未配置：结构化 503，error_code 供前端引导配置（issue #23 第三轮）。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "帮我拉取 nginx"}]},
    )
    assert response.status_code == 503
    body = response.json()
    assert body["error_code"] == "llm_not_configured"
    assert "未配置" in body["detail"]


def test_chat_success(client, admin_headers, fake_build_agent):
    fake_build_agent(
        [
            AIMessage(content="我来拉取这个镜像。", type="ai"),
            AIMessage(content="✅ 已通过 docker.m.daocloud.io 拉取 nginx:1.25", type="ai"),
        ]
    )
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "帮我拉取 nginx:1.25"}]},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["reply"] == "✅ 已通过 docker.m.daocloud.io 拉取 nginx:1.25"
    assert len(data["steps"]) == 2
    assert data["steps"][0]["role"] == "ai"


def test_chat_empty_messages(client, admin_headers):
    response = client.post("/admin/agent/chat", headers=admin_headers, json={"messages": []})
    assert response.status_code == 422


def test_chat_invalid_role(client, admin_headers):
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "superuser", "content": "hi"}]},
    )
    assert response.status_code == 422


def test_chat_missing_content(client, admin_headers):
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user"}]},
    )
    assert response.status_code == 422


def test_chat_invalid_max_iterations(client, admin_headers):
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}], "max_iterations": 0},
    )
    assert response.status_code == 422


def test_chat_upstream_error(client, admin_headers, monkeypatch):
    def raise_error(model=None):
        raise hermes_client.HermesError("hermes 请求失败（500）", status_code=502)

    monkeypatch.setattr(service, "build_agent", raise_error)
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "帮我拉取 nginx"}]},
    )
    assert response.status_code == 502
