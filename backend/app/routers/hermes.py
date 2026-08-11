"""Hermes 接入路由 — 调用其他设备上部署的 hermes 实例（OpenAI 兼容 API）。

- GET  /admin/hermes/status      — 接入配置状态 + 连接测试
- PUT  /admin/hermes/config      — 保存接入配置（前端设置页，数据库持久化）
- POST /admin/hermes/chat        — 非流式对话
- POST /admin/hermes/chat/stream — SSE 流式对话

所有端点受 X-API-Key 保护；配置优先级：数据库保存值 > 环境变量
（HERMES_BASE_URL 等），未配置时 /status 返回 enabled=false，对话端点返回 503。
"""

import json
from typing import List, Optional
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.core.security import get_api_key
from app.db.database import get_db
from app.services import hermes_client, hermes_config

router = APIRouter(prefix="/admin/hermes", tags=["hermes"])

_VALID_ROLES = {"system", "user", "assistant", "tool"}


class HermesConfigRequest(BaseModel):
    """保存 Hermes 接入配置请求体。

    base_url 为空字符串 = 禁用接入；api_key 为空字符串 = 不修改已存储的 Key。
    """

    base_url: str = Field(default="", max_length=512)
    api_key: str = Field(default="", max_length=1024)
    model: str = Field(default="", max_length=128)

    @field_validator("base_url")
    def validate_base_url(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            return ""
        if any(ch.isspace() for ch in stripped):
            raise ValueError("base_url 不能包含空白字符")
        url = stripped.rstrip("/")
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise ValueError("base_url 必须是合法的 http(s) 地址")
        return url


def _config_response() -> dict:
    """保存后的状态 + 连接测试结果（任何响应不含 Key 明文）。"""
    result = hermes_client.hermes_status()
    result["test"] = hermes_client.test_connection()
    return result


class HermesChatRequest(BaseModel):
    """对话请求体。messages 为 OpenAI 兼容的消息列表。"""

    messages: List[dict] = Field(min_length=1)
    model: Optional[str] = Field(default=None, max_length=128)
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)

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
def hermes_status(_: str = Depends(get_api_key)):
    """Hermes 接入配置状态 + 连接测试结果。

    配置来自环境变量与数据库保存值；即使未启用也返回 200，由 enabled 字段标识。
    """
    return _config_response()


@router.put("/config", response_model=dict)
def save_hermes_config(
    data: HermesConfigRequest,
    db: Session = Depends(get_db),
    _: str = Depends(get_api_key),
):
    """保存 Hermes 接入配置（前端设置页）。

    - base_url 为空字符串 = 禁用接入；非空必须是合法 http(s) 地址
    - api_key 为空字符串 = 不修改已存储的 Key（加密存储，响应不含明文）
    - 保存后立即同步运行时配置（无需重启后端），并返回状态 + 连接测试结果
    """
    config = hermes_config.save(
        db,
        base_url=data.base_url,
        api_key=data.api_key,
        model=data.model,
    )
    hermes_client.set_runtime_config(
        base_url=config["base_url"],
        api_key=config["api_key"],
        model=config["model"],
    )
    return _config_response()


@router.post("/chat", response_model=dict)
def hermes_chat(data: HermesChatRequest, _: str = Depends(get_api_key)):
    """调用 hermes 对话接口（非流式），透传 OpenAI 兼容的完整响应。"""
    try:
        return hermes_client.chat_completion(
            messages=data.messages,
            model=data.model,
            temperature=data.temperature,
        )
    except hermes_client.HermesNotConfiguredError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from None
    except hermes_client.HermesError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from None


@router.post("/chat/stream")
def hermes_chat_stream(data: HermesChatRequest, _: str = Depends(get_api_key)):
    """调用 hermes 对话接口（SSE 流式）。

    事件格式：{"type": "delta", "content"} / {"type": "done"} / {"type": "error", "message"}
    """
    try:
        hermes_client.ensure_configured()
    except hermes_client.HermesNotConfiguredError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from None

    events = hermes_client.stream_chat_completion(
        messages=data.messages,
        model=data.model,
        temperature=data.temperature,
    )

    def sse_generator():
        for event in events:
            yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(sse_generator(), media_type="text/event-stream")
