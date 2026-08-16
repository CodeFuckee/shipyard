"""AI 助手对话历史保存（issue #32/#38）。

对话记录持久化：每次成功对话（流式与非流式）自动把完整消息列表
（用户/助手消息 + 工具执行步骤）保存到会话记录。issue #32 为单例
覆盖式（agent_chat_history id=1）；issue #38 升级为多会话
（agent_chat_sessions 多行）：请求携带 session_id 更新该会话，否则
新建会话；标题取首条用户消息摘要；最多保留 100 条；支持删除单条；
旧单例记录首次访问时自动迁移为一条会话。

覆盖：
- 模块函数：空历史、保存往返、过滤 system/tool、空 reply 不追加、
  多会话创建/更新/标题摘要/100 条上限/删除/详情、旧单例迁移、
  清空幂等、空输入健壮性
- API 端点：401 未认证、会话列表/创建/详情/更新/删除、404 分支
- chat/chat-stream 集成：成功自动保存并返回 session_id、LLM 未配置/
  流内错误不破坏已有会话
"""

import json
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


# --- issue #38：多会话历史 ---


def test_save_creates_multiple_sessions(db_session):
    """不带 session_id 保存两次 → 创建两条会话，列表最新在前。"""
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "第一条"}],
        reply="回复一",
        events=[],
    )
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "第二条"}],
        reply="回复二",
        events=[],
    )
    db_session.commit()

    sessions = chat_history.get_sessions(db_session)
    assert len(sessions) == 2
    assert sessions[0]["title"] == "第二条"  # 最新在前
    assert sessions[1]["title"] == "第一条"
    # 最近会话的消息为第二次保存的内容
    messages = chat_history.get_messages(db_session)
    assert [m["content"] for m in messages] == ["第二条", "回复二"]


def test_save_updates_existing_session(db_session):
    """携带 session_id 保存 → 更新同一会话（标题保持首次摘要）。"""
    first = chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "首次问题"}],
        reply="首次回复",
        events=[],
    )
    chat_history.save_conversation(
        db_session,
        session_id=first["id"],
        messages=[
            {"role": "user", "content": "首次问题"},
            {"role": "assistant", "content": "首次回复"},
            {"role": "user", "content": "追问"},
        ],
        reply="追问回复",
        events=[],
    )
    db_session.commit()

    sessions = chat_history.get_sessions(db_session)
    assert len(sessions) == 1  # 仍是同一会话
    assert sessions[0]["id"] == first["id"]
    assert sessions[0]["title"] == "首次问题"  # 标题不变
    detail = chat_history.get_session_messages(db_session, first["id"])
    assert [m["content"] for m in detail["messages"]] == [
        "首次问题",
        "首次回复",
        "追问",
        "追问回复",
    ]


def test_title_from_first_user_message(db_session):
    """标题自动取首条用户消息摘要（前 30 字符，超长截断加省略号）。"""
    long_text = "请帮我拉取并运行一个 nginx 容器并配置端口映射和挂载卷" * 3
    chat_history.save_conversation(
        db_session,
        messages=[
            {"role": "system", "content": "你是 Docker 助手"},
            {"role": "user", "content": long_text},
        ],
        reply="好的",
        events=[],
    )
    db_session.commit()

    sessions = chat_history.get_sessions(db_session)
    assert len(sessions) == 1
    assert sessions[0]["title"].endswith("…")
    assert len(sessions[0]["title"]) == chat_history._TITLE_MAX_LEN + 1


def test_title_fallback_default(db_session):
    """无用户消息时标题回退「新会话」。"""
    chat_history.save_conversation(
        db_session,
        messages=[{"role": "assistant", "content": "你好"}],
        reply="",
        events=[],
    )
    db_session.commit()

    sessions = chat_history.get_sessions(db_session)
    assert sessions[0]["title"] == chat_history._DEFAULT_TITLE


