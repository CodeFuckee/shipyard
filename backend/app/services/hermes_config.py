"""Hermes 接入配置存储 — 前端设置页保存的配置（数据库持久化）。

优先级：数据库保存的配置 > 环境变量（HERMES_BASE_URL / HERMES_API_KEY /
HERMES_MODEL）。API Key 经 crypto.encrypt 加密后存储，任何响应不返回明文。

路由保存后调用 hermes_client.set_runtime_config() 同步到运行时，
hermes_client 读取时数据库值优先于环境变量，无需重启后端。
"""

from sqlalchemy.orm import Session

from app.core.crypto import decrypt, encrypt
from app.db.models import HermesConfigModel


def get_row(db: Session) -> HermesConfigModel:
    """读取单行配置（id=1）；不存在时返回 None。"""
    return db.get(HermesConfigModel, 1)


def load(db: Session) -> dict:
    """读取数据库保存的配置（含解密后的 API Key，仅供内部使用）。"""
    row = get_row(db)
    if row is None:
        return {"base_url": "", "api_key": "", "model": ""}
    api_key = decrypt(row.encrypted_api_key) if row.encrypted_api_key else ""
    return {
        "base_url": row.base_url or "",
        "api_key": api_key,
        "model": row.model or "",
    }


def save(db: Session, base_url: str, api_key: str, model: str) -> dict:
    """保存配置（upsert id=1）；api_key 为空字符串表示不修改已存储的 Key。"""
    row = get_row(db)
    if row is None:
        row = HermesConfigModel(id=1)
        db.add(row)

    row.base_url = base_url or ""
    if api_key:
        row.encrypted_api_key = encrypt(api_key)
    row.model = model or None
    db.commit()
    return load(db)
