"""Hermes 接入客户端 — 调用 hermes-agent 的 OpenAI 兼容 API Server（issue #25）。

hermes-agent（NousResearch 的 AI Agent，自带工具调用循环）通过
`hermes gateway` 以 OpenAI 兼容 REST API 对外提供服务
（API_SERVER_ENABLED=true 时监听 8642 端口），AIAgent 在 hermes 侧
完成全部工具调用循环（MCP 工具集），本模块只负责透传对话请求。

配置来源（优先级从高到低）：
1. 数据库保存的配置（前端设置页写入，见 app/services/hermes_config.py，
   启动时加载 + 保存时即时同步，无需重启后端）
2. 环境变量（见 app/core/config.py）：
   - HERMES_BASE_URL: hermes-agent API Server 地址（如 http://host:8642/v1），
     空 = 未启用
   - HERMES_API_KEY: hermes-agent 的 API_SERVER_KEY（Bearer 认证必填）
   - HERMES_MODEL: 传给 hermes 的模型名（可选，留空由 hermes 侧默认模型）

hermes-agent 部署与配置说明见仓库根目录 docs/hermes-agent-deployment.md。
"""

import json
from typing import Iterator, List, Optional

import httpx

from app.core.config import HERMES_API_KEY, HERMES_BASE_URL, HERMES_MODEL

# 请求超时（秒）：普通请求 30s，流式请求 120s
_TIMEOUT = 30.0
_STREAM_TIMEOUT = 120.0

# --- 运行时动态配置（前端设置页保存，优先级高于环境变量） ---
# None = 未设置，回落环境变量；经 set_runtime_config() / clear_runtime_config() 更新。
# 应用启动时从数据库加载（见 main.py lifespan），保存配置时由路由即时同步。
_runtime_base_url: Optional[str] = None
_runtime_api_key: Optional[str] = None
_runtime_model: Optional[str] = None


def set_runtime_config(base_url: str, api_key: str, model: str) -> None:
    """设置运行时配置（数据库保存值）；base_url 为空字符串表示禁用接入。"""
    global _runtime_base_url, _runtime_api_key, _runtime_model
    _runtime_base_url = base_url or ""
    _runtime_api_key = api_key
    _runtime_model = model or ""


def clear_runtime_config() -> None:
    """清除运行时配置，回落环境变量（用于测试与配置重置）。"""
    global _runtime_base_url, _runtime_api_key, _runtime_model
    _runtime_base_url = None
    _runtime_api_key = None
    _runtime_model = None


def _effective_base_url() -> str:
    """生效的实例地址：运行时配置优先，否则环境变量。"""
    return _runtime_base_url if _runtime_base_url is not None else HERMES_BASE_URL


def _effective_api_key() -> str:
    """生效的访问密钥。"""
    return _runtime_api_key if _runtime_api_key is not None else HERMES_API_KEY


def _effective_model() -> str:
    """生效的默认模型。"""
    return _runtime_model if _runtime_model is not None else HERMES_MODEL


def effective_api_key() -> str:
    """当前生效的访问密钥（供 agent 等模块调用上游接口时使用）。"""
    return _effective_api_key() or ""


class HermesError(Exception):
    """hermes 调用失败。status_code 为建议映射到 HTTP 响应的状态码。"""

    def __init__(self, message: str, status_code: int = 502):
        super().__init__(message)
        self.status_code = status_code
        self.message = message


class HermesNotConfiguredError(HermesError):
    """HERMES_BASE_URL 未配置，接入未启用。"""

    def __init__(self):
        super().__init__("未配置 HERMES_BASE_URL，Hermes 接入未启用", status_code=503)


def _normalize_base_url(url: str) -> str:
    """去除首尾空白与结尾斜杠，便于拼接 /models、/chat/completions 等端点。"""
    return url.strip().rstrip("/")


