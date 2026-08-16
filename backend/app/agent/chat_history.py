"""AI 助手对话历史 — 多会话保存、读取、删除与旧数据迁移（issue #38）。

多会话语义（issue #38，方案B）：
- 每次成功对话（流式与非流式）保存/更新到一条「会话」记录
  （agent_chat_sessions 表，多行）；前端在请求中携带 session_id，
  为空则新建会话，否则更新该会话
- 会话标题自动取首条用户消息摘要（前 30 字符，超长截断加省略号）
- 会话列表最多保留 MAX_SESSIONS（100）条，超出自动删除最旧会话
- 支持删除单条会话；聊天窗口头部「历史」按钮浏览全部会话并
  重新打开任意一条

旧数据迁移（单例 agent_chat_history，issue #32）：
- 升级前旧版只保存单条对话（id=1 覆盖式）。首次读取会话列表或
  历史消息时，若单例记录仍有消息，自动迁移为一条会话（标题取
  首条用户消息摘要），随后删除单例记录（幂等，仅迁移一次；
  旧表结构保留，旧端点继续可用）。

保存语义（沿用 issue #32）：
- 仅保留 user/assistant 消息（system/tool 不入库，前端恢复不需要）
- 追加本次回复为最后一条 assistant 消息，工具执行步骤（step /
  step_result 事件）挂在该消息的 steps 字段
- 空回复不追加（避免恢复后出现空消息占位）
- 失败对话不调用本模块：已有历史不被破坏
"""

import json
from datetime import datetime
from typing import List, Optional

from sqlalchemy.orm import Session

from app.db.models import AgentChatHistoryModel, AgentChatSessionModel

# 可恢复展示的角色：对话历史只需 user/assistant
_VISIBLE_ROLES = {"user", "assistant"}
# 挂到 assistant 消息 steps 上的事件类型
_STEP_EVENT_TYPES = {"step", "step_result"}
# 步骤事件对外暴露的字段
_STEP_FIELDS = ("type", "name", "arguments", "result")
# 会话列表上限：超出自动删除最旧会话（issue #38）
MAX_SESSIONS = 100
# 会话标题摘要长度：首条用户消息前 30 字符，超长截断加省略号
_TITLE_MAX_LEN = 30
# 无用户消息时的默认标题
_DEFAULT_TITLE = "新会话"


def _title_from_messages(messages: List[dict]) -> str:
    """会话标题：取首条用户消息的摘要（前 _TITLE_MAX_LEN 字符）。

    折叠换行为空格、去首尾空白；无用户消息或内容为空时回退「新会话」。
    """
    for msg in messages:
        if msg.get("role") == "user":
            content = (msg.get("content") or "").strip().replace("\n", " ")
            if content:
                suffix = "…" if len(content) > _TITLE_MAX_LEN else ""
                return content[:_TITLE_MAX_LEN] + suffix
    return _DEFAULT_TITLE


def _build_saved_messages(
    messages: List[dict], reply: str, events: List[dict]
) -> List[dict]:
    """过滤请求消息 + 追加本次助手回复（沿用 issue #32 保存语义）。"""
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
    return saved


def _load_messages_json(raw: Optional[str]) -> List[dict]:
    """解析 messages_json；空或非法 JSON 返回 []。"""
    if not raw:
        return []
    try:
        messages = json.loads(raw)
    except json.JSONDecodeError:
        return []
    return messages if isinstance(messages, list) else []


def _session_dict(row: AgentChatSessionModel, *, with_messages: bool = False) -> dict:
    """会话记录 → 对外 dict（列表摘要；with_messages 时含完整消息）。"""
    data = {
        "id": row.id,
        "title": row.title or _DEFAULT_TITLE,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }
    if with_messages:
        data["messages"] = _load_messages_json(row.messages_json)
    return data


def _migrate_singleton(db: Session) -> None:
    """旧单例历史迁移为会话（issue #38），幂等仅执行一次。

    升级前旧版仅保存单条对话（agent_chat_history id=1 覆盖式）。
    首次访问会话列表/历史消息时，若单例记录仍有消息，将其迁移为
    一条会话（标题取首条用户消息摘要），随后删除单例记录——记录
    已不存在时不再执行。数据库表已有数据时只增不删旧表结构，
    仅迁移完成后删除单例行（避免重复触发）。
    """
    row = (
        db.query(AgentChatHistoryModel)
        .filter(AgentChatHistoryModel.id == 1)
        .first()
    )
    if row is None:
        return
    messages = _load_messages_json(row.messages_json)
    if messages:
        base_time = row.updated_at or datetime.utcnow()
        db.add(
            AgentChatSessionModel(
                title=_title_from_messages(messages),
                messages_json=json.dumps(messages, ensure_ascii=False),
                created_at=base_time,
                updated_at=base_time,
            )
        )
    db.delete(row)  # 迁移完成删除单例记录（空记录一并删除，避免重复触发）
    db.commit()


