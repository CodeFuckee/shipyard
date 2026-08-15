"""AI 助手对话历史保存（issue #32）。

对话记录持久化：每次成功对话（流式与非流式）自动把完整消息列表
（用户/助手消息 + 工具执行步骤）覆盖保存到 agent_chat_history 单例
记录，供前端聊天窗口重新打开时恢复历史对话。

覆盖：
- 模块函数：空历史、保存往返、过滤 system/tool、空 reply 不追加、
  覆盖语义（单例会话）、steps 挂载、清空幂等、空输入健壮性
- API 端点：401 未认证、GET 空列表、DELETE 幂等、GET 完整字段
- chat/stream 集成：成功自动保存、LLM 未配置/流内错误不破坏已有历史
"""

from datetime import datetime

import pytest

from app.agent import chat_history, service
from app.services import hermes_client


@pytest.fixture(autouse=True)
def hermes_env(monkeypatch):
    """默认配置一个可用的 hermes 实例。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "https://hermes.example.com/v1")
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "sk-hermes-test")
    monkeypatch.setattr(hermes_client, "HERMES_MODEL", "hermes-chat")


def _sample_events():
    """标准 step/step_result 工具事件序列。"""
    return [
        {
            "type": "step",
            "name": "docker_mirror_pull",
            "arguments": {"image": "nginx"},
        },
        {
            "type": "step_result",
            "name": "docker_mirror_pull",
            "result": "拉取成功",
        },
    ]


# --- 模块函数 ---


def test_empty_history_returns_empty_list(db_session):
    """空库：返回空列表而非报错。"""
    assert chat_history.get_messages(db_session) == []


def test_save_and_get_roundtrip(db_session):
    """保存后读取：过滤后的消息 + 追加的助手回复（含 steps）。"""
    chat_history.save_conversation(
        db_session,
        messages=[
            {"role": "user", "content": "帮我拉取 nginx 镜像"},
            {"role": "assistant", "content": "好的，我来执行"},
        ],
        reply="已拉取 nginx 镜像",
        events=_sample_events(),
    )
    db_session.commit()

    messages = chat_history.get_messages(db_session)
    assert len(messages) == 3
    assert messages[0] == {"role": "user", "content": "帮我拉取 nginx 镜像"}
    assert messages[1]["role"] == "assistant"
    # 最后一条为本次回复，steps 挂载了工具事件
    last = messages[2]
    assert last["role"] == "assistant"
    assert last["content"] == "已拉取 nginx 镜像"
    assert [s["name"] for s in last["steps"]] == ["docker_mirror_pull", "docker_mirror_pull"]


def test_save_filters_system_and_tool_messages(db_session):
    """system/tool 消息不入对话历史（前端恢复只需要 user/assistant）。"""
    chat_history.save_conversation(
        db_session,
        messages=[
            {"role": "system", "content": "你是 Docker 助手"},
            {"role": "user", "content": "hi"},
            {"role": "tool", "content": "拉取成功"},
        ],
        reply="你好",
        events=[],
    )
    db_session.commit()

    messages = chat_history.get_messages(db_session)
    roles = [m["role"] for m in messages]
    assert roles == ["user", "assistant"]
    assert "system" not in roles and "tool" not in roles


def test_save_skips_empty_reply(db_session):
    """空回复不追加 assistant 消息（避免恢复后出现空消息）。"""
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "hi"}],
        reply="",
        events=[],
    )
    db_session.commit()

    messages = chat_history.get_messages(db_session)
    assert len(messages) == 1
    assert messages[0]["role"] == "user"


def test_save_overwrites_previous(db_session):
    """单例会话语义：第二次保存覆盖第一次（保留最新完整对话）。"""
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "第一条"}],
        reply="回复一",
        events=[],
    )
    chat_history.save_conversation(
        db_session,
        messages=[
            {"role": "user", "content": "第一条"},
            {"role": "assistant", "content": "回复一"},
            {"role": "user", "content": "第二条"},
        ],
        reply="回复二",
        events=[],
    )
    db_session.commit()

    messages = chat_history.get_messages(db_session)
    assert len(messages) == 4
    assert messages[-1]["content"] == "回复二"


def test_save_attaches_only_step_events(db_session):
    """events 中仅保留 step/step_result 事件（token/reply/done 丢弃）。"""
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "hi"}],
        reply="好的",
        events=[
            {"type": "token", "content": "好"},
            {"type": "step", "name": "list_containers", "arguments": {}},
            {"type": "step_result", "name": "list_containers", "result": "[]"},
            {"type": "done"},
        ],
    )
    db_session.commit()

    last = chat_history.get_messages(db_session)[-1]
    assert [s["type"] for s in last["steps"]] == ["step", "step_result"]


def test_clear_history_idempotent(db_session):
    """清空返回删除条数；空表再次清空幂等返回 0。"""
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "hi"}],
        reply="你好",
        events=[],
    )
    db_session.commit()

    assert chat_history.clear_history(db_session) == 1
    assert chat_history.get_messages(db_session) == []
    assert chat_history.clear_history(db_session) == 0


def test_save_with_empty_inputs_is_robust(db_session):
    """边界：空消息 + 空回复 + 空事件不崩溃，保存空列表。"""
    chat_history.save_conversation(db_session, messages=[], reply="", events=[])
    db_session.commit()
    assert chat_history.get_messages(db_session) == []


# --- API 端点 ---


def test_chat_history_get_requires_auth(client):
    response = client.get("/admin/agent/chat-history")
    assert response.status_code == 401


def test_chat_history_delete_requires_auth(client):
    response = client.delete("/admin/agent/chat-history")
    assert response.status_code == 401


def test_chat_history_get_empty(client, admin_headers):
    response = client.get("/admin/agent/chat-history", headers=admin_headers)
    assert response.status_code == 200
    assert response.json() == {"messages": []}


def test_chat_history_delete_empty(client, admin_headers):
    """空表清空：返回 deleted=0（幂等）。"""
    response = client.delete("/admin/agent/chat-history", headers=admin_headers)
    assert response.status_code == 200
    assert response.json() == {"deleted": 0}


# --- chat/stream 集成：成功自动保存 ---


class FakeAgent:
    """假 agent：invoke 返回固定消息列表（含一次工具调用步骤）。"""

    def invoke(self, inputs, config=None):
        from langchain_core.messages import AIMessage, ToolMessage

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


@pytest.fixture
def provider_config(monkeypatch):
    """provider 回退路径的 LLM 配置（issue #25：绕过 hermes 直通）。"""
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


