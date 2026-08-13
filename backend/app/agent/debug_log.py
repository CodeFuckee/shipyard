"""AI Agent 调试日志 — 记录、查询与清理（issue #24）。

设置页「AI 调试日志」的数据源：每次对话（流式与非流式）在路由层
调用 record_agent_log 落库 agent_chat_logs 表。列表接口只暴露摘要
字段，详情含完整请求消息、步骤/工具调用事件序列与最终回复。

保留策略：每次写入后自动清理，仅保留最近 MAX_LOGS（100）条，
防止 SQLite 无限膨胀；DELETE 端点支持一键清空。

安全：llm_config 中的 api_key / base_url 不入库，仅提取
source / name / model 三个展示字段。
"""

import json
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.db.models import AgentChatLogModel

MAX_LOGS = 100  # 调试记录上限：超出自动清理最旧记录


def record_agent_log(
    db: Session,
    *,
    request_messages: List[dict],
    request_text: str,
    llm_config: Optional[dict],
    tools_names: Optional[List[str]],
    status: str,
    error_message: str,
    duration_ms: int,
    events: List[dict],
    reply: str,
    created_at: Optional[datetime] = None,
) -> str:
    """写入一条调试记录并清理超限旧记录，返回记录 id。

    参数:
        request_messages: 完整请求消息（对话情况，原样 JSON 保存）
        request_text: 列表摘要用的最后一条用户消息
        llm_config: resolve_llm_config 的结果（仅提取 source/name/model）
        tools_names: 本次启用的工具名列表
        status: success | error
        error_message: 失败原因（status=error 时）
        duration_ms: 本次对话总耗时（毫秒）
        events: 步骤/工具调用事件序列（流式 step/step_result 或非流式 steps）
        reply: 最终回复全文
        created_at: 记录时间（测试注入用；缺省为当前时间）
    """
    log = AgentChatLogModel(
        created_at=created_at or datetime.utcnow(),
        request_text=request_text,
        llm_source=(llm_config or {}).get("source"),
        llm_name=(llm_config or {}).get("name"),
        llm_model=(llm_config or {}).get("model"),
        tools_names=json.dumps(tools_names or [], ensure_ascii=False),
        status=status,
        error_message=error_message or None,
        duration_ms=duration_ms,
        messages_json=json.dumps(request_messages, ensure_ascii=False),
        events_json=json.dumps(events, ensure_ascii=False),
        reply_text=reply,
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    _prune(db)
    return log.id


def _prune(db: Session) -> int:
    """删除超过 MAX_LOGS 的最旧记录，返回删除条数。"""
    total = db.query(AgentChatLogModel).count()
    if total <= MAX_LOGS:
        return 0
    newest_ids = (
        db.query(AgentChatLogModel.id)
        .order_by(AgentChatLogModel.created_at.desc(), AgentChatLogModel.id.desc())
        .limit(MAX_LOGS)
        .all()
    )
    keep = {row[0] for row in newest_ids}
    deleted = (
        db.query(AgentChatLogModel)
        .filter(~AgentChatLogModel.id.in_(keep))
        .delete(synchronize_session=False)
    )
    db.commit()
    return deleted


def _summary_dict(row: AgentChatLogModel) -> dict:
    """列表摘要字段（不含大体积的 messages/events/reply）。"""
    return {
        "id": row.id,
        "created_at": row.created_at.isoformat(),
        "request_text": row.request_text or "",
        "llm_source": row.llm_source,
        "llm_name": row.llm_name,
        "llm_model": row.llm_model,
        "status": row.status,
        "duration_ms": row.duration_ms or 0,
    }


def list_logs(db: Session) -> List[dict]:
    """全部记录摘要，最新在前（至多 MAX_LOGS 条）。"""
    rows = (
        db.query(AgentChatLogModel)
        .order_by(AgentChatLogModel.created_at.desc(), AgentChatLogModel.id.desc())
        .all()
    )
    return [_summary_dict(r) for r in rows]


def get_log(db: Session, log_id: str) -> Optional[dict]:
    """单条记录详情；不存在返回 None。"""
    row = db.query(AgentChatLogModel).filter(AgentChatLogModel.id == log_id).first()
    if row is None:
        return None
    detail = _summary_dict(row)
    detail.update(
        {
            "tools_names": json.loads(row.tools_names or "[]"),
            "error_message": row.error_message or "",
            "messages": json.loads(row.messages_json or "[]"),
            "events": json.loads(row.events_json or "[]"),
            "reply": row.reply_text or "",
        }
    )
    return detail


def clear_logs(db: Session) -> int:
    """清空全部调试记录，返回删除条数（对空表幂等）。"""
    deleted = db.query(AgentChatLogModel).delete(synchronize_session=False)
    db.commit()
    return deleted
