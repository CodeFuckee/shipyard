"""
MCP OAuth 2.0 数据库持久化认证提供者。

实现基于 SQLite 持久化的 OAuth 2.0 授权服务器，与 Mobile Portainer 的 API Key 系统集成。
遵循 RFC 6749 (OAuth 2.0) 和 RFC 7636 (PKCE) 规范。

=== 功能概述 ===

本模块实现 OAuthAuthorizationServerProvider 协议，提供：
- 动态客户端注册（Dynamic Client Registration）— 持久化到 oauth_clients 表
- 授权码流程（Authorization Code Grant）+ PKCE — 持久化到 oauth_auth_codes 表
- Access Token 签发与验证 — 持久化到 oauth_tokens 表
- Refresh Token 轮换（Token Rotation）
- Token 撤销（Token Revocation）

=== 与 API Key 系统的集成 ===

1. 传统 API Key 模式：
    - 设置 MOBILE_PORTAINER_API_KEY 环境变量
    - 客户端在请求头中以 Bearer token 方式携带 API Key
    - API Key 可以直接作为 access token 使用，无需 OAuth 流程
    - 适用于简单的脚本调用和直接 API 访问

2. OAuth 2.0 模式（本模块）：
    - 客户端动态注册，获取 client_id 和 client_secret（持久化到数据库）
    - 通过授权码流程（含 PKCE）获取 access token
    - 支持 token 刷新和撤销
    - 服务重启后状态不丢失
    - 适用于 Claude Code 等标准 MCP 客户端

=== PKCE 说明 ===

PKCE (Proof Key for Code Exchange，RFC 7636) 是 OAuth 2.0 的安全扩展：
- 客户端生成 code_verifier（随机字符串）
- 将 code_verifier 的 SHA-256 哈希作为 code_challenge 发送
- 交换 token 时提交原始 code_verifier
- 防止授权码拦截攻击

=== 与 InMemoryOAuthProvider 的区别 ===

旧版 InMemoryOAuthProvider 使用 Python 字典存储所有数据，
服务重启后全部丢失。本实现将所有 OAuth 数据持久化到 SQLite：
- oauth_clients: 客户端注册信息
- oauth_auth_codes: 授权码（短期有效）
- oauth_tokens: Access Token 和 Refresh Token
"""

import json
import logging
import os
import secrets
import time
from typing import Any

from pydantic import AnyUrl
from sqlalchemy.orm import Session

from mcp.server.auth.provider import (
    AccessToken,
    AuthorizationCode,
    AuthorizationParams,
    OAuthAuthorizationServerProvider,
    OAuthClientInformationFull,
    OAuthToken,
    RefreshToken,
)
from mcp.shared.auth import OAuthClientInformationFull as OAuthClientInfo

from app.db.database import SessionLocal
from app.db.models import OAuthAuthorizationCodeModel, OAuthClientModel, OAuthTokenModel

logger = logging.getLogger("mcp.portainer.auth")


# ================================================================
# DB → Pydantic 模型转换辅助函数
# ================================================================


def _model_to_client_info(m: OAuthClientModel) -> OAuthClientInformationFull:
    """将数据库模型转换为 OAuthClientInformationFull。"""
    return OAuthClientInformationFull(
        client_id=m.client_id,
        client_secret=m.client_secret,
        client_id_issued_at=m.client_id_issued_at,
        client_secret_expires_at=m.client_secret_expires_at,
        redirect_uris=_parse_json_list(m.redirect_uris),
        token_endpoint_auth_method=m.token_endpoint_auth_method or "client_secret_post",
        grant_types=_parse_json_list(m.grant_types)
        or ["authorization_code", "refresh_token"],
        response_types=_parse_json_list(m.response_types) or ["code"],
        scope=m.scope,
        client_name=m.client_name,
    )


def _model_to_auth_code(m: OAuthAuthorizationCodeModel) -> AuthorizationCode:
    """将数据库模型转换为 AuthorizationCode。"""
    return AuthorizationCode(
        code=m.code,
        client_id=m.client_id,
        scopes=_parse_json_list(m.scopes) or [],
        expires_at=m.expires_at,
        redirect_uri=AnyUrl(m.redirect_uri),
        code_challenge=m.code_challenge,
        redirect_uri_provided_explicitly=bool(m.redirect_uri_provided_explicitly),
        resource=m.resource,
        subject=m.subject,
    )


def _model_to_access_token(m: OAuthTokenModel) -> AccessToken:
    """将数据库模型转换为 AccessToken。"""
    return AccessToken(
        token=m.token,
        client_id=m.client_id,
        scopes=_parse_json_list(m.scopes) or [],
        expires_at=m.expires_at,
        resource=m.resource,
        subject=m.subject,
    )