def test_chat_success_saves_history(client, admin_headers, fake_build_agent, provider_config, db_session):
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "帮我拉取 nginx 镜像"}]},
    )
    assert response.status_code == 200

    messages = chat_history.get_messages(db_session)
    assert len(messages) == 2
    assert messages[0] == {"role": "user", "content": "帮我拉取 nginx 镜像"}
    assert messages[1]["role"] == "assistant"
    assert messages[1]["content"] == "好的，已拉取 nginx 镜像"


def test_chat_llm_not_configured_keeps_history(client, admin_headers, db_session, monkeypatch):
    """LLM 未配置（503）：不保存、不破坏已有历史。"""
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "历史消息"}],
        reply="历史回复",
        events=[],
    )
    db_session.commit()

    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "新消息"}]},
    )
    assert response.status_code == 503

    messages = chat_history.get_messages(db_session)
    assert len(messages) == 2
    assert messages[0]["content"] == "历史消息"


@pytest.fixture
def fake_stream_agent(monkeypatch):
    """假流式 agent：产出 token/step/step_result/reply/done 标准事件序列。"""

    async def fake(messages, tools_names=None, max_iterations=None, llm_config=None):
        yield {"type": "token", "content": "好的，"}
        yield {"type": "step", "name": "docker_mirror_pull", "arguments": {"image": "nginx"}}
        yield {
            "type": "step_result",
            "name": "docker_mirror_pull",
            "result": "拉取成功",
        }
        yield {"type": "token", "content": "已拉取 nginx 镜像"}
        yield {"type": "reply", "content": "好的，已拉取 nginx 镜像"}
        yield {"type": "done"}

    monkeypatch.setattr(service, "stream_agent", fake)


def test_stream_success_saves_history(client, admin_headers, fake_stream_agent, db_session):
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={
            "messages": [{"role": "user", "content": "帮我拉取 nginx 镜像"}],
            "tools": ["docker_mirror_pull"],
        },
    )
    assert response.status_code == 200
    assert "event: done" in response.text  # 完整消费 SSE 流触发落库

    messages = chat_history.get_messages(db_session)
    assert len(messages) == 2
    assert messages[0]["role"] == "user"
    last = messages[1]
    assert last["role"] == "assistant"
    assert last["content"] == "好的，已拉取 nginx 镜像"
    assert [s["type"] for s in last["steps"]] == ["step", "step_result"]
    assert last["steps"][0]["name"] == "docker_mirror_pull"


@pytest.fixture
def fake_stream_agent_error(monkeypatch):
    """假流式 agent：执行中途失败，产出 error 事件。"""

    async def fake(messages, tools_names=None, max_iterations=None, llm_config=None):
        yield {"type": "token", "content": "好的，"}
        yield {"type": "error", "message": "Agent 执行异常：拉取超时"}

    monkeypatch.setattr(service, "stream_agent", fake)


def test_stream_error_keeps_existing_history(client, admin_headers, fake_stream_agent_error, db_session):
    """流内错误：不保存本次对话、不破坏已有历史。"""
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "历史消息"}],
        reply="历史回复",
        events=[],
    )
    db_session.commit()

    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "新消息"}]},
    )
    assert response.status_code == 200
    assert "event: error" in response.text

    messages = chat_history.get_messages(db_session)
    assert len(messages) == 2
    assert messages[0]["content"] == "历史消息"
    assert messages[1]["content"] == "历史回复"
