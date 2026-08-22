"""OIDC 身份令牌交换与校验。"""

import hmac
import json
import os
from typing import Any
from urllib.parse import urlparse

import jwt
import requests
from jwt.algorithms import RSAAlgorithm

OIDC_ISSUER = os.getenv("OIDC_ISSUER", "").rstrip("/")
OIDC_CLIENT_ID = os.getenv("OIDC_CLIENT_ID", "")
OIDC_CLIENT_SECRET = os.getenv("OIDC_CLIENT_SECRET", "")
OIDC_REDIRECT_URIS = os.getenv("OIDC_REDIRECT_URIS", "")
OIDC_DISCOVERY_TIMEOUT = int(os.getenv("OIDC_DISCOVERY_TIMEOUT", "10"))

_discovery_cache: dict[str, Any] | None = None
_jwks_cache: dict[str, Any] | None = None


class OIDCError(Exception):
    """OIDC 供应商响应或令牌不符合安全约束。"""


def is_configured() -> bool:
    """只有 issuer 与客户端标识同时配置时才启用 OIDC。"""
    return bool(OIDC_ISSUER and OIDC_CLIENT_ID and configured_redirect_uris())


def configured_redirect_uris() -> set[str]:
    """解析白名单回调地址并拒绝空值。"""
    return {uri.strip() for uri in OIDC_REDIRECT_URIS.split(",") if uri.strip()}


def validate_redirect_uri(redirect_uri: str) -> None:
    """确保浏览器或移动端回调地址已由部署者显式白名单。"""
    if redirect_uri not in configured_redirect_uris():
        raise OIDCError("OIDC 回调地址未在 OIDC_REDIRECT_URIS 中配置")


def reset_discovery_cache() -> None:
    """清空缓存，供测试及配置热更新场景使用。"""
    global _discovery_cache, _jwks_cache
    _discovery_cache = None
    _jwks_cache = None


def _validate_https_endpoint(name: str, value: Any) -> str:
    endpoint = str(value or "")
    parsed = urlparse(endpoint)
    if parsed.scheme != "https" or not parsed.netloc:
        raise OIDCError(f"OIDC 发现文档的 {name} 必须是 HTTPS 地址")
    return endpoint


def get_discovery() -> dict[str, Any]:
    """读取并缓存 RFC 8414/OpenID Connect Discovery 文档。"""
    global _discovery_cache
    if not is_configured():
        raise OIDCError("未配置 OIDC")
    if _discovery_cache is not None:
        return _discovery_cache

    try:
        response = requests.get(
            f"{OIDC_ISSUER}/.well-known/openid-configuration",
            timeout=OIDC_DISCOVERY_TIMEOUT,
        )
        response.raise_for_status()
        discovery = response.json()
    except (requests.RequestException, ValueError) as exc:
        raise OIDCError("无法获取 OIDC 发现文档") from exc

    if discovery.get("issuer") != OIDC_ISSUER:
        raise OIDCError("OIDC 发现文档的 issuer 与配置不一致")
    for field in ("authorization_endpoint", "token_endpoint", "jwks_uri"):
        _validate_https_endpoint(field, discovery.get(field))
    _discovery_cache = discovery
    return discovery


def public_config() -> dict[str, Any]:
    """返回可安全暴露给客户端的 OIDC 发起登录配置。"""
    if not is_configured():
        return {"enabled": False}
    discovery = get_discovery()
    return {
        "enabled": True,
        "issuer": OIDC_ISSUER,
        "client_id": OIDC_CLIENT_ID,
        "authorization_endpoint": discovery["authorization_endpoint"],
        "scopes": ["openid", "profile", "email"],
    }


def _fetch_jwks(jwks_uri: str) -> dict[str, Any]:
    global _jwks_cache
    if _jwks_cache is not None:
        return _jwks_cache
    try:
        response = requests.get(jwks_uri, timeout=OIDC_DISCOVERY_TIMEOUT)
        response.raise_for_status()
        jwks = response.json()
    except (requests.RequestException, ValueError) as exc:
        raise OIDCError("无法获取 OIDC 签名密钥") from exc
    if not isinstance(jwks.get("keys"), list):
        raise OIDCError("OIDC 签名密钥格式无效")
    _jwks_cache = jwks
    return jwks


def _decode_id_token(
    id_token: str, nonce: str, discovery: dict[str, Any]
) -> dict[str, Any]:
    """按 issuer、audience、签名和 nonce 验证 ID Token。"""
    global _jwks_cache
    try:
        header = jwt.get_unverified_header(id_token)
        if header.get("alg") != "RS256" or not header.get("kid"):
            raise OIDCError("不支持的 OIDC ID Token 签名算法")
        keys = _fetch_jwks(discovery["jwks_uri"])["keys"]
        jwk = next((item for item in keys if item.get("kid") == header["kid"]), None)
        if jwk is None:
            # IdP 轮换签名密钥时，缓存可能尚未包含新 kid；刷新一次 JWKS 后重试。
            _jwks_cache = None
            keys = _fetch_jwks(discovery["jwks_uri"])["keys"]
            jwk = next(
                (item for item in keys if item.get("kid") == header["kid"]), None
            )
        if jwk is None:
            raise OIDCError("OIDC ID Token 签名密钥不存在")
        claims = jwt.decode(
            id_token,
            RSAAlgorithm.from_jwk(json.dumps(jwk)),
            algorithms=["RS256"],
            audience=OIDC_CLIENT_ID,
            issuer=OIDC_ISSUER,
            options={"require": ["exp", "iat", "sub"]},
        )
    except OIDCError:
        raise
    except jwt.PyJWTError as exc:
        raise OIDCError("OIDC ID Token 校验失败") from exc
    if not hmac.compare_digest(str(claims.get("nonce") or ""), nonce):
        raise OIDCError("OIDC ID Token nonce 校验失败")
    return claims


def exchange_code_for_identity(
    *, code: str, code_verifier: str, nonce: str, redirect_uri: str
) -> dict[str, Any]:
    """以授权码和 PKCE verifier 换取并验证外部身份。"""
    if not is_configured():
        raise OIDCError("未配置 OIDC")
    validate_redirect_uri(redirect_uri)
    discovery = get_discovery()
    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "client_id": OIDC_CLIENT_ID,
        "code_verifier": code_verifier,
    }
    if OIDC_CLIENT_SECRET:
        data["client_secret"] = OIDC_CLIENT_SECRET
    try:
        response = requests.post(
            discovery["token_endpoint"], data=data, timeout=OIDC_DISCOVERY_TIMEOUT
        )
        response.raise_for_status()
        token_payload = response.json()
    except (requests.RequestException, ValueError) as exc:
        raise OIDCError("OIDC 授权码交换失败") from exc
    id_token = token_payload.get("id_token")
    if not isinstance(id_token, str) or not id_token:
        raise OIDCError("OIDC 令牌响应未包含 ID Token")
    return _decode_id_token(id_token, nonce, discovery)
