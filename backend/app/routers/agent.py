"""AI Agent 路由。

- GET  /admin/agent/status     — Agent 状态（LLM 配置 + 工具 + 生效镜像源列表）
- GET  /admin/agent/tools      — 可用工具列表（skills 2 个 + MCP Docker 工具 33 个）
- POST /admin/agent/chat       — 非流式对话：Agent 自动调用工具执行
- POST /admin/agent/chat/stream — 流式对话（SSE）：token 增量 + 工具执行步骤
- GET/DELETE /admin/agent/debug-logs — 调试日志（issue #24）：
  每次对话自动落库 agent_chat_logs（保留最近 100 条），供设置页调试页查看
- GET/DELETE /admin/agent/chat-history — 对话历史（issue #32）：
  成功对话自动覆盖保存到 agent_chat_history 单例记录，供聊天窗口恢复历史
- GET/POST/PUT/DELETE /admin/agent/chat-sessions — 多会话历史（issue #38）：
  每次成功对话保存/更新为一条会话（agent_chat_sessions 多行记录），
  支持浏览会话列表、恢复单条会话、快照保存与删除单条；请求携带
  session_id 时更新该会话，否则新建；旧单例记录首次访问时自动迁移

所有端点受 X-API-Key 保护；LLM 优先 hermes 接入，未配置时回退 ai_providers
默认供应商（issue #21 第四轮），两者都不可用时返回 503。
LLM 相关错误响应携带结构化 error_code，前端据此展示引导提示（issue #23）。
"""

import json
import time
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field, ValidationError, field_validator
from sqlalchemy.orm import Session

from app.agent import chat_history, debug_log, mcp_tools, service
from app.agent.mirror_sources import get_mirror_prefixes
from app.agent.service import LLMNotConfiguredError, MCP_TOOL_NAMES
from app.core.security import get_api_key
from app.db.database import get_db
from app.services import hermes_client
from app.services.hermes_client import HermesError, HermesNotConfiguredError

router = APIRouter(prefix="/admin/agent", tags=["agent"])

_VALID_ROLES = {"system", "user", "assistant", "tool"}

# 结构化错误码（issue #23）：前端按 error_code 展示引导提示（如跳转配置页）。
ERROR_CODE_LLM_NOT_CONFIGURED = "llm_not_configured"
ERROR_CODE_LLM_UPSTREAM = "llm_upstream_error"


def _llm_error_response(status_code: int, error_code: str, detail: str) -> JSONResponse:
    """LLM 相关错误的结构化响应：error_code + 中文 detail（前端兼容旧解析）。"""
    return JSONResponse(
        status_code=status_code,
        content={"error_code": error_code, "detail": detail},
    )


