"""
测试 MCP HTTP 服务器的传输安全配置（DNS rebinding 防护 Host 校验）。

复现 bug：app/mcp/http_server.py 调用 streamable_http_app() 时未显式传入
transport_security，mcp SDK 检测到 host 参数默认 "127.0.0.1" 后自动启用
DNS rebinding 防护，allowed_hosts 仅包含 127.0.0.1/localhost/[::1]。

外部客户端（Claude Code）通过公网域名 https://home.chenkaidi.top:507 访问：
1. 无 token 请求在 RequireAuthMiddleware 层先返回 401（认证早于 Host 校验），
   掩盖了 Host 校验问题；
2. 完成 OAuth 流程携带有效 Bearer token 后，请求进入 StreamableHTTPASGIApp，
   此时 Host 校验生效 —— home.chenkaidi.top:507 不在 allowed_hosts，
   返回 421 "Invalid Host header"（与实测一致）。

修复：从 PUBLIC_BASE_URL 动态构造 TransportSecuritySettings，
allowed_hosts 包含公网主机名（保留 DNS rebinding 防护，evil 域名仍拒绝）。
"""

from urllib.parse import urlparse

import pytest

from mcp.server.transport_security import TransportSecurityMiddleware


def _validate_host_matches(settings, host: str) -> bool:
    """用中间件的 Host 校验逻辑判断 host 是否被允许。"""
    middleware = TransportSecurityMiddleware(settings)
    return middleware._validate_host(host)


class TestBuildTransportSecurity:
    """验证 build_transport_security() 的配置逻辑。"""

    def test_function_exists(self):
        """复现 bug：http_server.py 中不存在 build_transport_security。

        当前 http_server.py 直接调用 streamable_http_app() 未传
        transport_security，mcp SDK 自动启用仅允许 localhost 的
        DNS rebinding 防护，公网 Host 一律 421。
        """
        from app.mcp.http_server import build_transport_security

        assert callable(build_transport_security)

    def test_allows_public_host(self):
        """复现 bug：公网 Host 不在 allowed_hosts 中。

        配置为 https://home.chenkaidi.top:507 时，allowed_hosts 必须
        包含 home.chenkaidi.top（通配端口），否则真实客户端请求返回
        421 "Invalid Host header"。
        """
        from app.mcp.http_server import build_transport_security

        settings = build_transport_security("https://home.chenkaidi.top:507")
        assert any(
            h.startswith("home.chenkaidi.top") for h in settings.allowed_hosts
        ), (
            "build_transport_security() 的 allowed_hosts 未包含公网主机 "
            "home.chenkaidi.top！\n"
            "mcp SDK 默认的 DNS rebinding 防护只允许 localhost，\n"
            "外部客户端携带有效 token 的请求会收到 421 Invalid Host header。"
        )

    def test_public_host_validates_ok(self):
        """行为验证：home.chenkaidi.top:507 能通过 Host 校验。"""
        from app.mcp.http_server import build_transport_security

        settings = build_transport_security("https://home.chenkaidi.top:507")
        assert _validate_host_matches(settings, "home.chenkaidi.top:507") is True, (
            "Host 校验拒绝 home.chenkaidi.top:507，Claude Code 连接会失败。"
        )

    def test_rebinding_protection_kept(self):
        """安全验证：DNS rebinding 防护仍然生效（evil 域名被拒绝）。"""
        from app.mcp.http_server import build_transport_security

        settings = build_transport_security("https://home.chenkaidi.top:507")
        assert settings.enable_dns_rebinding_protection is True
        assert _validate_host_matches(settings, "evil-attacker.com") is False, (
            "修复不能关闭 DNS rebinding 防护——恶意 Host 应被拒绝。"
        )

    def test_localhost_still_allowed(self):
        """兼容验证：容器内健康检查/本地访问仍可通过。"""
        from app.mcp.http_server import build_transport_security

        settings = build_transport_security("https://home.chenkaidi.top:507")
        assert _validate_host_matches(settings, "127.0.0.1:80") is True
        assert _validate_host_matches(settings, "localhost:80") is True

    def test_origin_matches_public_scheme(self):
        """验证：allowed_origins 包含公网 origin（浏览器场景）。"""
        from app.mcp.http_server import build_transport_security

        settings = build_transport_security("https://home.chenkaidi.top:507")
        assert any("home.chenkaidi.top" in o for o in settings.allowed_origins), (
            "allowed_origins 未包含公网 origin，带 Origin 头的客户端会被 403。"
        )


class TestHttpServerModule:
    """验证 http_server.py 的模块级配置。"""

    def test_mcp_http_app_created_with_transport_security(self):
        """复现 bug：mcp_http_app 创建时是否显式传入 transport_security。

        检查 http_server.py 源码中 streamable_http_app() 的调用，
        必须显式传入 transport_security=...（否则 SDK 自动启用
        仅 localhost 的 DNS rebinding 防护 → 公网 Host 421）。
        """
        import inspect
        from pathlib import Path

        import app.mcp.http_server as http_server

        src = inspect.getsource(http_server)
        assert "transport_security=" in src, (
            "http_server.py 中 streamable_http_app() 调用未显式传入\n"
            "transport_security=...！\n"
            "mcp SDK 在 transport_security 为 None 且 host 为 127.0.0.1 时\n"
            "自动启用 DNS rebinding 防护，allowed_hosts 仅含 localhost，\n"
            "公网 Host（如 home.chenkaidi.top:507）的请求返回 421\n"
            "Invalid Host header，Claude Code 连接失败。"
        )
