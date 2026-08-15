"""AI 助手对话历史 — 保存、读取与清空（issue #32）。

前端聊天窗口打开时通过 GET /admin/agent/chat-history 恢复历史对话；
每次成功对话（流式与非流式）在路由层调用 save_conversation 覆盖
保存完整消息列表到 agent_chat_history 单例记录（id=1）。

保存语义：
- 仅保留 user/assistant 消息（system/tool 不入库，前端恢复不需要）
- 追加本次回复为最后一条 assistant 消息，工具执行步骤（step /
  step_result 事件）挂在该消息的 steps 字段
- 空回复不追加（避免恢复后出现空消息占位）
- 失败对话不调用本模块：已有历史不被破坏
"""

import json
from datetime import datetime
from typing import List

from sqlalchemy.orm import Session

from app.db.models import AgentChatHistoryModel

# 可恢复展示的角色：对话历史只需 user/assistant
_VISIBLE_ROLES = {"user", "assistant"}
# 挂到 assistant 消息 steps 上的事件类型
_STEP_EVENT_TYPES = {"step", "step_result"}
# 步骤事件对外暴露的字段
_STEP_FIELDS = ("type", "name", "arguments", "result")


def get_messages(db: Session) -> List[dict]:
    """读取单例记录的消息列表；无记录、空记录或非法 JSON 返回 []。"""
    row = (
        db.query(AgentChatHistoryModel)
        .filter(AgentChatHistoryModel.id == 1)
        .first()
    )
    if row is None or not row.messages_json:
        return []
    try:
        messages = json.loads(row.messages_json)
    except json.JSONDecodeError:
        return []
    return messages if isinstance(messages, list) else []


def save_conversation(
    db: Session,
    *,
    messages: List[dict],
    reply: str,
    events: List[dict],
) -> None:
    """覆盖保存完整对话：过滤后的请求消息 + 本次助手回复（含工具步骤）。

    参数:
        messages: 本次请求消息列表（前端每次发送带全部历史，覆盖保存
            即等于最新完整对话）
        reply: 最终回复全文；非空时追加为最后一条 assistant 消息
        events: 步骤/工具调用事件序列（流式 step/step_result 或非流式
            steps 转换而来）
    """
    saved = [
        {"role": m.get("role"), "content": m.get("content", "")}
        for m in messages
        if m.get("role") in _VISIBLE_ROLES and isinstance(m.get("content"), str)
    ]
    if reply:
        saved.append(
            {
                "role": "assistant",
                "content": reply,
                "steps": [
                    {k: v for k, v in e.items() if k in _STEP_FIELDS}
                    for e in events
                    if e.get("type") in _STEP_EVENT_TYPES
                ],
            }
        )
    row = (
        db.query(AgentChatHistoryModel)
        .filter(AgentChatHistoryModel.id == 1)
        .first()
    )
    if row is None:
        row = AgentChatHistoryModel(id=1)
        db.add(row)
    row.messages_json = json.dumps(saved, ensure_ascii=False)
    row.updated_at = datetime.utcnow()
    db.commit()


def clear_history(db: Session) -> int:
    """删除单例记录，返回删除条数（对空表幂等）。"""
    deleted = (
        db.query(AgentChatHistoryModel)
        .filter(AgentChatHistoryModel.id == 1)
        .delete(synchronize_session=False)
    )
    db.commit()
    return deleted