def test_sessions_pruned_to_max(db_session):
    """超过 100 条会话时自动删除最旧会话。"""
    for i in range(chat_history.MAX_SESSIONS + 5):
        chat_history.save_conversation(
            db_session,
            messages=[{"role": "user", "content": f"第{i}条"}],
            reply=f"回复{i}",
            events=[],
        )
    db_session.commit()

    sessions = chat_history.get_sessions(db_session)
    assert len(sessions) == chat_history.MAX_SESSIONS
    # 最旧的 5 条被清理，最新 100 条保留（标题从 5 开始）
    titles = [s["title"] for s in sessions]
    assert "第0条" not in titles and "第4条" not in titles
    assert "第5条" in titles and "第104条" in titles


def test_delete_session(db_session):
    """删除单条会话：存在返回 True，不存在返回 False。"""
    session = chat_history.save_conversation(
        db_session,
        messages=[{"role": "user", "content": "hi"}],
        reply="你好",
        events=[],
    )
    db_session.commit()

    assert chat_history.delete_session(db_session, session["id"]) is True
    assert chat_history.get_sessions(db_session) == []
    assert chat_history.delete_session(db_session, session["id"]) is False


def test_get_session_messages_none(db_session):
    """不存在的会话详情返回 None。"""
    assert chat_history.get_session_messages(db_session, 999) is None


def test_migrate_singleton(db_session):
    """旧单例记录首次访问时迁移为一条会话，随后删除单例记录（幂等）。"""
    from app.db.models import AgentChatHistoryModel

    old = AgentChatHistoryModel(
        id=1,
        messages_json=json.dumps(
            [
                {"role": "user", "content": "旧对话"},
                {"role": "assistant", "content": "旧回复"},
            ],
            ensure_ascii=False,
        ),
    )
    db_session.add(old)
    db_session.commit()

    sessions = chat_history.get_sessions(db_session)
    assert len(sessions) == 1
    assert sessions[0]["title"] == "旧对话"
    detail = chat_history.get_session_messages(db_session, sessions[0]["id"])
    assert [m["content"] for m in detail["messages"]] == ["旧对话", "旧回复"]

    # 迁移完成：旧单例记录已删除，再次访问不再产生新会话
    assert db_session.query(AgentChatHistoryModel).filter_by(id=1).first() is None
    assert len(chat_history.get_sessions(db_session)) == 1


# --- issue #38：多会话 API 端点 ---


def test_chat_sessions_list_requires_auth(client):
    response = client.get("/admin/agent/chat-sessions")
    assert response.status_code == 401


def test_chat_sessions_create_requires_auth(client):
    response = client.post(
        "/admin/agent/chat-sessions",
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert response.status_code == 401


def test_chat_sessions_get_empty(client, admin_headers):
    response = client.get("/admin/agent/chat-sessions", headers=admin_headers)
    assert response.status_code == 200
    assert response.json() == {"sessions": []}


def test_chat_sessions_create_and_list(client, admin_headers):
    response = client.post(
        "/admin/agent/chat-sessions",
        headers=admin_headers,
        json={
            "messages": [
                {"role": "user", "content": "快照第一条"},
                {"role": "assistant", "content": "快照回复"},
            ],
            "reply": "",
            "events": [],
        },
    )
    assert response.status_code == 200
    created = response.json()
    assert created["title"] == "快照第一条"
    assert created["id"] >= 1

    response = client.get("/admin/agent/chat-sessions", headers=admin_headers)
    sessions = response.json()["sessions"]
    assert len(sessions) == 1
    assert sessions[0]["id"] == created["id"]


def test_chat_sessions_detail_and_404(client, admin_headers):
    created = client.post(
        "/admin/agent/chat-sessions",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "详情消息"}]},
    ).json()

    response = client.get(
        f"/admin/agent/chat-sessions/{created['id']}", headers=admin_headers
    )
    assert response.status_code == 200
    detail = response.json()
    assert detail["title"] == "详情消息"
    assert [m["content"] for m in detail["messages"]] == ["详情消息"]

    response = client.get("/admin/agent/chat-sessions/999", headers=admin_headers)
    assert response.status_code == 404


