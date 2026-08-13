"""Hermes 接入客户端 — 状态、连接测试、对话（非流式 + SSE 流式）。

覆盖：
- 正常路径：连接测试成功、非流式对话成功、流式对话（多增量 + [DONE]）
- 边界情况：未配置（enabled=False / ensure 抛错）、超时、无法连接、
  401/403/404/500 错误分类、流式上游错误与连接中断、
  SSE 杂行/坏 JSON/无 choices 行跳过、流式无 [DONE] 也正常结束、
  base_url 尾斜杠与空白规范化、model 未指定时不发送该字段
"""

import json

import httpx
import pytest

from app.services import hermes_client
from app.services.hermes_client import (
    HermesError,
    HermesNotConfiguredError,
    chat_completion,
    ensure_configured,
    hermes_enabled,
    hermes_status,
    stream_chat_completion,

)


@pytest.fixture(autouse=True)
def hermes_env(monkeypatch):
    """默认配置一个可用的 hermes 实例；需要变更配置的测试自行覆盖。"""
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "https://hermes.example.com/v1")
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "sk-hermes-test")
    monkeypatch.setattr(hermes_client, "HERMES_MODEL", "hermes-chat")


@pytest.fixture
def install_mock(monkeypatch):
    """将 hermes_client._client 替换为 MockTransport 客户端。

    返回 install(handler) -> captured_requests：handler 接收 httpx.Request 返回
    httpx.Response 或抛异常；captured_requests 记录所有收到的请求。
    """

    def install(handler):
        captured = []

        def wrapper(request):
            captured.append(request)
            return handler(request)

        transport = httpx.MockTransport(wrapper)
        monkeypatch.setattr(
            hermes_client,
            "_client",
            lambda stream=False: httpx.Client(transport=transport, timeout=30.0),
        )
        return captured

    return install


def _chat_response() -> dict:
    return {
        "id": "chatcmpl-test",
        "object": "chat.completion",
        "model": "hermes-chat",
        "choices": [{"index": 0, "message": {"role": "assistant", "content": "你好"}, "finish_reason": "stop"}],
    }


# --- 状态与启用判定 ---


