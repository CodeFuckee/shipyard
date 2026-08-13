"""hermes 直通路径（issue #25）— hermes-agent 完全替代 langchain。

LLM 来源为 hermes 时（hermes-agent API Server），工具循环在 hermes 侧，
后端不再构建 langchain agent，直接透传 OpenAI 兼容调用：
- 非流式：chat_completion → reply（steps 为空，工具执行细节在 hermes 侧）
- 流式：stream_chat_completion → token/step/step_result/reply/done
  （hermes.tool.progress 事件映射为 step/step_result）
- ai_providers 默认供应商回退路径保留 langchain（普通 LLM 无工具循环）

覆盖：
- 正常路径：hermes 直通非流式（不构建 langchain）、流式事件映射、
  tools_names/max_iterations 在 hermes 路径下被忽略
- 边界情况：hermes_client 流内 error 透传、无 delta 只有工具事件、
  running 后缺 completed、hermes_client 抛异常转为 error 事件、
  provider 回退路径仍走 langchain
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


HERMES_CONFIG = {
    "source": "hermes",
    "name": "Hermes",
    "base_url": "https://hermes.example.com/v1",
    "api_key": "sk-hermes-test",
    "model": "hermes-chat",
}

PROVIDER_CONFIG = {
    "source": "provider",
    "name": "deepseek",
    "base_url": "https://api.deepseek.com",
    "api_key": "sk-test-123",
    "model": "deepseek-chat",
}


def _collect_stream(messages, tools_names=None, max_iterations=None, llm_config=None):
    """同步收集 async 生成器 stream_agent 的全部事件。"""

    async def _collect():
        return [
            event
            async for event in service.stream_agent(
                messages,
                tools_names=tools_names,
                max_iterations=max_iterations,
                llm_config=llm_config,
            )
        ]

    return asyncio.run(_collect())


def _chat_response(content: str) -> dict:
    return {
        "id": "chatcmpl-test",
        "object": "chat.completion",
        "model": "hermes-chat",
        "choices": [
            {"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}
        ],
    }


# --- 非流式 hermes 直通 ---


def test_run_agent_hermes_direct_skips_langchain(monkeypatch):
    """hermes 来源：直接调 hermes_client.chat_completion，不构建 langchain agent。"""
    captured = {}

    def fake_chat_completion(messages, model=None, temperature=0.7):
        captured["messages"] = messages
        captured["model"] = model
        return _chat_response("已拉取 nginx:1.25")

    def explode_build_agent(**kwargs):
        raise AssertionError("hermes 直通路径不应构建 langchain agent")

    monkeypatch.setattr(hermes_client, "chat_completion", fake_chat_completion)
    monkeypatch.setattr(service, "build_agent", explode_build_agent)

    result = service.run_agent(
        [{"role": "user", "content": "拉取 nginx:1.25"}], llm_config=HERMES_CONFIG
    )
    assert result == {"reply": "已拉取 nginx:1.25", "steps": []}
    assert captured["messages"] == [{"role": "user", "content": "拉取 nginx:1.25"}]
    assert captured["model"] == "hermes-chat"


def test_run_agent_hermes_direct_passes_model_through(monkeypatch):
    """配置的模型名透传给 hermes（hermes 侧按需路由）。"""
    captured = {}

    def fake_chat_completion(messages, model=None, temperature=0.7):
        captured["model"] = model
        return _chat_response("ok")

    monkeypatch.setattr(hermes_client, "chat_completion", fake_chat_completion)
    config = {**HERMES_CONFIG, "model": "qwen-max"}
    service.run_agent([{"role": "user", "content": "hi"}], llm_config=config)
    assert captured["model"] == "qwen-max"


def test_run_agent_hermes_direct_empty_choices(monkeypatch):
    """上游返回空 choices：reply 为空字符串，不抛异常。"""
    monkeypatch.setattr(
        hermes_client,
        "chat_completion",
        lambda messages, model=None, temperature=0.7: {"choices": []},
    )
    result = service.run_agent([{"role": "user", "content": "hi"}], llm_config=HERMES_CONFIG)
    assert result == {"reply": "", "steps": []}


def test_run_agent_provider_fallback_uses_langchain(monkeypatch):
    """provider 来源：回退路径保留 langchain（普通 LLM 无工具循环）。"""

    class FakeAgent:
        def invoke(self, inputs, config=None):
            return {
                "messages": [
                    type("M", (), {"type": "ai", "content": "✅ 完成"})(),
                ]
            }

    monkeypatch.setattr(
        service,
        "build_agent",
        lambda model=None, tools_names=None, system_prompt=None, llm_config=None: FakeAgent(),
    )
    result = service.run_agent([{"role": "user", "content": "hi"}], llm_config=PROVIDER_CONFIG)
    assert result["reply"] == "✅ 完成"


# --- 流式 hermes 直通 ---


def _fake_stream_events(events):
    """把事件 dict 序列包装为同步生成器（模拟 hermes_client.stream_chat_completion）。"""

    def fake_stream_chat_completion(messages, model=None, temperature=0.7):
        for e in events:
            yield e

    return fake_stream_chat_completion


def test_stream_agent_hermes_direct_maps_events(monkeypatch):
    """delta → token；tool_progress running/completed → step/step_result；
    结束时汇总 reply + done。"""
    monkeypatch.setattr(
        hermes_client,
        "stream_chat_completion",
        _fake_stream_events(
            [
                {"type": "delta", "content": "我看看容器"},
                {"type": "tool_progress", "tool": "list_containers", "label": "列出全部容器",
                 "status": "running", "tool_call_id": "call_1"},
                {"type": "delta", "content": ""},
                {"type": "tool_progress", "tool": "list_containers", "label": "[1 个容器]",
                 "status": "completed", "tool_call_id": "call_1"},
                {"type": "delta", "content": "，共 1 个容器"},
                {"type": "done"},
            ]
        ),
    )

    events = _collect_stream([{"role": "user", "content": "看看容器"}], llm_config=HERMES_CONFIG)
    assert events == [
        {"type": "token", "content": "我看看容器"},
        {"type": "step", "name": "list_containers", "arguments": {"label": "列出全部容器"}},
        {"type": "token", "content": ""},
        {"type": "step_result", "name": "list_containers", "result": "[1 个容器]"},
        {"type": "token", "content": "，共 1 个容器"},
        {"type": "reply", "content": "我看看容器，共 1 个容器"},
        {"type": "done"},
    ]


def test_stream_agent_hermes_direct_ignores_tools_names_and_iterations(monkeypatch):
    """hermes 路径：tools_names/max_iterations 无意义（工具循环在 hermes 侧），
    直接忽略，不构建 langchain、不报未知工具错。"""
    monkeypatch.setattr(
        hermes_client,
        "stream_chat_completion",
        _fake_stream_events([{"type": "delta", "content": "ok"}, {"type": "done"}]),
    )

    def explode_build_agent(**kwargs):
        raise AssertionError("hermes 直通路径不应构建 langchain agent")

    monkeypatch.setattr(service, "build_agent", explode_build_agent)

    events = _collect_stream(
        [{"role": "user", "content": "hi"}],
        tools_names=["list_containers"],
        max_iterations=50,
        llm_config=HERMES_CONFIG,
    )
    assert events[-2] == {"type": "reply", "content": "ok"}
    assert events[-1] == {"type": "done"}


def test_stream_agent_hermes_direct_no_delta_only_tools(monkeypatch):
    """hermes 全程只有工具事件（无文本 delta）：reply 为空字符串，步骤保留。"""
    monkeypatch.setattr(
        hermes_client,
        "stream_chat_completion",
        _fake_stream_events(
            [
                {"type": "tool_progress", "tool": "pull_image", "label": "拉取 nginx",
                 "status": "running", "tool_call_id": "call_1"},
                {"type": "tool_progress", "tool": "pull_image", "label": "拉取成功",
                 "status": "completed", "tool_call_id": "call_1"},
                {"type": "done"},
            ]
        ),
    )

    events = _collect_stream([{"role": "user", "content": "拉取 nginx"}], llm_config=HERMES_CONFIG)
    assert events == [
        {"type": "step", "name": "pull_image", "arguments": {"label": "拉取 nginx"}},
        {"type": "step_result", "name": "pull_image", "result": "拉取成功"},
        {"type": "reply", "content": ""},
        {"type": "done"},
    ]


def test_stream_agent_hermes_direct_running_without_completed(monkeypatch):
    """工具 running 事件后流结束（缺 completed）：不崩溃，正常收尾。"""
    monkeypatch.setattr(
        hermes_client,
        "stream_chat_completion",
        _fake_stream_events(
            [
                {"type": "tool_progress", "tool": "list_images", "label": "列出镜像",
                 "status": "running", "tool_call_id": "call_1"},
                {"type": "done"},
            ]
        ),
    )

    events = _collect_stream([{"role": "user", "content": "看看镜像"}], llm_config=HERMES_CONFIG)
    assert events[0]["type"] == "step"
    assert events[-1] == {"type": "done"}


def test_stream_agent_hermes_direct_upstream_error(monkeypatch):
    """hermes 流内 error 事件：透传并终止，不追加 reply/done。"""
    monkeypatch.setattr(
        hermes_client,
        "stream_chat_completion",
        _fake_stream_events([{"type": "error", "message": "hermes API Key 无效或被拒绝（401）"}]),
    )

    events = _collect_stream([{"role": "user", "content": "hi"}], llm_config=HERMES_CONFIG)
    assert events == [{"type": "error", "message": "hermes API Key 无效或被拒绝（401）"}]


def test_stream_agent_hermes_direct_client_raises(monkeypatch):
    """hermes_client 调用抛出 HermesError：转为 error 事件（流内终止）。"""
    from app.services.hermes_client import HermesError

    def raising_stream(messages, model=None, temperature=0.7):
        raise HermesError("无法连接 hermes 服务器")
        yield  # pragma: no cover（生成器函数必须有 yield 才是 generator）

    monkeypatch.setattr(hermes_client, "stream_chat_completion", raising_stream)

    events = _collect_stream([{"role": "user", "content": "hi"}], llm_config=HERMES_CONFIG)
    assert events == [{"type": "error", "message": "无法连接 hermes 服务器"}]


def test_stream_agent_hermes_direct_without_explicit_config(monkeypatch):
    """llm_config 缺省：自动 resolve（hermes 已配置 → hermes 直通，不构建 langchain）。"""
    monkeypatch.setattr(
        hermes_client,
        "stream_chat_completion",
        _fake_stream_events([{"type": "delta", "content": "你好"}, {"type": "done"}]),
    )

    def explode_build_agent(**kwargs):
        raise AssertionError("hermes 直通路径不应构建 langchain agent")

    monkeypatch.setattr(service, "build_agent", explode_build_agent)

    events = _collect_stream([{"role": "user", "content": "hi"}])
    assert events[-2] == {"type": "reply", "content": "你好"}
    assert events[-1] == {"type": "done"}
