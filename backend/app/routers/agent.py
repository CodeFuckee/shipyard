"""镜像拉取 Agent 路由。

- GET  /admin/agent/status — Agent 状态（LLM 配置 + 工具 + 生效镜像源列表）
- POST /admin/agent/chat   — 非流式对话：Agent 自动调用 skill 工具拉取镜像

所有端点受 X-API-Key 保护；LLM 复用 hermes 接入配置，未启用时返回 503。
"""

from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.agent import service
from app.agent.mirror_sources import get_mirror_prefixes
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


@router.get("/status", response_model=dict)
def agent_status(_: str = Depends(get_api_key)):
    """Agent 状态：LLM 配置（复用 hermes）+ 可用工具 + 生效镜像源列表。"""
    status = hermes_client.hermes_status()
    status["tools"] = ["docker_mirror_pull", "docker_pull_from_file"]
    status["mirror_prefixes"] = get_mirror_prefixes()
    return status


@router.post("/chat", response_model=dict)
def agent_chat(data: AgentChatRequest, _: str = Depends(get_api_key)):
    """与镜像拉取 Agent 对话：Agent 自动调用工具完成拉取，返回最终回复与执行步骤。"""
    try:
        return service.run_agent(data.messages, max_iterations=data.max_iterations)
    except HermesNotConfiguredError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from None
    except HermesError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from None
