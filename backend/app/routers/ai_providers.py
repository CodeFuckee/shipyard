"""AI API 供应商配置路由 — 纯配置存储，为后续 AI 功能做准备。

- API Key 使用 crypto.encrypt 加密后存储，任何响应不返回明文。
- 「测试连接」通过 OpenAI 兼容的 /models 端点验证 Base URL 与 Key 有效性。
"""

from typing import List, Optional
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.core.crypto import decrypt, encrypt
from app.core.security import get_api_key
from app.db.database import get_db
from app.db.models import AIProviderModel

router = APIRouter(prefix="/admin/ai-providers", tags=["admin"])

# 测试连接超时（秒）
_TEST_TIMEOUT = 10.0


class AIProviderCreateRequest(BaseModel):
    """创建供应商请求体。"""

    name: str = Field(min_length=1, max_length=64)
    provider_type: str = Field(default="custom")
    base_url: str = Field(min_length=1, max_length=512)
    api_key: str = Field(min_length=1, max_length=1024)
    default_model: str = Field(default="", max_length=128)
    enabled: bool = True

    @field_validator("base_url")
    def validate_base_url(cls, value: str) -> str:
        url = _normalize_base_url(value)
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise ValueError("base_url 必须是合法的 http(s) 地址")
        return url


class AIProviderModelsPreviewRequest(BaseModel):
    """新增供应商前预览模型列表：按临时 base_url + api_key 请求，不落库。"""

    base_url: str = Field(min_length=1, max_length=512)
    api_key: str = Field(min_length=1, max_length=1024)

    @field_validator("base_url")
    def validate_base_url(cls, value: str) -> str:
        url = _normalize_base_url(value)
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise ValueError("base_url 必须是合法的 http(s) 地址")
        return url