class AgentChatRequest(BaseModel):
    """对话请求体。messages 为 OpenAI 兼容的消息列表。

    session_id（issue #38）：当前对话所属会话 id，由前端在恢复历史
    会话或收到新建会话 id 后携带；为空时成功对话新建一条会话。
    """

    messages: List[dict] = Field(min_length=1)
    max_iterations: Optional[int] = Field(default=None, ge=1, le=50)
    session_id: Optional[int] = Field(default=None, ge=1)

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
def agent_status(db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """Agent 状态：LLM 配置（hermes 或回退的 AI 供应商）+ 可用工具 + 生效镜像源列表。

    llm_source / llm_name 标识实际生效的 LLM 来源（hermes | provider），
    两者都不可用时为 null（issue #21 第四轮）。
    """
    status = hermes_client.hermes_status()
    try:
        llm = service.resolve_llm_config(db)
        status["llm_source"] = llm["source"]
        status["llm_name"] = llm["name"]
    except LLMNotConfiguredError:
        status["llm_source"] = None
        status["llm_name"] = None
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


def _last_user_text(messages: List[dict]) -> str:
    """提取最后一条 user 消息文本，作为调试日志列表的摘要。"""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            return msg.get("content", "")
    return ""


@router.post("/chat", response_model=dict)
def agent_chat(
    data: AgentChatRequest,
    db: Session = Depends(get_db),
    _: str = Depends(get_api_key),
):
    """与 Agent 对话：Agent 自动调用工具执行，返回最终回复与执行步骤。

    LLM 优先 hermes，未配置时回退 ai_providers 默认供应商（issue #21）。
    每次对话（成功或失败）都记录调试日志（issue #24）。
    """
    started = time.monotonic()
    llm_config = None
    try:
        llm_config = service.resolve_llm_config(db)
        result = service.run_agent(
            data.messages, max_iterations=data.max_iterations, llm_config=llm_config
        )
        debug_log.record_agent_log(
            db,
            request_messages=data.messages,
            request_text=_last_user_text(data.messages),
            llm_config=llm_config,
            tools_names=None,  # 非流式对话使用默认 skill 工具集
            status="success",
            error_message="",
            duration_ms=int((time.monotonic() - started) * 1000),
            events=result.get("steps", []),
            reply=result.get("reply", ""),
        )
        # issue #32/#38：成功对话（有回复）保存/更新对话历史：
        # 携带 session_id 更新该会话，否则新建会话，响应附加会话 id
        reply = result.get("reply", "")
        if reply:
            session = chat_history.save_conversation(
                db,
                session_id=data.session_id,
                messages=data.messages,
                reply=reply,
                events=result.get("steps", []),
            )
            result["session_id"] = session["id"]
        return result
    except LLMNotConfiguredError as exc:
        debug_log.record_agent_log(
            db,
            request_messages=data.messages,
            request_text=_last_user_text(data.messages),
            llm_config=llm_config,
            tools_names=None,
            status="error",
            error_message=exc.message,
            duration_ms=int((time.monotonic() - started) * 1000),
            events=[],
            reply="",
        )
        return _llm_error_response(exc.status_code, ERROR_CODE_LLM_NOT_CONFIGURED, exc.message)
    except HermesNotConfiguredError as exc:
        debug_log.record_agent_log(
            db,
            request_messages=data.messages,
            request_text=_last_user_text(data.messages),
            llm_config=llm_config,
            tools_names=None,
            status="error",
            error_message=exc.message,
            duration_ms=int((time.monotonic() - started) * 1000),
            events=[],
            reply="",
        )
        return _llm_error_response(exc.status_code, ERROR_CODE_LLM_NOT_CONFIGURED, exc.message)
    except HermesError as exc:
        debug_log.record_agent_log(
            db,
            request_messages=data.messages,
            request_text=_last_user_text(data.messages),
            llm_config=llm_config,
            tools_names=None,
            status="error",
            error_message=exc.message,
            duration_ms=int((time.monotonic() - started) * 1000),
            events=[],
            reply="",
        )
        return _llm_error_response(exc.status_code, ERROR_CODE_LLM_UPSTREAM, exc.message)


def _validate_tool_names(tools_names: Optional[List[str]]) -> None:
    """校验工具名集合：含未知工具名时返回 400（防静默降级）。"""
    if not tools_names:
        return
    known = set(service.SKILL_TOOL_NAMES) | MCP_TOOL_NAMES
    unknown = [n for n in tools_names if n not in known]
    if unknown:
        raise HTTPException(status_code=400, detail=f"未知工具：{', '.join(unknown)}")


async def _parse_chat_stream_body(request: Request) -> AgentChatStreamRequest:
    """解析流式对话请求体，兼容缺失 Content-Type: application/json 的字符串 body。

    前端 SSE 客户端发送 JSON 字符串时未带 application/json 头（issue #23），
    FastAPI 不解析 JSON，把整个字符串绑定给 Pydantic 模型报
    model_attributes_type 422。这里手动 json.loads 兜底，再走相同的
    Pydantic 校验，校验错误仍以标准 422 格式返回。
    """
    raw = await request.body()
    try:
        payload = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise HTTPException(status_code=422, detail=f"请求体不是有效的 JSON：{exc}") from None
    if not isinstance(payload, dict):
        raise HTTPException(status_code=422, detail="请求体必须是 JSON 对象")
    try:
        return AgentChatStreamRequest.model_validate(payload)
    except ValidationError as exc:
        raise RequestValidationError(exc.errors()) from None


@router.post("/chat/stream")
async def agent_chat_stream(
    data: AgentChatStreamRequest = Depends(_parse_chat_stream_body),
    db: Session = Depends(get_db),
    _: str = Depends(get_api_key),
):
    """流式对话（SSE）：逐段推送 token 增量与工具执行步骤。

    SSE 事件：token / step / step_result / reply / done / error。
    LLM 优先 hermes，未配置时回退 ai_providers 默认供应商（issue #21）；
    两者都不可用时直接返回结构化 503（无流）；流内上游错误转为 error 事件。
    """
    try:
        llm_config = service.resolve_llm_config(db)
    except LLMNotConfiguredError as exc:
        debug_log.record_agent_log(
            db,
            request_messages=data.messages,
            request_text=_last_user_text(data.messages),
            llm_config=None,
            tools_names=data.tools,
            status="error",
            error_message=exc.message,
            duration_ms=0,
            events=[],
            reply="",
        )
        return _llm_error_response(exc.status_code, ERROR_CODE_LLM_NOT_CONFIGURED, exc.message)
    _validate_tool_names(data.tools)

    async def _sse_events():
        """把 agent 事件 dict 编码为 SSE 帧，同时收集调试日志（issue #24）。

        token 增量拼接为最终回复；step/step_result 存入事件序列；
        error 事件标记失败。finally 落库，客户端中途断开也记录。
        """
        started = time.monotonic()
        events: List[dict] = []
        reply = ""
        status = "success"
        error_message = ""
        try:
            async for event in service.stream_agent(
                data.messages,
                tools_names=data.tools,
                max_iterations=data.max_iterations,
                llm_config=llm_config,
            ):
                event_type = event["type"]
                if event_type == "token":
                    reply += event.get("content", "")
                elif event_type == "reply":
                    reply = event.get("content", "")
                elif event_type == "error":
                    status = "error"
                    error_message = event.get("message", "")
                elif event_type in ("step", "step_result"):
                    events.append(event)
                payload = {k: v for k, v in event.items() if k != "type"}
                data_json = json.dumps(payload, ensure_ascii=False)
                yield f"event: {event_type}\ndata: {data_json}\n\n"
        finally:
            debug_log.record_agent_log(
                db,
                request_messages=data.messages,
                request_text=_last_user_text(data.messages),
                llm_config=llm_config,
                tools_names=data.tools,
                status=status,
                error_message=error_message,
                duration_ms=int((time.monotonic() - started) * 1000),
                events=events,
                reply=reply,
            )
            # issue #32/#38：仅成功且回复非空的对话保存/更新历史，
            # 失败对话（error 事件）不破坏已有记录；携带 session_id
            # 更新该会话，否则新建会话。
            session = None
            if status == "success" and reply:
                session = chat_history.save_conversation(
                    db,
                    session_id=data.session_id,
                    messages=data.messages,
                    reply=reply,
                    events=events,
                )
            # issue #38：把新建/更新后的会话 id 推给前端（首次对话后
            # 前端持有 id，后续对话携带以便更新同一会话）。
            # 客户端中途断开（GeneratorExit）时 yield 无效：会话已
            # 落库，前端下次打开历史列表仍可恢复，忽略即可。
            if session is not None:
                try:
                    yield (
                        f"event: session_id\n"
                        f"data: {json.dumps({'session_id': session['id']}, ensure_ascii=False)}\n\n"
                    )
                except GeneratorExit:
                    pass

    return StreamingResponse(
        _sse_events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.get("/debug-logs", response_model=dict)
def agent_debug_logs(db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """调试日志列表（issue #24）：每次对话的摘要，最新在前。

    仅返回摘要字段（不含完整消息/事件/回复正文），详情见
    GET /admin/agent/debug-logs/{log_id}。
    """
    return {"logs": debug_log.list_logs(db)}


@router.get("/debug-logs/{log_id}", response_model=dict)
def agent_debug_log_detail(
    log_id: str,
    db: Session = Depends(get_db),
    _: str = Depends(get_api_key),
):
    """调试日志详情（issue #24）：完整请求消息、步骤/工具调用事件与回复。"""
    log = debug_log.get_log(db, log_id)
    if log is None:
        raise HTTPException(status_code=404, detail="调试记录不存在")
    return log


@router.delete("/debug-logs", response_model=dict)
def agent_debug_logs_clear(db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """清空全部调试日志（issue #24），返回删除条数。"""
    return {"deleted": debug_log.clear_logs(db)}


@router.get("/chat-history", response_model=dict)
def agent_chat_history(db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """对话历史（issue #32）：完整消息列表，供聊天窗口打开时恢复。

    消息格式：{"role": "user"|"assistant", "content": str,
    "steps": [{"type", "name", "arguments"|"result"}]}（steps 仅
    assistant 消息携带）。无历史时返回 {"messages": []}。
    """
    return {"messages": chat_history.get_messages(db)}


@router.delete("/chat-history", response_model=dict)
def agent_chat_history_clear(db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """清空对话历史（issue #32），返回删除条数（空表幂等返回 0）。"""
    return {"deleted": chat_history.clear_history(db)}


class AgentSessionSaveRequest(BaseModel):
    """会话保存请求（issue #38）：快照保存/更新历史会话，不触发 LLM。

    reply/events 用于「打开新会话」前把当前对话完整快照保存为一条
    历史会话（reply 为空时仅保存用户与助手消息，不追加空占位）。
    """

    messages: List[dict] = Field(default_factory=list)
    reply: Optional[str] = Field(default="")
    events: List[dict] = Field(default_factory=list)


@router.get("/chat-sessions", response_model=dict)
def agent_chat_sessions(db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """多会话历史列表（issue #38）：全部会话摘要，最新在前。

    每项含 id/title（首条用户消息摘要）/updated_at；最多保留 100 条。
    首次访问时自动迁移旧版单例对话历史（agent_chat_history）为一条会话。
    """
    return {"sessions": chat_history.get_sessions(db)}


@router.post("/chat-sessions", response_model=dict)
def agent_chat_session_create(
    data: AgentSessionSaveRequest,
    db: Session = Depends(get_db),
    _: str = Depends(get_api_key),
):
    """新建历史会话（issue #38）：保存当前对话快照，返回会话摘要。

    供前端「打开新会话」前把尚未落库的当前对话存入历史；
    标题自动取首条用户消息摘要。
    """
    return chat_history.save_conversation(
        db,
        session_id=None,
        messages=data.messages,
        reply=data.reply or "",
        events=data.events or [],
    )


@router.get("/chat-sessions/{session_id}", response_model=dict)
def agent_chat_session_detail(
    session_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(get_api_key),
):
    """单条会话详情（issue #38）：完整消息列表，供前端恢复该会话。"""
    session = chat_history.get_session_messages(db, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="会话不存在")
    return session


@router.put("/chat-sessions/{session_id}", response_model=dict)
def agent_chat_session_update(
    session_id: int,
    data: AgentSessionSaveRequest,
    db: Session = Depends(get_db),
    _: str = Depends(get_api_key),
):
    """更新历史会话（issue #38）：覆盖该会话的消息列表（标题不变）。"""
    if chat_history.get_session_messages(db, session_id) is None:
        raise HTTPException(status_code=404, detail="会话不存在")
    return chat_history.save_conversation(
        db,
        session_id=session_id,
        messages=data.messages,
        reply=data.reply or "",
        events=data.events or [],
    )


@router.delete("/chat-sessions/{session_id}", response_model=dict)
def agent_chat_session_delete(
    session_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(get_api_key),
):
    """删除单条历史会话（issue #38），返回删除条数。"""
    if not chat_history.delete_session(db, session_id):
        raise HTTPException(status_code=404, detail="会话不存在")
    return {"deleted": 1}
