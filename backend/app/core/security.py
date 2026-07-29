import base64
import hashlib
import hmac
import os

from fastapi import Security, HTTPException, status, Depends, Request
from fastapi.security import APIKeyHeader
from sqlalchemy.orm import Session
from app.core.config import API_KEY_NAME, ADMIN_USER, ADMIN_PASSWORD
from app.db.database import get_db
from app.db.models import APIKeyModel, AdminCredentialModel

api_key_header = APIKeyHeader(
    name=API_KEY_NAME,
    description="输入你的 API Key（也可使用 Authorization: Bearer <token> 格式）",
    auto_error=False,
)


_PASSWORD_HASH_ITERATIONS = 600_000


def hash_password(password: str) -> str:
    """使用 PBKDF2-SHA256 生成可持久化的密码哈希。"""
    salt = os.urandom(16)
    password_hash = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, _PASSWORD_HASH_ITERATIONS
    )
    return "$".join(
        (
            str(_PASSWORD_HASH_ITERATIONS),
            base64.urlsafe_b64encode(salt).decode("ascii"),
            base64.urlsafe_b64encode(password_hash).decode("ascii"),
        )
    )


def verify_password(password: str, stored_password_hash: str) -> bool:
    """校验 PBKDF2-SHA256 密码哈希。"""
    try:
        iterations, salt, expected_hash = stored_password_hash.split("$", 2)
        actual_hash = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            base64.urlsafe_b64decode(salt.encode("ascii")),
            int(iterations),
        )
        return hmac.compare_digest(
            actual_hash, base64.urlsafe_b64decode(expected_hash.encode("ascii"))
        )
    except (ValueError, TypeError):
        return False


def verify_admin_credentials(db: Session, admin_user: str, admin_pass: str) -> bool:
    """检查管理员凭据，优先使用已修改并持久化的密码。"""
    if not hmac.compare_digest(admin_user or "", ADMIN_USER):
        return False

    credential = db.get(AdminCredentialModel, 1)
    if credential:
        return verify_password(admin_pass or "", credential.password_hash)
    return hmac.compare_digest(admin_pass or "", ADMIN_PASSWORD)


def _verify_admin_credentials(request: Request, db: Session) -> bool:
    """检查请求中的 Admin 凭据是否有效。"""
    return verify_admin_credentials(
        db,
        request.headers.get("X-Admin-User"),
        request.headers.get("X-Admin-Pass"),
    )


def _extract_api_key_from_request(request: Request) -> str | None:
    """从请求中提取 API Key，支持多种传递方式。"""
    # 1. X-API-Key 请求头
    api_key = request.headers.get(API_KEY_NAME)
    if api_key:
        return api_key

    # 2. Authorization: Bearer <token>
    auth_header = request.headers.get("Authorization")
    if auth_header:
        scheme, _, token = auth_header.partition(" ")
        if scheme.lower() == "bearer" and token:
            return token

    return None


async def get_api_key(
    request: Request,
    api_key_header: str = Security(api_key_header),
    db: Session = Depends(get_db),
):
    # 先尝试 API Key 认证（支持 X-API-Key 和 Authorization: Bearer）
    api_key = _extract_api_key_from_request(request)
    if api_key:
        key_record = db.query(APIKeyModel).filter(APIKeyModel.key == api_key).first()
        if key_record:
            return api_key

    # 回退到 Admin 凭据认证（Web UI 登录用户）
    if _verify_admin_credentials(request, db):
        return "admin"

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid API Key or Admin Credentials",
    )