class AIProviderUpdateRequest(BaseModel):
    """更新供应商请求体。api_key 省略或为空字符串表示不修改已存储的 Key。"""

    name: Optional[str] = Field(default=None, min_length=1, max_length=64)
    provider_type: Optional[str] = Field(default=None)
    base_url: Optional[str] = Field(default=None, min_length=1, max_length=512)
    api_key: Optional[str] = Field(default=None, max_length=1024)
    default_model: Optional[str] = Field(default=None, max_length=128)
    enabled: Optional[bool] = None

    @field_validator("base_url")
    def validate_base_url(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return value
        url = _normalize_base_url(value)
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise ValueError("base_url 必须是合法的 http(s) 地址")
        return url


def _normalize_base_url(url: str) -> str:
    """去除首尾空白与结尾斜杠，便于拼接 /models 等端点。

    校验在 validator 中完成；此处仅规范化。URL 中间不允许出现空白
    （如 "https:// 有空格"），否则 urlparse 会误判为合法地址。
    """
    stripped = url.strip().rstrip("/")
    if any(ch.isspace() for ch in stripped):
        raise ValueError("base_url 不能包含空白字符")
    return stripped


def _serialize(provider: AIProviderModel) -> dict:
    """序列化供应商；永不包含明文 API Key。"""
    return {
        "id": provider.id,
        "name": provider.name,
        "provider_type": provider.provider_type,
        "base_url": provider.base_url,
        "default_model": provider.default_model or "",
        "enabled": bool(provider.enabled),
        "api_key_configured": bool(provider.encrypted_api_key),
        "created_at": provider.created_at.isoformat() if provider.created_at else None,
        "updated_at": provider.updated_at.isoformat() if provider.updated_at else None,
    }


def _get_provider_or_404(db: Session, provider_id: str) -> AIProviderModel:
    provider = db.get(AIProviderModel, provider_id)
    if provider is None:
        raise HTTPException(status_code=404, detail=f"供应商不存在: {provider_id}")
    return provider


def _request_models(provider: AIProviderModel) -> tuple:
    """请求 OpenAI 兼容的 {base_url}/models 端点（使用库中已加密存储的 Key）。

    返回 (response, error_message)：error_message 为空表示成功拿到 200 响应；
    否则 response 为 None。供「测试连接」与「获取模型列表」两个端点复用。
    """
    if not provider.encrypted_api_key:
        return None, "该供应商尚未配置 API Key"

    api_key = decrypt(provider.encrypted_api_key)
    return _request_models_url(provider.base_url, api_key)


def _request_models_url(base_url: str, api_key: str) -> tuple:
    """按临时 base_url + api_key 请求 OpenAI 兼容的 {base_url}/models 端点。

    供新增供应商「预览模型列表」使用（Key 不落库、不依赖已创建的供应商 id）；
    错误处理与 _request_models 完全一致，两者共用同一契约。
    """
    url = f"{base_url}/models"

    try:
        response = httpx.get(
            url,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=_TEST_TIMEOUT,
        )
    except httpx.TimeoutException:
        return None, f"连接超时（{_TEST_TIMEOUT:.0f} 秒），请检查 Base URL 或网络"
    except httpx.ConnectError:
        return None, "无法连接服务器，请检查 Base URL 或网络"
    except httpx.HTTPError as exc:
        return None, f"请求失败: {exc}"

    if response.status_code == 200:
        return response, ""
    if response.status_code in (401, 403):
        return None, f"API Key 无效或被拒绝（{response.status_code}）"
    if response.status_code == 404:
        return None, "接口不存在（404），请检查 Base URL 是否正确"
    return None, f"请求失败（{response.status_code}）"


def _parse_models_payload(response: httpx.Response) -> dict:
    """解析 /models 的 200 响应为 {"ok", "models", "message"}。

    OpenAI 标准结构：{"data": [{"id": "...", "name": "..."}]}。
    模型项缺 name 时用 id 兜底；data 中非 dict / 无 id 的项跳过。
    """
    try:
        payload = response.json()
    except ValueError:
        return {"ok": False, "message": "响应不是合法的 JSON", "models": []}

    if not isinstance(payload, dict):
        return {"ok": False, "message": "响应结构异常，缺少 data 数组", "models": []}

    models = []
    for item in payload.get("data") or []:
        if not isinstance(item, dict):
            continue
        model_id = item.get("id")
        if not model_id:
            continue
        models.append({"id": str(model_id), "name": str(item.get("name") or model_id)})
    return {"ok": True, "message": "", "models": models}


@router.get("", response_model=List[dict])
def list_providers(db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """获取全部 AI 供应商配置（不包含 API Key）。"""
    providers = db.query(AIProviderModel).order_by(AIProviderModel.created_at).all()
    return [_serialize(p) for p in providers]


@router.get("/{provider_id}", response_model=dict)
def get_provider(provider_id: str, db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """获取单个供应商配置（不包含 API Key）。"""
    return _serialize(_get_provider_or_404(db, provider_id))


@router.post("", response_model=dict)
def create_provider(
    data: AIProviderCreateRequest, db: Session = Depends(get_db), _: str = Depends(get_api_key)
):
    """创建 AI 供应商；API Key 加密存储。"""
    exists = db.query(AIProviderModel).filter(AIProviderModel.name == data.name).first()
    if exists:
        raise HTTPException(status_code=409, detail=f"供应商名称已存在: {data.name}")

    provider = AIProviderModel(
        name=data.name,
        provider_type=data.provider_type,
        base_url=data.base_url,
        encrypted_api_key=encrypt(data.api_key),
        default_model=data.default_model or None,
        enabled=1 if data.enabled else 0,
    )
    db.add(provider)
    db.commit()
    db.refresh(provider)
    return _serialize(provider)


@router.put("/{provider_id}", response_model=dict)
def update_provider(
    provider_id: str, data: AIProviderUpdateRequest, db: Session = Depends(get_db), _: str = Depends(get_api_key)
):
    """更新供应商；api_key 省略或为空时保留原 Key。"""
    provider = _get_provider_or_404(db, provider_id)

    if data.name is not None and data.name != provider.name:
        exists = db.query(AIProviderModel).filter(AIProviderModel.name == data.name).first()
        if exists:
            raise HTTPException(status_code=409, detail=f"供应商名称已存在: {data.name}")
        provider.name = data.name
    if data.provider_type is not None:
        provider.provider_type = data.provider_type
    if data.base_url is not None:
        provider.base_url = data.base_url
    if data.api_key is not None and data.api_key != "":
        provider.encrypted_api_key = encrypt(data.api_key)
    if data.default_model is not None:
        provider.default_model = data.default_model or None
    if data.enabled is not None:
        provider.enabled = 1 if data.enabled else 0

    db.commit()
    db.refresh(provider)
    return _serialize(provider)


@router.delete("/{provider_id}")
def delete_provider(provider_id: str, db: Session = Depends(get_db), _: str = Depends(get_api_key)):
    """删除供应商。"""
    provider = _get_provider_or_404(db, provider_id)
    db.delete(provider)
    db.commit()
    return {"message": f"供应商已删除: {provider.name}"}


@router.post("/{provider_id}/test", response_model=dict)
def test_provider_connection(
    provider_id: str, db: Session = Depends(get_db), _: str = Depends(get_api_key)
):
    """测试供应商连接：请求 OpenAI 兼容的 {base_url}/models 端点验证 Key。

    返回 ok=true/false 与人类可读的失败原因，HTTP 状态始终 200。
    """
    provider = _get_provider_or_404(db, provider_id)

    response, error = _request_models(provider)
    if error:
        return {"ok": False, "message": error}
    return {"ok": True, "message": "连接成功"}


@router.get("/{provider_id}/models", response_model=dict)
def get_provider_models(
    provider_id: str, db: Session = Depends(get_db), _: str = Depends(get_api_key)
):
    """获取供应商模型列表：请求 OpenAI 兼容的 {base_url}/models 端点。

    解析响应的 data 数组（OpenAI 标准结构），返回
    {"ok": true, "models": [{"id": "...", "name": "..."}]}；
    失败时 {"ok": false, "message": "..."}，HTTP 状态始终 200（与测试连接一致）。
    """
    provider = _get_provider_or_404(db, provider_id)

    response, error = _request_models(provider)
    if error:
        return {"ok": False, "message": error, "models": []}
    return _parse_models_payload(response)


@router.post("/preview-models", response_model=dict)
def preview_provider_models(
    data: AIProviderModelsPreviewRequest, _: str = Depends(get_api_key)
):
    """新增供应商前按临时 base_url + api_key 预览模型列表（不落库）。

    与 GET /{provider_id}/models 相同契约：成功 {"ok": true, "models": [...]}，
    失败 {"ok": false, "message": "..."}，HTTP 状态始终 200。供前端新增
    供应商表单拉取模型列表下拉选择使用（无需先创建供应商）。
    """
    response, error = _request_models_url(data.base_url, data.api_key)
    if error:
        return {"ok": False, "message": error, "models": []}
    return _parse_models_payload(response)
