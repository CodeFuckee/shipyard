"""AI Agent 路由。

- GET  /admin/agent/status     — Agent 状态（LLM 配置 + 工具 + 生效镜像源列表）
- GET  /admin/agent/tools      — 可用工具列表（skills 2 个 + MCP Docker 工具 33 个）
- POST /admin/agent/chat       — 非流式对话：Agent 自动调用工具执行
- POST /admin/agent/chat/stream — 流式对话（SSE）：token 增量 + 工具执行步骤

所有端点受 X-API-Key 保护；LLM 复用 hermes 接入配置，未启用时返回 503。
"""

import json
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field, field_validator

from app.agent import mcp_tools, service
from app.agent.mirror_sources import get_mirror_prefixes
from app.agent.service import MCP_TOOL_NAMES
from app.core.security import get_api_key
from app.services import hermes_client
from app.services.hermes_client import HermesError, HermesNotConfiguredError

router = APIRouter(prefix="/admin/agent", tags=["agent"])

_VALID_ROLES = {"system", "user", "assistant", "tool"}


class AgentChatRequest(BaseModel):
    """对话请求体。messages 为 OpenAI 兼容的消息列表。"""

    messages: List[dict] = Field(min_length=1)
    max_iterations: Optional[int] = Field(default=None, ge=1, le=50)

    @field_validator("messages")
    def validate_messages(cls, value: List[dict]) -> List[dict]:
        for msg in value:
            role = msg.get("role")
            if role not in _VALID_ROLES:
                raise ValueError(f"非法 role: {role!r}（必须为 system/user/assistant/tool 之一）")
            if not isinstance(msg.get("content"), str):
                raise ValueError("每条消息必须包含字符串类型的 content 字段")
        return value


class AgentChatStreamRequest(AgentChatRequest):
    """流式对话请求体：额外支持动态选择工具。

    tools 为空数组或全空白时视为未指定（None），回退默认 skill 工具——
    前端在工具全不选或加载失败时会发送空数组，宽容处理避免 422（issue #23）。
    """

    tools: Optional[List[str]] = Field(default=None)

    @field_validator("tools")
    def validate_tools(cls, value: Optional[List[str]]) -> Optional[List[str]]:
        if value is None:
            return None
        names = [v.strip() for v in value if v and v.strip()]
        if not names:
            return None  # 空数组/全空白 → 未指定（默认 skill 工具）
        return list(dict.fromkeys(names))  # 去重并保持顺序


@router.get("/status", response_model=dict)
def agent_status(_: str = Depends(get_api_key)):
    """Agent 状态：LLM 配置（复用 hermes）+ 可用工具 + 生效镜像源列表。"""
    status = hermes_client.hermes_status()
    status["tools"] = service.SKILL_TOOL_NAMES
    status["mirror_prefixes"] = get_mirror_prefixes()
    return status


@router.get("/tools", response_model=dict)
def agent_tools(_: str = Depends(get_api_key)):
    """可用工具列表：skills（backend/skills 两个）+ MCP Docker 工具（33 个）。

    供前端 AI agent 聊天框的选择器使用；tools 含 name/description/group/parameters。
    """
    return {
        "skills": mcp_tools.SKILL_TOOL_META,
        "tools": mcp_tools.get_mcp_tools_meta(),
    }


@router.post("/chat", response_model=dict)
def agent_chat(data: AgentChatRequest, _: str = Depends(get_api_key)):
    """与 Agent 对话：Agent 自动调用工具执行，返回最终回复与执行步骤。"""
    try:
        return service.run_agent(data.messages, max_iterations=data.max_iterations)
    except HermesNotConfiguredError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from None
    except HermesError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from None


def _validate_tool_names(tools_names: Optional[List[str]]) -> None:
    """校验工具名集合：含未知工具名时返回 400（防静默降级）。"""
    if not tools_names:
        return
    known = set(service.SKILL_TOOL_NAMES) | MCP_TOOL_NAMES
    unknown = [n for n in tools_names if n not in known]
    if unknown:
        raise HTTPException(status_code=400, detail=f"未知工具：{', '.join(unknown)}")


@router.post("/chat/stream")
async def agent_chat_stream(
    data: AgentChatStreamRequest, _: str = Depends(get_api_key)
):
    """流式对话（SSE）：逐段推送 token 增量与工具执行步骤。

    SSE 事件：token / step / step_result / reply / done / error。
    hermes 未配置时直接 503（无流）；流内上游错误转为 error 事件。
    """
    if not hermes_client.hermes_status()["enabled"]:
        raise HTTPException(status_code=503, detail="LLM 未配置")
    _validate_tool_names(data.tools)

    async def _sse_events():
        """把 agent 事件 dict 编码为 SSE 帧（event: <type>\\ndata: <json>\\n\\n）。"""
        async for event in service.stream_agent(
            data.messages, tools_names=data.tools, max_iterations=data.max_iterations
        ):
            event_type = event["type"]
            payload = {k: v for k, v in event.items() if k != "type"}
            data_json = json.dumps(payload, ensure_ascii=False)
            yield f"event: {event_type}\ndata: {data_json}\n\n"

    return StreamingResponse(
        _sse_events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