def test_chat_sessions_update_and_404(client, admin_headers):
    created = client.post(
        "/admin/agent/chat-sessions",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "初始"}]},
    ).json()

    response = client.put(
        f"/admin/agent/chat-sessions/{created['id']}",
        headers=admin_headers,
        json={
            "messages": [
                {"role": "user", "content": "初始"},
                {"role": "assistant", "content": "回复"},
                {"role": "user", "content": "更新"},
            ],
            "reply": "更新回复",
            "events": [],
        },
    )
    assert response.status_code == 200
    assert response.json()["id"] == created["id"]

    detail = client.get(
        f"/admin/agent/chat-sessions/{created['id']}", headers=admin_headers
    ).json()
    assert [m["content"] for m in detail["messages"]] == ["初始", "回复", "更新", "更新回复"]

    response = client.put(
        "/admin/agent/chat-sessions/999",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "x"}]},
    )
    assert response.status_code == 404


def test_chat_sessions_delete_and_404(client, admin_headers):
    created = client.post(
        "/admin/agent/chat-sessions",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "待删除"}]},
    ).json()

    response = client.delete(
        f"/admin/agent/chat-sessions/{created['id']}", headers=admin_headers
    )
    assert response.status_code == 200
    assert response.json() == {"deleted": 1}

    response = client.delete(
        f"/admin/agent/chat-sessions/{created['id']}", headers=admin_headers
    )
    assert response.status_code == 404


def test_chat_response_contains_session_id(
    client, admin_headers, fake_build_agent, provider_config
):
    """非流式 /chat 成功响应携带 session_id。"""
    response = client.post(
        "/admin/agent/chat",
        headers=admin_headers,
        json={"messages": [{"role": "user", "content": "帮我拉取 nginx 镜像"}]},
    )
    assert response.status_code == 200
    assert isinstance(response.json().get("session_id"), int)


def test_stream_sends_session_id_event(client, admin_headers, fake_stream_agent, db_session):
    """流式成功对话后推送 session_id 事件，且可继续更新同一会话。"""
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={
            "messages": [{"role": "user", "content": "帮我拉取 nginx 镜像"}],
            "tools": ["docker_mirror_pull"],
        },
    )
    assert response.status_code == 200
    assert "event: session_id" in response.text

    sessions = chat_history.get_sessions(db_session)
    assert len(sessions) == 1
    session_id = sessions[0]["id"]

    # 第二次对话携带 session_id：更新同一会话而非新建
    response = client.post(
        "/admin/agent/chat/stream",
        headers=admin_headers,
        json={
            "messages": [
                {"role": "user", "content": "帮我拉取 nginx 镜像"},
                {"role": "assistant", "content": "好的，已拉取 nginx 镜像"},
                {"role": "user", "content": "再拉一个 redis"},
            ],
            "tools": ["docker_mirror_pull"],
            "session_id": session_id,
        },
    )
    assert response.status_code == 200
    assert "event: session_id" in response.text

    sessions = chat_history.get_sessions(db_session)
    assert len(sessions) == 1  # 仍是同一会话
    detail = chat_history.get_session_messages(db_session, session_id)
    assert detail["messages"][-1]["content"] == "好的，已拉取 nginx 镜像"


def test_stream_error_keeps_sessions_untouched(client, admin_headers, fake_stream_agent_error, db_session):
    """流内错误：不新建会话，已有会话不被破坏。"""
    created = chat_history.save_conversation(
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
    assert "event: session_id" not in response.text

    sessions = chat_history.get_sessions(db_session)
    assert len(sessions) == 1
    assert sessions[0]["id"] == created["id"]
