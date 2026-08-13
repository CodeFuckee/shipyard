"""AI Agent 调试日志 — 记录、查询、清理（issue #24）。

设置页「AI 调试日志」的数据源：每次对话（流式与非流式）在路由层记录
结构化调试信息到 agent_chat_logs 表，保留最近 100 条自动清理。

覆盖：
- 记录/查询/清理模块函数：正常路径、边界（未知 id、空表清空幂等、
  超过 100 条自动清理最旧记录）
- API 端点：401 未认证、空列表、列表仅摘要、详情全字段、404、清空
- chat 集成：非流式成功记录、LLM 未配置 503 记录 error、流式成功/失败记录
"""

import json
from datetime import datetime, timedelta

import pytest
from langchain_core.messages import AIMessage, ToolMessage

from app.agent import service
from app.agent.debug_log import (
    AgentChatLogModel,
    clear_logs,
    get_log,
    list_logs,
    record_agent_log,
)
from app.services import hermes_client


@pytest.fixture(autouse=True)
def hermes_env(monkeypatch):
    """默认配置一个可用的 hermes 实例。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "https://hermes.example.com/v1")
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "sk-hermes-test")
    monkeypatch.setattr(hermes_client, "HERMES_MODEL", "hermes-chat")


def _sample_log_kwargs(**overrides):
    """构造一条标准记录参数（缺省为 success）。"""
    kwargs = dict(
        request_messages=[{"role": "user", "content": "帮我拉取 nginx 镜像"}],
        request_text="帮我拉取 nginx 镜像",
        llm_config={"source": "hermes", "name": "Hermes", "model": "hermes-chat"},
        tools_names=["docker_mirror_pull"],
        status="success",
        error_message="",
        duration_ms=1234,
        events=[
            {"type": "step", "name": "docker_mirror_pull", "arguments": {"image": "nginx"}},
            {"type": "step_result", "name": "docker_mirror_pull", "result": "拉取成功"},
        ],
        reply="好的，已拉取 nginx 镜像",
    )
    kwargs.update(overrides)
    return kwargs


def _insert_log(db_session, index=0, **overrides):
    """插入一条记录（index 用于错开 created_at），返回 id。"""
    record_agent_log(
        db_session,
        created_at=datetime(2026, 8, 13, 10, 0, 0) + timedelta(seconds=index),
        **_sample_log_kwargs(**overrides),
    )
    db_session.commit()
    return (
        db_session.query(AgentChatLogModel)
        .order_by(AgentChatLogModel.created_at.desc())
        .first()
        .id
    )


# --- 模块函数：记录 / 查询 / 清理 ---


def test_record_and_list_fields_complete(db_session):
    record_agent_log(db_session, **_sample_log_kwargs())
    db_session.commit()

    logs = list_logs(db_session)
    assert len(logs) == 1
    log = logs[0]
    assert log["id"]
    assert log["created_at"].startswith("2026-")
    assert log["request_text"] == "帮我拉取 nginx 镜像"
    assert log["llm_source"] == "hermes"
    assert log["llm_name"] == "Hermes"
    assert log["llm_model"] == "hermes-chat"
    assert log["status"] == "success"
    assert log["duration_ms"] == 1234


def test_record_error_status(db_session):
    record_agent_log(
        db_session,
        **_sample_log_kwargs(
            status="error",
            error_message="Agent 执行异常：超时",
            events=[],
            reply="",
        ),
    )
    db_session.commit()

    log_id = (
        db_session.query(AgentChatLogModel)
        .order_by(AgentChatLogModel.created_at.desc())
        .first()
        .id
    )
    log = get_log(db_session, log_id)
    assert log["status"] == "error"
    assert "超时" in log["error_message"]


def test_list_orders_by_latest_first(db_session):
    _insert_log(db_session, index=0)
    _insert_log(db_session, index=1)
    db_session.commit()

    logs = list_logs(db_session)
    assert len(logs) == 2
    assert logs[0]["created_at"] > logs[1]["created_at"]


def test_prune_keeps_latest_100(db_session):
    """插入 105 条 → 仅保留最新 100 条，最旧 5 条被清理。"""
    for i in range(105):
        _insert_log(db_session, index=i)
    db_session.commit()

    rows = db_session.query(AgentChatLogModel).all()
    assert len(rows) == 100
    oldest = min(r.created_at for r in rows)
    assert oldest == datetime(2026, 8, 13, 10, 0, 5)  # index 0-4 已被删


def test_get_log_full_detail(db_session):
    log_id = _insert_log(db_session, index=0)
    db_session.commit()

    log = get_log(db_session, log_id)
    assert log["id"] == log_id
    # 详情含完整请求消息、事件序列与回复全文（get_log 返回已解析对象）
    assert log["messages"][0]["content"] == "帮我拉取 nginx 镜像"
    assert log["events"][0]["type"] == "step"
    assert log["events"][0]["name"] == "docker_mirror_pull"
    assert log["reply"] == "好的，已拉取 nginx 镜像"
    assert log["tools_names"] == ["docker_mirror_pull"]


def test_get_unknown_log_returns_none(db_session):
    assert get_log(db_session, "no-such-id") is None


def test_clear_logs_removes_all_and_idempotent(db_session):
    _insert_log(db_session, index=0)
    _insert_log(db_session, index=1)
    db_session.commit()

    deleted = clear_logs(db_session)
    assert deleted == 2
    assert list_logs(db_session) == []
    # 空表再次清空：幂等返回 0
    assert clear_logs(db_session) == 0


def test_record_without_llm_config_and_empty_events(db_session):
    """边界：无 LLM 配置来源、无事件、空回复、0 耗时。"""
    record_agent_log(
        db_session,
        request_messages=[],
        request_text="",
        llm_config=None,
        tools_names=None,
        status="error",
        error_message="LLM 未配置",
        duration_ms=0,
        events=[],
        reply="",
    )
    db_session.commit()

    logs = list_logs(db_session)
    assert len(logs) == 1
    assert logs[0]["llm_source"] is None
    assert logs[0]["duration_ms"] == 0


# --- API 端点 ---


def test_debug_logs_list_requires_auth(client):
    response = client.get("/admin/agent/debug-logs")
    assert response.status_code == 401


def test_debug_logs_detail_requires_auth(client, db_session):
    log_id = _insert_log(db_session, index=0)
    db_session.commit()
    response = client.get(f"/admin/agent/debug-logs/{log_id}")
    assert response.status_code == 401


def test_debug_logs_clear_requires_auth(client):
    response = client.delete("/admin/agent/debug-logs")
    assert response.status_code == 401


def test_debug_logs_list_empty(client, admin_headers):
    response = client.get("/admin/agent/debug-logs", headers=admin_headers)
    assert response.status_code == 200
    assert response.json() == {"logs": []}


def test_debug_logs_list_returns_summary_only(client, admin_headers, db_session):
    """列表只返回摘要字段，不含大体积的 messages/events/reply。"""
    _insert_log(db_session, index=0)
    db_session.commit()

    response = client.get("/admin/agent/debug-logs", headers=admin_headers)
    assert response.status_code == 200
    logs = response.json()["logs"]
    assert len(logs) == 1
    summary = logs[0]
    assert set(summary.keys()) == {
        "id",
        "created_at",
        "request_text",
        "llm_source",
        "llm_name",
        "llm_model",
        "status",
        "duration_ms",
    }
    assert summary["status"] == "success"


def test_debug_logs_detail_returns_full_fields(client, admin_headers, db_session):
    log_id = _insert_log(db_session, index=0)
    db_session.commit()

    response = client.get(f"/admin/agent/debug-logs/{log_id}", headers=admin_headers)
    assert response.status_code == 200
    detail = response.json()
    assert detail["id"] == log_id
    assert detail["reply"] == "好的，已拉取 nginx 镜像"
    assert detail["error_message"] == ""
    assert detail["events"][1]["type"] == "step_result"
    assert detail["messages"][0]["role"] == "user"


def test_debug_logs_detail_not_found(client, admin_headers):
    response = client.get("/admin/agent/debug-logs/no-such-id", headers=admin_headers)
    assert response.status_code == 404


def test_debug_logs_clear(client, admin_headers, db_session):
    _insert_log(db_session, index=0)
    _insert_log(db_session, index=1)
    db_session.commit()

    response = client.delete("/admin/agent/debug-logs", headers=admin_headers)
    assert response.status_code == 200
    assert response.json() == {"deleted": 2}

    response = client.get("/admin/agent/debug-logs", headers=admin_headers)
    assert response.json() == {"logs": []}


# --- chat 集成：对话自动记录 ---


class FakeAgent:
    """假 agent：invoke 返回固定消息列表（含一次工具调用步骤）。"""

    def invoke(self, inputs, config=None):
        return {
            "messages": [
                AIMessage(content="我来调用工具"),
                ToolMessage(content="拉取成功", name="docker_mirror_pull", tool_call_id="t1"),
                AIMessage(content="好的，已拉取 nginx 镜像"),
            ]
        }


@pytest.fixture
def fake_build_agent(monkeypatch):
    monkeypatch.setattr(
        service,
        "build_agent",
        lambda model=None, tools_names=None, system_prompt=None, llm_config=None: FakeAgent(),
    )


def test_chat_success_records_log(client, admin_headers, fake_build_agent, db_session, monkeypatch):
    # issue #25：langchain 路径（provider 回退）需 mock resolve_llm_config，
    # hermes 已配置时会走 hermes-agent 直通
    monkeypatch.setattr(
        service,
        "resolve_llm_config",
        lambda db=None: {
            "source": "provider",
            "name": "deepseek",
            "base_url": "https://api.deepseek.com",
            "api_key": "sk-test-123",
            "model": "deepseek-chat",
        },
    )
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "帮我拉取 nginx 镜像"}]},
    )
    assert response.status_code == 200

    logs = list_logs(db_session)
    assert len(logs) == 1
    log = get_log(db_session, logs[0]["id"])
    assert log["status"] == "success"
    assert log["llm_source"] == "provider"
    assert log["request_text"] == "帮我拉取 nginx 镜像"
    assert log["reply"] == "好的，已拉取 nginx 镜像"
    assert log["duration_ms"] >= 0
    steps = log["events"]
    assert [s["role"] for s in steps] == ["ai", "tool", "ai"]


def test_chat_llm_not_configured_records_error_log(client, admin_headers, db_session, monkeypatch):
    """LLM 未配置（503）也记录 error 日志，便于排查失败原因。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "帮我拉取 nginx 镜像"}]},
    )
    assert response.status_code == 503

    logs = list_logs(db_session)
    assert len(logs) == 1
    assert logs[0]["status"] == "error"
    assert logs[0]["request_text"] == "帮我拉取 nginx 镜像"
    detail = get_log(db_session, logs[0]["id"])
    assert "LLM 未配置" in detail["error_message"]