def hermes_enabled() -> bool:
    """接入是否启用：生效的 HERMES_BASE_URL 非空。"""
    return bool(_effective_base_url().strip())


def ensure_configured() -> None:
    """未配置时抛出 HermesNotConfiguredError，供路由提前校验。"""
    if not hermes_enabled():
        raise HermesNotConfiguredError()


def hermes_status() -> dict:
    """当前生效配置状态（不包含 API Key 明文）。

    source 标识配置来源：database = 前端设置页保存的配置，env = 环境变量。
    """
    base_url = _effective_base_url()
    enabled = bool(base_url.strip())
    return {
        "enabled": enabled,
        "source": "database" if _runtime_base_url is not None else "env",
        "base_url": _normalize_base_url(base_url) if enabled else "",
        "model": _effective_model() or "",
        "api_key_configured": bool(_effective_api_key()),
    }


def _headers() -> dict:
    """请求头；配置了 API Key 时附加 Bearer 认证。"""
    headers = {"Content-Type": "application/json"}
    if _effective_api_key():
        headers["Authorization"] = f"Bearer {_effective_api_key()}"
    return headers


def _client(stream: bool = False) -> httpx.Client:
    """创建 HTTP 客户端；流式请求使用更长超时。"""
    timeout = _STREAM_TIMEOUT if stream else _TIMEOUT
    return httpx.Client(timeout=timeout, follow_redirects=True)


def _map_status_message(response: httpx.Response) -> str:
    """将上游 HTTP 状态码转为人类可读的错误信息。"""
    if response.status_code in (401, 403):
        return (
            f"hermes API Key 无效或被拒绝（{response.status_code}），"
            f"请确认 HERMES_API_KEY 与 hermes-agent 的 API_SERVER_KEY 一致"
        )
    if response.status_code == 404:
        return (
            f"接口不存在（404），请检查 HERMES_BASE_URL 是否正确"
            f"（应指向 hermes-agent API Server，缺少 /v1 前缀时补上，"
            f"如 http://host:8642/v1）"
        )
    return f"hermes 请求失败（{response.status_code}）"


def test_connection() -> dict:
    """测试 hermes 连接：请求 {base}/models 验证可达性与密钥有效性。

    返回 {"ok": true/false, "message": ...}，HTTP 层始终成功（200）。
    """
    if not hermes_enabled():
        return {"ok": False, "message": "未配置 HERMES_BASE_URL，Hermes 接入未启用"}

    url = f"{_normalize_base_url(_effective_base_url())}/models"
    try:
        with _client() as client:
            response = client.get(url, headers=_headers())
    except httpx.TimeoutException:
        return {"ok": False, "message": f"连接超时（{_TIMEOUT:.0f} 秒），请检查 HERMES_BASE_URL 与网络"}
    except httpx.ConnectError:
        return {"ok": False, "message": "无法连接服务器，请检查 HERMES_BASE_URL 与网络"}
    except httpx.HTTPError as exc:
        return {"ok": False, "message": f"请求失败: {exc}"}

    if response.status_code == 200:
        return {"ok": True, "message": "连接成功"}
    return {"ok": False, "message": _map_status_message(response)}


def _build_payload(
    messages: List[dict],
    model: Optional[str],
    temperature: float,
    stream: bool,
) -> dict:
    """构造 chat/completions 请求体；未指定的可选字段不发送。"""
    payload: dict = {
        "messages": messages,
        "temperature": temperature,
        "stream": stream,
    }
    resolved_model = (model or "").strip() or _effective_model()
    if resolved_model:
        payload["model"] = resolved_model
    return payload