def _prune_sessions(db: Session) -> int:
    """删除超过 MAX_SESSIONS 的最旧会话，返回删除条数（对空表幂等）。"""
    total = db.query(AgentChatSessionModel).count()
    if total <= MAX_SESSIONS:
        return 0
    newest_ids = (
        db.query(AgentChatSessionModel.id)
        .order_by(
            AgentChatSessionModel.updated_at.desc(),
            AgentChatSessionModel.id.desc(),
        )
        .limit(MAX_SESSIONS)
        .all()
    )
    keep = {row[0] for row in newest_ids}
    deleted = (
        db.query(AgentChatSessionModel)
        .filter(~AgentChatSessionModel.id.in_(keep))
        .delete(synchronize_session=False)
    )
    db.commit()
    return deleted


def save_conversation(
    db: Session,
    *,
    session_id: Optional[int] = None,
    messages: List[dict],
    reply: str,
    events: List[dict],
) -> dict:
    """保存/更新会话，返回会话摘要 {id, title, updated_at}（issue #38）。

    session_id 为 None 时新建会话；否则更新该会话（标题保持首次创建
    时的摘要不变）。新建后清理超限的最旧会话。
    """
    saved = _build_saved_messages(messages, reply, events)
    now = datetime.utcnow()
    if session_id is not None:
        row = (
            db.query(AgentChatSessionModel)
            .filter(AgentChatSessionModel.id == session_id)
            .first()
        )
        if row is not None:
            row.messages_json = json.dumps(saved, ensure_ascii=False)
            row.updated_at = now
            db.commit()
            return _session_dict(row)
    row = AgentChatSessionModel(
        title=_title_from_messages(messages),
        messages_json=json.dumps(saved, ensure_ascii=False),
        created_at=now,
        updated_at=now,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    _prune_sessions(db)
    return _session_dict(row)


def get_sessions(db: Session) -> List[dict]:
    """全部会话摘要，最新在前（至多 MAX_SESSIONS 条；含旧数据迁移）。"""
    _migrate_singleton(db)
    rows = (
        db.query(AgentChatSessionModel)
        .order_by(
            AgentChatSessionModel.updated_at.desc(),
            AgentChatSessionModel.id.desc(),
        )
        .all()
    )
    return [_session_dict(r) for r in rows]


def get_session_messages(db: Session, session_id: int) -> Optional[dict]:
    """单条会话详情（含完整消息列表）；不存在返回 None。"""
    _migrate_singleton(db)
    row = (
        db.query(AgentChatSessionModel)
        .filter(AgentChatSessionModel.id == session_id)
        .first()
    )
    if row is None:
        return None
    return _session_dict(row, with_messages=True)


def delete_session(db: Session, session_id: int) -> bool:
    """删除单条会话，返回是否存在（存在即已删除）。"""
    deleted = (
        db.query(AgentChatSessionModel)
        .filter(AgentChatSessionModel.id == session_id)
        .delete(synchronize_session=False)
    )
    db.commit()
    return deleted > 0


def get_messages(db: Session) -> List[dict]:
    """（旧端点兼容，issue #32 单例语义升级后）返回最近会话的消息列表。

    先迁移旧单例记录，再返回最新会话（updated_at 最大）的完整消息；
    无任何会话时返回 []。
    """
    _migrate_singleton(db)
    row = (
        db.query(AgentChatSessionModel)
        .order_by(
            AgentChatSessionModel.updated_at.desc(),
            AgentChatSessionModel.id.desc(),
        )
        .first()
    )
    if row is None:
        return []
    return _load_messages_json(row.messages_json)


def clear_history(db: Session) -> int:
    """（旧端点兼容）清空全部会话，返回删除条数（对空表幂等）。"""
    _migrate_singleton(db)
    deleted = db.query(AgentChatSessionModel).delete(synchronize_session=False)
    db.commit()
    return deleted