@pytest.fixture
def fake_stream_agent(monkeypatch):
    """假流式 agent：产出 token/step/step_result/reply/done 标准事件序列。"""

    async def fake(messages, tools_names=None, max_iterations=None, llm_config=None):
        yield {"type": "token", "content": "好的，"}
        yield {
            "type": "step",
            "name": "docker_mirror_pull",
            "arguments": {"image": "nginx"},
        }
        yield {
            "type": "step_result",
            "name": "docker_mirror_pull",
            "result": "拉取成功",
        }
        yield {"type": "token", "content": "已拉取 nginx 镜像"}
        yield {"type": "reply", "content": "好的，已拉取 nginx 镜像"}
        yield {"type": "done"}

    monkeypatch.setattr(service, "stream_agent", fake)


def test_stream_chat_records_log(client, admin_headers, fake_stream_agent, db_session):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={
            "messages": [{"role": "user", "content": "帮我拉取 nginx 镜像"}],
            "tools": ["docker_mirror_pull"],
        },
    )
    assert response.status_code == 200
    # 完整消费 SSE 流，触发生成器结束后的落库
    body = response.text
    assert "event: done" in body

    logs = list_logs(db_session)
    assert len(logs) == 1
    log = get_log(db_session, logs[0]["id"])
    assert log["status"] == "success"
    assert log["reply"] == "好的，已拉取 nginx 镜像"
    assert log["tools_names"] == ["docker_mirror_pull"]
    events = log["events"]
    assert [e["type"] for e in events] == ["step", "step_result"]
    assert events[0]["name"] == "docker_mirror_pull"
    assert events[0]["arguments"] == {"image": "nginx"}
    assert events[1]["result"] == "拉取成功"