def _model_to_refresh_token(m: OAuthTokenModel) -> RefreshToken:
    """将数据库模型转换为 RefreshToken。"""
    return RefreshToken(
        token=m.token,
        client_id=m.client_id,
        scopes=_parse_json_list(m.scopes) or [],
        expires_at=m.expires_at,
        subject=m.subject,
    )


def _parse_json_list(raw: str | None) -> list[str] | None:
    """安全地解析 JSON 字符串为列表。"""
    if not raw:
        return None
    try:
        parsed = json.loads(raw)
        return parsed if isinstance(parsed, list) else None
    except (json.JSONDecodeError, TypeError):
        return None


def _to_json_list(items: list[Any] | None) -> str | None:
    """将列表序列化为 JSON 字符串。"""
    if items is None:
        return None
    return json.dumps([str(i) for i in items])


# ================================================================
# DatabaseOAuthProvider
# ================================================================


class DatabaseOAuthProvider(OAuthAuthorizationServerProvider):
    """数据库持久化的 OAuth 2.0 授权服务器提供者。

    与 InMemoryOAuthProvider 接口完全兼容，但所有数据存储在 SQLite 中。
    服务重启后 OAuth 状态不丢失。

    === 使用方式 ===

    在 MCPServer 实例上配置：

        auth_provider = DatabaseOAuthProvider(
            session_factory=SessionLocal,
            api_key=os.environ.get("MOBILE_PORTAINER_API_KEY"),
        )

    === 线程安全 ===

    每个方法内部创建独立的数据库 session，方法返回前关闭。
    SQLite 使用 WAL 模式 + check_same_thread=False，支持基本并发。
    """

    def __init__(
        self,
        session_factory: Any = None,
        api_key: str | None = None,
    ):
        """初始化数据库 OAuth 提供者。

        参数:
            session_factory: SQLAlchemy sessionmaker（默认使用 SessionLocal）
            api_key: 可选的 API Key，用作备用认证方式。如果为 None，从 MOBILE_PORTAINER_API_KEY 环境变量读取。
        """
        self._session_factory = session_factory or SessionLocal
        self._api_key = api_key or os.environ.get("MOBILE_PORTAINER_API_KEY")

    # ================================================================
    # 内部辅助方法
    # ================================================================

    def _make_session(self) -> Session:
        """创建一个新的数据库 session。"""
        return self._session_factory()

    def _generate_token(self, prefix: str = "") -> str:
        """生成加密安全的随机 token。

        使用 secrets.token_hex(32) 生成 64 个十六进制字符（256 位熵）。
        """
        raw = secrets.token_hex(32)
        return f"{prefix}{raw}" if prefix else raw

    def _cleanup_expired(self, db: Session) -> None:
        """惰性清理过期的授权码和 token。"""
        now = time.time()
        now_int = int(now)

        # 清理过期授权码
        db.query(OAuthAuthorizationCodeModel).filter(
            OAuthAuthorizationCodeModel.expires_at < now
        ).delete()

        # 清理过期的 access token
        db.query(OAuthTokenModel).filter(
            OAuthTokenModel.token_type == "access",
            OAuthTokenModel.expires_at.isnot(None),
            OAuthTokenModel.expires_at < now_int,
        ).delete()

        db.commit()

    # ================================================================
    # TokenVerifier 接口 — Token 验证
    # ================================================================

    async def load_access_token(self, token: str) -> AccessToken | None:
        """验证 access token 或备用的 API Key。

        这是 MCP 协议层在每个请求中调用的方法，
        用于验证客户端提供的 Bearer token 是否有效。

        验证逻辑：
        1. 如果 token 匹配 API Key 环境变量，返回管理员级 token
        2. 在 oauth_tokens 表中查找 access token
        3. 惰性清理过期数据
        """
        # API Key 作为 Bearer token（向后兼容）
        if self._api_key and token == self._api_key:
            return AccessToken(
                token=token,
                client_id="api_key_client",
                scopes=["*"],
                subject="admin",
            )

        db = self._make_session()
        try:
            self._cleanup_expired(db)

            record = (
                db.query(OAuthTokenModel)
                .filter(
                    OAuthTokenModel.token == token,
                    OAuthTokenModel.token_type == "access",
                )
                .first()
            )
            if record is None:
                return None

            # 检查是否过期
            if record.expires_at and record.expires_at < int(time.time()):
                return None

            return _model_to_access_token(record)
        finally:
            db.close()

    # ================================================================
    # 客户端管理
    # ================================================================

    async def get_client(self, client_id: str) -> OAuthClientInformationFull | None:
        """根据 client_id 查找已注册的 OAuth 客户端。"""
        db = self._make_session()
        try:
            record = (
                db.query(OAuthClientModel)
                .filter(OAuthClientModel.client_id == client_id)
                .first()
            )
            if record is None:
                return None
            return _model_to_client_info(record)
        finally:
            db.close()

    async def register_client(self, client_info: OAuthClientInformationFull) -> None:
        """注册新的 OAuth 2.0 客户端，持久化到数据库。

        如果客户端未提供 client_id 或 client_secret，会自动生成。
        """
        db = self._make_session()
        try:
            # 自动生成 client_id（如果未提供）
            if not client_info.client_id:
                client_info.client_id = self._generate_token("client_")

            # 自动生成 client_secret（如果未提供且 auth_method 不是 "none"）
            if (
                not client_info.client_secret
                and client_info.token_endpoint_auth_method != "none"
            ):
                client_info.client_secret = self._generate_token("secret_")

            now = int(time.time())
            client_info.client_id_issued_at = now
            client_info.client_secret_expires_at = 0  # 0 = 永不过期

            # 创建数据库记录
            record = OAuthClientModel(
                client_id=client_info.client_id,
                client_secret=client_info.client_secret,
                client_id_issued_at=client_info.client_id_issued_at,
                client_secret_expires_at=(
                    client_info.client_secret_expires_at
                    if client_info.client_secret_expires_at != 0
                    else None
                ),
                redirect_uris=_to_json_list(
                    [str(u) for u in client_info.redirect_uris]
                    if client_info.redirect_uris
                    else None
                ),
                token_endpoint_auth_method=client_info.token_endpoint_auth_method
                or "client_secret_post",
                grant_types=_to_json_list(client_info.grant_types),
                response_types=_to_json_list(client_info.response_types),
                scope=client_info.scope,
                client_name=client_info.client_name,
            )
            db.add(record)
            db.commit()
        finally:
            db.close()

    # ================================================================
    # 授权流程
    # ================================================================

    async def authorize(
        self, client: OAuthClientInformationFull, params: AuthorizationParams
    ) -> str:
        """处理 OAuth 2.0 授权请求。

        自动批准：直接生成授权码并返回重定向 URL。
        不需要用户交互式的授权页面。

        安全机制：
        - 授权码有效期 10 分钟
        - PKCE code_challenge 存储到数据库，用于后续验证
        - state 参数原样返回，防止 CSRF
        """
        code_value = self._generate_token("code_")

        db = self._make_session()
        try:
            record = OAuthAuthorizationCodeModel(
                code=code_value,
                client_id=client.client_id or "",
                scopes=_to_json_list(params.scopes),
                expires_at=time.time() + 600,  # 10 分钟
                redirect_uri=str(params.redirect_uri),
                code_challenge=params.code_challenge,
                redirect_uri_provided_explicitly=(
                    1 if params.redirect_uri_provided_explicitly else 0
                ),
                resource=params.resource,
            )
            db.add(record)
            db.commit()
        finally:
            db.close()

        # 构造重定向 URL
        redirect_uri = str(params.redirect_uri)
        separator = "&" if "?" in redirect_uri else "?"
        redirect_url = f"{redirect_uri}{separator}code={code_value}"

        if params.state:
            redirect_url += f"&state={params.state}"

        return redirect_url

    async def load_authorization_code(
        self, client: OAuthClientInformationFull, authorization_code: str
    ) -> AuthorizationCode | None:
        """加载并验证授权码的有效性。

        验证条件：
        1. 授权码存在且属于请求的客户端
        2. 授权码未过期
        """
        db = self._make_session()
        try:
            record = (
                db.query(OAuthAuthorizationCodeModel)
                .filter(OAuthAuthorizationCodeModel.code == authorization_code)
                .first()
            )
            if not record:
                return None

            # 验证授权码属于请求的客户端
            if record.client_id != client.client_id:
                return None

            # 验证是否过期
            if record.expires_at < time.time():
                db.delete(record)
                db.commit()
                return None

            return _model_to_auth_code(record)
        finally:
            db.close()

    async def exchange_authorization_code(
        self,
        client: OAuthClientInformationFull,
        authorization_code: AuthorizationCode,
    ) -> OAuthToken:
        """用授权码交换 access token 和 refresh token。

        安全机制：
        - 授权码一次性使用（用后即删）
        - PKCE 验证由 MCP 框架在调用本方法前完成
        - Access token 有效期 1 小时
        - Refresh token 有效期 30 天
        """
        db = self._make_session()
        try:
            # 删除已使用的授权码（一次性使用）
            db.query(OAuthAuthorizationCodeModel).filter(
                OAuthAuthorizationCodeModel.code == authorization_code.code
            ).delete()

            scopes = authorization_code.scopes
            access_token_str = self._generate_token("at_")
            refresh_token_str = self._generate_token("rt_")
            expires_in = 3600  # 1 小时

            # 写入 access token
            db.add(
                OAuthTokenModel(
                    token=access_token_str,
                    token_type="access",
                    client_id=client.client_id or "",
                    scopes=_to_json_list(scopes),
                    expires_at=int(time.time()) + expires_in,
                    subject=authorization_code.subject,
                    resource=authorization_code.resource,
                )
            )

            # 写入 refresh token
            db.add(
                OAuthTokenModel(
                    token=refresh_token_str,
                    token_type="refresh",
                    client_id=client.client_id or "",
                    scopes=_to_json_list(scopes),
                    expires_at=int(time.time()) + 86400 * 30,  # 30 天
                    subject=authorization_code.subject,
                )
            )

            db.commit()

            return OAuthToken(
                access_token=access_token_str,
                token_type="Bearer",
                expires_in=expires_in,
                scope=" ".join(scopes) if scopes else None,
                refresh_token=refresh_token_str,
            )
        finally:
            db.close()

    # ================================================================
    # Token 刷新
    # ================================================================

    async def load_refresh_token(
        self, client: OAuthClientInformationFull, refresh_token: str
    ) -> RefreshToken | None:
        """加载并验证 refresh token。"""
        db = self._make_session()
        try:
            record = (
                db.query(OAuthTokenModel)
                .filter(
                    OAuthTokenModel.token == refresh_token,
                    OAuthTokenModel.token_type == "refresh",
                )
                .first()
            )
            if not record:
                return None

            # 验证 token 属于请求的客户端
            if record.client_id != client.client_id:
                return None

            return _model_to_refresh_token(record)
        finally:
            db.close()

    async def exchange_refresh_token(
        self,
        client: OAuthClientInformationFull,
        refresh_token: RefreshToken,
        scopes: list[str],
    ) -> OAuthToken:
        """用 refresh token 交换新的 access token 和 refresh token（Token 轮换）。"""
        db = self._make_session()
        try:
            # 撤销旧的 refresh token
            db.query(OAuthTokenModel).filter(
                OAuthTokenModel.token == refresh_token.token,
                OAuthTokenModel.token_type == "refresh",
            ).delete()

            new_scopes = scopes if scopes else refresh_token.scopes
            access_token_str = self._generate_token("at_")
            refresh_token_str = self._generate_token("rt_")
            expires_in = 3600

            # 写入新的 access token
            db.add(
                OAuthTokenModel(
                    token=access_token_str,
                    token_type="access",
                    client_id=client.client_id or "",
                    scopes=_to_json_list(new_scopes),
                    expires_at=int(time.time()) + expires_in,
                    subject=refresh_token.subject,
                )
            )

            # 写入新的 refresh token
            db.add(
                OAuthTokenModel(
                    token=refresh_token_str,
                    token_type="refresh",
                    client_id=client.client_id or "",
                    scopes=_to_json_list(new_scopes),
                    expires_at=int(time.time()) + 86400 * 30,
                    subject=refresh_token.subject,
                )
            )

            db.commit()

            return OAuthToken(
                access_token=access_token_str,
                token_type="Bearer",
                expires_in=expires_in,
                scope=" ".join(new_scopes) if new_scopes else None,
                refresh_token=refresh_token_str,
            )
        finally:
            db.close()

    # ================================================================
    # Token 撤销
    # ================================================================

    async def revoke_token(
        self, token: AccessToken | RefreshToken | AuthorizationCode
    ) -> None:
        """撤销（作废）指定的 token。"""
        db = self._make_session()
        try:
            if isinstance(token, AccessToken):
                # 撤销 access token
                db.query(OAuthTokenModel).filter(
                    OAuthTokenModel.token == token.token,
                    OAuthTokenModel.token_type == "access",
                ).delete()
                # 级联撤销关联的 refresh token（通过 client_id 和 subject 匹配）
                db.query(OAuthTokenModel).filter(
                    OAuthTokenModel.token_type == "refresh",
                    OAuthTokenModel.client_id == token.client_id,
                    OAuthTokenModel.subject == token.subject,
                ).delete()

            elif isinstance(token, RefreshToken):
                db.query(OAuthTokenModel).filter(
                    OAuthTokenModel.token == token.token,
                    OAuthTokenModel.token_type == "refresh",
                ).delete()

            elif isinstance(token, AuthorizationCode):
                db.query(OAuthAuthorizationCodeModel).filter(
                    OAuthAuthorizationCodeModel.code == token.code
                ).delete()

            db.commit()
        finally:
            db.close()