def test_enabled_false_when_base_url_empty(monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    assert hermes_enabled() is False
    assert hermes_status()["enabled"] is False


def test_enabled_false_when_base_url_blank(monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "   ")
    assert hermes_enabled() is False


def test_status_configured():
    status = hermes_status()
    assert status == {
        "enabled": True,
        "source": "env",
        "base_url": "https://hermes.example.com/v1",
        "model": "hermes-chat",
        "api_key_configured": True,
    }


def test_status_without_api_key(monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "")
    status = hermes_status()
    assert status["enabled"] is True
    assert status["api_key_configured"] is False


def test_ensure_configured_raises_when_disabled(monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    with pytest.raises(HermesNotConfiguredError):
        ensure_configured()


# --- 连接测试 ---


def test_test_connection_success(install_mock):
    captured = install_mock(lambda request: httpx.Response(200, json={"data": []}))
    result = hermes_client.test_connection()
    assert result == {"ok": True, "message": "连接成功"}
    assert captured[0].url == "https://hermes.example.com/v1/models"
    assert captured[0].headers["Authorization"] == "Bearer sk-hermes-test"


def test_test_connection_base_url_normalization(install_mock, monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "  https://hermes.example.com/v1/  ")
    captured = install_mock(lambda request: httpx.Response(200, json={"data": []}))
    assert hermes_client.test_connection()["ok"] is True
    assert captured[0].url == "https://hermes.example.com/v1/models"


def test_test_connection_timeout(install_mock):
    def handler(request):
        raise httpx.TimeoutException("timeout")

    install_mock(handler)
    result = hermes_client.test_connection()
    assert result["ok"] is False
    assert "连接超时" in result["message"]


def test_test_connection_connect_error(install_mock):
    def handler(request):
        raise httpx.ConnectError("refused")

    install_mock(handler)
    result = hermes_client.test_connection()
    assert result["ok"] is False
    assert "无法连接" in result["message"]


def test_test_connection_unauthorized(install_mock):
    install_mock(lambda request: httpx.Response(401, json={"error": "invalid_key"}))
    result = hermes_client.test_connection()
    assert result["ok"] is False
    assert "API Key 无效" in result["message"]


def test_test_connection_not_found_suggests_v1(install_mock):
    install_mock(lambda request: httpx.Response(404, json={}))
    result = hermes_client.test_connection()
    assert result["ok"] is False
    assert "/v1" in result["message"]


def test_test_connection_server_error(install_mock):
    install_mock(lambda request: httpx.Response(500, json={}))
    result = hermes_client.test_connection()
    assert result["ok"] is False
    assert "500" in result["message"]


def test_test_connection_when_disabled(monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    result = hermes_client.test_connection()
    assert result["ok"] is False
    assert "HERMES_BASE_URL" in result["message"]


# --- 非流式对话 ---


def test_chat_completion_success(install_mock):
    captured = install_mock(lambda request: httpx.Response(200, json=_chat_response()))
    result = chat_completion(
        [{"role": "user", "content": "你好"}], model="custom-model", temperature=0.3
    )
    assert result["choices"][0]["message"]["content"] == "你好"

    request = captured[0]
    assert request.url == "https://hermes.example.com/v1/chat/completions"
    assert request.headers["Authorization"] == "Bearer sk-hermes-test"
    payload = json.loads(request.content)
    assert payload == {
        "messages": [{"role": "user", "content": "你好"}],
        "temperature": 0.3,
        "stream": False,
        "model": "custom-model",
    }


def test_chat_completion_omits_model_when_unset(install_mock, monkeypatch):
    """HERMES_MODEL 与请求 model 均未指定时，payload 不包含 model 字段。"""
    monkeypatch.setattr(hermes_client, "HERMES_MODEL", "")
    captured = install_mock(lambda request: httpx.Response(200, json=_chat_response()))
    chat_completion([{"role": "user", "content": "hi"}])
    payload = json.loads(captured[0].content)
    assert "model" not in payload


def test_chat_completion_no_api_key_header(install_mock, monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_API_KEY", "")
    captured = install_mock(lambda request: httpx.Response(200, json=_chat_response()))
    chat_completion([{"role": "user", "content": "hi"}])
    assert "Authorization" not in captured[0].headers


def test_chat_completion_unauthorized(install_mock):
    install_mock(lambda request: httpx.Response(401, json={}))
    with pytest.raises(HermesError) as exc_info:
        chat_completion([{"role": "user", "content": "hi"}])
    assert "API Key 无效" in exc_info.value.message
    assert exc_info.value.status_code == 502


def test_chat_completion_not_found(install_mock):
    install_mock(lambda request: httpx.Response(404, json={}))
    with pytest.raises(HermesError) as exc_info:
        chat_completion([{"role": "user", "content": "hi"}])
    assert "/v1" in exc_info.value.message


def test_chat_completion_server_error(install_mock):
    install_mock(lambda request: httpx.Response(503, json={}))
    with pytest.raises(HermesError) as exc_info:
        chat_completion([{"role": "user", "content": "hi"}])
    assert "503" in exc_info.value.message


def test_chat_completion_timeout(install_mock):
    def handler(request):
        raise httpx.TimeoutException("timeout")

    install_mock(handler)
    with pytest.raises(HermesError) as exc_info:
        chat_completion([{"role": "user", "content": "hi"}])
    assert "连接超时" in exc_info.value.message


def test_chat_completion_connect_error(install_mock):
    def handler(request):
        raise httpx.ConnectError("refused")

    install_mock(handler)
    with pytest.raises(HermesError) as exc_info:
        chat_completion([{"role": "user", "content": "hi"}])
    assert "无法连接" in exc_info.value.message


def test_chat_completion_not_configured(monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    with pytest.raises(HermesNotConfiguredError) as exc_info:
        chat_completion([{"role": "user", "content": "hi"}])
    assert exc_info.value.status_code == 503


# --- 流式对话 ---


def _sse_lines(chunks, with_done=True):
    lines = [f"data: {json.dumps(c, ensure_ascii=False)}" for c in chunks]
    if with_done:
        lines.append("data: [DONE]")
    return "\n".join(lines)


def test_stream_success(install_mock):
    chunks = [
        {"choices": [{"delta": {"content": "你"}, "finish_reason": None}]},
        {"choices": [{"delta": {"content": "好"}, "finish_reason": None}]},
    ]
    install_mock(
        lambda request: httpx.Response(
            200, text=_sse_lines(chunks), headers={"Content-Type": "text/event-stream"}
        )
    )
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert events == [
        {"type": "delta", "content": "你"},
        {"type": "delta", "content": "好"},
        {"type": "done"},
    ]


def test_stream_skips_garbage_lines(install_mock):
    """非 data: 行、坏 JSON、无 choices 的 chunk 应被跳过。"""
    raw_lines = [
        ": keep-alive comment",
        "ping",
        "data: {bad json",
        'data: {"choices": []}',
        'data: {"choices": [{"delta": {}}]}',
        'data: {"choices": [{"delta": {"content": "ok"}, "finish_reason": null}]}',
        "data: [DONE]",
    ]
    install_mock(
        lambda request: httpx.Response(
            200, text="\n".join(raw_lines), headers={"Content-Type": "text/event-stream"}
        )
    )
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert events == [{"type": "delta", "content": "ok"}, {"type": "done"}]


def test_stream_finishes_without_done_marker(install_mock):
    """流结束但未收到 [DONE]（部分实现省略）也应正常结束。"""
    chunks = [{"choices": [{"delta": {"content": "好"}}]}]
    install_mock(
        lambda request: httpx.Response(
            200, text=_sse_lines(chunks, with_done=False),
            headers={"Content-Type": "text/event-stream"},
        )
    )
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert events[-1] == {"type": "done"}


def test_stream_upstream_error_yields_error_event(install_mock):
    install_mock(lambda request: httpx.Response(401, json={}))
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert len(events) == 1
    assert events[0]["type"] == "error"
    assert "API Key 无效" in events[0]["message"]


def test_stream_connect_error_yields_error_event(install_mock):
    def handler(request):
        raise httpx.ConnectError("refused")

    install_mock(handler)
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert len(events) == 1
    assert events[0]["type"] == "error"
    assert "无法连接" in events[0]["message"] or "失败" in events[0]["message"]


def test_stream_not_configured_raises(monkeypatch):
    monkeypatch.setattr(hermes_client, "HERMES_BASE_URL", "")
    with pytest.raises(HermesNotConfiguredError):
        list(stream_chat_completion([{"role": "user", "content": "hi"}]))


# --- hermes-agent API Server 的 hermes.tool.progress 事件（issue #25） ---


def test_stream_parses_tool_progress_events(install_mock):
    """hermes-agent 流式响应携带 event: hermes.tool.progress 行，
    解析为 tool_progress 事件（供 agent 映射 step/step_result）。"""
    raw = "\n".join(
        [
            'data: {"choices": [{"delta": {"content": "你"}}]}',
            "event: hermes.tool.progress",
            'data: {"tool": "list_containers", "emoji": "🐳", "label": "列出容器",'
            ' "toolCallId": "call_1", "status": "running"}',
            "event: hermes.tool.progress",
            'data: {"tool": "list_containers", "emoji": "🐳", "label": "[1 个容器]",'
            ' "toolCallId": "call_1", "status": "completed"}',
            'data: {"choices": [{"delta": {"content": "，共 1 个"}}]}',
            "data: [DONE]",
        ]
    )
    install_mock(
        lambda request: httpx.Response(
            200, text=raw, headers={"Content-Type": "text/event-stream"}
        )
    )
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert events == [
        {"type": "delta", "content": "你"},
        {
            "type": "tool_progress",
            "tool": "list_containers",
            "label": "列出容器",
            "status": "running",
            "tool_call_id": "call_1",
        },
        {
            "type": "tool_progress",
            "tool": "list_containers",
            "label": "[1 个容器]",
            "status": "completed",
            "tool_call_id": "call_1",
        },
        {"type": "delta", "content": "，共 1 个"},
        {"type": "done"},
    ]


def test_stream_tool_progress_bad_json_skipped(install_mock):
    """tool.progress 事件 data 为坏 JSON：跳过该行，不影响后续解析。"""
    raw = "\n".join(
        [
            "event: hermes.tool.progress",
            "data: {bad json",
            'data: {"choices": [{"delta": {"content": "ok"}}]}',
            "data: [DONE]",
        ]
    )
    install_mock(
        lambda request: httpx.Response(
            200, text=raw, headers={"Content-Type": "text/event-stream"}
        )
    )
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert events == [{"type": "delta", "content": "ok"}, {"type": "done"}]


def test_stream_tool_progress_without_data_line_skipped(install_mock):
    """只有 event: 行没有 data: 行：不产生事件，正常结束。"""
    raw = "\n".join(
        [
            "event: hermes.tool.progress",
            "event: hermes.tool.progress",
            "data: [DONE]",
        ]
    )
    install_mock(
        lambda request: httpx.Response(
            200, text=raw, headers={"Content-Type": "text/event-stream"}
        )
    )
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert events == [{"type": "done"}]


def test_stream_tool_progress_unknown_status_passthrough(install_mock):
    """status 为未知值：原样透传（客户端自行决定是否展示）。"""
    raw = "\n".join(
        [
            "event: hermes.tool.progress",
            'data: {"tool": "_thinking", "label": "", "toolCallId": "call_9", "status": "thinking"}',
            "data: [DONE]",
        ]
    )
    install_mock(
        lambda request: httpx.Response(
            200, text=raw, headers={"Content-Type": "text/event-stream"}
        )
    )
    events = list(stream_chat_completion([{"role": "user", "content": "hi"}]))
    assert events[0]["type"] == "tool_progress"
    assert events[0]["status"] == "thinking"
    assert events[0]["tool"] == "_thinking"