@pytest.fixture
def fake_stream_agent_error(monkeypatch):
    """假流式 agent：执行中途失败，产出 error 事件。"""

    async def fake(messages, tools_names=None, max_iterations=None, llm_config=None):
        yield {"type": "token", "content": "好的，"}
        yield {
            "type": "step",
            "name": "docker_mirror_pull",
            "arguments": {"image": "nginx"},
        }
        yield {"type": "error", "message": "Agent 执行异常：拉取超时"}

    monkeypatch.setattr(service, "stream_agent", fake)


def test_stream_chat_error_records_log(client, admin_headers, fake_stream_agent_error, db_session):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "帮我拉取 nginx 镜像"}]},
    )
    assert response.status_code == 200
    assert "event: error" in response.text

    logs = list_logs(db_session)
    assert len(logs) == 1
    log = get_log(db_session, logs[0]["id"])
    assert log["status"] == "error"
    assert "拉取超时" in log["error_message"]
    # 失败前的步骤已记录
    events = log["events"]
    assert [e["type"] for e in events] == ["step"]
    assert events[0]["name"] == "docker_mirror_pull"


def test_stream_invalid_tools_no_log(client, admin_headers, db_session):
    """边界：未知工具 400 在业务执行前拦截，不产生日志。"""
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={
            "messages": [{"role": "user", "content": "hi"}],
            "tools": ["not_a_tool"],
        },
    )
    assert response.status_code == 400
    assert list_logs(db_session) == []
