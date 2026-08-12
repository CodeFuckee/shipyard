"""Agent 流式 API 与工具列表 — /admin/agent/tools、/admin/agent/chat/stream。

覆盖：
- 正常路径：工具列表（skills 2 个 + MCP 工具 33 个）、SSE 流式对话事件序列
- 边界情况：未认证 401、hermes 未配置 503、非法参数 422
  （空 messages / 非法 role / 缺 content / 空 tools / 全空白 tools / max_iterations 越界）、
  未知工具名 400、上游异常转为 SSE error 事件
"""

import asyncio

import pytest

from app.agent import service
from app.services import hermes_client


@pytest.fixture(autouse=True)
def hermes_env(monkeypatch):
    """默认配置一个可用的 hermes 实例。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "https://hermes.example.com/v1")
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "sk-hermes-test")
    monkeypatch.setattr(hermes_client, "HERMES_MODEL", "hermes-chat")


# --- /admin/agent/tools ---


def test_tools_requires_auth(client):
    response = client.get("/admin/agent/tools")
    assert response.status_code == 401


def test_tools_returns_skills_and_mcp_tools(client, admin_headers):
    response = client.get("/admin/agent/tools", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    skills = data["skills"]
    assert [s["name"] for s in skills] == ["docker_mirror_pull", "docker_pull_from_file"]
    assert all(s["description"] for s in skills)
    tools = data["tools"]
    assert len(tools) == 33
    assert all(t["name"] and t["description"] and t["group"] for t in tools)


# --- /admin/agent/chat/stream ---


def _parse_sse(lines):
    """解析 SSE 行序列为事件列表 [(event, data), ...]。"""
    events = []
    event = None
    data_lines = []
    for line in lines:
        if line == "":
            if event is not None:
                events.append((event, "\n".join(data_lines)))
            event = None
            data_lines = []
            continue
        if line.startswith("event:"):
            event = line[len("event:"):].strip()
        elif line.startswith("data:"):
            data_lines.append(line[len("data:"):].strip())
    if event is not None:
        events.append((event, "\n".join(data_lines)))
    return events


def test_stream_requires_auth(client):
    response = client.post(
        "/admin/agent/chat/stream", json={"messages": [{"role": "user", "content": "hi"}]}
    )
    assert response.status_code == 401


def test_stream_when_not_configured(client, admin_headers, monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 503


def test_stream_empty_messages(client, admin_headers):
    response = client.post(
        "/admin/agent/chat/stream", headers=admin_headers, json={"messages": []}
    )
    assert response.status_code == 422


def test_stream_invalid_role(client, admin_headers):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "superuser", "content": "hi"}]},
    )
    assert response.status_code == 422


def test_stream_missing_content(client, admin_headers):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user"}]},
    )
    assert response.status_code == 422


def test_stream_empty_tools(client, admin_headers):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}], "tools": []},
    )
    assert response.status_code == 422


def test_stream_blank_tools(client, admin_headers):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}], "tools": [" ", ""]},
    )
    assert response.status_code == 422


def test_stream_invalid_max_iterations(client, admin_headers):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}], "max_iterations": 0},
    )
    assert response.status_code == 422


def test_stream_unknown_tool_returns_400(client, admin_headers):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}], "tools": ["not_a_tool"]},
    )
    assert response.status_code == 400


def _collect_stream(messages, tools_names=None, max_iterations=None):
    """同步收集 async 生成器 stream_agent 的全部事件。"""

    async def _collect():
        return [
            event
            async for event in service.stream_agent(
                messages, tools_names=tools_names, max_iterations=max_iterations
            )
        ]

    return asyncio.run(_collect())


def test_stream_success_emits_expected_events(client, admin_headers, monkeypatch):
    """正常路径：mock stream_agent 产生完整事件序列，验证 SSE 帧格式与顺序。"""

    async def fake_stream_agent(messages, tools_names=None, max_iterations=None):
        yield {"type": "token", "content": "你好"}
        yield {"type": "step", "name": "list_containers", "arguments": {"summary": True}}
        yield {"type": "step_result", "name": "list_containers", "result": "[1 个容器]"}
        yield {"type": "token", "content": "，共 1 个容器"}
        yield {"type": "reply", "content": "你好，共 1 个容器"}
        yield {"type": "done"}

    monkeypatch.setattr(service, "stream_agent", fake_stream_agent)
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "看看容器"}], "tools": ["list_containers"]},
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")

    events = _parse_sse(response.text.splitlines())
    types = [e[0] for e in events]
    assert types == ["token", "step", "step_result", "token", "reply", "done"]
    assert events[0][1] == '{"content": "你好"}'
    assert events[1][1] == '{"name": "list_containers", "arguments": {"summary": true}}'
    assert events[5][1] == "{}"


def test_stream_upstream_error_yields_error_event(client, admin_headers, monkeypatch):
    """上游 hermes 异常：转为 SSE error 事件，HTTP 仍 200（流内错误）。"""

    async def failing_stream_agent(messages, tools_names=None, max_iterations=None):
        yield {"type": "error", "message": "hermes 请求失败（500）"}

    monkeypatch.setattr(service, "stream_agent", failing_stream_agent)
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 200
    events = _parse_sse(response.text.splitlines())
    assert events[0][0] == "error"
    assert "hermes" in events[0][1]


# --- service.stream_agent（直接调用） ---


class FakeAgent:
    """假 agent：提供 astream_events 事件流。"""

    def __init__(self, events):
        self._events = events

    def build_input(self, messages):
        return {"messages": messages}

    async def astream_events(self, inputs, version=None, config=None):
        for ev in self._events:
            yield ev


def _model_stream_event(content):
    return {"event": "on_chat_model_stream", "data": {"chunk": type("C", (), {"content": content})()}, "metadata": {"langgraph_node": "model"}}


def _tool_start_event(name, args):
    return {"event": "on_tool_start", "name": name, "data": {"input": args}}


def _tool_end_event(name, output):
    return {"event": "on_tool_end", "name": name, "data": {"output": output}}


def _chain_end_event(final_content):
    message = type("M", (), {"content": final_content})()
    return {"event": "on_chain_end", "name": "agent", "data": {"output": {"messages": [message]}}}


def test_stream_agent_event_sequence(monkeypatch):
    """token / step / step_result / reply / done 序列。"""
    events = [
        _model_stream_event("你"),
        _model_stream_event("好"),
        _tool_start_event("list_containers", {"summary": True}),
        _tool_end_event("list_containers", "[1 个容器]"),
        _model_stream_event("，共 1 个"),
        _chain_end_event("你好，共 1 个容器"),
    ]
    monkeypatch.setattr(service, "build_agent", lambda tools_names=None, system_prompt=None: FakeAgent(events))

    collected = _collect_stream([{"role": "user", "content": "hi"}])
    types = [c["type"] for c in collected]
    assert types == ["token", "token", "step", "step_result", "token", "reply", "done"]
    assert collected[0]["content"] == "你"
    assert collected[2]["name"] == "list_containers"
    assert collected[3]["result"] == "[1 个容器]"
    assert collected[5]["content"] == "你好，共 1 个容器"


def test_stream_agent_skips_empty_token(monkeypatch):
    """空 content 的 token 事件应被过滤（工具调用时 chunk 无文本）。"""
    events = [
        _model_stream_event(""),  # 工具调用的空 token
        _tool_start_event("list_images", {}),
        _tool_end_event("list_images", "[]"),
        _chain_end_event("共 0 个镜像"),
    ]
    monkeypatch.setattr(service, "build_agent", lambda tools_names=None, system_prompt=None: FakeAgent(events))

    collected = _collect_stream([{"role": "user", "content": "hi"}])
    types = [c["type"] for c in collected]
    assert types == ["step", "step_result", "reply", "done"]
    assert collected[-2]["content"] == "共 0 个镜像"


def test_stream_agent_build_failure_yields_error(monkeypatch):
    """build_agent 抛 HermesNotConfiguredError → 仅 error 事件。"""

    def raise_error(tools_names=None, system_prompt=None):
        raise hermes_client.HermesNotConfiguredError()

    monkeypatch.setattr(service, "build_agent", raise_error)
    collected = _collect_stream([{"role": "user", "content": "hi"}])
    assert [c["type"] for c in collected] == ["error"]
    assert "未配置" in collected[0]["message"]


def test_stream_agent_reply_fallback_when_no_tokens(monkeypatch):
    """LLM 直接返回最终答案（无 token 流、无工具调用）：reply 事件携带完整回复。"""
    events = [_chain_end_event("直接回答")]
    monkeypatch.setattr(service, "build_agent", lambda tools_names=None, system_prompt=None: FakeAgent(events))

    collected = _collect_stream([{"role": "user", "content": "hi"}])
    assert [c["type"] for c in collected] == ["reply", "done"]
    assert collected[0]["content"] == "直接回答"