def chat_completion(
    messages: List[dict],
    model: Optional[str] = None,
    temperature: float = 0.7,
) -> dict:
    """调用 hermes 对话接口（非流式），返回 OpenAI 兼容的完整响应。

    未配置时抛 HermesNotConfiguredError；上游出错时抛 HermesError。
    """
    ensure_configured()

    url = f"{_normalize_base_url(_effective_base_url())}/chat/completions"
    payload = _build_payload(messages, model, temperature, stream=False)
    try:
        with _client() as client:
            response = client.post(url, headers=_headers(), json=payload)
    except httpx.TimeoutException:
        raise HermesError(f"hermes 连接超时（{_TIMEOUT:.0f} 秒），请检查网络") from None
    except httpx.ConnectError:
        raise HermesError("无法连接 hermes 服务器，请检查 HERMES_BASE_URL 与网络") from None
    except httpx.HTTPError as exc:
        raise HermesError(f"hermes 请求失败: {exc}") from None

    if response.status_code != 200:
        raise HermesError(_map_status_message(response))
    return response.json()


def stream_chat_completion(
    messages: List[dict],
    model: Optional[str] = None,
    temperature: float = 0.7,
) -> Iterator[dict]:
    """流式调用 hermes 对话接口，逐个产生增量事件。

    每个事件为 dict：
    - {"type": "delta", "content": str} — 增量文本
    - {"type": "tool_progress", "tool", "label", "status", "tool_call_id"} —
      hermes-agent 自定义事件（issue #25）：工具调用开始/结束
      （status 为 running / completed，见 hermes API Server 文档）
    - {"type": "done"} — 正常结束
    - {"type": "error", "message": str} — 上游错误或连接中断

    未配置时立即抛 HermesNotConfiguredError（调用方应先 ensure_configured()）。
    """
    ensure_configured()

    url = f"{_normalize_base_url(_effective_base_url())}/chat/completions"
    payload = _build_payload(messages, model, temperature, stream=True)

    try:
        with _client(stream=True) as client:
            with client.stream("POST", url, headers=_headers(), json=payload) as response:
                if response.status_code != 200:
                    yield {"type": "error", "message": _map_status_message(response)}
                    return

                # 跟踪 SSE 事件名：hermes-agent 的工具进度帧为
                # "event: hermes.tool.progress" + "data: {...}" 成对出现
                current_event: Optional[str] = None
                for line in response.iter_lines():
                    if not line:
                        continue
                    if line.startswith("event:"):
                        current_event = line[len("event:"):].strip()
                        continue
                    if not line.startswith("data:"):
                        continue
                    data = line[len("data:"):].strip()
                    if current_event == "hermes.tool.progress":
                        current_event = None  # 工具进度帧仅跟随一条 data 行
                        progress = _parse_tool_progress(data)
                        if progress is not None:
                            yield progress
                        continue
                    if data == "[DONE]":
                        yield {"type": "done"}
                        return
                    try:
                        chunk = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    choices = chunk.get("choices") or []
                    if not choices:
                        continue
                    delta = choices[0].get("delta", {}) or {}
                    content = delta.get("content")
                    if content:
                        yield {"type": "delta", "content": content}
                # 流式响应结束且未收到 [DONE]，视为正常结束
                yield {"type": "done"}
    except HermesError:
        raise
    except httpx.TimeoutException:
        yield {"type": "error", "message": f"hermes 连接超时（{_STREAM_TIMEOUT:.0f} 秒），请检查网络"}
    except httpx.HTTPError as exc:
        yield {"type": "error", "message": f"hermes 流式请求失败: {exc}"}


def _parse_tool_progress(data: str) -> dict:
    """解析 hermes-agent 的 hermes.tool.progress 事件负载。

    data 为 JSON 字符串：{"tool", "emoji", "label", "toolCallId", "status"}。
    坏 JSON / 非对象 / 缺 tool 名时返回 None（调用方跳过）。
    """
    try:
        payload = json.loads(data)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict) or not payload.get("tool"):
        return None
    return {
        "type": "tool_progress",
        "tool": payload.get("tool") or "",
        "label": payload.get("label") or "",
        "status": payload.get("status") or "",
        "tool_call_id": payload.get("toolCallId") or "",
    }
